import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/imaging/eight_bit_png.dart';
import 'package:runiac_app/core/share/share_card_export_service.dart';

/// Coverage note, stated plainly because it matters for how much these tests
/// prove: the defect that actually broke sharing on device was
/// `capturePng` returning `encodeEightBitPng(image)` without awaiting it, so
/// the `finally` disposed the image mid-encode. That only surfaces on the
/// second encode pass, which `encodeEightBitPng` runs solely when the first
/// encode came back at bit depth 16 — and host/simulator Skia always emits
/// depth 8 (see eight_bit_png_test.dart, which records the same limitation).
/// So these tests CANNOT reproduce it; only a wide-gamut device can, and that
/// stays user-owned verification.
///
/// What they do pin is the part that made a one-word bug invisible for a week:
/// `capturePng` must return `null` on a failure rather than throwing, because
/// every caller treats `null` as "show the runner an error" and an escaping
/// exception was swallowed by the caller's catch-less busy wrapper.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = ShareCardExportService();

  testWidgets('capturePng rasterizes a laid-out boundary to a decodable PNG', (
    WidgetTester tester,
  ) async {
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: const SizedBox(
              width: 40,
              height: 24,
              child: ColoredBox(color: Color(0xFF2F51C8)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Uint8List? bytes;
    int? decodedWidth;
    int? decodedHeight;
    // Everything that waits on an engine callback must run inside runAsync:
    // `flutter_test`'s fake async never pumps those, so a bare await hangs.
    await tester.runAsync(() async {
      bytes = await service.capturePng(boundaryKey, pixelRatio: 2.0);
      if (bytes != null) {
        final decoded = await _decode(bytes!);
        decodedWidth = decoded.width;
        decodedHeight = decoded.height;
        decoded.dispose();
      }
    });

    expect(bytes, isNotNull);
    expect(
      isEightBitPng(bytes!),
      isTrue,
      reason: 'the export pipeline must produce a real PNG, not empty bytes',
    );
    expect(decodedWidth, 80);
    expect(decodedHeight, 48);
  });

  testWidgets('capturePng returns null when the key holds no boundary', (
    WidgetTester tester,
  ) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(home: SizedBox(key: key, width: 10, height: 10)),
    );
    await tester.pumpAndSettle();

    Uint8List? bytes;
    var threw = false;
    await tester.runAsync(() async {
      try {
        bytes = await service.capturePng(key);
      } catch (_) {
        threw = true;
      }
    });

    expect(threw, isFalse, reason: 'a failure must be reportable, not thrown');
    expect(bytes, isNull);
  });

  testWidgets('capturePng returns null for an unattached key', (
    WidgetTester tester,
  ) async {
    // A key that was never attached has no render object at all. The share
    // sheet reaches this when the sheet is torn down mid-export; it must
    // surface as a null result the caller can report, never as an exception.
    Uint8List? bytes;
    var threw = false;
    await tester.runAsync(() async {
      try {
        bytes = await service.capturePng(GlobalKey());
      } catch (_) {
        threw = true;
      }
    });

    expect(threw, isFalse);
    expect(bytes, isNull);
  });
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}
