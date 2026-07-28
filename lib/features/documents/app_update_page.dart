import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';

import '../../shared/download_error_message.dart';
import '../../state/network_providers.dart';

class AppUpdatePageArgs {
  const AppUpdatePageArgs({
    required this.version,
    required this.changelog,
  });

  final String version;
  final String changelog;
}

class AppUpdatePage extends ConsumerStatefulWidget {
  const AppUpdatePage({required this.args, super.key});

  final AppUpdatePageArgs args;

  @override
  ConsumerState<AppUpdatePage> createState() => _AppUpdatePageState();
}

enum _Phase { downloading, awaitingInstall, failure }

class _AppUpdatePageState extends ConsumerState<AppUpdatePage> {
  _Phase _phase = _Phase.downloading;
  double _fraction = 0;
  String _statusText = '';
  String? _errorMessage;
  String? _apkPath;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _statusText = '正在下载新版本 v${widget.args.version}…';
    WidgetsBinding.instance.addPostFrameCallback((_) => _startDownload());
  }

  Future<void> _startDownload() async {
    final token = CancelToken();
    _cancelToken = token;
    if (!mounted) return;
    setState(() {
      _phase = _Phase.downloading;
      _fraction = 0;
      _errorMessage = null;
      _statusText = '正在下载新版本 v${widget.args.version}…';
    });

    try {
      final downloader = ref.read(apkDownloaderProvider);
      final path = await downloader.download(
        widget.args.version,
        cancelToken: token,
        onProgress: (f) {
          if (!mounted) return;
          setState(() {
            _fraction = f;
            _statusText =
                '正在下载新版本 v${widget.args.version}… ${(f * 100).toInt()}%';
          });
        },
      );
      _apkPath = path;
      await _launchInstaller();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failure;
        _errorMessage = null;
        _statusText = downloadErrorMessage(e);
      });
    }
  }

  Future<void> _launchInstaller() async {
    final path = _apkPath;
    if (path == null) return;
    final result = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
    if (!mounted) return;
    // OpenFilex returns a result message; treat non-"done" as soft warning
    // but still transition to awaitingInstall — user can retry via button.
    setState(() {
      _phase = _Phase.awaitingInstall;
      _statusText = '请在系统弹出的安装界面完成安装。\n若未自动打开，请点击下方"重试"按钮重新唤起。';
      if (result.type != ResultType.done) {
        _errorMessage = result.message;
      }
    });
  }

  Future<void> _cleanup() async {
    final path = _apkPath;
    _apkPath = null;
    if (path == null) return;
    try {
      await ref.read(apkDownloaderProvider).cleanup(path);
    } on Object {
      // best-effort
    }
  }

  Future<bool> _confirmCancel() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消升级'),
        content: const Text('是否取消升级？取消后需重新检测新版本。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续升级'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('取消升级'),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  void dispose() {
    _cancelToken?.cancel('disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PopScope(
      canPop: _phase == _Phase.failure,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navContext = context;
        final cancel = await _confirmCancel();
        if (!cancel) return;
        _cancelToken?.cancel('user canceled');
        await _cleanup();
        if (!navContext.mounted) return;
        navContext.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('版本更新'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildCenter(colorScheme, theme)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    widget.args.changelog.isEmpty
                        ? '（暂无更新说明）'
                        : '更新说明：${widget.args.changelog}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildBottomButton(colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenter(ColorScheme colorScheme, ThemeData theme) {
    switch (_phase) {
      case _Phase.downloading:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: _fraction,
                    strokeWidth: 12,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                  Center(
                    child: Text(
                      '${(_fraction * 100).toInt()}%',
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(_statusText, style: theme.textTheme.bodyMedium),
          ],
        );
      case _Phase.awaitingInstall:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.system_update_alt,
                size: 120, color: colorScheme.primary),
            const SizedBox(height: 20),
            Text('等待安装', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _launchInstaller(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        );
      case _Phase.failure:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 120, color: colorScheme.error),
            const SizedBox(height: 20),
            Text('下载失败', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? _statusText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _startDownload(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试下载'),
            ),
          ],
        );
    }
  }

  Widget _buildBottomButton(ColorScheme colorScheme) {
    switch (_phase) {
      case _Phase.downloading:
      case _Phase.awaitingInstall:
        return const SizedBox.shrink();
      case _Phase.failure:
        return FilledButton(
          onPressed: () => context.go('/documents'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('返回'),
        );
    }
  }
}
