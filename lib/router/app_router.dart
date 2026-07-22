import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/devices/add_device_page.dart';
import '../features/devices/devices_page.dart';
import '../features/devices/ota_update_page.dart';
import '../features/documents/add_document_page.dart';
import '../features/documents/document_detail_page.dart';
import '../features/documents/document_page.dart';
import '../features/documents/document_preview_page.dart';
import '../features/remote/remote_mode_page.dart';
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
    GoRoute(
      path: '/devices/ota',
      name: 'device_ota',
      builder: (BuildContext context, GoRouterState state) {
        final args = state.extra as OtaUpdatePageArgs?;
        if (args == null) {
          return const DevicesPage();
        }
        return OtaUpdatePage(args: args);
      },
    ),
    GoRoute(
      path: '/documents/detail',
      name: 'document_detail',
      builder: (BuildContext context, GoRouterState state) {
        return const DocumentDetailPage();
      },
    ),
    GoRoute(
      path: '/documents/preview',
      name: 'document_preview',
      builder: (BuildContext context, GoRouterState state) {
        final args = state.extra as DocumentPreviewPageArgs?;
        if (args == null) {
          return const DocumentDetailPage();
        }
        return DocumentPreviewPage(args: args);
      },
    ),
    GoRoute(
      path: '/documents/add',
      name: 'add_document',
      builder: (BuildContext context, GoRouterState state) {
        return const AddDocumentPage();
      },
    ),
    GoRoute(
      path: '/remote/mode',
      name: 'remote_mode',
      builder: (BuildContext context, GoRouterState state) {
        return const RemoteModePage();
      },
    ),
  ],
);
