import 'dart:typed_data';

import '../../../you/presentation/widgets/activity_route_preview.dart';
import 'feed_thumbnail_artifact.dart';

class FeedThumbnailCapture {
  const FeedThumbnailCapture({required this.provider});

  final ActivityRouteThumbnailProvider provider;

  Future<FeedThumbnailArtifact> capture(
    ActivityRouteThumbnailRequest request,
  ) async {
    final result = await provider.resolve(request);
    final bytes = result.pngBytes;
    if (!result.hasReadyImage || bytes == null) {
      throw const FeedThumbnailCaptureException(
        'A private route preview is not available yet.',
      );
    }
    final scale = request.canonicalDevicePixelRatio;
    final logicalWidth = request.logicalSize.width;
    final logicalHeight = request.logicalSize.height;
    final hasSupportedLogicalSize =
        (logicalWidth == 88 && logicalHeight == 88) ||
        (logicalWidth == 344 && logicalHeight == 184);
    final expectedWidth = (logicalWidth * scale).round();
    final expectedHeight = (logicalHeight * scale).round();
    final details = _readPngDetails(bytes);
    if (!hasSupportedLogicalSize ||
        details.width != expectedWidth ||
        details.height != expectedHeight ||
        bytes.lengthInBytes > _maxPngBytes) {
      throw const FeedThumbnailCaptureException(
        'This route preview cannot be posted. Please try again.',
      );
    }
    return FeedThumbnailArtifact(bytes);
  }
}

class FeedThumbnailCaptureException implements Exception {
  const FeedThumbnailCaptureException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _PngDetails {
  const _PngDetails({required this.width, required this.height});
  final int width;
  final int height;
}

_PngDetails _readPngDetails(Uint8List bytes) {
  if (bytes.lengthInBytes < 33 || !_hasPngSignature(bytes)) {
    throw const FeedThumbnailCaptureException(
      'This route preview cannot be posted. Please try again.',
    );
  }
  var offset = 8;
  int? width;
  int? height;
  var foundIend = false;
  var foundNonEmptyIdat = false;
  var sawIhdr = false;
  final seenTypes = <String>{};
  while (offset + 12 <= bytes.lengthInBytes) {
    final length = _readU32(bytes, offset);
    final typeOffset = offset + 4;
    final dataOffset = offset + 8;
    final next = dataOffset + length + 4;
    if (next > bytes.lengthInBytes) break;
    final type = String.fromCharCodes(
      bytes.sublist(typeOffset, typeOffset + 4),
    );
    if (!seenTypes.add(type) && type != 'IDAT') break;
    if (_crc32(bytes, typeOffset, dataOffset + length) !=
        _readU32(bytes, dataOffset + length)) {
      break;
    }
    if (type == 'IHDR' &&
        length == 13 &&
        !sawIhdr &&
        offset == 8 &&
        _validIhdr(bytes, dataOffset)) {
      sawIhdr = true;
      width = _readU32(bytes, dataOffset);
      height = _readU32(bytes, dataOffset + 4);
    } else if (_validBenignPreIdat(
      type,
      bytes,
      dataOffset,
      length,
      sawIhdr,
      foundNonEmptyIdat,
    )) {
      offset = next;
      continue;
    } else if (type == 'IDAT' && sawIhdr && length > 0) {
      foundNonEmptyIdat = true;
    } else if (type == 'IEND' &&
        length == 0 &&
        foundNonEmptyIdat &&
        next == bytes.lengthInBytes) {
      foundIend = true;
      break;
    } else {
      break;
    }
    offset = next;
  }
  if (width == null || height == null || !foundNonEmptyIdat || !foundIend) {
    throw const FeedThumbnailCaptureException(
      'This route preview cannot be posted. Please try again.',
    );
  }
  return _PngDetails(width: width, height: height);
}

bool _hasPngSignature(Uint8List bytes) =>
    bytes[0] == 137 &&
    bytes[1] == 80 &&
    bytes[2] == 78 &&
    bytes[3] == 71 &&
    bytes[4] == 13 &&
    bytes[5] == 10 &&
    bytes[6] == 26 &&
    bytes[7] == 10;

bool _validIhdr(Uint8List bytes, int offset) =>
    _readU32(bytes, offset) > 0 &&
    _readU32(bytes, offset + 4) > 0 &&
    bytes[offset + 8] == 8 &&
    bytes[offset + 9] == 6 &&
    bytes[offset + 10] == 0 &&
    bytes[offset + 11] == 0 &&
    bytes[offset + 12] == 0;

bool _validBenignPreIdat(
  String type,
  Uint8List bytes,
  int offset,
  int length,
  bool sawIhdr,
  bool foundIdat,
) =>
    sawIhdr &&
    !foundIdat &&
    switch (type) {
      'sBIT' =>
        length == 4 &&
            bytes.sublist(offset, offset + 4).every((value) => value == 8),
      'sRGB' => length == 1 && bytes[offset] == 0,
      'gAMA' => length == 4 && _readU32(bytes, offset) == 45455,
      'cHRM' => length == 32 && _matchesCanonicalChromaticities(bytes, offset),
      _ => false,
    };

bool _matchesCanonicalChromaticities(Uint8List bytes, int offset) {
  for (var index = 0; index < _canonicalChromaticities.length; index += 1) {
    if (_readU32(bytes, offset + index * 4) !=
        _canonicalChromaticities[index]) {
      return false;
    }
  }
  return true;
}

const _canonicalChromaticities = <int>[
  31270,
  32900,
  64000,
  33000,
  30000,
  60000,
  15000,
  6000,
];

int _readU32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _crc32(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var index = start; index < end; index += 1) {
    crc ^= bytes[index];
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

const _maxPngBytes = 1024 * 1024;
