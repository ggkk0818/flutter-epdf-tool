import 'dart:convert';

class DeviceInfo {
  const DeviceInfo({
    required this.deviceName,
    required this.firmwareVersion,
    required this.batteryLevel,
    required this.batteryCharging,
    required this.screenWidth,
    required this.screenHeight,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.storageTotalMb,
    required this.storageUsedMb,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceName: (json['device_name'] as String?) ?? '',
      firmwareVersion: (json['firmware_version'] as String?) ?? '',
      batteryLevel: _readInt(json, 'battery_level'),
      batteryCharging: (json['battery_charging'] as bool?) ?? false,
      screenWidth: _readInt(json, 'screen_width'),
      screenHeight: _readInt(json, 'screen_height'),
      viewportWidth: _readInt(json, 'viewport_width'),
      viewportHeight: _readInt(json, 'viewport_height'),
      storageTotalMb: _readInt(json, 'storage_total_mb'),
      storageUsedMb: _readInt(json, 'storage_used_mb'),
    );
  }

  final String deviceName;
  final String firmwareVersion;
  final int batteryLevel;
  final bool batteryCharging;
  final int screenWidth;
  final int screenHeight;
  final int viewportWidth;
  final int viewportHeight;
  final int storageTotalMb;
  final int storageUsedMb;

  Map<String, dynamic> toJson() => {
        'device_name': deviceName,
        'firmware_version': firmwareVersion,
        'battery_level': batteryLevel,
        'battery_charging': batteryCharging,
        'screen_width': screenWidth,
        'screen_height': screenHeight,
        'viewport_width': viewportWidth,
        'viewport_height': viewportHeight,
        'storage_total_mb': storageTotalMb,
        'storage_used_mb': storageUsedMb,
      };

  static int _readInt(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}

class DocumentMeta {
  const DocumentMeta({
    required this.name,
    required this.time,
    required this.pages,
  });

  factory DocumentMeta.fromJson(Map<String, dynamic> json) {
    return DocumentMeta(
      name: (json['name'] as String?) ?? '',
      time: (json['time'] as String?) ?? '',
      pages: _readInt(json, 'pages'),
    );
  }

  final String name;
  final String time;
  final int pages;

  Map<String, dynamic> toJson() => {
        'name': name,
        'time': time,
        'pages': pages,
      };

  static int _readInt(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}

class PairedDevice {
  const PairedDevice({
    required this.remoteId,
    required this.displayName,
    required this.pairedAt,
    this.cachedInfo,
  });

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    final info = json['cached_info'];
    return PairedDevice(
      remoteId: (json['remote_id'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      pairedAt: (json['paired_at'] as int?) ?? 0,
      cachedInfo: info is Map<String, dynamic>
          ? DeviceInfo.fromJson(info)
          : null,
    );
  }

  final String remoteId;
  final String displayName;
  final int pairedAt;
  final DeviceInfo? cachedInfo;

  PairedDevice copyWith({DeviceInfo? cachedInfo}) {
    return PairedDevice(
      remoteId: remoteId,
      displayName: displayName,
      pairedAt: pairedAt,
      cachedInfo: cachedInfo ?? this.cachedInfo,
    );
  }

  Map<String, dynamic> toJson() => {
        'remote_id': remoteId,
        'display_name': displayName,
        'paired_at': pairedAt,
        if (cachedInfo != null) 'cached_info': cachedInfo!.toJson(),
      };

  static String encodeList(List<PairedDevice> devices) {
    return jsonEncode(devices.map((d) => d.toJson()).toList());
  }

  static List<PairedDevice> decodeList(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(PairedDevice.fromJson)
            .toList(growable: false);
      }
    } on Object {
      // fall through
    }
    return const [];
  }
}
