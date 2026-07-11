import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
}
