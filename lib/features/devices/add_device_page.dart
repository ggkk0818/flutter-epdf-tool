import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shared/ble/ble_constants.dart';
import '../../shared/ble/ble_service.dart';
import '../../shared/ble/models.dart';
import '../../state/ble_providers.dart';

class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({super.key});

  @override
  ConsumerState<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends ConsumerState<AddDevicePage> {
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanStateSub;
  final Map<String, ScanResult> _results = <String, ScanResult>{};
  bool _scanning = false;
  bool _pairing = false;
  String? _permissionMessage;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanStateSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final ok = await _ensurePermissions();
    if (!ok) return;
    await _startScan();
  }

  Future<bool> _ensurePermissions() async {
    final requests = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];
    if (_needsLegacyLocationPermission) {
      requests.add(Permission.locationWhenInUse);
    }
    final statuses = await requests.request();
    final denied = statuses.entries
        .where((e) => !e.value.isGranted)
        .map((e) => e.key.toString())
        .toList(growable: false);
    if (denied.isEmpty) return true;
    setState(() {
      _permissionMessage = '缺少权限: ${denied.join(', ')}';
    });
    return false;
  }

  bool get _needsLegacyLocationPermission {
    if (!Platform.isAndroid) return false;
    final match = RegExp(
      r'SDK\s+(\d+)',
    ).firstMatch(Platform.operatingSystemVersion);
    final sdkInt = int.tryParse(match?.group(1) ?? '');
    return sdkInt != null && sdkInt <= 30;
  }

  Future<bool> _ensureAdapterReady() async {
    if (!await FlutterBluePlus.isSupported) {
      if (mounted) {
        setState(() {
          _permissionMessage = '当前设备不支持蓝牙';
        });
      }
      return false;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState == BluetoothAdapterState.on) {
      return true;
    }

    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
      } on Object {
        // Fall through to the state wait below.
      }
    }

    try {
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 10));
      return true;
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _permissionMessage = '请先开启手机蓝牙';
        });
      }
      return false;
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _permissionMessage = '蓝牙不可用: $e';
        });
      }
      return false;
    }
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    final adapterReady = await _ensureAdapterReady();
    if (!adapterReady) return;

    await _scanSub?.cancel();
    _scanSub = null;
    _scanStateSub ??= FlutterBluePlus.isScanning.distinct().listen((scanning) {
      if (!mounted) return;
      setState(() {
        _scanning = scanning;
      });
    });

    setState(() {
      _scanning = true;
      _results.clear();
      _permissionMessage = null;
    });
    _scanSub = FlutterBluePlus.onScanResults.listen(
      (List<ScanResult> results) {
        for (final r in results) {
          _results[r.device.remoteId.str] = r;
        }
        if (mounted) {
          setState(() {});
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _permissionMessage = '扫描失败: $e';
          _scanning = false;
        });
      },
    );
    try {
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(
        withServices: [BleConstants.epdfServiceUuid],
        timeout: const Duration(seconds: 10),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionMessage = '扫描失败: $e';
        _scanning = false;
      });
    }
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
    if (mounted) {
      setState(() {
        _scanning = false;
      });
    }
  }

  Future<void> _onTapDevice(ScanResult result) async {
    if (_pairing) return;
    final messenger = ScaffoldMessenger.of(context);
    await _stopScan();
    setState(() => _pairing = true);

    final device = result.device;
    final BleService bleService = ref.read(bleServiceProvider);

    try {
      final connectResult = await bleService.connectAndQueryInfo(device);
      final paired = PairedDevice(
        remoteId: device.remoteId.str,
        displayName: connectResult.info.deviceName.isEmpty
            ? (device.platformName.isNotEmpty
                  ? device.platformName
                  : device.remoteId.str)
            : connectResult.info.deviceName,
        pairedAt: DateTime.now().millisecondsSinceEpoch,
        cachedInfo: connectResult.info,
      );
      await ref.read(pairedDevicesProvider.notifier).addOrReplace(paired);
      await ref.read(currentDeviceIdProvider.notifier).set(paired.remoteId);
      await ref.read(activeConnectionProvider.notifier).connectTo(paired);
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('添加成功')));
        context.pop();
      }
    } on Object catch (e) {
      await bleService.disconnect();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('配对失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _pairing = false);
        if (!_scanning) {
          _startScan();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _results.values.toList(growable: false)
      ..sort((a, b) {
        final ra = a.rssi;
        final rb = b.rssi;
        return rb.compareTo(ra);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加设备'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _pairing ? null : () => context.pop(),
        ),
      ),
      body: _pairing
          ? const _PairingIndicator()
          : _permissionMessage != null
          ? _MessageState(
              message: _permissionMessage!,
              actionLabel: '重试',
              onAction: _bootstrap,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      if (_scanning)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      Text(
                        _scanning ? '正在扫描 EPDF 设备…' : '已发现 ${list.length} 个设备',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _scanning ? null : _startScan,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重新扫描'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: list.isEmpty
                      ? const _MessageState(message: '未发现 EPDF 设备\n请确认设备已开机')
                      : ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                          ),
                          itemBuilder: (BuildContext context, int index) {
                            final r = list[index];
                            final name = r.device.platformName;
                            return ListTile(
                              leading: const Icon(Icons.bluetooth),
                              title: Text(
                                name.isEmpty ? r.device.remoteId.str : name,
                              ),
                              subtitle: Text(
                                '${r.device.remoteId.str} · RSSI ${r.rssi}',
                              ),
                              onTap: () => _onTapDevice(r),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _PairingIndicator extends StatelessWidget {
  const _PairingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('正在配对并获取设备信息…', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            '请保持设备开启',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
