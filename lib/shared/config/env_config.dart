import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Accessor for values loaded from `assets/env/.env.prod` or `.env.local`.
///
/// `.env.local` overrides `.env.prod` at runtime when present; both are
/// declared via the `assets/env/` directory in `pubspec.yaml`. Use this
/// class instead of reading `dotenv` directly so URLs stay in one place.
class EnvConfig {
  const EnvConfig._();

  /// Fallback when `OTA_BASE_URL` is missing or empty (e.g. dotenv failed
  /// to load). Matches the production OSS endpoint so OTA still works.
  static const String _defaultBaseUrl = '';

  static String get baseUrl {
    final raw = dotenv.env['OTA_BASE_URL'];
    if (raw == null || raw.isEmpty) return _defaultBaseUrl;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static String get dataJsonUrl => '$baseUrl/data.json';

  static String firmwareUrl(String version) => '$baseUrl/firmware$version.bin';
}
