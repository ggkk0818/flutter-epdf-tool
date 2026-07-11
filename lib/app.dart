import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'shared/ble/models.dart';
import 'state/ble_providers.dart';

class EpdfToolApp extends ConsumerStatefulWidget {
  const EpdfToolApp({super.key});

  @override
  ConsumerState<EpdfToolApp> createState() => _EpdfToolAppState();
}

class _EpdfToolAppState extends ConsumerState<EpdfToolApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final notifier = ref.read(activeConnectionProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      notifier.setForeground(true);
      notifier.reconnectIfOffline();
    } else {
      notifier.setForeground(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PairedDevice?>(currentPairedDeviceProvider, (previous, next) {
      final notifier = ref.read(activeConnectionProvider.notifier);
      if (next == null) {
        if (previous != null) {
          unawaited(notifier.disconnect());
        }
        return;
      }

      final active = ref.read(activeConnectionProvider).valueOrNull;
      final isConnectedToSelection =
          active?.connection?.device.remoteId.str == next.remoteId &&
          active?.bluetoothState == BluetoothConnectionState.connected &&
          active?.isOffline == false;

      if (!isConnectedToSelection) {
        unawaited(notifier.connectTo(next));
      }
    });

    return MaterialApp.router(
      title: 'EPDF Tool',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
      routerConfig: appRouter,
    );
  }
}
