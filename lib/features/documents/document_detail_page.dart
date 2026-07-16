import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../shared/ble/models.dart';
import '../../state/document_detail_providers.dart';
import '../../state/document_upload_providers.dart';
import 'document_preview_page.dart';

class DocumentDetailPage extends ConsumerWidget {
  const DocumentDetailPage({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    DocumentMeta meta,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除文档'),
          content: Text('确认删除“${meta.name}”吗？该操作会同时清理本地缓存。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(documentDetailControllerProvider.notifier)
          .deleteDocument(meta);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('文档已删除')));
      context.pop();
    } on Object catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showPageActions(
    BuildContext context,
    WidgetRef ref,
    DocumentMeta meta,
    int pageIndex,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.zoom_out_map_outlined),
                title: const Text('预览'),
                onTap: () async {
                  Navigator.of(bottomSheetContext).pop();
                  await _openPreview(context, ref, meta, pageIndex);
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new_outlined),
                title: const Text('在设备上打开'),
                onTap: () {
                  Navigator.of(bottomSheetContext).pop();
                  _openOnDevice(context, ref, meta, pageIndex);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPreview(
    BuildContext context,
    WidgetRef ref,
    DocumentMeta meta,
    int pageIndex,
  ) async {
    try {
      await ref
          .read(documentDetailControllerProvider.notifier)
          .ensurePreviewPageCached(meta: meta, pageIndex: pageIndex);
      if (!context.mounted) {
        return;
      }
      context.push(
        '/documents/preview',
        extra: DocumentPreviewPageArgs(meta: meta, initialPage: pageIndex),
      );
    } on Object catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openOnDevice(
    BuildContext context,
    WidgetRef ref,
    DocumentMeta meta,
    int pageIndex,
  ) async {
    try {
      await ref
          .read(documentDetailControllerProvider.notifier)
          .viewOnDevice(meta: meta, pageIndex: pageIndex);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已在设备上打开')),
      );
    } on Object catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Map<int, String> _buildCachedPageMap(List<String> paths) {
    final map = <int, String>{};
    for (final path in paths) {
      final name = p.basenameWithoutExtension(path);
      final match = RegExp(r'page_(\d+)$').firstMatch(name);
      if (match == null) {
        continue;
      }
      final page = int.tryParse(match.group(1) ?? '');
      if (page == null || page <= 0) {
        continue;
      }
      map[page - 1] = path;
    }
    return map;
  }

  Widget _buildPageTile({
    required BuildContext context,
    required ThemeData theme,
    required int index,
    required String? cachedPath,
    required VoidCallback? onTap,
    required VoidCallback? onLongPress,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: cachedPath == null
                    ? Icon(
                        Icons.description_outlined,
                        size: 48,
                        color: theme.colorScheme.primary,
                      )
                    : Image.file(File(cachedPath), fit: BoxFit.contain),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      '第${index + 1}页',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = GoRouterState.of(context).extra as DocumentMeta?;
    final detailState = ref.watch(documentDetailControllerProvider);
    final title = (meta?.name.isEmpty ?? true) ? '文档详情' : meta!.name;
    final pages = meta?.pages ?? 0;
    final cachedPages = meta == null
        ? const AsyncValue<List<String>>.data(<String>[])
        : ref.watch(documentCachedPagePathsProvider(meta));

    if (meta == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('文档详情')),
        body: const Center(child: Text('缺少文档信息')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: detailState.isDeleting
                ? null
                : () => _confirmDelete(context, ref, meta),
            icon: detailState.isDeleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            tooltip: '删除文档',
          ),
        ],
      ),
      body: Stack(
        children: [
          cachedPages.when(
            data: (paths) {
              if (pages == 0) {
                return Center(
                  child: Text(
                    '文档没有页面',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }

              final cachedPageMap = _buildCachedPageMap(paths);
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: pages,
                itemBuilder: (BuildContext context, int index) {
                  return _buildPageTile(
                    context: context,
                    theme: theme,
                    index: index,
                    cachedPath: cachedPageMap[index],
                    onTap: detailState.isBusy
                        ? null
                        : () => _openPreview(context, ref, meta, index),
                    onLongPress: detailState.isBusy
                        ? null
                        : () => _showPageActions(context, ref, meta, index),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemCount: pages,
              itemBuilder: (BuildContext context, int index) {
                return _buildPageTile(
                  context: context,
                  theme: theme,
                  index: index,
                  cachedPath: null,
                  onTap: detailState.isBusy
                      ? null
                      : () => _openPreview(context, ref, meta, index),
                  onLongPress: detailState.isBusy
                      ? null
                      : () => _showPageActions(context, ref, meta, index),
                );
              },
            ),
          ),
          if (detailState.isBusy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.18),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            detailState.isDeleting
                                ? '正在删除文档...'
                                : detailState.viewingOnDevice
                                    ? '正在设备上打开...'
                                    : '正在加载预览...',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
