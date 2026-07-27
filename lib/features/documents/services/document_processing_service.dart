import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../shared/ble/epdf_page_bin_codec.dart';
import '../../../shared/ble/models.dart';
import '../../../shared/storage/document_cache_store.dart';
import '../document_naming.dart';
import '../document_upload_models.dart';

const int _kPreviewMaxDimension = 1200;

@pragma('vm:entry-point')
Uint8List? _processPreviewImageForIsolate(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }

    final srcW = decoded.width;
    final srcH = decoded.height;
    final longest = math.max(srcW, srcH);
    final scale = longest > _kPreviewMaxDimension
        ? _kPreviewMaxDimension / longest
        : 1.0;

    img.Image working;
    if (scale < 1.0) {
      working = img.copyResize(
        decoded,
        width: (srcW * scale).round(),
        height: (srcH * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    } else {
      working = decoded;
    }

    if (working.width > working.height) {
      working = img.copyRotate(working, angle: 90);
    }

    return img.encodePng(working);
  } on Object {
    return null;
  }
}

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
        final previewSize = _fitWithin(
          page.width.round().clamp(1, 1 << 20),
          page.height.round().clamp(1, 1 << 20),
          1200,
          1200,
          allowUpscale: true,
        );
        var previewImage = await _renderPdfPageImage(
          page,
          width: previewSize.width,
          height: previewSize.height,
        );
        previewImage = _rotateIfLandscape(previewImage);
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

  Future<List<DocumentPreviewItem>> buildImagePreviewItems(List<String> paths) async {
    final sessionId = 'img_preview_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await _cacheStore.createSessionDirectory(sessionId);

    final allBytes = await Future.wait(
      paths.map((path) => _readImageBytes(path)),
    );

    final encodedList = await Future.wait(
      allBytes.map((bytes) => compute(_processPreviewImageForIsolate, bytes)),
    );

    if (encodedList.any((bytes) => bytes == null)) {
      throw const DocumentTransferException('图片解析失败，请重新选择图片。');
    }

    final previewPaths = List<String>.generate(paths.length, (index) {
      return p.join(
        sessionDir.path,
        'preview_${(index + 1).toString().padLeft(3, '0')}.png',
      );
    });

    await Future.wait(
      List<Future<void>>.generate(paths.length, (index) {
        return File(previewPaths[index]).writeAsBytes(encodedList[index]!);
      }),
    );

    return List<DocumentPreviewItem>.generate(paths.length, (index) {
      final path = paths[index];
      return DocumentPreviewItem(
        id: 'img:$sessionId:$index:${path.hashCode}',
        sourceKind: DocumentPreviewSourceKind.imageFile,
        sourcePath: path,
        previewPath: previewPaths[index],
        label: p.basename(path),
      );
    });
  }

  Future<Uint8List> _readImageBytes(String path) async {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.heic' || ext == '.heif') {
      try {
        final result = await FlutterImageCompress.compressWithFile(
          path,
          format: CompressFormat.jpeg,
          quality: 95,
          minWidth: 1200,
          minHeight: 1200,
        );
        if (result == null) {
          throw const DocumentTransferException('HEIC 图片解码失败，请重试。');
        }
        return result;
      } on DocumentTransferException {
        rethrow;
      } on Object catch (e) {
        throw DocumentTransferException('HEIC 图片解码失败，请重试。', e);
      }
    }
    return File(path).readAsBytes();
  }

  Future<PreparedDocument> prepareDocumentForUpload({
    required List<DocumentPreviewItem> items,
    required DeviceInfo deviceInfo,
    required String remoteId,
    required String documentName,
    required String displayTime,
    required DocumentType documentType,
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

      final displayImage = await _buildDisplayImage(
        items[index],
        deviceInfo,
        documentType,
      );
      final pageNumber = (index + 1).toString().padLeft(3, '0');
      final previewPath = p.join(cacheDir.path, 'page_$pageNumber.png');
      final binPath = p.join(tempDir.path, 'page_$pageNumber.bin');

      await File(previewPath).writeAsBytes(img.encodePng(displayImage));
      await File(binPath).writeAsBytes(EpdfPageBinCodec.encode(displayImage));

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
    DocumentType documentType,
  ) async {
    final source = await _loadSourceImage(item, deviceInfo);
    final oriented = _rotateIfLandscape(source);
    final flattened = _flattenOnWhite(oriented);
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
            interpolation: img.Interpolation.cubic,
          );
    img.convolution(resized, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0], amount: 0.3);
    switch (documentType) {
      case DocumentType.score:
        img.luminanceThreshold(resized, threshold: 0.85);
        break;
      case DocumentType.thinScore:
        img.luminanceThreshold(resized, threshold: 0.5);
        break;
      case DocumentType.document:
        _bradleyRothBinarize(resized);
        break;
      case DocumentType.photo:
        _floydSteinbergDither(resized, threshold: 0.5, serpentine: true);
        break;
    }
    return resized;
  }

  img.Image _rotateIfLandscape(img.Image image) {
    if (image.width <= image.height) {
      return image;
    }
    return img.copyRotate(image, angle: 90);
  }

  void _bradleyRothBinarize(img.Image image, {int window = 32, double t = 0.15}) {
    final W = image.width;
    final H = image.height;

    final lum = Uint8List(W * H);
    for (final p in image) {
      final v = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      lum[p.y * W + p.x] = v < 0 ? 0 : (v > 255 ? 255 : v.round());
    }

    final stride = W + 1;
    final sat = Float64List((H + 1) * stride);
    for (int y = 1; y <= H; y++) {
      double rowSum = 0;
      final prevRowBase = (y - 1) * stride;
      final curRowBase = y * stride;
      for (int x = 1; x <= W; x++) {
        rowSum += lum[(y - 1) * W + (x - 1)];
        sat[curRowBase + x] = sat[prevRowBase + x] + rowSum;
      }
    }

    final half = window ~/ 2;
    final factor = 1.0 - t;
    for (final p in image) {
      final x = p.x;
      final y = p.y;
      final xLeft = (x - half).clamp(0, W);
      final xRight = (x + half + 1).clamp(0, W);
      final yTop = (y - half).clamp(0, H);
      final yBot = (y + half + 1).clamp(0, H);

      final sum = sat[yBot * stride + xRight] -
          sat[yBot * stride + xLeft] -
          sat[yTop * stride + xRight] +
          sat[yTop * stride + xLeft];

      final cnt = (yBot - yTop) * (xRight - xLeft);
      final thresh = (sum / cnt) * factor;

      final c = lum[y * W + x] < thresh ? 0 : 255;
      p
        ..r = c
        ..g = c
        ..b = c
        ..a = p.maxChannelValue;
    }
  }

  void _floydSteinbergDither(
    img.Image image, {
    required double threshold,
    bool serpentine = true,
  }) {
    final width = image.width;
    final height = image.height;
    final luminance = Float32List(width * height);

    for (final p in image) {
      final y =
          0.3 * p.rNormalized +
          0.59 * p.gNormalized +
          0.11 * p.bNormalized;
      luminance[p.y * width + p.x] = y;
    }

    for (int y = 0; y < height; y++) {
      final dir = (serpentine && (y.isOdd)) ? -1 : 1;
      final xStart = dir == 1 ? 0 : width - 1;
      final xEnd = dir == 1 ? width : -1;
      final hasNextRow = y + 1 < height;

      for (int x = xStart; x != xEnd; x += dir) {
        final idx = y * width + x;
        final old = luminance[idx];
        final newV = old < threshold ? 0.0 : 1.0;
        luminance[idx] = newV;
        final err = old - newV;
        if (err == 0) {
          continue;
        }

        final xAhead = x + dir;
        if (xAhead >= 0 && xAhead < width) {
          luminance[idx + dir] += err * (7.0 / 16.0);
          if (hasNextRow) {
            final aheadNext = (y + 1) * width + xAhead;
            luminance[aheadNext] += err * (1.0 / 16.0);
          }
        }
        if (hasNextRow) {
          final behindX = x - dir;
          if (behindX >= 0 && behindX < width) {
            luminance[(y + 1) * width + behindX] += err * (3.0 / 16.0);
          }
          luminance[(y + 1) * width + x] += err * (5.0 / 16.0);
        }
      }
    }

    for (final p in image) {
      final v = luminance[p.y * width + p.x];
      final c = v < 0.5 ? 0 : p.maxChannelValue;
      p
        ..r = c
        ..g = c
        ..b = c
        ..a = p.maxChannelValue;
    }
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
          final target = _fitWithin(
            page.width.round().clamp(1, 1 << 20),
            page.height.round().clamp(1, 1 << 20),
            math.max(deviceInfo.viewportWidth, 1),
            math.max(deviceInfo.viewportHeight, 1),
            allowUpscale: true,
          );
          return _renderPdfPageImage(
            page,
            width: target.width,
            height: target.height,
          );
        } finally {
          await document.dispose();
        }
      case DocumentPreviewSourceKind.imageFile:
        final bytes = await _readImageBytes(item.sourcePath);
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw const DocumentTransferException('图片解析失败，请重新选择图片。');
        }
        return decoded;
    }
  }

  Future<img.Image> _renderPdfPageImage(
    PdfPage page, {
    required int width,
    required int height,
  }) async {
    final rendered = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
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