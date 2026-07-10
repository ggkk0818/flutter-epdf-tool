import 'dart:convert';
import 'dart:typed_data';

class LineBuffer {
  LineBuffer();

  final List<int> _buf = <int>[];

  void add(List<int> chunk) {
    if (chunk.isEmpty) return;
    _buf.addAll(chunk);
  }

  List<String> drain() {
    final List<String> lines = <String>[];
    int idx;
    while ((idx = _buf.indexOf(0x0A)) >= 0) {
      final lineBytes = _buf.sublist(0, idx);
      _buf.removeRange(0, idx + 1);
      if (lineBytes.isEmpty) continue;
      try {
        lines.add(utf8.decode(lineBytes));
      } on Object {
        continue;
      }
    }
    return lines;
  }

  void clear() => _buf.clear();
}

class BleCommand {
  BleCommand._();

  static Uint8List encode(Map<String, dynamic> payload) {
    final body = jsonEncode(payload);
    final bytes = utf8.encode('$body\n');
    return Uint8List.fromList(bytes);
  }

  static Map<String, dynamic>? decode(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) return decoded;
    } on Object {
      // not valid JSON — ignore
    }
    return null;
  }
}
