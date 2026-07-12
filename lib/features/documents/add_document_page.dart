import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../state/document_providers.dart';
import '../../state/document_upload_providers.dart';
import 'document_naming.dart';
import 'document_upload_models.dart';

class AddDocumentPage extends ConsumerStatefulWidget {
  const AddDocumentPage({super.key});

  @override
  ConsumerState<AddDocumentPage> createState() => _AddDocumentPageState();
}

class _AddDocumentPageState extends ConsumerState<AddDocumentPage> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    try {
      await ref.read(documentUploadControllerProvider.notifier).pickPdf();
    } on Object catch (e) {
      _showMessage(e.toString());
    }
  }

  Future<void> _pickImages({bool append = false}) async {
    try {
      await ref
          .read(documentUploadControllerProvider.notifier)
          .pickImages(append: append);
    } on Object catch (e) {
      _showMessage(e.toString());
    }
  }

  Future<void> _confirmTransfer(DocumentUploadState state) async {
    final message = validateDocumentName(_nameController.text);
    if (message != null) {
      _showMessage(message);
      return;
    }

    final minutes = math.max(1, (state.selectedCount / 3).ceil());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认开始传输'),
        content: Text(
          '文档传输预计需要$minutes分钟，请靠近设备并保持蓝牙开启。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('开始传输'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await ref.read(documentUploadControllerProvider.notifier).startTransfer();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageStatus = ref.watch(documentPageStatusProvider);
    final state = ref.watch(documentUploadControllerProvider);
    final theme = Theme.of(context);
    final nameError = validateDocumentName(_nameController.text);

    if (_nameController.text != state.documentName) {
      _nameController.value = TextEditingValue(
        text: state.documentName,
        selection: TextSelection.collapsed(offset: state.documentName.length),
      );
    }

    return PopScope(
      canPop: !state.isBusy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titleForStep(state.step)),
          automaticallyImplyLeading: !state.isBusy,
        ),
        body: pageStatus != DocumentPageStatus.ready
            ? _DisconnectedGuard(theme: theme)
            : _buildBody(context, state, theme, nameError),
        bottomNavigationBar: pageStatus != DocumentPageStatus.ready
            ? null
            : _buildBottomBar(state, nameError),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    DocumentUploadState state,
    ThemeData theme,
    String? nameError,
  ) {
    switch (state.step) {
      case DocumentUploadStep.chooseSource:
        return _SourceStep(
          onPickPdf: _pickPdf,
          onPickImages: _pickImages,
        );
      case DocumentUploadStep.preview:
        return _PreviewStep(
          state: state,
          onAddImages: state.sourceType == DocumentSourceType.images
              ? () => _pickImages(append: true)
              : null,
          onLayoutChanged: (layout) => ref
              .read(documentUploadControllerProvider.notifier)
              .setPreviewLayout(layout),
          onSelectionChanged: (itemId, selected) => ref
              .read(documentUploadControllerProvider.notifier)
              .toggleSelection(itemId, selected),
        );
      case DocumentUploadStep.confirm:
        return _ConfirmStep(
          state: state,
          theme: theme,
          controller: _nameController,
          nameError: nameError,
          onChanged: (value) => ref
              .read(documentUploadControllerProvider.notifier)
              .updateDocumentName(value),
        );
      case DocumentUploadStep.progress:
        return _ProgressStep(progress: state.progress);
      case DocumentUploadStep.success:
        return const _ResultStep(
          success: true,
          title: '文档传输完成',
          message: '文档已成功写入设备。',
        );
      case DocumentUploadStep.failure:
        return _ResultStep(
          success: false,
          title: '文档传输失败',
          message: state.failureReason ?? '传输过程中发生未知错误。',
        );
    }
  }

  Widget? _buildBottomBar(DocumentUploadState state, String? nameError) {
    switch (state.step) {
      case DocumentUploadStep.chooseSource:
        return null;
      case DocumentUploadStep.preview:
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton(
            onPressed: state.selectedCount == 0
                ? null
                : () => ref
                    .read(documentUploadControllerProvider.notifier)
                    .goToConfirm(),
            child: Text('下一步 (${state.selectedCount}页)'),
          ),
        );
      case DocumentUploadStep.confirm:
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton(
            onPressed: nameError != null || state.selectedCount == 0
                ? null
                : () => _confirmTransfer(state),
            child: const Text('开始传输'),
          ),
        );
      case DocumentUploadStep.progress:
        return null;
      case DocumentUploadStep.success:
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton(
            onPressed: () async {
              await ref
                  .read(documentUploadControllerProvider.notifier)
                  .completeAndRefresh();
              if (!mounted) {
                return;
              }
              context.pop();
            },
            child: const Text('完成'),
          ),
        );
      case DocumentUploadStep.failure:
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton.tonal(
            onPressed: () => context.pop(),
            child: const Text('返回'),
          ),
        );
    }
  }

  String _titleForStep(DocumentUploadStep step) {
    switch (step) {
      case DocumentUploadStep.chooseSource:
        return '添加文档';
      case DocumentUploadStep.preview:
        return '页面预览';
      case DocumentUploadStep.confirm:
        return '信息确认';
      case DocumentUploadStep.progress:
        return '传输中';
      case DocumentUploadStep.success:
        return '传输完成';
      case DocumentUploadStep.failure:
        return '传输失败';
    }
  }
}

