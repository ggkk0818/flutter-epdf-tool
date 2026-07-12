import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../shared/ble/models.dart';
import '../../../shared/storage/document_cache_store.dart';
import '../document_naming.dart';
import '../document_upload_models.dart';

class DocumentProcessingService {
  DocumentProcessingService(this._cacheStore);

  static Future<void>? _pdfrxInitFuture;

  final DocumentCacheStore _cacheStore;

  Future<List<DocumentPreviewItem>> buildPdfPreviewItems(String pdfPath) async {
    final sessionId = 'pdf_preview_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await _cacheStore.createSessionDirectory(sessionId);
    await _ensurePdfRuntimeInitialized();
    final document = await PdfDocument.openFile(pdfPath);
    final items = <DocumentPreviewItem>[];

    try {
      for (int index = 0; index < document.pages.length; index++) {
        final page = document.pages[index];
        final previewImage = await _renderPdfPageImage(page, maxSide: 1200);
        final previewPath = p.join(
          sessionDir.path,
          'preview_${(index + 1).toString().padLeft(3, '0')}.png',
        );
        await File(previewPath).writeAsBytes(img.encodePng(previewImage));

        items.add(
          DocumentPreviewItem(
            id: 'pdf:$pdfPath:${index + 1}',
            sourceKind: DocumentPreviewSourceKind.pdfPage,
            sourcePath: pdfPath,
            previewPath: previewPath,
            pageNumber: index + 1,
            label: '第${index + 1}页',
          ),
        );
      }
    } catch (e) {
      throw DocumentTransferException('PDF 解析失败，请确认文件内容正常。', e);
    } finally {
      await document.dispose();
    }

    return items;
  }

