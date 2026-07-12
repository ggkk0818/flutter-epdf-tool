enum DocumentSourceType { pdf, images }

enum DocumentPreviewLayout { list, grid }

enum DocumentUploadStep { chooseSource, preview, confirm, progress, success, failure }

enum DocumentUploadStage { converting, uploading }

enum DocumentPreviewSourceKind { pdfPage, imageFile }

class DocumentPreviewItem {
  const DocumentPreviewItem({
    required this.id,
    required this.sourceKind,
    required this.sourcePath,
    required this.previewPath,
    required this.label,
    this.pageNumber,
    this.isSelected = true,
  });

  final String id;
  final DocumentPreviewSourceKind sourceKind;
  final String sourcePath;
  final String previewPath;
  final String label;
  final int? pageNumber;
  final bool isSelected;

  DocumentPreviewItem copyWith({bool? isSelected}) {
    return DocumentPreviewItem(
      id: id,
      sourceKind: sourceKind,
      sourcePath: sourcePath,
      previewPath: previewPath,
      label: label,
      pageNumber: pageNumber,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class DocumentTransferProgress {
  const DocumentTransferProgress({
    required this.stage,
    required this.currentPage,
    required this.totalPages,
    required this.progress,
  });

  final DocumentUploadStage stage;
  final int currentPage;
  final int totalPages;
  final double progress;
}

class DocumentTransferSuccess {
  const DocumentTransferSuccess({
    required this.name,
    required this.time,
    required this.pages,
    required this.cacheKey,
  });

  final String name;
  final String time;
  final int pages;
  final String cacheKey;
}

class PreparedDocumentPage {
  const PreparedDocumentPage({
    required this.binPath,
    required this.previewPath,
    required this.width,
    required this.height,
  });

  final String binPath;
  final String previewPath;
  final int width;
  final int height;
}

class PreparedDocument {
  const PreparedDocument({
    required this.cacheKey,
    required this.tempSessionId,
    required this.pages,
  });

  final String cacheKey;
  final String tempSessionId;
  final List<PreparedDocumentPage> pages;
}

class DocumentTransferException implements Exception {
  const DocumentTransferException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class DocumentUploadState {
  const DocumentUploadState({
    required this.step,
    required this.previewLayout,
    required this.items,
    this.sourceType,
    this.documentName = '',
    this.progress,
    this.failureReason,
    this.success,
  });

  const DocumentUploadState.initial()
      : step = DocumentUploadStep.chooseSource,
        previewLayout = DocumentPreviewLayout.list,
        items = const <DocumentPreviewItem>[],
        sourceType = null,
        documentName = '',
        progress = null,
        failureReason = null,
        success = null;

  final DocumentUploadStep step;
  final DocumentSourceType? sourceType;
  final DocumentPreviewLayout previewLayout;
  final List<DocumentPreviewItem> items;
  final String documentName;
  final DocumentTransferProgress? progress;
  final String? failureReason;
  final DocumentTransferSuccess? success;

  List<DocumentPreviewItem> get selectedItems => items
      .where((item) => item.isSelected)
      .toList(growable: false);

  int get selectedCount => selectedItems.length;

  bool get isBusy => step == DocumentUploadStep.progress;

  DocumentUploadState copyWith({
    DocumentUploadStep? step,
    DocumentSourceType? sourceType,
    DocumentPreviewLayout? previewLayout,
    List<DocumentPreviewItem>? items,
    String? documentName,
    DocumentTransferProgress? progress,
    String? failureReason,
    DocumentTransferSuccess? success,
    bool clearProgress = false,
    bool clearFailure = false,
    bool clearSuccess = false,
  }) {
    return DocumentUploadState(
      step: step ?? this.step,
      sourceType: sourceType ?? this.sourceType,
      previewLayout: previewLayout ?? this.previewLayout,
      items: items ?? this.items,
      documentName: documentName ?? this.documentName,
      progress: clearProgress ? null : (progress ?? this.progress),
      failureReason: clearFailure ? null : (failureReason ?? this.failureReason),
      success: clearSuccess ? null : (success ?? this.success),
    );
  }
}