import 'package:flutter/material.dart';

import 'router/app_router.dart';

class EpdfToolApp extends StatelessWidget {
  const EpdfToolApp({super.key});

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