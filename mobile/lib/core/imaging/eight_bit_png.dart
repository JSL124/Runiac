import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Encodes [image] as PNG bytes, narrowed to 8 bits per channel whenever the
/// platform allows it.
///
/// This is a drop-in replacement for
/// `image.toByteData(format: ui.ImageByteFormat.png)` followed by
/// `data?.buffer.asUint8List()`, and keeps that contract exactly: it returns
/// null in the same case (the engine could not encode at all) and never throws
/// on the narrowing path, so every call site keeps its own null handling.
///
/// The bit depth of a directly encoded PNG is not a choice the encoder makes:
/// it follows the surface Flutter rendered into. On a wide-gamut (Display P3)
/// device — every recent iPhone — that surface is F16, so Skia emits depth 16
/// with `sBIT` 10,10,10,10 and the same picture costs roughly twice the bytes.
/// Reading the pixels back with [ui.ImageByteFormat.rawRgba] (8-bit
/// premultiplied) and rebuilding the image through [ui.decodeImageFromPixels]
/// at an explicitly `rgba8888` pixel format produces an image whose encode is
/// depth 8. The narrowing is real and intended: colours outside sRGB are
/// clamped, which is what buys the size reduction.
///
/// Measured, not estimated: one 16-bit 256x256 upload re-encoded from 291,599
/// bytes to 127,643 bytes, a 56% reduction. Production feed thumbnails at
/// 1032x552 show the same split — 382,632 bytes from a wide-gamut device
/// against 252,994 bytes for the same dimensions from one that is not.
///
/// Every failure mode degrades to the direct encode instead of failing the
/// caller, because this is purely a size optimisation on paths that work
/// either way. The narrowed result is accepted only after its IHDR is
/// confirmed to declare depth 8, so a platform where the round-trip does not
/// actually narrow costs one wasted encode rather than a silent regression.
///
/// The direct encode is deliberately attempted FIRST, and the round-trip runs
/// only when that encode really did come back at depth 16. That ordering is
/// load-bearing, not a micro-optimisation: [ui.decodeImageFromPixels] delivers
/// its result through an engine callback that `flutter_test`'s fake async
/// never pumps, so calling it inside a `testWidgets` body hangs forever rather
/// than failing. Host and simulator Skia always encode at depth 8, so with
/// this ordering every widget test returns on the first encode and never
/// reaches the round-trip at all, while a real wide-gamut device — the only
/// place depth 16 occurs, and where the engine callback does fire — still
/// narrows. Do not reorder these two steps.
Future<Uint8List?> encodeEightBitPng(ui.Image image) async {
  final direct = await _encodePngOrNull(image);
  if (direct == null || isEightBitPng(direct)) return direct;
  return await _narrowToEightBitPng(image) ?? direct;
}

Future<Uint8List?> _narrowToEightBitPng(ui.Image image) async {
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) return null;
  final narrowed = await _imageFromPremultipliedRgba8888(
    raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
    image.width,
    image.height,
  );
  try {
    final encoded = await _encodePngOrNull(narrowed);
    if (encoded == null || !isEightBitPng(encoded)) return null;
    return encoded;
  } finally {
    narrowed.dispose();
  }
}

/// Wraps [ui.decodeImageFromPixels] — whose callback form owns the buffer and
/// descriptor disposal contract — as a future. [pixels] must be premultiplied,
/// which is exactly what [ui.ImageByteFormat.rawRgba] produces.
Future<ui.Image> _imageFromPremultipliedRgba8888(
  Uint8List pixels,
  int width,
  int height,
) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<Uint8List?> _encodePngOrNull(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) return null;
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// True when [bytes] is a PNG whose IHDR declares bit depth 8. Reads only the
/// signature and fixed-offset IHDR fields, because the PNG spec requires IHDR
/// to be the first chunk: 8 signature bytes, a 4-byte length, a 4-byte type,
/// then width, height, and the bit depth at byte 24.
///
/// Exposed (rather than private) so tests can assert the property this module
/// exists to guarantee without re-implementing a chunk walker.
bool isEightBitPng(Uint8List bytes) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 25) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return bytes[12] == 0x49 &&
      bytes[13] == 0x48 &&
      bytes[14] == 0x44 &&
      bytes[15] == 0x52 &&
      bytes[24] == 8;
}
