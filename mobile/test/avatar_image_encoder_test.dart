import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/data/avatar/avatar_image_encoder.dart';

/// The server's strict allow-list PNG parser (`validateAvatarPng` in
/// `functions/src/feed/png.ts`) is tested there against hand-built fixtures,
/// never against what Skia's own encoder actually emits. These tests close
/// that gap: they run [encodeAvatarPng] on a real generated source image and
/// walk the emitted bytes with a small local chunk-walker, asserting the
/// exact structural properties the server demands.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('encodeAvatarPng', () {
    test(
      'encodes a landscape source into a server-compliant 256x256 avatar PNG',
      () async {
        final source = await _sourcePng(400, 200);
        await _expectCompliantAvatarPng(await encodeAvatarPng(source));
      },
    );

    test(
      'encodes a portrait source into a server-compliant 256x256 avatar PNG',
      () async {
        final source = await _sourcePng(200, 500);
        await _expectCompliantAvatarPng(await encodeAvatarPng(source));
      },
    );

    test(
      'encodes a source smaller than 256x256 into a server-compliant avatar PNG',
      () async {
        final source = await _sourcePng(64, 64);
        await _expectCompliantAvatarPng(await encodeAvatarPng(source));
      },
    );

    test(
      'encodes a source much larger than 256x256 into a server-compliant avatar PNG',
      () async {
        final source = await _sourcePng(2048, 3000);
        await _expectCompliantAvatarPng(await encodeAvatarPng(source));
      },
    );

    // The encoder narrows its output to 8 bits per channel by reading the
    // rendered pixels back as raw RGBA and rebuilding the image from them.
    // That round-trip is where a wrong pixel format or a premultiplied/straight
    // alpha mismatch would silently corrupt every uploaded photo rather than
    // fail it, so this decodes the encoded result and checks the actual pixels
    // survived: the centre lands inside the source's yellow circle and the
    // corner in its blue field, with the centre crop keeping both in place.
    test('preserves image content through the 8-bit round trip', () async {
      final encoded = await encodeAvatarPng(await _sourcePng(400, 200));
      final pixels = await _decodeToRgba(encoded);

      _expectPixel(pixels, x: 128, y: 128, red: 0xFF, green: 0xCC, blue: 0x00);
      _expectPixel(pixels, x: 4, y: 4, red: 0x33, green: 0x66, blue: 0x99);
    });

    test('encodes an opaque avatar, so the round trip loses no alpha', () async {
      final encoded = await encodeAvatarPng(await _sourcePng(400, 200));
      final pixels = await _decodeToRgba(encoded);

      const corners = <List<int>>[
        <int>[0, 0],
        <int>[255, 0],
        <int>[0, 255],
        <int>[255, 255],
        <int>[128, 128],
      ];
      for (final point in corners) {
        final offset = ((point[1] * avatarEncodedDimension) + point[0]) * 4;
        expect(
          pixels.getUint8(offset + 3),
          255,
          reason: 'pixel ${point[0]},${point[1]} must stay fully opaque',
        );
      }
    });
  });
}

/// Decodes [png] back into raw RGBA bytes so a test can assert on real pixel
/// values rather than only on chunk structure.
Future<ByteData> _decodeToRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  try {
    expect(image.width, avatarEncodedDimension);
    expect(image.height, avatarEncodedDimension);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull, reason: 'the encoded avatar PNG must be decodable');
    return data!;
  } finally {
    image.dispose();
  }
}

/// Asserts the pixel at ([x], [y]) matches the expected channels. The tolerance
/// absorbs resampling at the circle's antialiased edge and the sRGB clamp the
/// narrowing step performs; it is far tighter than any channel swap, alpha
/// premultiplication mistake, or garbled round-trip would produce.
void _expectPixel(
  ByteData pixels, {
  required int x,
  required int y,
  required int red,
  required int green,
  required int blue,
}) {
  final offset = ((y * avatarEncodedDimension) + x) * 4;
  final actual = <int>[
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
  ];
  final expected = <int>[red, green, blue];
  for (var channel = 0; channel < expected.length; channel++) {
    expect(
      actual[channel],
      closeTo(expected[channel], 8),
      reason: 'pixel $x,$y expected RGB $expected but decoded as $actual',
    );
  }
}

Future<void> _expectCompliantAvatarPng(Uint8List encoded) async {
  expect(
    encoded.lengthInBytes,
    lessThanOrEqualTo(1024 * 1024),
    reason: 'avatar PNGs must stay within the server\'s 1 MiB byte limit',
  );
  final structure = _walkPng(encoded);
  expect(structure.width, avatarEncodedDimension);
  expect(structure.height, avatarEncodedDimension);
  // Host/simulator Skia emits bit depth 8; a wide-gamut (Display P3) device
  // renders into an F16 surface and emits bit depth 16 with sBIT 10,10,10,10
  // instead. The server accepts both and nothing else, so this test cannot
  // pin the depth to 8 — that assertion passed on the host while every real
  // device upload was rejected.
  expect(
    structure.bitDepth,
    anyOf(8, 16),
    reason: 'validateAvatarPng requires bit depth 8, or 16 with sBIT 10',
  );
  final significantBits = structure.bitDepth == 16 ? 10 : 8;
  if (structure.bitDepth == 16) {
    expect(
      structure.sBitValues,
      isNotNull,
      reason: 'validateAvatarPng requires an sBIT chunk at bit depth 16',
    );
  }
  if (structure.sBitValues != null) {
    expect(
      structure.sBitValues,
      List<int>.filled(4, significantBits),
      reason: 'validateAvatarPng requires sBIT to declare $significantBits '
          'significant bits per channel at bit depth ${structure.bitDepth}',
    );
  }
  expect(structure.colorType, 6, reason: 'validateAvatarPng requires colour type 6 (RGBA)');
  expect(structure.compression, 0);
  expect(structure.filter, 0);
  expect(structure.interlace, 0, reason: 'validateAvatarPng rejects interlaced PNGs');
  expect(
    structure.idatChunkCount,
    greaterThan(0),
    reason: 'validateAvatarPng requires at least one non-empty IDAT',
  );
  expect(structure.idatTotalBytes, greaterThan(0));
}

