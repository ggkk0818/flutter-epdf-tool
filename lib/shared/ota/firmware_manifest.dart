import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Describes a firmware bundle shipped in the app's `assets/ota/` directory.
/// `data.json` lists the available versions; the matching `firmware{version}.bin`
/// file sits next to it and is loaded on demand by the OTA uploader.
class FirmwareManifest {
  const FirmwareManifest({
    required this.version,
    required this.releaseDate,
    required this.changelog,
    required this.assetPath,
  });

  /// Semantic version string, e.g. "0.2.0".
  final String version;
  final String releaseDate;
  final String changelog;

  /// Asset key for the binary, e.g. "assets/ota/firmware0.2.0.bin".
  final String assetPath;

  /// Load `assets/ota/data.json`, pick the highest version, resolve its bin
  /// path. Returns null if the manifest is missing or empty so callers can
  /// silently skip the OTA prompt instead of crashing the devices page.
  static Future<FirmwareManifest?> loadLatest() async {
    try {
      final raw = await rootBundle.loadString('assets/ota/data.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final versions = decoded['versions'];
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
          assetPath: 'assets/ota/firmware$version.bin',
        );
        if (best == null ||
            compareSemver(manifest.version, best.version) > 0) {
          best = manifest;
        }
      }
      return best;
    } on Object {
      return null;
    }
  }

  /// Load the firmware binary as bytes. Throws if the asset is missing or
  /// unreadable — callers should surface this as an OTA preparation error.
  Future<Uint8List> loadBytes() async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  }
}

/// Compare two semantic version strings of the form "major.minor.patch".
/// Returns negative if [a] < [b], zero if equal, positive if [a] > [b].
/// Non-numeric segments are treated as 0. Missing segments are treated as 0.
int compareSemver(String a, String b) {
  final sa = a.split('.');
  final sb = b.split('.');
  final maxLen = sa.length > sb.length ? sa.length : sb.length;
  for (int i = 0; i < maxLen; i++) {
    final va = i < sa.length ? _parseInt(sa[i]) : 0;
    final vb = i < sb.length ? _parseInt(sb[i]) : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

int _parseInt(String s) {
  final v = int.tryParse(s);
  return v ?? 0;
}
