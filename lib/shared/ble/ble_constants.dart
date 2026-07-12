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

  static const String cmdGetList = 'get_list';
  static const String respList = 'list_resp';

  static const String cmdDelete = 'delete';
  static const String respDelete = 'delete_resp';

  static const String cmdPreview = 'preview';
  static const String respPreviewEnd = 'preview_end';
  static const String respPreviewError = 'preview_error';

  static const String cmdUploadStart = 'upload_start';
  static const String respUploadAck = 'upload_ack';
  static const String respUploadError = 'upload_error';
  static const String respPageAck = 'page_ack';
  static const String cmdUploadEnd = 'upload_end';
  static const String respUploadEnd = 'upload_end_resp';

  static const Duration getDeviceInfoTimeout = Duration(seconds: 10);
  static const Duration getListTimeout = Duration(seconds: 10);
  static const Duration deleteTimeout = Duration(seconds: 10);
  static const Duration previewTimeout = Duration(seconds: 20);
  static const Duration uploadStartTimeout = Duration(seconds: 10);
  static const Duration uploadPageAckTimeout = Duration(seconds: 20);
  static const Duration uploadEndTimeout = Duration(seconds: 15);
  static const Duration uploadChunkSpacing = Duration(milliseconds: 6);

  static const int uploadChunkCeiling = 180;

  static const int connectRetryCount = 3;
  static const Duration connectRetryDelay = Duration(milliseconds: 500);

  static const Duration deviceInfoRefreshInterval = Duration(minutes: 1);
}
