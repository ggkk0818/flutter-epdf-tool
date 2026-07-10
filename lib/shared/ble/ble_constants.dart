import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleConstants {
  BleConstants._();

  static final Guid epdfServiceUuid =
      Guid('0000ffe0-0000-1000-8000-00805f9b34fb');
  static final Guid cmdCharUuid =
      Guid('0000ffe1-0000-1000-8000-00805f9b34fb');
  static final Guid dataCharUuid =
      Guid('0000ffe2-0000-1000-8000-00805f9b34fb');

  static const int targetMtu = 512;

  static const String cmdGetDeviceInfo = 'get_device_info';
  static const String respDeviceInfo = 'device_info_resp';

  static const Duration getDeviceInfoTimeout = Duration(seconds: 10);
}
