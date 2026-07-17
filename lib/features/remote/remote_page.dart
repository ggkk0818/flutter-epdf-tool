import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../shared/widgets/device_status_chip.dart';
import '../../state/document_providers.dart';

class RemotePage extends ConsumerWidget {
  const RemotePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(documentPageStatusProvider);

    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: DeviceStatusChip(),
        ),
        Expanded(child: _buildBody(context, status)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, DocumentPageStatus status) {
    switch (status) {
      case DocumentPageStatus.connecting:
        return const Center(child: CircularProgressIndicator());
      case DocumentPageStatus.noDevice:
        return _RemotePlaceholder(
          icon: Icons.bluetooth_searching,
          title: '还没有选择设备',
          message: '请先去设备页添加并选择 EPDF 设备',
        );
      case DocumentPageStatus.offline:
        return _RemotePlaceholder(
          icon: Icons.cloud_off,
          title: '设备当前离线',
          message: '请前往设备页重新连接设备后再使用遥控',
        );
      case DocumentPageStatus.ready:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.settings_remote,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '设备已连接',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '进入遥控模式后可在手机上滑动、点按\n来远程翻页与操作阅读器',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/remote/mode'),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('进入遥控模式'),
              ),
            ],
          ),
        );
    }
  }
}

class _RemotePlaceholder extends StatelessWidget {
  const _RemotePlaceholder({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => context.go(AppSection.devices.path),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('前往设备页'),
            ),
          ],
        ),
      ),
    );
  }
}
