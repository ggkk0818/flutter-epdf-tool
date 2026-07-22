import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleConstants {
  BleConstants._();

  static final Guid epdfServiceUuid =
      Guid('0000ffe0-0000-1000-8000-00805f9b34fb');
  static final Guid cmdCharUuid =
      Guid('0000ffe1-0000-1000-8000-00805f9b34fb');
  static final Guid dataCharUuid =
      Guid('0000ffe2-0000-1000-8000-00805f9b34fb');

  // OTA service — separate from EPDF service so OTA traffic does not collide
  // with the JSON cmd protocol or PDF data stream.
  static final Guid otaServiceUuid =
      Guid('0000ff00-0000-1000-8000-00805f9b34fb');
  static final Guid otaCtrlCharUuid =
      Guid('0000ff01-0000-1000-8000-00805f9b34fb');
  static final Guid otaDataCharUuid =
      Guid('0000ff02-0000-1000-8000-00805f9b34fb');

  // OTA protocol bytes — must match cfg::ota in Config.h on the ESP32 side.
  static const int otaCmdStart = 0x01;
  static const int otaCmdPause = 0x02;
  static const int otaCmdResume = 0x03;
  static const int otaCmdEnd = 0x04;
  static const int otaCmdReboot = 0x05;

  static const int otaStatusAck = 0x10;
  static const int otaStatusStartFail = 0x11;
  static const int otaStatusCrcFail = 0x12;
  static const int otaStatusCrcOk = 0x13;

  // Sliding-window flow control. Phone keeps up to otaWindowBytes in flight;
  // ESP32 acks every otaAckIntervalBytes written. Tuned for ~30-50 KB/s on a
  // 512-byte MTU with 2M PHY.
  static const int otaWindowBytes = 16 * 1024;
  static const int otaAckIntervalBytes = 4096;
  static const int otaChunkCeiling = 180;

  static const Duration otaStartAckTimeout = Duration(seconds: 10);
  static const Duration otaFinalAckTimeout = Duration(seconds: 30);
  static const Duration otaChunkSpacing = Duration(milliseconds: 4);

  static const int targetMtu = 512;

  static const String cmdGetDeviceInfo = 'get_device_info';
  static const String respDeviceInfo = 'device_info_resp';

  static const String cmdGetList = 'get_list';
  static const String respList = 'list_resp';

  static const String cmdDelete = 'delete';
  static const String respDelete = 'delete_resp';

  static const String cmdPreview = 'preview';
  static const String respPreviewEnd = 'preview_end';
  static const String respPreviewError = 'preview_error';

  static const String cmdViewOnDevice = 'view_on_device';
  static const String respViewOnDevice = 'view_on_device_resp';

  static const String cmdUploadStart = 'upload_start';
  static const String respUploadAck = 'upload_ack';
  static const String respUploadError = 'upload_error';
  static const String respPageAck = 'page_ack';
  static const String cmdUploadEnd = 'upload_end';
  static const String respUploadEnd = 'upload_end_resp';

  static const String cmdInputEvent = 'input_event';
  static const String respInputEvent = 'input_event_resp';

  // Event names sent inside input_event.data.event and echoed back in the resp.
  static const String inputEventEnter = 'enter';
  static const String inputEventBack = 'back';
  static const String inputEventUpLeft = 'up_left';
  static const String inputEventDownRight = 'down_right';

  static const Duration getDeviceInfoTimeout = Duration(seconds: 10);
  static const Duration getListTimeout = Duration(seconds: 10);
  static const Duration deleteTimeout = Duration(seconds: 10);
  static const Duration previewTimeout = Duration(seconds: 20);
  static const Duration viewOnDeviceTimeout = Duration(seconds: 10);
  static const Duration uploadStartTimeout = Duration(seconds: 10);
  static const Duration uploadPageAckTimeout = Duration(seconds: 20);
  static const Duration uploadEndTimeout = Duration(seconds: 15);
  static const Duration uploadChunkSpacing = Duration(milliseconds: 6);
  static const Duration inputEventTimeout = Duration(seconds: 2);

  static const int uploadChunkCeiling = 180;

  static const int connectRetryCount = 3;
  static const Duration connectRetryDelay = Duration(milliseconds: 500);

  static const Duration deviceInfoRefreshInterval = Duration(minutes: 1);
}
