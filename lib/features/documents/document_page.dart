import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/device_status_chip.dart';
import '../../state/ble_providers.dart';
import '../../state/document_providers.dart';
import 'widgets/document_list_item.dart';

class DocumentPage extends ConsumerStatefulWidget {
  const DocumentPage({super.key});

  @override
  ConsumerState<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends ConsumerState<DocumentPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(documentListProvider.notifier).refresh();
    });
  }

  Future<void> _refresh() async {
    final conn = ref.read(activeConnectionProvider).valueOrNull?.connection;
    if (conn == null) {
      await ref.read(activeConnectionProvider.notifier).reconnectIfOffline();
    }
    await ref.read(documentListProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(documentListProvider);

    return Stack(
      children: [
        Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: DeviceStatusChip(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: asyncList.when(
                  data: (list) => list.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            _EmptyState(),
                          ],
                        )
                      : ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 52,
                          ),
                          itemBuilder: (BuildContext context, int index) {
                            final meta = list[index];
                            return DocumentListItem(
                              document: meta,
                              onTap: () => context.push(
                                '/documents/detail',
                                extra: meta,
                              ),
                            );
                          },
                        ),
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (e, _) => _ErrorState(
                    message: '$e',
                    onRetry: _refresh,
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () => context.push('/documents/add'),
            tooltip: '添加文档',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
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
            Icons.folder_open,
            size: 64,
            color:
                theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text('暂无文档', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '点击右下角 + 添加文档',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning,
            size: 64,
            color: theme.colorScheme.error.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          Text('读取失败: $message', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
