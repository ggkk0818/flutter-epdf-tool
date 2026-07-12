import 'package:path/path.dart' as p;

import '../../shared/ble/models.dart';

final RegExp _illegalFatNameChars = RegExp(r'[\\/:*?"<>|]');

String? validateDocumentName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '请输入文档名称';
  }
  if (trimmed.startsWith('.') || trimmed.endsWith('.') ||
      value.endsWith(' ') || value.startsWith(' ')) {
    return '文档名不能以空格或点开头或结尾';
  }
  if (_illegalFatNameChars.hasMatch(trimmed)) {
    return '文档名不能包含 \\ / : * ? " < > |';
  }
  for (final codeUnit in trimmed.codeUnits) {
    if (codeUnit < 32) {
      return '文档名不能包含控制字符';
    }
  }
  return null;
}

String sanitizeSuggestedDocumentName(String raw) {
  var name = raw.trim().replaceAll(_illegalFatNameChars, '_');
  name = name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  if (name.isEmpty) {
    return '新文档';
  }
  return name;
}

String suggestDocumentNameFromPath(String path) {
  return sanitizeSuggestedDocumentName(p.basenameWithoutExtension(path));
}

String buildDocumentDisplayTime(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

String buildCanonicalDocumentKey({
  required String name,
  required String displayTime,
  required int pages,
}) {
  final normalizedTime = displayTime
      .replaceFirst(' ', '_')
      .replaceRange(13, 14, '-')
      .replaceRange(16, 17, '-');
  final pagePart = pages.toString().padLeft(3, '0');
  return '${normalizedTime}_${pagePart}_$name';
}

String buildCanonicalDocumentKeyFromMeta(DocumentMeta meta) {
  return buildCanonicalDocumentKey(
    name: meta.name,
    displayTime: meta.time,
    pages: meta.pages,
  );
}