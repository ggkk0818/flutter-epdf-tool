import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/documents/document_naming.dart';
import '../features/documents/document_upload_models.dart';
import '../shared/ble/epdf_page_bin_codec.dart';
import '../shared/ble/models.dart';
import 'ble_providers.dart';
import 'document_providers.dart';
import 'document_upload_providers.dart';

class DocumentDetailState {
  const DocumentDetailState({
    this.isDeleting = false,
    this.previewingPages = const <int>{},
    this.viewingOnDevice = false,
  });

  final bool isDeleting;
  final Set<int> previewingPages;
  final bool viewingOnDevice;

  bool get isBusy =>
      isDeleting || previewingPages.isNotEmpty || viewingOnDevice;

  DocumentDetailState copyWith({
    bool? isDeleting,
    Set<int>? previewingPages,
    bool? viewingOnDevice,
  }) {
    return DocumentDetailState(
      isDeleting: isDeleting ?? this.isDeleting,
      previewingPages: previewingPages ?? this.previewingPages,
      viewingOnDevice: viewingOnDevice ?? this.viewingOnDevice,
    );
  }
}

class DocumentDetailController extends StateNotifier<DocumentDetailState> {
  DocumentDetailController(this._ref) : super(const DocumentDetailState());

  final Ref _ref;

  Future<void> deleteDocument(DocumentMeta meta) async {
    if (state.isDeleting) {
      return;
    }

    final remoteId = _ref.read(currentDeviceIdProvider);
    final connection = _ref.read(activeConnectionProvider).valueOrNull?.connection;
    if (remoteId == null || remoteId.isEmpty || connection == null) {
      throw const DocumentTransferException('设备连接已断开，请重新连接后再试。');
    }

    final documentKey = buildCanonicalDocumentKeyFromMeta(meta);
    state = state.copyWith(isDeleting: true);
    try {
      await _ref.read(bleServiceProvider).deleteDocument(
            connection: connection,
            meta: meta,
          );
      await _ref.read(documentCacheStoreProvider).deleteDocumentCache(
            remoteId,
            documentKey,
          );
      _ref.invalidate(documentCachedPagePathsProvider(meta));
      await _ref.read(documentListProvider.notifier).refresh();
    } finally {
      state = state.copyWith(isDeleting: false);
    }
  }

  Future<void> viewOnDevice({
    required DocumentMeta meta,
    required int pageIndex,
  }) async {
    if (state.viewingOnDevice) {
      return;
    }

    final connection = _ref.read(activeConnectionProvider).valueOrNull?.connection;
    if (connection == null) {
      throw const DocumentTransferException('设备连接已断开，请重新连接后再试。');
    }

    state = state.copyWith(viewingOnDevice: true);
    try {
      await _ref.read(bleServiceProvider).viewOnDevice(
            connection: connection,
            meta: meta,
            pageIndex: pageIndex,
          );
    } finally {
      state = state.copyWith(viewingOnDevice: false);
    }
  }

  Future<String> ensurePreviewPageCached({
    required DocumentMeta meta,
    required int pageIndex,
  }) async {
    if (pageIndex < 0 || pageIndex >= meta.pages) {
      throw const DocumentTransferException('请求的页码超出文档范围。');
    }

    final remoteId = _ref.read(currentDeviceIdProvider);
    if (remoteId == null || remoteId.isEmpty) {
      throw const DocumentTransferException('还没有选中设备。');
    }

    final cacheStore = _ref.read(documentCacheStoreProvider);
    final documentKey = buildCanonicalDocumentKeyFromMeta(meta);
    final hasCache = await cacheStore.hasCachedPage(
      remoteId: remoteId,
      documentKey: documentKey,
      pageIndex: pageIndex,
    );
    if (hasCache) {
      return cacheStore.cachedPagePath(
        remoteId: remoteId,
        documentKey: documentKey,
        pageIndex: pageIndex,
      );
    }

    final connection = _ref.read(activeConnectionProvider).valueOrNull?.connection;
    if (connection == null) {
      throw const DocumentTransferException('设备连接已断开，请重新连接后再试。');
    }

    state = state.copyWith(
      previewingPages: <int>{...state.previewingPages, pageIndex},
    );
    try {
      final preview = await _ref.read(bleServiceProvider).fetchPreviewPage(
            connection: connection,
            meta: meta,
            pageIndex: pageIndex,
          );
      final decoded = EpdfPageBinCodec.decode(preview.bytes);
      if ((preview.width > 0 && preview.width != decoded.header.width) ||
          (preview.height > 0 && preview.height != decoded.header.height)) {
        throw const DocumentTransferException('预览尺寸与文件头不一致，请重试。');
      }

      final path = await cacheStore.writeCachedPageImage(
        remoteId: remoteId,
        documentKey: documentKey,
        pageIndex: pageIndex,
        image: decoded.image,
      );
      _ref.invalidate(documentCachedPagePathsProvider(meta));
      return path;
    } on FormatException catch (e) {
      throw DocumentTransferException('预览数据格式错误：${e.message}', e);
    } finally {
      final nextPages = <int>{...state.previewingPages}..remove(pageIndex);
      state = state.copyWith(previewingPages: nextPages);
    }
  }
}

final documentDetailControllerProvider =
    StateNotifierProvider.autoDispose<DocumentDetailController, DocumentDetailState>((ref) {
  return DocumentDetailController(ref);
});