import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ble/ble_connection.dart';
import '../shared/ble/ble_constants.dart';
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
    this.isOffline = false,
  });

  final BleConnection? connection;
  final DeviceInfo? info;
  final BluetoothConnectionState bluetoothState;
  final bool isOffline;

  ActiveConnection copyWith({
    BleConnection? connection,
    DeviceInfo? info,
    BluetoothConnectionState? bluetoothState,
    bool? isOffline,
  }) {
    return ActiveConnection(
      connection: connection ?? this.connection,
      info: info ?? this.info,
      bluetoothState: bluetoothState ?? this.bluetoothState,
      isOffline: isOffline ?? this.isOffline,
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
  Timer? _refreshTimer;
  String? _activeId;
  PairedDevice? _lastPaired;
  bool _isForeground = true;
  bool _isConnecting = false;

  Future<void> connectTo(PairedDevice paired) =>
      _doConnect(paired, force: false);

  /// Re-connect to the last paired device if currently offline or without
  /// a live connection. Triggered by app foreground / devices-page enter.
  Future<void> reconnectIfOffline() async {
    if (_isConnecting) return;
    final paired = _lastPaired;
    if (paired == null) return;
    final current = state.valueOrNull;
    final needsReconnect =
        current == null || current.isOffline || current.connection == null;
    if (needsReconnect) {
      await _doConnect(paired, force: true);
    }
  }

  /// Pause periodic refresh when app goes background; resume on foreground.
  void setForeground(bool foreground) {
    _isForeground = foreground;
    if (!foreground) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    final current = state.valueOrNull;
    final connected = current != null &&
        !current.isOffline &&
        current.connection != null &&
        current.bluetoothState == BluetoothConnectionState.connected;
    if (connected) {
      _startRefreshTimer();
      unawaited(_tickRefresh());
    }
  }

  Future<void> disconnect() async {
    await _cancel();
    _lastPaired = null;
    state = const AsyncValue.data(ActiveConnection());
  }

  Future<void> _doConnect(PairedDevice paired, {required bool force}) async {
    if (_isConnecting) return;
    if (!force && _activeId == paired.remoteId) return;
    _isConnecting = true;
    try {
      await _cancel();
      _activeId = paired.remoteId;
      _lastPaired = paired;
      _device = BluetoothDevice.fromId(paired.remoteId);

      state = AsyncValue<ActiveConnection>.loading().copyWithPrevious(state);

      _stateSub = _device!.connectionState.listen((s) {
        final current = state.valueOrNull;
        if (current == null) return;
        if (s == BluetoothConnectionState.connected) {
          state = AsyncValue.data(current.copyWith(bluetoothState: s));
        } else {
          // Drop the connection reference so downstream callers don't try
          // to use a stale BleConnection.
          state = AsyncValue.data(ActiveConnection(
            info: current.info,
            bluetoothState: s,
            isOffline: current.isOffline,
          ));
          _refreshTimer?.cancel();
          _refreshTimer = null;
        }
      });

      try {
        final result = await _connectWithRetry(_device!);
        state = AsyncValue.data(ActiveConnection(
          connection: result.connection,
          info: result.info,
          bluetoothState: BluetoothConnectionState.connected,
        ));
        _startRefreshTimer();
        unawaited(
          _ref
              .read(pairedDevicesProvider.notifier)
              .updateCachedInfo(paired.remoteId, result.info),
        );
      } on Object {
        await _stateSub?.cancel();
        _stateSub = null;
        await _ref.read(bleServiceProvider).disconnect();
        try {
          await _device?.disconnect();
        } on Object {
          // best effort
        }
        _device = null;
        // Keep _activeId and _lastPaired so reconnectIfOffline can retry.
        state = const AsyncValue.data(ActiveConnection(isOffline: true));
      }
    } finally {
      _isConnecting = false;
    }
  }

  Future<ConnectResult> _connectWithRetry(BluetoothDevice device) async {
    Object? lastError;
    for (int i = 0; i < BleConstants.connectRetryCount; i++) {
      try {
        return await _ref.read(bleServiceProvider).connectAndQueryInfo(device);
      } on Object catch (e) {
        lastError = e;
        await _ref.read(bleServiceProvider).disconnect();
        try {
          await device.disconnect();
        } on Object {
          // best effort — partial connects need cleanup before retry
        }
        if (i < BleConstants.connectRetryCount - 1) {
          await Future.delayed(BleConstants.connectRetryDelay);
        }
      }
    }
    throw lastError ?? StateError('connect failed');
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      BleConstants.deviceInfoRefreshInterval,
      (_) => _tickRefresh(),
    );
  }

  Future<void> _tickRefresh() async {
    if (!_isForeground) return;
    final conn = state.valueOrNull?.connection;
    if (conn == null) return;
    try {
      final info = await _ref.read(bleServiceProvider).refreshDeviceInfo(conn);
      final current = state.valueOrNull;
      if (current == null) return;
      state = AsyncValue.data(current.copyWith(info: info));
      final paired = _lastPaired;
      if (paired != null) {
        unawaited(
          _ref
              .read(pairedDevicesProvider.notifier)
              .updateCachedInfo(paired.remoteId, info),
        );
      }
    } on Object {
      // best effort — keep current state
    }
  }

  Future<void> _cancel() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
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
    _refreshTimer?.cancel();
    _refreshTimer = null;
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
