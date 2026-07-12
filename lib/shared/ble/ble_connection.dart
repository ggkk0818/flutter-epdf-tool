import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_constants.dart';
import 'ble_protocol.dart';

/// Single active BLE connection to an EPDF device. Owns the cmd/data
/// characteristics and exposes a JSON-line stream for cmd notifies plus
/// helpers for sending commands (reliable) and bulk data (without response).
class BleConnection {
  BleConnection._({
    required this.device,
    required this.cmdCharacteristic,
    required this.dataCharacteristic,
  });

  final BluetoothDevice device;
  final BluetoothCharacteristic cmdCharacteristic;
  final BluetoothCharacteristic dataCharacteristic;

  final LineBuffer _lineBuffer = LineBuffer();
  final StreamController<Map<String, dynamic>> _cmdController =
      StreamController<Map<String, dynamic>>.broadcast();
    final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<List<int>>? _cmdSubscription;
    StreamSubscription<List<int>>? _dataSubscription;

  Stream<Map<String, dynamic>> get cmdMessages => _cmdController.stream;
    Stream<Uint8List> get dataPackets => _dataController.stream;

  int get mtuNow => device.mtuNow;

  static Future<BleConnection> establish(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == BleConstants.epdfServiceUuid,
      orElse: () => throw StateError('EPDF service not found'),
    );

    BluetoothCharacteristic? cmd;
    BluetoothCharacteristic? data;
    for (final c in service.characteristics) {
      if (c.uuid == BleConstants.cmdCharUuid) {
        cmd = c;
      } else if (c.uuid == BleConstants.dataCharUuid) {
        data = c;
      }
    }
    if (cmd == null || data == null) {
      throw StateError('EPDF characteristics missing');
    }

    if (!cmd.isNotifying) {
      await cmd.setNotifyValue(true);
    }
    if (!data.isNotifying) {
      await data.setNotifyValue(true);
    }

    final connection = BleConnection._(
      device: device,
      cmdCharacteristic: cmd,
      dataCharacteristic: data,
    );
    connection._listenCmd(cmd);
    connection._listenData(data);
    return connection;
  }

  void _listenCmd(BluetoothCharacteristic cmd) {
    _cmdSubscription = cmd.lastValueStream.listen((List<int> chunk) {
      if (chunk.isEmpty) return;
      _lineBuffer.add(chunk);
      for (final line in _lineBuffer.drain()) {
        final msg = BleCommand.decode(line);
        if (msg != null) {
          _cmdController.add(msg);
        }
      }
    });
  }

  void _listenData(BluetoothCharacteristic data) {
    _dataSubscription = data.lastValueStream.listen((List<int> chunk) {
      if (chunk.isEmpty) return;
      _dataController.add(Uint8List.fromList(chunk));
    });
  }

  Future<void> sendCommand(Map<String, dynamic> payload) async {
    final bytes = BleCommand.encode(payload);
    await cmdCharacteristic.write(bytes, withoutResponse: false);
  }

  /// Send raw bytes on the data characteristic using write-without-response
  /// for throughput. Caller is responsible for chunking and pacing.
  Future<void> sendData(Uint8List bytes) async {
    await dataCharacteristic.write(bytes, withoutResponse: true);
  }

  Future<void> dispose() async {
    await _cmdSubscription?.cancel();
    _cmdSubscription = null;
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    await _cmdController.close();
    await _dataController.close();
    _lineBuffer.clear();
  }
}
