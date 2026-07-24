import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ota/firmware_downloader.dart';
import '../shared/ota/ota_manifest_service.dart';

/// App-wide Dio instance. Configure timeouts once; per-request overrides
/// can use `Options(sendTimeout: ...)` etc.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 15),
  ));
  ref.onDispose(dio.close);
  return dio;
});

final otaManifestServiceProvider = Provider<OtaManifestService>((ref) {
  return OtaManifestService(ref.watch(dioProvider));
});

final firmwareDownloaderProvider = Provider<FirmwareDownloader>((ref) {
  return FirmwareDownloader(ref.watch(dioProvider));
});
