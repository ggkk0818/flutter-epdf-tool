import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DocumentCacheStore {
  static const String _rootFolder = 'document_cache';
  static const String _sessionFolder = '_sessions';

  Future<Directory> createSessionDirectory(String sessionId) async {
    final root = await _rootDirectory();
    final dir = Directory(p.join(root.path, _sessionFolder, sessionId));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> deleteSessionDirectory(String sessionId) async {
    final root = await _rootDirectory();
    final dir = Directory(p.join(root.path, _sessionFolder, sessionId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<Directory> ensureDocumentCacheDirectory(
    String remoteId,
    String documentKey,
  ) async {
    final root = await _rootDirectory();
    final dir = Directory(
      p.join(root.path, _safePathSegment(remoteId), documentKey),
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> writeCachedPagePng({
    required String remoteId,
    required String documentKey,
    required int pageIndex,
    required Uint8List pngBytes,
  }) async {
    final path = await cachedPagePath(
      remoteId: remoteId,
      documentKey: documentKey,
      pageIndex: pageIndex,
    );
    await File(path).writeAsBytes(pngBytes, flush: true);
    return path;
  }

  Future<String> writeCachedPageImage({
    required String remoteId,
    required String documentKey,
    required int pageIndex,
    required img.Image image,
  }) {
    return writeCachedPagePng(
      remoteId: remoteId,
      documentKey: documentKey,
      pageIndex: pageIndex,
      pngBytes: Uint8List.fromList(img.encodePng(image)),
    );
  }

  Future<String> cachedPagePath({
    required String remoteId,
    required String documentKey,
    required int pageIndex,
  }) async {
    final dir = await ensureDocumentCacheDirectory(remoteId, documentKey);
    return p.join(dir.path, _pageFileName(pageIndex));
  }

  Future<bool> hasCachedPage({
    required String remoteId,
    required String documentKey,
    required int pageIndex,
  }) async {
    final path = await cachedPagePath(
      remoteId: remoteId,
      documentKey: documentKey,
      pageIndex: pageIndex,
    );
    return File(path).exists();
  }

  Future<void> deleteDocumentCache(String remoteId, String documentKey) async {
    final root = await _rootDirectory();
    final dir = Directory(
      p.join(root.path, _safePathSegment(remoteId), documentKey),
    );
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<List<String>> listCachedPages(
    String remoteId,
    String documentKey,
  ) async {
    final root = await _rootDirectory();
    final dir = Directory(
      p.join(root.path, _safePathSegment(remoteId), documentKey),
    );
    if (!await dir.exists()) {
      return const <String>[];
    }

    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.toLowerCase().endsWith('.png'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files.map((file) => file.path).toList(growable: false);
  }

  Future<Directory> _rootDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, _rootFolder));
    await dir.create(recursive: true);
    return dir;
  }

  String _safePathSegment(String value) {
    return value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _pageFileName(int pageIndex) {
    final page = (pageIndex + 1).toString().padLeft(3, '0');
    return 'page_$page.png';
  }
}