/// Generates real, decodable source PNG bytes at an arbitrary size (a solid
/// fill plus a circle, so the pixel data is not degenerate) via the same
/// Canvas -> toImage -> toByteData(png) pipeline the app itself uses. This is
/// standing in for whatever `image_picker` would hand back from the gallery.
Future<Uint8List> _sourcePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const Color(0xFF336699),
  );
  canvas.drawCircle(
    ui.Offset(width / 2, height / 2),
    (width < height ? width : height) / 3,
    ui.Paint()..color = const Color(0xFFFFCC00),
  );
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

const _allowedAvatarPngChunkTypes = <String>{
  'IHDR',
  'cHRM',
  'gAMA',
  'sBIT',
  'sRGB',
  'IDAT',
  'IEND',
};

class _PngStructure {
  _PngStructure({
    required this.width,
    required this.height,
    required this.bitDepth,
    required this.colorType,
    required this.compression,
    required this.filter,
    required this.interlace,
    required this.idatChunkCount,
    required this.idatTotalBytes,
    required this.sBitValues,
  });

  final int width;
  final int height;
  final int bitDepth;
  final int colorType;
  final int compression;
  final int filter;
  final int interlace;
  final int idatChunkCount;
  final int idatTotalBytes;

  /// The four sBIT bytes when the encoder emitted an sBIT chunk, or null when
  /// it did not. `validateAvatarPng` requires one at bit depth 16 and pins its
  /// value in either case.
  final List<int>? sBitValues;
}

/// Small local PNG chunk-walker, deliberately independent of the server's
/// TypeScript implementation, that asserts exactly the structural properties
/// `validateAvatarPng` in `functions/src/feed/png.ts` demands: the PNG
/// signature; a single IHDR at offset 8 declaring 256x256/8-bit/colour-type
/// 6/no interlace; every chunk type present is in the allow-list; at least
/// one non-empty IDAT; and IEND is the last chunk with nothing following it.
_PngStructure _walkPng(Uint8List bytes) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  expect(
    bytes.length,
    greaterThanOrEqualTo(signature.length),
    reason: 'PNG must be at least as long as its signature',
  );
  for (var index = 0; index < signature.length; index++) {
    expect(bytes[index], signature[index], reason: 'PNG signature byte $index');
  }

  var offset = signature.length;
  int? width;
  int? height;
  int? bitDepth;
  int? colorType;
  int? compression;
  int? filter;
  int? interlace;
  var sawIhdr = false;
  var idatCount = 0;
  var idatBytes = 0;
  var sawIend = false;
  List<int>? sBitValues;

  while (offset < bytes.length) {
    expect(
      offset + 12 <= bytes.length,
      isTrue,
      reason: 'chunk length/type/CRC header must fit within the byte stream',
    );
    final length = _uint32(bytes, offset);
    final typeStart = offset + 4;
    final dataStart = offset + 8;
    final dataEnd = dataStart + length;
    final crcEnd = dataEnd + 4;
    expect(
      crcEnd <= bytes.length,
      isTrue,
      reason: 'chunk data/CRC must fit within the byte stream',
    );
    final type = String.fromCharCodes(bytes.sublist(typeStart, typeStart + 4));
    expect(
      _allowedAvatarPngChunkTypes.contains(type),
      isTrue,
      reason: 'chunk type "$type" is outside the server allow-list',
    );

    if (type == 'IHDR') {
      expect(offset, signature.length, reason: 'IHDR must be the first chunk');
      expect(length, 13);
      width = _uint32(bytes, dataStart);
      height = _uint32(bytes, dataStart + 4);
      bitDepth = bytes[dataStart + 8];
      colorType = bytes[dataStart + 9];
      compression = bytes[dataStart + 10];
      filter = bytes[dataStart + 11];
      interlace = bytes[dataStart + 12];
      sawIhdr = true;
    } else if (type == 'sBIT') {
      expect(length, 4, reason: 'validateAvatarPng requires a 4-byte sBIT');
      sBitValues = bytes.sublist(dataStart, dataStart + length).toList();
    } else if (type == 'IDAT') {
      expect(sawIhdr, isTrue, reason: 'IDAT must follow IHDR');
      expect(length, greaterThan(0), reason: 'IDAT chunk must not be empty');
      idatCount += 1;
      idatBytes += length;
    } else if (type == 'IEND') {
      expect(length, 0);
      expect(
        crcEnd,
        bytes.length,
        reason: 'IEND must be the final chunk with nothing following it',
      );
      sawIend = true;
    }

    offset = crcEnd;
    if (sawIend) {
      break;
    }
  }

  expect(sawIend, isTrue, reason: 'PNG stream must end with IEND');
  expect(
    offset,
    bytes.length,
    reason: 'no bytes may appear after IEND',
  );
  expect(idatCount, greaterThan(0), reason: 'PNG must contain at least one IDAT');

  return _PngStructure(
    width: width!,
    height: height!,
    bitDepth: bitDepth!,
    colorType: colorType!,
    compression: compression!,
    filter: filter!,
    interlace: interlace!,
    idatChunkCount: idatCount,
    idatTotalBytes: idatBytes,
    sBitValues: sBitValues,
  );
}

int _uint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
