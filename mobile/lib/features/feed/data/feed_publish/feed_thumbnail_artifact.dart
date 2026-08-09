import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// A verified, privacy-masked PNG used by both History and Feed publishing.
class FeedThumbnailArtifact {
  FeedThumbnailArtifact(this.pngBytes)
    : assert(pngBytes.isNotEmpty, 'A thumbnail artifact cannot be empty');

  final Uint8List pngBytes;

  MemoryImage get memoryImage => MemoryImage(pngBytes);
}
