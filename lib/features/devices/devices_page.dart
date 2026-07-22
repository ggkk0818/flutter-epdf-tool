import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/ble_providers.dart';
import '../../shared/ble/models.dart';
import '../../shared/ota/firmware_manifest.dart';
import 'ota_update_page.dart';
import 'widgets/device_list_item.dart';

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  final Set<String> _otaPromptedRemoteIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeConnectionProvider.notifier).reconnectIfOffline();
      ref.listenManual(
        activeConnectionProvider,
        (AsyncValue<ActiveConnection>? prev,
            AsyncValue<ActiveConnection> next) {
          _checkForUpdate(next);
        },
      );
    });
  }

  /// Trigger an OTA-availability check each time the active connection lands
  /// in a connected state with a fresh DeviceInfo. The set above prevents
  /// re-prompting for the same device during the lifetime of this page.
  Future<void> _checkForUpdate(AsyncValue<ActiveConnection> next) async {
    final conn = next.valueOrNull;
    if (conn == null) return;
    if (conn.bluetoothState != BluetoothConnectionState.connected) return;
    if (conn.isOffline) return;
    final info = conn.info;
    if (info == null) return;
    final paired = ref.read(currentPairedDeviceProvider);
    if (paired == null) return;
    if (_otaPromptedRemoteIds.contains(paired.remoteId)) return;

    final manifest = await FirmwareManifest.loadLatest();
    if (manifest == null) return;
    if (info.firmwareVersion.isEmpty) return;
    if (compareSemver(manifest.version, info.firmwareVersion) <= 0) return;

    _otaPromptedRemoteIds.add(paired.remoteId);
    if (!mounted) return;
    _showOtaPrompt(paired, manifest);
  }

  void _showOtaPrompt(
      PairedDevice device, FirmwareManifest manifest) async {
    final displayName = device.displayName.isEmpty
        ? device.remoteId
        : device.displayName;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新固件'),
        content: Text(
          '设备「$displayName」有新固件可用，是否更新？\n'
          '版本号：${manifest.version}\n'
          '更新说明：${manifest.changelog.isEmpty ? "（暂无）" : manifest.changelog}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('更新'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    if (!mounted) return;
    context.push(
      '/devices/ota',
      extra: OtaUpdatePageArgs(
        remoteId: device.remoteId,
        version: manifest.version,
        changelog: manifest.changelog,
        assetPath: manifest.assetPath,
      ),
    );
  }

  Future<void> _onSelectDevice(PairedDevice device) async {
    final notifier = ref.read(currentDeviceIdProvider.notifier);
    final activeNotifier = ref.read(activeConnectionProvider.notifier);
    await notifier.set(device.remoteId);
    await activeNotifier.connectTo(device);
  }

  Future<void> _onDeleteDevice(
    BuildContext context,
    WidgetRef ref,
    PairedDevice device,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除设备'),
        content: Text(
          '确定删除「${device.displayName.isEmpty ? device.remoteId : device.displayName}」吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final currentId = ref.read(currentDeviceIdProvider);
    if (currentId == device.remoteId) {
      await ref.read(activeConnectionProvider.notifier).disconnect();
      await ref.read(currentDeviceIdProvider.notifier).set(null);
    }
    await ref.read(pairedDevicesProvider.notifier).remove(device.remoteId);
    messenger.showSnackBar(const SnackBar(content: Text('已删除设备')));
  }

  @override
  Widget build(BuildContext context) {
    final paired = ref.watch(pairedDevicesProvider);
    final currentId = ref.watch(currentDeviceIdProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/devices/add'),
        tooltip: '添加设备',
        child: const Icon(Icons.add),
      ),
      body: paired.when(
        data: (list) => list.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  indent: 52,
                ),
                itemBuilder: (BuildContext context, int index) {
                  final d = list[index];
                  return DeviceListItem(
                    device: d,
                    isSelected: d.remoteId == currentId,
                    onTap: () => _onSelectDevice(d),
                    onDelete: () => _onDeleteDevice(context, ref, d),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('读取失败: $e')),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bluetooth_searching,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text('还没有添加设备', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '点击右下角 + 添加 EPDF 设备',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
