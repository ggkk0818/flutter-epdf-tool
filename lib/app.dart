import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
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
