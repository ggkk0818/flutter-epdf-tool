import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/ble_providers.dart';

class DeviceStatusChip extends ConsumerWidget {
  const DeviceStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeConn = ref.watch(activeConnectionProvider);
    final paired = ref.watch(currentPairedDeviceProvider);

    String label;
    Color? bg;
    Color? fg;
    IconData icon = Icons.bluetooth;
    void onTap() => context.go('/devices');

    if (paired == null) {
      label = '未选择设备';
    } else {
      final connState = activeConn.valueOrNull?.bluetoothState;
      final connected = activeConn.hasValue &&
          connState == BluetoothConnectionState.connected;
      final info = activeConn.valueOrNull?.info ?? paired.cachedInfo;
      if (info != null && connected) {
        label =
            '${info.deviceName.isEmpty ? paired.displayName : info.deviceName} · '
            '电量 ${info.batteryLevel}% · '
            '${info.storageUsedMb}/${info.storageTotalMb} MB';
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        icon = Icons.bluetooth_connected;
      } else if (activeConn.isLoading) {
        label = '正在连接 ${paired.displayName}…';
        icon = Icons.bluetooth_searching;
      } else {
        label = '${paired.displayName}（未连接）';
        icon = Icons.bluetooth_disabled;
        fg = colorScheme.error;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: bg ?? colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg ?? colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg ?? colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: fg ?? colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
