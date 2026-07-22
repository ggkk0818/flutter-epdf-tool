import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../ble/ble_constants.dart';
import '../ble/ble_ota_connection.dart';
import 'crc32.dart';

/// Progress emitted by [BleOtaUploader.run]. Terminal events have [done]=true;
/// either [success] or a non-null [errorMessage] indicates the final outcome.
class OtaProgress {
  const OtaProgress({
    required this.sent,
    required this.total,
    required this.done,
    this.success = false,
    this.errorMessage,
  });

  final int sent;
  final int total;
  final bool done;
  final bool success;
  final String? errorMessage;

  double get fraction => total <= 0 ? 0 : (sent / total).clamp(0.0, 1.0);
}

enum OtaFailureReason { startRejected, crcMismatch, transport, disconnected }

/// Runs the OTA flow against [connection] using the firmware [bytes]. Emits
/// [OtaProgress] events on the returned stream — intermediate events track
/// bytes-sent, terminal events carry success/failure. The stream closes after
/// the terminal event; the caller should cancel its subscription.
class BleOtaUploader {
  BleOtaUploader(this.connection);

  final BleOtaConnection connection;

  int _sentBytes = 0;
  int _ackedBytes = 0;
  Completer<void>? _windowWaiter;
  Completer<void>? _firstAckWaiter;
  Completer<bool>? _finalWaiter; // true on CRC_OK, false on CRC_FAIL
  int _total = 0;

  StreamController<OtaProgress>? _controller;

  Stream<OtaProgress> run(Uint8List bytes) {
    final controller = StreamController<OtaProgress>();
    _controller = controller;
    _execute(bytes).then((_) {
      if (!controller.isClosed) controller.close();
    });
    return controller.stream;
  }

  Future<void> _execute(Uint8List bytes) async {
    _total = bytes.length;
    final controller = _controller!;

    StreamSubscription<Uint8List>? sub;
    Timer? livenessTimer;
    try {
      sub = connection.ctrlNotifications.listen(_onCtrl);
      // flutter_blue_plus doesn't deliver a notify when the link drops, so
      // poll mtuNow (0 on a dead link) to unblock pending waiters.
      livenessTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _checkLiveness(),
      );

      // 1. START with size, wait for the device's first ack.
      _firstAckWaiter = Completer<void>();
      await connection.writeCtrl(_buildStartPayload(_total));
      await _firstAckWaiter!.future.timeout(
        BleConstants.otaStartAckTimeout,
        onTimeout: () => throw _OtaFailure(
            OtaFailureReason.startRejected, '设备未就绪，未能启动升级。'),
      );

      // 2. Stream with sliding window.
      final chunkSize = math.max(
        20,
        math.min(connection.mtuNow - 3, BleConstants.otaChunkCeiling),
      );
      while (_sentBytes < _total) {
        while (_sentBytes - _ackedBytes >= BleConstants.otaWindowBytes) {
          _windowWaiter = Completer<void>();
          await _windowWaiter!.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw _OtaFailure(OtaFailureReason.transport, '设备应答超时。'),
          );
        }
        final end = math.min(_sentBytes + chunkSize, _total);
        await connection.writeData(Uint8List.sublistView(bytes, _sentBytes, end));
        _sentBytes = end;
        if (!controller.isClosed) {
          controller.add(OtaProgress(
            sent: _sentBytes,
            total: _total,
            done: false,
          ));
        }
        await Future<void>.delayed(BleConstants.otaChunkSpacing);
      }

