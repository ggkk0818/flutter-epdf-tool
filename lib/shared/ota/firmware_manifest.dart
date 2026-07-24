/// Describes a firmware release listed in the remote OTA manifest
/// (`data.json` on the OSS bucket). The matching `firmware{version}.bin`
/// sits next to it and is downloaded on demand by [FirmwareDownloader].
class FirmwareManifest {
  const FirmwareManifest({
    required this.version,
    required this.releaseDate,
    required this.changelog,
  });

  /// Semantic version string, e.g. "0.3.0".
  final String version;
  final String releaseDate;
  final String changelog;
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