class _DisconnectedGuard extends StatelessWidget {
  const _DisconnectedGuard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text('设备当前不可用', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '请先回到设备页连接设备，再开始添加文档。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => context.go(AppSection.devices.path),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('前往设备页'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceStep extends StatelessWidget {
  const _SourceStep({required this.onPickPdf, required this.onPickImages});

  final Future<void> Function() onPickPdf;
  final Future<void> Function({bool append}) onPickImages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('选择添加方式', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '你可以导入 PDF，或直接选择多张图片生成文档。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        _SourceCard(
          icon: Icons.picture_as_pdf,
          title: '从 PDF 添加',
          message: '选择 1 个 PDF 文件，预览每一页后再确认上传。',
          onTap: onPickPdf,
        ),
        const SizedBox(height: 16),
        _SourceCard(
          icon: Icons.photo_library_outlined,
          title: '从图片添加',
          message: '可一次选择多张图片，也支持后续继续追加到列表末尾。',
          onTap: () => onPickImages(append: false),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.state,
    required this.onLayoutChanged,
    required this.onSelectionChanged,
    this.onAddImages,
  });

  final DocumentUploadState state;
  final ValueChanged<DocumentPreviewLayout> onLayoutChanged;
  final void Function(String itemId, bool selected) onSelectionChanged;
  final VoidCallback? onAddImages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<DocumentPreviewLayout>(
                  segments: const [
                    ButtonSegment(
                      value: DocumentPreviewLayout.list,
                      icon: Icon(Icons.view_agenda_outlined),
                      label: Text('大图'),
                    ),
                    ButtonSegment(
                      value: DocumentPreviewLayout.grid,
                      icon: Icon(Icons.grid_view_outlined),
                      label: Text('网格'),
                    ),
                  ],
                  selected: <DocumentPreviewLayout>{state.previewLayout},
                  onSelectionChanged: (selection) {
                    onLayoutChanged(selection.first);
                  },
                ),
              ),
              if (onAddImages != null) ...[
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: onAddImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('添加图片'),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '已选 ${state.selectedCount} / ${state.items.length} 页',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: state.items.isEmpty
              ? Center(
                  child: Text(
                    state.sourceType == DocumentSourceType.images
                        ? '当前没有图片，请继续添加。'
                        : '没有可预览的页面。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : state.previewLayout == DocumentPreviewLayout.list
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: state.items.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: FractionallySizedBox(
                              widthFactor: 0.9,
                              child: _PreviewCard(
                                item: state.items[index],
                                compact: false,
                                removableWhenUnchecked:
                                    state.sourceType == DocumentSourceType.images,
                                onSelectionChanged: onSelectionChanged,
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: state.items.length,
                      itemBuilder: (context, index) {
                        return _PreviewCard(
                          item: state.items[index],
                          compact: true,
                          removableWhenUnchecked:
                              state.sourceType == DocumentSourceType.images,
                          onSelectionChanged: onSelectionChanged,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.item,
    required this.compact,
    required this.removableWhenUnchecked,
    required this.onSelectionChanged,
  });

  final DocumentPreviewItem item;
  final bool compact;
  final bool removableWhenUnchecked;
  final void Function(String itemId, bool selected) onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = Image.file(
      File(item.previewPath),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return Opacity(
      opacity: item.isSelected ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(compact ? 8 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (compact)
                    Expanded(child: image)
                  else
                    AspectRatio(
                      aspectRatio: 0.72,
                      child: image,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: compact
                        ? theme.textTheme.labelMedium
                        : theme.textTheme.titleSmall,
                  ),
                  if (removableWhenUnchecked && !compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      '取消勾选后将从列表中移除',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Checkbox(
                value: item.isSelected,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  onSelectionChanged(item.id, value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.state,
    required this.theme,
    required this.controller,
    required this.nameError,
    required this.onChanged,
  });

  final DocumentUploadState state;
  final ThemeData theme;
  final TextEditingController controller;
  final String? nameError;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('确认文档信息', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '上传前请确认文档名称与页数。文档名支持中文、英文、数字与常见合法符号。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: '文档名称',
            hintText: '请输入文档名称',
            errorText: nameError,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '本次将传输 ${state.selectedCount} 页',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({required this.progress});

  final DocumentTransferProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = progress?.currentPage ?? 0;
    final total = progress?.totalPages ?? 0;
    final stage = progress?.stage ?? DocumentUploadStage.converting;
    final label = stage == DocumentUploadStage.uploading
        ? '传输第$current页，共$total页'
        : '正在处理第$current页，共$total页';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 132,
              height: 132,
              child: CircularProgressIndicator(
                value: progress?.progress,
                strokeWidth: 10,
              ),
            ),
            const SizedBox(height: 24),
            Text(label, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              stage == DocumentUploadStage.uploading
                  ? '请保持蓝牙开启，并尽量靠近设备。'
                  : '正在将页面转换为适合墨水屏展示的黑白位图。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultStep extends StatelessWidget {
  const _ResultStep({
    required this.success,
    required this.title,
    required this.message,
  });

  final bool success;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success ? Icons.check_circle : Icons.cancel,
              size: 76,
              color: success ? Colors.green : theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
