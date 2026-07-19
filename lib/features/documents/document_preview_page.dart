import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/ble/models.dart';
import '../../state/document_detail_providers.dart';

class DocumentPreviewPageArgs {
  const DocumentPreviewPageArgs({
    required this.meta,
    required this.initialPage,
  });

  final DocumentMeta meta;
  final int initialPage;
}

class DocumentPreviewPage extends ConsumerStatefulWidget {
  const DocumentPreviewPage({
    required this.args,
    super.key,
  });

  final DocumentPreviewPageArgs args;

  @override
  ConsumerState<DocumentPreviewPage> createState() => _DocumentPreviewPageState();
}

class _DocumentPreviewPageState extends ConsumerState<DocumentPreviewPage> {
  late final PageController _pageController;
  late int _currentPage;
  final Map<int, Future<String>> _pageFutures = <int, Future<String>>{};

  DocumentMeta get _meta => widget.args.meta;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.args.initialPage;
    _pageController = PageController(initialPage: widget.args.initialPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmPages(_currentPage);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<String> _futureForPage(int pageIndex) {
    return _pageFutures.putIfAbsent(
      pageIndex,
      () => ref.read(documentDetailControllerProvider.notifier).ensurePreviewPageCached(
            meta: _meta,
            pageIndex: pageIndex,
          ),
    );
  }

  void _warmPages(int centerPage) {
    _futureForPage(centerPage);
    if (centerPage > 0) {
      _futureForPage(centerPage - 1);
    }
    if (centerPage + 1 < _meta.pages) {
      _futureForPage(centerPage + 1);
    }
  }

  void _retryPage(int pageIndex) {
    setState(() {
      _pageFutures.remove(pageIndex);
    });
    _warmPages(pageIndex);
  }

  Future<void> _showImageActions(int pageIndex) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new_outlined),
                title: const Text('在设备上打开'),
                onTap: () {
                  Navigator.of(bottomSheetContext).pop();
                  _openOnDevice(pageIndex);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openOnDevice(int pageIndex) async {
    try {
      await ref
          .read(documentDetailControllerProvider.notifier)
          .viewOnDevice(meta: _meta, pageIndex: pageIndex);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已在设备上打开')),
      );
    } on Object catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _meta.name.isEmpty ? '预览' : _meta.name;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            Text(
              '第${_currentPage + 1} / ${_meta.pages}页',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _meta.pages,
        onPageChanged: (int index) {
          setState(() {
            _currentPage = index;
          });
          _warmPages(index);
        },
        itemBuilder: (BuildContext context, int index) {
          return FutureBuilder<String>(
            future: _futureForPage(index),
            builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _PreviewErrorState(
                  message: '${snapshot.error}',
                  onRetry: () => _retryPage(index),
                );
              }
              final path = snapshot.data;
              if (path == null || path.isEmpty) {
                return _PreviewErrorState(
                  message: '未找到预览图片。',
                  onRetry: () => _retryPage(index),
                );
              }

              return GestureDetector(
                onLongPress: () => _showImageActions(index),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PreviewErrorState extends StatelessWidget {
  const _PreviewErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}