import 'package:flutter/material.dart';

import '../../../shared/ble/models.dart';

class DeviceListItem extends StatelessWidget {
  const DeviceListItem({
    required this.device,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final PairedDevice device;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isSelected ? colorScheme.primaryContainer : colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.bluetooth_connected,
                size: 24,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.displayName.isEmpty
                          ? device.remoteId
                          : device.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _buildSubtitle(device.cachedInfo),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.85)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除设备',
                onPressed: onDelete,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildSubtitle(DeviceInfo? info) {
    if (info == null) {
      return '未获取设备信息';
    }
    final parts = <String>[
      '电量 ${info.batteryLevel}%',
      '存储 ${info.storageUsedMb}/${info.storageTotalMb} MB',
    ];
    if (info.firmwareVersion.isNotEmpty) {
      parts.add('固件 v${info.firmwareVersion}');
    }
    return parts.join(' · ');
  }
}
