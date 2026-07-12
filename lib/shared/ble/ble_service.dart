import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../features/documents/document_upload_models.dart';
import 'ble_connection.dart';
import 'ble_constants.dart';
import 'models.dart';

class ConnectResult {
  const ConnectResult({required this.connection, required this.info});

  final BleConnection connection;
  final DeviceInfo info;
}

class BleService {
  BleConnection? _active;
  BluetoothDevice? _activeDevice;

  BleConnection? get activeConnection => _active;
  BluetoothDevice? get activeDevice => _activeDevice;

  /// Connects to [device], raises MTU to 512, discovers EPDF service,
  /// subscribes to cmd notifies, then sends get_device_info and waits for
  /// device_info_resp. Throws on any failure — caller should disconnect.
  Future<ConnectResult> connectAndQueryInfo(BluetoothDevice device) async {
    await device.connect(autoConnect: false);

    try {
      await device.requestMtu(BleConstants.targetMtu);
    } on Object {
      // some platforms reject requestMtu if already negotiated — ignore
    }

    final connection = await BleConnection.establish(device);

    _active = connection;
    _activeDevice = device;

    final Completer<DeviceInfo> completer =
        Completer<DeviceInfo>();
    final StreamSubscription<Map<String, dynamic>> sub =
        connection.cmdMessages.listen((msg) {
      if (msg['cmd'] == BleConstants.respDeviceInfo) {
        final data = msg['data'];
        if (data is Map<String, dynamic>) {
          if (!completer.isCompleted) {
            completer.complete(DeviceInfo.fromJson(data));
          }
        }
      }
    });

    try {
      await connection.sendCommand(const {'cmd': BleConstants.cmdGetDeviceInfo});
      final info = await completer.future
          .timeout(BleConstants.getDeviceInfoTimeout);
      return ConnectResult(connection: connection, info: info);
    } finally {
      await sub.cancel();
    }
  }

  /// Disconnect and dispose any active connection. Safe to call when idle.
  Future<void> disconnect() async {
    final active = _active;
    final device = _activeDevice;
    _active = null;
    _activeDevice = null;
    if (active != null) {
      await active.dispose();
    }
    if (device != null) {
      try {
        await device.disconnect();
      } on Object {
        // best effort
      }
    }
  }

  /// Re-sends get_device_info on an established connection and awaits
  /// device_info_resp. Used for periodic refresh while connected.
  Future<DeviceInfo> refreshDeviceInfo(BleConnection connection) async {
    final completer = Completer<DeviceInfo>();
    final sub = connection.cmdMessages.listen((msg) {
      if (msg['cmd'] == BleConstants.respDeviceInfo) {
        final data = msg['data'];
        if (data is Map<String, dynamic> && !completer.isCompleted) {
          completer.complete(DeviceInfo.fromJson(data));
        }
      }
    });
    try {
      await connection.sendCommand(const {'cmd': BleConstants.cmdGetDeviceInfo});
      return await completer.future.timeout(BleConstants.getDeviceInfoTimeout);
    } finally {
      await sub.cancel();
    }
  }

  /// Sends get_list on an established connection and awaits list_resp.
  /// Returns an empty list when the device reports no documents.
  Future<List<DocumentMeta>> fetchDocumentList(BleConnection connection) async {
    final completer = Completer<List<DocumentMeta>>();
    final sub = connection.cmdMessages.listen((msg) {
      if (msg['cmd'] == BleConstants.respList) {
        final data = msg['data'];
        if (data is Map<String, dynamic> && !completer.isCompleted) {
          final files = data['files'];
          final List<DocumentMeta> docs = files is List
              ? files
                  .whereType<Map<String, dynamic>>()
                  .map(DocumentMeta.fromJson)
                  .toList(growable: false)
              : const <DocumentMeta>[];
          completer.complete(docs);
        }
      }
    });
    try {
      await connection.sendCommand(const {'cmd': BleConstants.cmdGetList});
      return await completer.future.timeout(BleConstants.getListTimeout);
    } finally {
      await sub.cancel();
    }
  }

