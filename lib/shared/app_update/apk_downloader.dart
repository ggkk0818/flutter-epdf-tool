import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/env_config.dart';

/// Downloads `app-release{version}.apk` from the OTA bucket to a temp file
/// for the system installer to consume via `open_filex`. Mirrors
/// [FirmwareDownloader] in shape so call sites stay symmetric.
class ApkDownloader {
  ApkDownloader(this._dio);

  final Dio _dio;

  /// Download the APK for [version] into the temp directory.
  /// [onProgress] receives a fraction in `[0.0, 1.0]` as bytes arrive.
  /// [cancelToken] can be used to abort an in-flight download.
  /// Returns the absolute path to the downloaded file.
  Future<String> download(
    String version, {
    void Function(double fraction)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getTemporaryDirectory();
    final filePath = p.join(dir.path, 'app_release_$version.apk');

    await _dio.download(
      EnvConfig.appApkUrl(version),
      filePath,
      onReceiveProgress: (received, total) {
        if (total <= 0) return;
        final fraction = (received / total).clamp(0.0, 1.0);
        onProgress?.call(fraction);
      },
      cancelToken: cancelToken,
    );
    return filePath;
  }

  /// Delete the downloaded APK. Safe to call when the file is already gone.
  Future<void> cleanup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } on Object {
      // Best-effort; a lingering temp file in the cache dir is fine.
    }
  }
}
