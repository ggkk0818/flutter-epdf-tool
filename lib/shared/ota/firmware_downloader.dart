import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/env_config.dart';

/// Downloads `firmware{version}.bin` from the OTA bucket to a temporary
/// file, reads it back as bytes for the BLE uploader, and cleans up on
/// completion. The file lives in the OS temp/cache directory so the OS
/// may reclaim it under storage pressure.
class FirmwareDownloader {
  FirmwareDownloader(this._dio);

  final Dio _dio;

  /// Download the firmware for [version] into the temp directory.
  /// [onProgress] receives a fraction in `[0.0, 1.0]` as bytes arrive.
  /// Returns the absolute path to the downloaded file.
  Future<String> download(
    String version, {
    void Function(double fraction)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getTemporaryDirectory();
    final filePath = p.join(dir.path, 'firmware_$version.bin');

    await _dio.download(
      EnvConfig.firmwareUrl(version),
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

  /// Read the downloaded file into memory. Throws if the file is missing
  /// or unreadable — the caller should surface this as an OTA failure.
  Future<Uint8List> readBytes(String filePath) async {
    final file = File(filePath);
    return file.readAsBytes();
  }

  /// Delete the downloaded file. Safe to call when the file is already gone
  /// (e.g. upgrade succeeded then user backed out and re-entered).
  Future<void> cleanup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } on Object {
      // Best-effort cleanup; a lingering temp file in the cache dir is fine.
    }
  }
}
