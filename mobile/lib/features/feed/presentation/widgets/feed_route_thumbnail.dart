import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../domain/models/feed_display_models.dart';

class FeedRouteThumbnail extends StatelessWidget {
  const FeedRouteThumbnail({required this.thumbnail, super.key});

  final FeedRouteThumbnailReadModel thumbnail;

  @override
  Widget build(BuildContext context) {
    final bytes = thumbnail.pngBytes;
    return Semantics(
      label: bytes == null || bytes.isEmpty
          ? 'Private route preview unavailable'
          : thumbnail.accessibilityLabel,
      image: true,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 212,
          width: double.infinity,
          child: bytes == null || bytes.isEmpty
              ? const _FeedRouteThumbnailPlaceholder()
              : Image.memory(bytes, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _FeedRouteThumbnailPlaceholder extends StatelessWidget {
  const _FeedRouteThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: RuniacColors.sectionSurface,
    child: const Center(
      child: Icon(Icons.route_outlined, color: RuniacColors.textSecondary),
    ),
  );
}
