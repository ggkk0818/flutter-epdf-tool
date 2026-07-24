import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/ble/ble_ota_connection.dart';
import '../../shared/ota/ble_ota_uploader.dart';
import '../../state/network_providers.dart';

class OtaUpdatePageArgs {
  const OtaUpdatePageArgs({
    required this.remoteId,
    required this.version,
    required this.changelog,
  });

  final String remoteId;
  final String version;
  final String changelog;
}

class OtaUpdatePage extends ConsumerStatefulWidget {
  const OtaUpdatePage({required this.args, super.key});

  final OtaUpdatePageArgs args;

  @override
  ConsumerState<OtaUpdatePage> createState() => _OtaUpdatePageState();
}

enum _Phase { preparing, downloading, uploading, success, failure }

/// Combined progress weighting: download occupies 0%–10% of the bar,
/// BLE upload occupies 10%–100%. Keeping the weights here in one place
/// makes it trivial to re-tune later.
const double _downloadWeight = 0.10;
const double _downloadBase = 0.0;
const double _uploadBase = 0.10;

class _OtaUpdatePageState extends ConsumerState<OtaUpdatePage> {
  _Phase _phase = _Phase.preparing;
  double _fraction = 0;
  String _statusText = '正在准备升级…';
  String? _errorMessage;
  StreamSubscription<OtaProgress>? _sub;
  BleOtaConnection? _otaConnection;
  String? _downloadedFilePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.preparing;
      _statusText = '正在准备升级…';
      _errorMessage = null;
      _fraction = 0;
    });

    try {
      // 1. Establish the BLE OTA connection first so we can surface a
      //    "device not reachable" failure before the (slow) download.
      final device = BluetoothDevice.fromId(widget.args.remoteId);
      final connection = await BleOtaConnection.establish(device);
      _otaConnection = connection;

      // 2. Download the firmware to a temp file. Maps 0..1 onto the first
      //    10% of the total progress bar.
      setState(() {
        _phase = _Phase.downloading;
        _statusText = '正在下载固件 v${widget.args.version}…';
      });
      final downloader = ref.read(firmwareDownloaderProvider);
      final filePath = await downloader.download(
        widget.args.version,
        onProgress: (f) {
          if (!mounted) return;
          setState(() {
            _fraction = _downloadBase + (f * _downloadWeight);
            _statusText =
                '正在下载固件 v${widget.args.version}… ${(f * 100).toInt()}%';
          });
        },
      );
      _downloadedFilePath = filePath;
      final Uint8List bytes = await downloader.readBytes(filePath);

      // 3. Stream over BLE. Maps the uploader's 0..1 onto 10%–100%.
      setState(() {
        _phase = _Phase.uploading;
        _statusText = '正在升级到 v${widget.args.version}…';
      });
      final uploader = BleOtaUploader(connection);
      _sub = uploader.run(bytes).listen(
        (p) {
          if (p.done) {
            setState(() {
              _phase = p.success ? _Phase.success : _Phase.failure;
              _fraction = p.success ? 1.0 : _fraction;
              _statusText = p.success
                  ? '升级成功，设备正在重启。'
                  : (p.errorMessage ?? '升级失败。');
              _errorMessage = p.errorMessage;
            });
          } else {
            setState(() {
              _fraction = _uploadBase + (p.fraction * (1 - _uploadBase));
              _statusText =
                  '正在升级到 v${widget.args.version}… ${(p.fraction * 100).toInt()}%';
            });
          }
        },
        onError: (Object e) {
          setState(() {
            _phase = _Phase.failure;
            _statusText = '升级失败：$e';
            _errorMessage = e.toString();
          });
        },
      );
    } on Object catch (e) {
      setState(() {
        _phase = _Phase.failure;
        _statusText = '升级失败：$e';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _cleanupTempFile() async {
    final path = _downloadedFilePath;
    if (path == null) return;
    _downloadedFilePath = null;
    try {
      await ref.read(firmwareDownloaderProvider).cleanup(path);
    } on Object {
      // Best-effort; a lingering cache file is acceptable.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _otaConnection?.dispose();
    // Fire-and-forget cleanup on dispose; the cache dir will reclaim it
    // eventually anyway.
    _cleanupTempFile();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PopScope(
      canPop: _phase == _Phase.success || _phase == _Phase.failure,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('固件升级'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildCenter(colorScheme, theme),
                ),
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
      case _Phase.preparing:
      case _Phase.downloading:
      case _Phase.uploading:
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
                    value: _phase == _Phase.preparing ? null : _fraction,
                    strokeWidth: 12,
                    backgroundColor:
                        colorScheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                  Center(
                    child: Text(
                      _phase == _Phase.preparing
                          ? '准备中'
                          : '${(_fraction * 100).toInt()}%',
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
      case _Phase.success:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle,
                size: 120, color: colorScheme.primary),
            const SizedBox(height: 20),
            Text('升级成功', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      case _Phase.failure:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 120, color: colorScheme.error),
            const SizedBox(height: 20),
            Text('升级失败', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? _statusText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildBottomButton(ColorScheme colorScheme) {
    switch (_phase) {
      case _Phase.preparing:
      case _Phase.downloading:
      case _Phase.uploading:
        return const SizedBox.shrink();
      case _Phase.success:
      case _Phase.failure:
        return FilledButton(
          onPressed: () => context.go('/devices'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('完成'),
        );
    }
  }
}
