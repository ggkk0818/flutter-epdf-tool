import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ble/ble_connection.dart';
import '../shared/ble/ble_service.dart';
import '../shared/ble/models.dart';
import '../shared/storage/device_store.dart';

final deviceStoreProvider = Provider<DeviceStore>((ref) {
  return DeviceStore();
});

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(service.disconnect);
  return service;
});

class PairedDevicesNotifier
    extends StateNotifier<AsyncValue<List<PairedDevice>>> {
  PairedDevicesNotifier(this._store) : super(const AsyncValue.loading()) {
    _init();
  }

  final DeviceStore _store;

  Future<void> _init() async {
    try {
      state = AsyncValue.data(await _store.loadPaired());
    } on Object catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addOrReplace(PairedDevice device) async {
    final current = state.valueOrNull ?? const <PairedDevice>[];
    final next = [...current];
    final idx = next.indexWhere((d) => d.remoteId == device.remoteId);
    if (idx >= 0) {
      next[idx] = device;
    } else {
      next.add(device);
    }
    state = AsyncValue.data(next);
    await _store.savePaired(next);
  }

  Future<void> updateCachedInfo(String remoteId, DeviceInfo info) async {
    final current = state.valueOrNull ?? const <PairedDevice>[];
    final next = [...current];
    final idx = next.indexWhere((d) => d.remoteId == remoteId);
    if (idx >= 0) {
      next[idx] = next[idx].copyWith(cachedInfo: info);
      state = AsyncValue.data(next);
      await _store.savePaired(next);
    }
  }

  Future<void> remove(String remoteId) async {
    final current = state.valueOrNull ?? const <PairedDevice>[];
    final next = current.where((d) => d.remoteId != remoteId).toList();
    state = AsyncValue.data(next);
    await _store.savePaired(next);
  }
}

final pairedDevicesProvider = StateNotifierProvider<PairedDevicesNotifier,
    AsyncValue<List<PairedDevice>>>((ref) {
  return PairedDevicesNotifier(ref.watch(deviceStoreProvider));
});

class CurrentDeviceNotifier extends StateNotifier<String?> {
  CurrentDeviceNotifier(this._store) : super(null) {
    _init();
  }

  final DeviceStore _store;

  Future<void> _init() async {
    state = await _store.loadCurrentId();
  }

  Future<void> set(String? id) async {
    state = id;
    await _store.saveCurrentId(id);
  }
}

final currentDeviceIdProvider =
    StateNotifierProvider<CurrentDeviceNotifier, String?>((ref) {
  return CurrentDeviceNotifier(ref.watch(deviceStoreProvider));
});

/// Live connection state of the active device. Auto-(re)connects when
/// currentDeviceId changes. Exposes the [DeviceInfo] obtained at connect.
class ActiveConnection {
  const ActiveConnection({
    this.connection,
    this.info,
    this.bluetoothState = BluetoothConnectionState.disconnected,
  });

  final BleConnection? connection;
  final DeviceInfo? info;
  final BluetoothConnectionState bluetoothState;

  ActiveConnection copyWith({
    BleConnection? connection,
    DeviceInfo? info,
    BluetoothConnectionState? bluetoothState,
  }) {
    return ActiveConnection(
      connection: connection ?? this.connection,
      info: info ?? this.info,
      bluetoothState: bluetoothState ?? this.bluetoothState,
    );
  }
}

class ActiveConnectionNotifier
    extends StateNotifier<AsyncValue<ActiveConnection>> {
  ActiveConnectionNotifier(this._ref)
      : super(const AsyncValue.data(ActiveConnection()));

  final Ref _ref;

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  String? _activeId;

  Future<void> connectTo(PairedDevice paired) async {
    if (_activeId == paired.remoteId) return;
    await _cancel();
    _activeId = paired.remoteId;

    state = AsyncValue<ActiveConnection>.loading().copyWithPrevious(state);

    final device = BluetoothDevice.fromId(paired.remoteId);
    _device = device;
    _stateSub = device.connectionState.listen((s) {
      final current = state.valueOrNull;
      if (current == null) return;
      state = AsyncValue.data(current.copyWith(bluetoothState: s));
    });

    try {
      final result =
          await _ref.read(bleServiceProvider).connectAndQueryInfo(device);
      final next = ActiveConnection(
        connection: result.connection,
        info: result.info,
        bluetoothState: device.isConnected
            ? BluetoothConnectionState.connected
            : BluetoothConnectionState.disconnected,
      );
      state = AsyncValue.data(next);
      unawaited(
        _ref
            .read(pairedDevicesProvider.notifier)
            .updateCachedInfo(paired.remoteId, result.info),
      );
    } on Object catch (e, st) {
      state = AsyncValue.error(e, st);
      await _ref.read(bleServiceProvider).disconnect();
      _device = null;
      _activeId = null;
    }
  }

  Future<void> disconnect() async {
    await _cancel();
    state = const AsyncValue.data(ActiveConnection());
  }

  Future<void> _cancel() async {
    await _stateSub?.cancel();
    _stateSub = null;
    if (_device != null) {
      await _ref.read(bleServiceProvider).disconnect();
    }
    _device = null;
    _activeId = null;
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }
}

final activeConnectionProvider = StateNotifierProvider<ActiveConnectionNotifier,
    AsyncValue<ActiveConnection>>((ref) {
  return ActiveConnectionNotifier(ref);
});

/// Resolve the active paired device based on currentDeviceId.
final currentPairedDeviceProvider = Provider<PairedDevice?>((ref) {
  final id = ref.watch(currentDeviceIdProvider);
  final list = ref.watch(pairedDevicesProvider).valueOrNull ?? const [];
  if (id == null) return null;
  for (final d in list) {
    if (d.remoteId == id) return d;
  }
  return null;
});

/// Transmission progress for bulk data (file upload etc.). Null when idle.
final transmissionProgressProvider = StateProvider<int?>((ref) => null);
