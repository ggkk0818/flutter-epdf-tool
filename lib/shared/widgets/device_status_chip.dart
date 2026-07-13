import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../storage/storage_display.dart';
import '../../state/ble_providers.dart';

class DeviceStatusChip extends ConsumerWidget {
  const DeviceStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeConn = ref.watch(activeConnectionProvider);
    final paired = ref.watch(currentPairedDeviceProvider);

    String? label;
    String? connectedDeviceName;
    int? batteryLevel;
    String? storageUsage;
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
        connectedDeviceName =
            info.deviceName.isEmpty ? paired.displayName : info.deviceName;
        batteryLevel = info.batteryLevel;
        storageUsage = formatStorageUsage(
          info.storageUsedMb,
          info.storageTotalMb,
        );
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        icon = Icons.bluetooth_connected;
      } else if (activeConn.valueOrNull?.isOffline == true) {
        label = '${paired.displayName}（离线）';
        icon = Icons.cloud_off;
        fg = colorScheme.error;
      } else if (activeConn.isLoading) {
        label = '正在连接 ${paired.displayName}…';
        icon = Icons.bluetooth_searching;
      } else {
        label = '${paired.displayName}（未连接）';
        icon = Icons.bluetooth_disabled;
        fg = colorScheme.error;
      }
    }

    final foreground = fg ?? colorScheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: foreground,
    );

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
            child: SizedBox(
              width: double.infinity,
              child: Row(
                children: [
                  Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: 6),
                  Expanded(
                    child: connectedDeviceName != null &&
                            batteryLevel != null &&
                            storageUsage != null
                        ? Row(
                            children: [
                              Expanded(
                                child: Text(
                                  connectedDeviceName,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusMetrics(
                                batteryLevel: batteryLevel,
                                storageUsage: storageUsage,
                                color: foreground,
                                textStyle: labelStyle,
                              ),
                            ],
                          )
                        : Text(
                            label ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle,
                          ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: foreground,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusMetrics extends StatelessWidget {
  const _StatusMetrics({
    required this.batteryLevel,
    required this.storageUsage,
    required this.color,
    required this.textStyle,
  });

  final int batteryLevel;
  final String storageUsage;
  final Color color;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: textStyle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.battery_std, size: 14, color: color),
          const SizedBox(width: 2),
          Text('$batteryLevel%'),
          const SizedBox(width: 8),
          Icon(Icons.sd_storage, size: 14, color: color),
          const SizedBox(width: 2),
          Text(storageUsage),
        ],
      ),
    );
  }
}
