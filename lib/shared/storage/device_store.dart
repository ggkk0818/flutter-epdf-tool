import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../ble/models.dart';

class DeviceStore {
  DeviceStore();

  static const String _kPairedKey = 'epdf.paired_devices';
  static const String _kCurrentIdKey = 'epdf.current_device_id';

  Future<List<PairedDevice>> loadPaired() async {
    final prefs = await SharedPreferences.getInstance();
    return PairedDevice.decodeList(prefs.getString(_kPairedKey) ?? '');
  }

  Future<void> savePaired(List<PairedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPairedKey, PairedDevice.encodeList(devices));
  }

  Future<String?> loadCurrentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCurrentIdKey);
  }

  Future<void> saveCurrentId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kCurrentIdKey);
    } else {
      await prefs.setString(_kCurrentIdKey, id);
    }
  }
}
