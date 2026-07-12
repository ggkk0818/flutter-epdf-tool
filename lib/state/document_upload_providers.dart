import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/documents/document_naming.dart';
import '../features/documents/document_upload_models.dart';
import '../features/documents/services/document_processing_service.dart';
import '../shared/ble/models.dart';
import '../shared/storage/document_cache_store.dart';
import 'ble_providers.dart';
import 'document_providers.dart';

final documentCacheStoreProvider = Provider<DocumentCacheStore>((ref) {
  return DocumentCacheStore();
});

final documentProcessingServiceProvider = Provider<DocumentProcessingService>((ref) {
  return DocumentProcessingService(ref.watch(documentCacheStoreProvider));
});

class DocumentUploadController extends StateNotifier<DocumentUploadState> {
  DocumentUploadController(this._ref, this._processingService)
      : super(const DocumentUploadState.initial());

  final Ref _ref;
  final DocumentProcessingService _processingService;

  Future<void> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }

    final items = await _processingService.buildPdfPreviewItems(path);
    state = state.copyWith(
      step: DocumentUploadStep.preview,
      sourceType: DocumentSourceType.pdf,
      items: items,
      previewLayout: DocumentPreviewLayout.list,
      documentName: suggestDocumentNameFromPath(path),
      clearFailure: true,
      clearSuccess: true,
      clearProgress: true,
    );
  }

  Future<void> pickImages({bool append = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final paths = result.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) {
      return;
    }

    final items = _processingService.buildImagePreviewItems(paths);
    final nextItems = append ? <DocumentPreviewItem>[...state.items, ...items] : items;
    final suggestedName = append && state.documentName.isNotEmpty
        ? state.documentName
        : suggestDocumentNameFromPath(paths.first);

    state = state.copyWith(
      step: DocumentUploadStep.preview,
      sourceType: DocumentSourceType.images,
      items: nextItems,
      previewLayout: DocumentPreviewLayout.list,
      documentName: suggestedName,
      clearFailure: true,
      clearSuccess: true,
      clearProgress: true,
    );
  }

  void setPreviewLayout(DocumentPreviewLayout layout) {
    state = state.copyWith(previewLayout: layout);
  }

  void updateDocumentName(String value) {
    state = state.copyWith(documentName: value);
  }

  void toggleSelection(String itemId, bool selected) {
    if (state.sourceType == DocumentSourceType.images && !selected) {
      state = state.copyWith(
        items: state.items.where((item) => item.id != itemId).toList(),
      );
      return;
    }

    state = state.copyWith(
      items: state.items
          .map((item) => item.id == itemId ? item.copyWith(isSelected: selected) : item)
          .toList(growable: false),
    );
  }

  void goToConfirm() {
    if (state.selectedCount == 0) {
      return;
    }
    state = state.copyWith(
      step: DocumentUploadStep.confirm,
      clearFailure: true,
    );
  }

  void backToPreview() {
    state = state.copyWith(step: DocumentUploadStep.preview, clearFailure: true);
  }

  Future<void> startTransfer() async {
    final nameError = validateDocumentName(state.documentName);
    if (nameError != null) {
      throw DocumentTransferException(nameError);
    }

    final active = _ref.read(activeConnectionProvider).valueOrNull;
    final remoteId = _ref.read(currentDeviceIdProvider);
    final connection = active?.connection;
    final info = active?.info;
    final selectedItems = state.selectedItems;

    if (remoteId == null || remoteId.isEmpty || connection == null || info == null) {
      state = state.copyWith(
        step: DocumentUploadStep.failure,
        failureReason: '设备连接已断开，请重新连接后再试。',
        clearProgress: true,
      );
      return;
    }
    if (selectedItems.isEmpty) {
      state = state.copyWith(
        step: DocumentUploadStep.failure,
        failureReason: '请至少保留 1 页内容再开始传输。',
        clearProgress: true,
      );
      return;
    }

    final displayTime = buildDocumentDisplayTime(DateTime.now());
    PreparedDocument? prepared;

    state = state.copyWith(
      step: DocumentUploadStep.progress,
      progress: DocumentTransferProgress(
        stage: DocumentUploadStage.converting,
        currentPage: 1,
        totalPages: selectedItems.length,
        progress: 0,
      ),
      clearFailure: true,
      clearSuccess: true,
    );

    try {
      prepared = await _processingService.prepareDocumentForUpload(
        items: selectedItems,
        deviceInfo: info,
        remoteId: remoteId,
        documentName: state.documentName.trim(),
        displayTime: displayTime,
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );

      await _ref.read(bleServiceProvider).uploadPreparedDocument(
        connection: connection,
        name: state.documentName.trim(),
        time: displayTime,
        pages: prepared.pages,
        onPageStarted: (pageNumber, totalPages) {
          state = state.copyWith(
            progress: DocumentTransferProgress(
              stage: DocumentUploadStage.uploading,
              currentPage: pageNumber,
              totalPages: totalPages,
              progress: 0.5 + (((pageNumber - 1) / totalPages) * 0.5),
            ),
          );
        },
        onPageUploaded: (pageNumber, totalPages) {
          state = state.copyWith(
            progress: DocumentTransferProgress(
              stage: DocumentUploadStage.uploading,
              currentPage: pageNumber,
              totalPages: totalPages,
              progress: 0.5 + ((pageNumber / totalPages) * 0.5),
            ),
          );
        },
      );

      state = state.copyWith(
        step: DocumentUploadStep.success,
        success: DocumentTransferSuccess(
          name: state.documentName.trim(),
          time: displayTime,
          pages: prepared.pages.length,
          cacheKey: prepared.cacheKey,
        ),
        clearFailure: true,
        clearProgress: true,
      );
    } on DocumentTransferException catch (e) {
      state = state.copyWith(
        step: DocumentUploadStep.failure,
        failureReason: e.message,
        clearProgress: true,
      );
    } on Object {
      state = state.copyWith(
        step: DocumentUploadStep.failure,
        failureReason: '处理文档失败，请重试。',
        clearProgress: true,
      );
    } finally {
      if (prepared != null) {
        await _processingService.cleanupSession(prepared.tempSessionId);
      }
    }
  }

  Future<void> completeAndRefresh() async {
    await _ref.read(documentListProvider.notifier).refresh();
  }
}

final documentUploadControllerProvider =
    StateNotifierProvider.autoDispose<DocumentUploadController, DocumentUploadState>((ref) {
  return DocumentUploadController(ref, ref.watch(documentProcessingServiceProvider));
});

final documentCachedPagePathsProvider =
    FutureProvider.autoDispose.family<List<String>, DocumentMeta>((ref, meta) async {
  final remoteId = ref.watch(currentDeviceIdProvider);
  if (remoteId == null || remoteId.isEmpty) {
    return const <String>[];
  }
  return ref.watch(documentCacheStoreProvider).listCachedPages(
        remoteId,
        buildCanonicalDocumentKeyFromMeta(meta),
      );
});