import 'dart:typed_data';

import 'package:image/image.dart' as img;

class EpdfPageBinHeader {
  const EpdfPageBinHeader({
    required this.magic,
    required this.version,
    required this.width,
    required this.height,
    required this.reserved,
  });

  final int magic;
  final int version;
  final int width;
  final int height;
  final int reserved;
}

class EpdfPageBinImage {
  const EpdfPageBinImage({
    required this.header,
    required this.image,
  });

  final EpdfPageBinHeader header;
  final img.Image image;
}

class EpdfPageBinCodec {
  EpdfPageBinCodec._();

  static const int magic = 0xE5;
  static const int version = 0x01;
  static const int headerBytes = 8;

  static Uint8List encode(img.Image image) {
    final header = ByteData(headerBytes)
      ..setUint8(0, magic)
      ..setUint8(1, version)
      ..setUint16(2, image.width, Endian.little)
      ..setUint16(4, image.height, Endian.little)
      ..setUint16(6, 0, Endian.little);

    final rowBytes = ((image.width + 7) ~/ 8);
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

  static EpdfPageBinImage decode(Uint8List bytes) {
    if (bytes.length < headerBytes) {
      throw const FormatException('Preview data is missing the EPDF header.');
    }

    final data = ByteData.sublistView(bytes);
    final header = EpdfPageBinHeader(
      magic: data.getUint8(0),
      version: data.getUint8(1),
      width: data.getUint16(2, Endian.little),
      height: data.getUint16(4, Endian.little),
      reserved: data.getUint16(6, Endian.little),
    );

    if (header.magic != magic) {
      throw FormatException('Unsupported EPDF magic: 0x${header.magic.toRadixString(16)}');
    }
    if (header.version != version) {
      throw FormatException('Unsupported EPDF version: ${header.version}');
    }
    if (header.width <= 0 || header.height <= 0) {
      throw const FormatException('Preview image dimensions are invalid.');
    }

    final rowBytes = ((header.width + 7) ~/ 8);
    final expectedBodyBytes = rowBytes * header.height;
    final actualBodyBytes = bytes.length - headerBytes;
    if (actualBodyBytes != expectedBodyBytes) {
      throw FormatException(
        'Preview payload length mismatch: expected $expectedBodyBytes, got $actualBodyBytes.',
      );
    }

    final image = img.Image(width: header.width, height: header.height);
    final bodyOffset = headerBytes;
    for (int y = 0; y < header.height; y++) {
      final rowOffset = bodyOffset + (y * rowBytes);
      for (int x = 0; x < header.width; x++) {
        final byteValue = bytes[rowOffset + (x ~/ 8)];
        final bit = (byteValue & (0x80 >> (x % 8))) != 0;
        image.setPixelRgba(
          x,
          y,
          bit ? 0 : 255,
          bit ? 0 : 255,
          bit ? 0 : 255,
          255,
        );
      }
    }

    return EpdfPageBinImage(header: header, image: image);
  }
}