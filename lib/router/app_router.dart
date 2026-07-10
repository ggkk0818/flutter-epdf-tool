import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/devices/add_device_page.dart';
import '../features/devices/devices_page.dart';
import '../features/documents/document_page.dart';
import '../features/remote/remote_page.dart';
import '../shared/widgets/app_shell.dart';

enum AppSection {
  document('/documents', '文档', Icons.description_outlined),
  remote('/remote', '遥控', Icons.settings_remote_outlined),
  devices('/devices', '设备', Icons.bluetooth_searching_outlined);

  const AppSection(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppSection.document.path,
  routes: <RouteBase>[
    ShellRoute(
      builder: (BuildContext context, GoRouterState state, Widget child) {
        return AppShell(currentLocation: state.uri.path, child: child);
      },
      routes: <RouteBase>[
        GoRoute(
          path: AppSection.document.path,
          name: 'documents',
          builder: (BuildContext context, GoRouterState state) {
            return const DocumentPage();
          },
        ),
        GoRoute(
          path: AppSection.remote.path,
          name: 'remote',
          builder: (BuildContext context, GoRouterState state) {
            return const RemotePage();
          },
        ),
        GoRoute(
          path: AppSection.devices.path,
          name: 'devices',
          builder: (BuildContext context, GoRouterState state) {
            return const DevicesPage();
          },
        ),
      ],
    ),
    GoRoute(
      path: '/devices/add',
      name: 'add_device',
      builder: (BuildContext context, GoRouterState state) {
        return const AddDevicePage();
      },
    ),
  ],
);
