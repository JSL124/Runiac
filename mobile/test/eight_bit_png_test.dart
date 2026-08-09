import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/imaging/eight_bit_png.dart';

/// [encodeEightBitPng] exists to make the PNGs this app uploads independent of
/// the surface precision the device rendered into: on a wide-gamut (Display
/// P3) device Flutter renders into F16 and Skia emits bit depth 16, which
/// roughly doubles the bytes on every feed thumbnail, share card, and avatar.
///
/// Host and simulator Skia emit depth 8 regardless, so these tests cannot
/// prove the wide-gamut path narrows — only a real device can, and the capsule
/// records that as user-owned. What they DO prove is the part that would fail
/// silently rather than loudly: that the raw-RGBA round-trip returns a real,
/// decodable image with its pixels and alpha intact, which is exactly what a
/// wrong pixel format or a premultiplied/straight alpha mismatch would break.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('encodeEightBitPng', () {
    test('encodes a decodable PNG declaring bit depth 8', () async {
      final image = await _renderTestImage(120, 90);
      try {
        final encoded = await encodeEightBitPng(image);

        expect(encoded, isNotNull);
        expect(
          isEightBitPng(encoded!),
          isTrue,
          reason: 'the narrowed encode must declare bit depth 8 in its IHDR',
        );
      } finally {
        image.dispose();
      }
    });

    test('preserves pixels and alpha through the round trip', () async {
      final image = await _renderTestImage(120, 90);
      try {
        final encoded = await encodeEightBitPng(image);
        final pixels = await _decodeToRgba(encoded!, 120, 90);

        // The source is a blue field with a yellow band across its middle.
        _expectPixel(pixels, 120, x: 8, y: 8, rgb: <int>[0x33, 0x66, 0x99]);
        _expectPixel(pixels, 120, x: 60, y: 45, rgb: <int>[0xFF, 0xCC, 0x00]);
        _expectAlpha(pixels, 120, x: 8, y: 8);
        _expectAlpha(pixels, 120, x: 60, y: 45);
      } finally {
        image.dispose();
      }
    });

    test('preserves the source dimensions exactly', () async {
      final image = await _renderTestImage(37, 101);
      try {
        final encoded = await encodeEightBitPng(image);
        final decoded = await _decodeImage(encoded!);

        try {
          expect(decoded.width, 37);
          expect(decoded.height, 101);
        } finally {
          decoded.dispose();
        }
      } finally {
        image.dispose();
      }
    });
  });

  group('isEightBitPng', () {
    test('rejects bytes that are not a PNG at all', () {
      expect(isEightBitPng(Uint8List.fromList(List<int>.filled(64, 0))), isFalse);
    });

    test('rejects a truncated PNG', () {
      expect(
        isEightBitPng(
          Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0]),
        ),
        isFalse,
      );
    });

    test('rejects a PNG whose IHDR declares bit depth 16', () {
      expect(isEightBitPng(_ihdrOnlyPng(bitDepth: 16)), isFalse);
      expect(isEightBitPng(_ihdrOnlyPng(bitDepth: 8)), isTrue);
    });
  });
}

/// Renders a blue field with a yellow band across the middle, so a decoded
/// result has two unambiguous sample points and is never a degenerate flat
/// image that would hide a channel swap.
Future<ui.Image> _renderTestImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const Color(0xFF336699),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, height / 3, width.toDouble(), height / 3),
    ui.Paint()..color = const Color(0xFFFFCC00),
  );
  return recorder.endRecording().toImage(width, height);
}

Future<ui.Image> _decodeImage(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<ByteData> _decodeToRgba(Uint8List png, int width, int height) async {
  final image = await _decodeImage(png);
  try {
    expect(image.width, width);
    expect(image.height, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull, reason: 'the encoded PNG must be decodable');
    return data!;
  } finally {
    image.dispose();
  }
}

void _expectPixel(
  ByteData pixels,
  int width, {
  required int x,
  required int y,
  required List<int> rgb,
}) {
  final offset = ((y * width) + x) * 4;
  final actual = <int>[
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
  ];
  for (var channel = 0; channel < rgb.length; channel++) {
    expect(
      actual[channel],
      closeTo(rgb[channel], 8),
      reason: 'pixel $x,$y expected RGB $rgb but decoded as $actual',
    );
  }
}

void _expectAlpha(ByteData pixels, int width, {required int x, required int y}) {
  expect(
    pixels.getUint8((((y * width) + x) * 4) + 3),
    255,
    reason: 'pixel $x,$y must stay fully opaque through the round trip',
  );
}

/// A PNG signature plus a single IHDR chunk, which is all [isEightBitPng]
/// reads. Not a decodable image, and deliberately so: this exercises the
/// header check in isolation from any encoder.
Uint8List _ihdrOnlyPng({required int bitDepth}) {
  return Uint8List.fromList(<int>[
    137, 80, 78, 71, 13, 10, 26, 10, // signature
    0, 0, 0, 13, // IHDR length
    0x49, 0x48, 0x44, 0x52, // "IHDR"
    0, 0, 0, 16, // width
    0, 0, 0, 16, // height
    bitDepth, 6, 0, 0, 0, // depth, colour type, compression, filter, interlace
  ]);
}
