import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/env_config.dart';
import 'firmware_manifest.dart';

/// Fetches and parses the remote OTA manifest (`data.json`).
///
/// Centralised so that both firmware and (future) app-version checks share
/// one network round-trip and one parsing path. All public methods swallow
/// errors and return `null` — OTA availability is best-effort and must never
/// block the user with an error dialog.
class OtaManifestService {
  OtaManifestService(this._dio);

  final Dio _dio;

  /// GET the raw manifest document. Returns `null` on any failure (network,
  /// HTTP, JSON parse) — callers treat this as "no update info available".
  Future<Map<String, dynamic>?> fetchManifestJson() async {
    try {
      final resp = await _dio.get<dynamic>(
        EnvConfig.dataJsonUrl,
        options: Options(responseType: ResponseType.json),
      );
      final data = resp.data;
      if (data is String) {
        final decoded = jsonDecode(data);
        return decoded is Map<String, dynamic> ? decoded : null;
      }
      if (data is Map<String, dynamic>) return data;
      return null;
    } on Object {
      return null;
    }
  }

  /// Pick the highest firmware version in `client_versions` that is newer
  /// than [currentVersion]. Returns `null` if the manifest is missing or
  /// no candidate beats the current version.
  Future<FirmwareManifest?> fetchLatestFirmware({
    String? currentVersion,
  }) async {
    final json = await fetchManifestJson();
    if (json == null) return null;
    final versions = json['client_versions'];
    if (versions is! List) return null;

    FirmwareManifest? best;
    for (final item in versions) {
      if (item is! Map<String, dynamic>) continue;
      final version = item['version'];
      if (version is! String) continue;
      final manifest = FirmwareManifest(
        version: version,
        releaseDate: (item['release_date'] as String?) ?? '',
        changelog: (item['changelog'] as String?) ?? '',
      );
      if (best == null ||
          compareSemver(manifest.version, best.version) > 0) {
        best = manifest;
      }
    }
    if (best == null) return null;
    if (currentVersion != null &&
        currentVersion.isNotEmpty &&
        compareSemver(best.version, currentVersion) <= 0) {
      return null;
    }
    return best;
  }

  /// Reserved for future app-version checks. Always returns `null` today;
  /// included so call sites can be wired up before the feature ships.
  Future<FirmwareManifest?> fetchLatestApp({
    String? currentVersion,
  }) async {
    final json = await fetchManifestJson();
    if (json == null) return null;
    final versions = json['app_versions'];
    if (versions is! List) return null;

    FirmwareManifest? best;
    for (final item in versions) {
      if (item is! Map<String, dynamic>) continue;
      final version = item['version'];
      if (version is! String) continue;
      final manifest = FirmwareManifest(
        version: version,
        releaseDate: (item['release_date'] as String?) ?? '',
        changelog: (item['changelog'] as String?) ?? '',
      );
      if (best == null ||
          compareSemver(manifest.version, best.version) > 0) {
        best = manifest;
      }
    }
    if (best == null) return null;
    if (currentVersion != null &&
        currentVersion.isNotEmpty &&
        compareSemver(best.version, currentVersion) <= 0) {
      return null;
    }
    return best;
  }
}
