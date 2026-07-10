import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/ble_providers.dart';
import '../../shared/ble/models.dart';
import 'widgets/device_list_item.dart';

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    onTap: () => _onSelectDevice(ref, d),
                    onDelete: () => _onDeleteDevice(context, ref, d),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('读取失败: $e')),
      ),
    );
  }

  Future<void> _onSelectDevice(WidgetRef ref, PairedDevice device) async {
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
        content: Text('确定删除「${device.displayName.isEmpty ? device.remoteId : device.displayName}」吗？'),
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