  Future<void> uploadPreparedDocument({
    required BleConnection connection,
    required String name,
    required String time,
    required List<PreparedDocumentPage> pages,
    void Function(int pageNumber, int totalPages)? onPageStarted,
    void Function(int pageNumber, int totalPages)? onPageUploaded,
  }) async {
    final uploadAck = Completer<String>();
    final uploadEnd = Completer<Map<String, dynamic>>();
    final pageAcks = <int, Completer<void>>{};

    final sub = connection.cmdMessages.listen((msg) {
      final cmd = msg['cmd'];
      if (cmd == BleConstants.respUploadAck) {
        final status = msg['status'] as String? ?? 'error';
        if (!uploadAck.isCompleted) {
          uploadAck.complete(status);
        }
        return;
      }

      if (cmd == BleConstants.respPageAck) {
        final page = msg['page'];
        final pageNumber = page is num ? page.toInt() : 0;
        final completer = pageAcks[pageNumber];
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      if (cmd == BleConstants.respUploadEnd) {
        if (!uploadEnd.isCompleted) {
          uploadEnd.complete(msg);
        }
        return;
      }

      if (cmd == BleConstants.respUploadError) {
        final status = msg['status'] as String? ?? 'session_error';
        if (!uploadEnd.isCompleted) {
          uploadEnd.complete({'status': status});
        }
      }
    });

    try {
      await connection.sendCommand({
        'cmd': BleConstants.cmdUploadStart,
        'data': {
          'name': name,
          'time': time,
          'pages': pages.length,
        },
      });

      final startStatus = await uploadAck.future.timeout(
        BleConstants.uploadStartTimeout,
      );
      if (startStatus != 'ready') {
        throw DocumentTransferException(_uploadStartMessage(startStatus));
      }

      for (int index = 0; index < pages.length; index++) {
        final pageNumber = index + 1;
        onPageStarted?.call(pageNumber, pages.length);

        final ack = Completer<void>();
        pageAcks[pageNumber] = ack;

        final bytes = await File(pages[index].binPath).readAsBytes();
        final chunkSize = math.max(
          20,
          math.min(connection.mtuNow - 3, BleConstants.uploadChunkCeiling),
        );

        for (int offset = 0; offset < bytes.length; offset += chunkSize) {
          final end = math.min(offset + chunkSize, bytes.length);
          await connection.sendData(bytes.sublist(offset, end));
          await Future<void>.delayed(BleConstants.uploadChunkSpacing);
        }

        await ack.future.timeout(BleConstants.uploadPageAckTimeout);
        onPageUploaded?.call(pageNumber, pages.length);
        pageAcks.remove(pageNumber);
      }

      await connection.sendCommand(const {'cmd': BleConstants.cmdUploadEnd});
      final endMessage = await uploadEnd.future.timeout(
        BleConstants.uploadEndTimeout,
      );
      final status = endMessage['status'] as String? ?? 'error';
      if (status != 'ok') {
        throw DocumentTransferException(_uploadEndMessage(status));
      }
    } on TimeoutException catch (e) {
      throw DocumentTransferException('蓝牙传输超时，请保持设备连接稳定。', e);
    } on DocumentTransferException {
      rethrow;
    } on Object catch (e) {
      throw DocumentTransferException('蓝牙传输失败，请稍后重试。', e);
    } finally {
      await sub.cancel();
    }
  }

  String _uploadStartMessage(String status) {
    switch (status) {
      case 'busy':
        return '设备正在处理其他任务，请稍后再试。';
      case 'bad_dir_name':
        return '文档名称不符合设备要求，请修改后重试。';
      case 'sd_error':
        return '设备存储不可用，请检查设备空间后重试。';
      default:
        return '设备拒绝开始传输。';
    }
  }

  String _uploadEndMessage(String status) {
    switch (status) {
      case 'partial':
        return '设备只接收到了部分页面，请重新传输。';
      case 'not_active':
        return '设备上传会话已中断，请重新开始传输。';
      case 'io_error':
        return '设备写入文档失败，请检查设备存储后重试。';
      case 'session_error':
        return '设备在接收页面数据时发生错误。';
      default:
        return '设备未能完成文档传输。';
    }
  }
}