  List<DocumentPreviewItem> buildImagePreviewItems(List<String> paths) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return List<DocumentPreviewItem>.generate(paths.length, (index) {
      final path = paths[index];
      return DocumentPreviewItem(
        id: 'img:$now:$index:${path.hashCode}',
        sourceKind: DocumentPreviewSourceKind.imageFile,
        sourcePath: path,
        previewPath: path,
        label: p.basename(path),
      );
    }, growable: false);
  }

  Future<PreparedDocument> prepareDocumentForUpload({
    required List<DocumentPreviewItem> items,
    required DeviceInfo deviceInfo,
    required String remoteId,
    required String documentName,
    required String displayTime,
    void Function(DocumentTransferProgress progress)? onProgress,
  }) async {
    final cacheKey = buildCanonicalDocumentKey(
      name: documentName,
      displayTime: displayTime,
      pages: items.length,
    );
    final cacheDir = await _cacheStore.ensureDocumentCacheDirectory(
      remoteId,
      cacheKey,
    );
    final sessionId = 'upload_${DateTime.now().millisecondsSinceEpoch}';
    final tempDir = await _cacheStore.createSessionDirectory(sessionId);
    final preparedPages = <PreparedDocumentPage>[];

    for (int index = 0; index < items.length; index++) {
      onProgress?.call(
        DocumentTransferProgress(
          stage: DocumentUploadStage.converting,
          currentPage: index + 1,
          totalPages: items.length,
          progress: items.isEmpty ? 0 : ((index + 1) / items.length) * 0.5,
        ),
      );

      final displayImage = await _buildDisplayImage(items[index], deviceInfo);
      final pageNumber = (index + 1).toString().padLeft(3, '0');
      final previewPath = p.join(cacheDir.path, 'page_$pageNumber.png');
      final binPath = p.join(tempDir.path, 'page_$pageNumber.bin');

      await File(previewPath).writeAsBytes(img.encodePng(displayImage));
      await File(binPath).writeAsBytes(_encodeBin(displayImage));

      preparedPages.add(
        PreparedDocumentPage(
          binPath: binPath,
          previewPath: previewPath,
          width: displayImage.width,
          height: displayImage.height,
        ),
      );
    }

    return PreparedDocument(
      cacheKey: cacheKey,
      tempSessionId: sessionId,
      pages: preparedPages,
    );
  }

  Future<void> cleanupSession(String sessionId) {
    return _cacheStore.deleteSessionDirectory(sessionId);
  }

  Future<void> _ensurePdfRuntimeInitialized() async {
    try {
      await (_pdfrxInitFuture ??= pdfrxFlutterInitialize());
    } on Object {
      _pdfrxInitFuture = null;
      rethrow;
    }
  }

  Future<img.Image> _buildDisplayImage(
    DocumentPreviewItem item,
    DeviceInfo deviceInfo,
  ) async {
    final source = await _loadSourceImage(item, deviceInfo);
    final flattened = _flattenOnWhite(source);
    img.grayscale(flattened);

    final fitted = _fitWithin(
      flattened.width,
      flattened.height,
      math.max(deviceInfo.viewportWidth, 1),
      math.max(deviceInfo.viewportHeight, 1),
    );
    final resized = fitted.width == flattened.width &&
            fitted.height == flattened.height
        ? flattened
        : img.copyResize(
            flattened,
            width: fitted.width,
            height: fitted.height,
            interpolation: img.Interpolation.average,
          );
    img.luminanceThreshold(resized, threshold: 0.72);
    return resized;
  }

  Future<img.Image> _loadSourceImage(
    DocumentPreviewItem item,
    DeviceInfo deviceInfo,
  ) async {
    switch (item.sourceKind) {
      case DocumentPreviewSourceKind.pdfPage:
        await _ensurePdfRuntimeInitialized();
        final document = await PdfDocument.openFile(item.sourcePath);
        try {
          final page = document.pages[item.pageNumber! - 1];
          final maxSide =
              math.max(deviceInfo.viewportWidth, deviceInfo.viewportHeight) * 2;
          return _renderPdfPageImage(page, maxSide: math.max(maxSide, 1200));
        } finally {
          await document.dispose();
        }
      case DocumentPreviewSourceKind.imageFile:
        final bytes = await File(item.sourcePath).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw const DocumentTransferException('图片解析失败，请重新选择图片。');
        }
        return decoded;
    }
  }

  Future<img.Image> _renderPdfPageImage(
    PdfPage page, {
    required int maxSide,
  }) async {
    final pageSize = _fitWithin(
      page.width.round().clamp(1, 1 << 20),
      page.height.round().clamp(1, 1 << 20),
      maxSide,
      maxSide,
      allowUpscale: true,
    );
    final rendered = await page.render(
      width: pageSize.width,
      height: pageSize.height,
      fullWidth: pageSize.width.toDouble(),
      fullHeight: pageSize.height.toDouble(),
    );
    if (rendered == null) {
      throw const DocumentTransferException('PDF 页面渲染失败，请重试。');
    }
    try {
      return rendered.createImageNF();
    } finally {
      rendered.dispose();
    }
  }

  img.Image _flattenOnWhite(img.Image source) {
    final flattened = img.Image.from(source);
    for (final pixel in flattened) {
      final alpha = pixel.aNormalized;
      if (alpha >= 1) {
        continue;
      }
      pixel
        ..r = ((pixel.r * alpha) + (255 * (1 - alpha))).round()
        ..g = ((pixel.g * alpha) + (255 * (1 - alpha))).round()
        ..b = ((pixel.b * alpha) + (255 * (1 - alpha))).round()
        ..a = pixel.maxChannelValue;
    }
    return flattened;
  }

  Uint8List _encodeBin(img.Image image) {
    final header = ByteData(8)
      ..setUint8(0, 0xE5)
      ..setUint8(1, 0x01)
      ..setUint16(2, image.width, Endian.little)
      ..setUint16(4, image.height, Endian.little)
      ..setUint16(6, 0, Endian.little);

    final rowBytes = (image.width + 7) ~/ 8;
    final body = Uint8List(rowBytes * image.height);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        if (pixel.r < 128) {
          final offset = y * rowBytes + (x ~/ 8);
          body[offset] |= 0x80 >> (x % 8);
        }
      }
    }

    final output = BytesBuilder(copy: false);
    output.add(header.buffer.asUint8List());
    output.add(body);
    return output.takeBytes();
  }

  ({int width, int height}) _fitWithin(
    int width,
    int height,
    int maxWidth,
    int maxHeight, {
    bool allowUpscale = false,
  }) {
    if (width <= 0 || height <= 0) {
      return (width: 1, height: 1);
    }

    var scale = math.min(maxWidth / width, maxHeight / height);
    if (!allowUpscale) {
      scale = math.min(scale, 1);
    }
    if (scale <= 0 || scale.isNaN || scale.isInfinite) {
      scale = 1;
    }
    return (
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  }
}