import 'dart:io';

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
}