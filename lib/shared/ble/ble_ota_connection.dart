import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_constants.dart';

/// Discovers the OTA service on an already-connected device and exposes the
/// control/data characteristics. Mirrors [BleConnection.establish] but for
/// the OTA service (0xFF00) — separate from the EPDF service used for normal
/// traffic, so the two can be used in parallel without sharing state.
class BleOtaConnection {
  BleOtaConnection._({
    required this.device,
    required this.ctrlCharacteristic,
    required this.dataCharacteristic,
  });

  final BluetoothDevice device;
  final BluetoothCharacteristic ctrlCharacteristic;
  final BluetoothCharacteristic dataCharacteristic;

  StreamSubscription<List<int>>? _ctrlSubscription;

  final StreamController<Uint8List> _ctrlController =
      StreamController<Uint8List>.broadcast();

  /// Raw bytes received from the OTA control characteristic (notify). The
  /// uploader interprets the first byte as a status code.
  Stream<Uint8List> get ctrlNotifications => _ctrlController.stream;

  int get mtuNow => device.mtuNow;

  /// Discover services on [device] and resolve the OTA service + control +
  /// data characteristics. Subscribes to control notifies. Throws if the
  /// service or characteristics are missing.
  static Future<BleOtaConnection> establish(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == BleConstants.otaServiceUuid,
      orElse: () =>
          throw StateError('OTA service not found on device'),
    );

    BluetoothCharacteristic? ctrl;
    BluetoothCharacteristic? data;
    for (final c in service.characteristics) {
      if (c.uuid == BleConstants.otaCtrlCharUuid) {
        ctrl = c;
      } else if (c.uuid == BleConstants.otaDataCharUuid) {
        data = c;
      }
    }
    if (ctrl == null || data == null) {
      throw StateError('OTA characteristics missing');
    }

    if (!ctrl.isNotifying) {
      await ctrl.setNotifyValue(true);
    }

    final connection = BleOtaConnection._(
      device: device,
      ctrlCharacteristic: ctrl,
      dataCharacteristic: data,
    );
    connection._listenCtrl(ctrl);
    return connection;
  }

  void _listenCtrl(BluetoothCharacteristic ctrl) {
    _ctrlSubscription = ctrl.lastValueStream.listen((List<int> chunk) {
      if (chunk.isEmpty) return;
      _ctrlController.add(Uint8List.fromList(chunk));
    });
  }

  Future<void> writeCtrl(Uint8List bytes) async {
    await ctrlCharacteristic.write(bytes, withoutResponse: false);
  }

  /// Send raw firmware bytes on the data characteristic using
  /// write-without-response for throughput. Caller chunks and paces.
  Future<void> writeData(Uint8List bytes) async {
    await dataCharacteristic.write(bytes, withoutResponse: true);
  }

  Future<void> dispose() async {
    await _ctrlSubscription?.cancel();
    _ctrlSubscription = null;
    await _ctrlController.close();
  }
}
