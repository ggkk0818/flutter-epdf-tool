import 'dart:typed_data';

import 'package:epdf_tool/shared/ble/epdf_page_bin_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('encodes and decodes EPDF page bin images', () {
    final image = img.Image(width: 10, height: 2);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    image.setPixelRgba(0, 0, 0, 0, 0, 255);
    image.setPixelRgba(7, 0, 0, 0, 0, 255);
    image.setPixelRgba(9, 1, 0, 0, 0, 255);

    final bytes = EpdfPageBinCodec.encode(image);
    final decoded = EpdfPageBinCodec.decode(bytes);

    expect(decoded.header.magic, EpdfPageBinCodec.magic);
    expect(decoded.header.version, EpdfPageBinCodec.version);
    expect(decoded.header.width, 10);
    expect(decoded.header.height, 2);

    expect(decoded.image.getPixel(0, 0).r, 0);
    expect(decoded.image.getPixel(7, 0).r, 0);
    expect(decoded.image.getPixel(9, 1).r, 0);
    expect(decoded.image.getPixel(1, 0).r, 255);
    expect(decoded.image.getPixel(8, 1).r, 255);
  });

  test('rejects truncated EPDF preview payloads', () {
    final image = img.Image(width: 8, height: 1);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final bytes = EpdfPageBinCodec.encode(image);
    final truncated = Uint8List.fromList(bytes.sublist(0, bytes.length - 1));

    expect(
      () => EpdfPageBinCodec.decode(truncated),
      throwsA(isA<FormatException>()),
    );
  });
}