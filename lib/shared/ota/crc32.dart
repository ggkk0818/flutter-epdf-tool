import 'dart:typed_data';

/// Standard IEEE CRC32 (polynomial 0xEDB88320, init 0xFFFFFFFF, final XOR
/// 0xFFFFFFFF) — same value zip, PNG, and `esp_crc32_le` on the ESP32 produce.
/// Used by OTA to verify the firmware image end-to-end.
class Crc32 {
  Crc32._();

  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
        final table = Uint32List(256);
        for (int i = 0; i < 256; i++) {
            int c = i;
            for (int k = 0; k < 8; k++) {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
            }
            table[i] = c & 0xFFFFFFFF;
        }
        return table;
  }

  /// Compute CRC32 of [data]. Returns the standard zip-style CRC as an
  /// unsigned 32-bit integer.
  static int compute(Uint8List data) {
    int crc = 0xFFFFFFFF;
    final t = _table;
    for (int i = 0; i < data.length; i++) {
      crc = (crc >>> 8) ^ t[(crc ^ data[i]) & 0xFF];
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