      // 3. Drain in-flight chunks: wait until the device has written every
      //    queued byte before sending END.
      while (_ackedBytes < _total) {
        _windowWaiter = Completer<void>();
        await _windowWaiter!.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () =>
              throw _OtaFailure(OtaFailureReason.transport, '设备应答超时。'),
        );
      }

      // 4. END with CRC, wait for OK / FAIL.
      _finalWaiter = Completer<bool>();
      await connection.writeCtrl(_buildEndPayload(Crc32.compute(bytes)));
      final ok = await _finalWaiter!.future.timeout(
        BleConstants.otaFinalAckTimeout,
        onTimeout: () => throw _OtaFailure(
            OtaFailureReason.transport, '设备校验超时。'),
      );
      if (!ok) {
        throw _OtaFailure(OtaFailureReason.crcMismatch, '固件校验失败，请重试。');
      }

      // 5. Trigger reboot into the new firmware.
      await connection.writeCtrl(Uint8List.fromList(
          const <int>[BleConstants.otaCmdReboot]));

      if (!controller.isClosed) {
        controller.add(const OtaProgress(
          sent: 0,
          total: 0,
          done: true,
          success: true,
        ));
      }
    } on _OtaFailure catch (e) {
      if (!controller.isClosed) {
        controller.add(OtaProgress(
          sent: _sentBytes,
          total: _total,
          done: true,
          success: false,
          errorMessage: e.message,
        ));
      }
    } on Object catch (e) {
      if (!controller.isClosed) {
        controller.add(OtaProgress(
          sent: _sentBytes,
          total: _total,
          done: true,
          success: false,
          errorMessage: '升级失败：$e',
        ));
      }
    } finally {
      livenessTimer?.cancel();
      await sub?.cancel();
    }
  }

  void _onCtrl(Uint8List data) {
    if (data.isEmpty) return;
    switch (data[0]) {
      case BleConstants.otaStatusAck:
        if (data.length < 5) return;
        _ackedBytes = _readLe32(data, 1);
        // First-ack arrives with acked=0 right after START; release the
        // start-ack waiter.
        if (_firstAckWaiter != null && !_firstAckWaiter!.isCompleted) {
          _firstAckWaiter!.complete();
        }
        // Release any window-waiter — the await loop re-checks the budget
        // and re-waits if still over budget.
        if (_windowWaiter != null && !_windowWaiter!.isCompleted) {
          _windowWaiter!.complete();
        }
        break;
      case BleConstants.otaStatusStartFail:
        final errCode = data.length >= 2 ? data[1] : 0;
        if (_firstAckWaiter != null && !_firstAckWaiter!.isCompleted) {
          _firstAckWaiter!.completeError(_OtaFailure(
            OtaFailureReason.startRejected,
            _startFailMessage(errCode),
          ));
        }
        break;
      case BleConstants.otaStatusCrcFail:
        if (_finalWaiter != null && !_finalWaiter!.isCompleted) {
          _finalWaiter!.complete(false);
        }
        break;
      case BleConstants.otaStatusCrcOk:
        if (_finalWaiter != null && !_finalWaiter!.isCompleted) {
          _finalWaiter!.complete(true);
        }
        break;
    }
  }

  void _checkLiveness() {
    // mtuNow is 0 when the BLE link is gone; unblock any pending waiter so
    // the uploader terminates with a disconnected error instead of stalling.
    if (connection.mtuNow != 0) return;
    final err = _OtaFailure(
      OtaFailureReason.disconnected,
      '蓝牙连接已断开，请保持设备靠近手机后重试。',
    );
    _firstAckWaiter?.completeError(err);
    _windowWaiter?.completeError(err);
    _finalWaiter?.completeError(err);
  }

  String _startFailMessage(int errCode) {
    switch (errCode) {
      case 0x02:
        return '设备存储空间不足，无法升级。';
      case 0x03:
        return '设备写入固件失败。';
      default:
        return '设备拒绝启动升级。';
    }
  }

  static Uint8List _buildStartPayload(int total) {
    final data = Uint8List(5);
    data[0] = BleConstants.otaCmdStart;
    _writeLe32(data, 1, total);
    return data;
  }

  static Uint8List _buildEndPayload(int crc) {
    final data = Uint8List(5);
    data[0] = BleConstants.otaCmdEnd;
    _writeLe32(data, 1, crc);
    return data;
  }

  static void _writeLe32(Uint8List dst, int offset, int value) {
    dst[offset] = value & 0xFF;
    dst[offset + 1] = (value >>> 8) & 0xFF;
    dst[offset + 2] = (value >>> 16) & 0xFF;
    dst[offset + 3] = (value >>> 24) & 0xFF;
  }

  static int _readLe32(Uint8List src, int offset) {
    return (src[offset] & 0xFF) |
        ((src[offset + 1] & 0xFF) << 8) |
        ((src[offset + 2] & 0xFF) << 16) |
        ((src[offset + 3] & 0xFF) << 24);
  }
}

class _OtaFailure implements Exception {
  const _OtaFailure(this.reason, this.message);
  final OtaFailureReason reason;
  final String message;
}
