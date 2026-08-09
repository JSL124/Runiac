import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_level_profile_badge.dart';
import '../../../feed/data/feed_publish/feed_thumbnail_artifact.dart';
import '../../../feed/domain/models/feed_display_models.dart';
import '../../domain/models/run_summary_snapshot.dart';

/// Shows what a run will look like as a feed post, before it is published.
///
/// Built from the same display models the real feed renders, so the preview
/// cannot drift away from the posted result — if the feed card changes, this
/// changes with it.
class ShareRouteFeedPostPreview extends StatelessWidget {
  const ShareRouteFeedPostPreview({
    required this.artifact,
    required this.summary,
    required this.authorProfile,
    super.key,
  });

  final FeedThumbnailArtifact? artifact;
  final RunSummarySnapshot summary;
  final FeedAuthorProfileSnapshot authorProfile;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: RuniacColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: RuniacColors.primaryBlue.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 9),
              child: _FeedPreviewHeader(authorProfile: authorProfile),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                summary.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RuniacColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
            ),
            _FeedPreviewThumbnail(artifact: artifact),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: ShareRouteMetrics(summary: summary),
            ),
            const Divider(
              height: 22,
              thickness: 1,
              indent: 14,
              endIndent: 14,
              color: RuniacColors.border,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _FeedPreviewAction(icon: Icons.favorite_border, value: '0'),
                  SizedBox(width: 20),
                  _FeedPreviewAction(
                    icon: Icons.mode_comment_outlined,
                    value: '0',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedPreviewHeader extends StatelessWidget {
  const _FeedPreviewHeader({required this.authorProfile});

  final FeedAuthorProfileSnapshot authorProfile;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      RuniacLevelProfileBadge(
        key: const ValueKey('share-feed-preview-profile-badge'),
        initials: authorProfile.avatarInitials,
        levelLabel: authorProfile.compactLevelLabel,
        progressFraction: authorProfile.levelProgressFraction,
        photoUrl: authorProfile.avatarUrl,
        size: 40,
        badgeHeight: 15,
        badgeMinWidth: 39,
        badgeHorizontalPadding: 5,
        badgeFontSize: 8.5,
        ringStrokeWidth: 4,
        discColor: RuniacColors.primaryBlue,
        discBorderColor: RuniacColors.white,
        initialsColor: RuniacColors.white,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              authorProfile.displayName,
              style: const TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 1),
            const Text(
              'Ready to post',
              style: TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      Icon(Icons.more_horiz, color: RuniacColors.textSecondary, size: 20),
    ],
  );
}

class _FeedPreviewThumbnail extends StatelessWidget {
  const _FeedPreviewThumbnail({required this.artifact});

  final FeedThumbnailArtifact? artifact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: artifact == null
        ? 'Private route preview unavailable'
        : 'Feed route thumbnail preview',
    image: true,
    child: ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 344 / 184,
        child: artifact == null
            ? const ColoredBox(
                color: RuniacColors.sectionSurface,
                child: Center(
                  child: Icon(
                    Icons.route_outlined,
                    color: RuniacColors.textSecondary,
                  ),
                ),
              )
            : Image(image: artifact!.memoryImage, fit: BoxFit.cover),
      ),
    ),
  );
}

class ShareRouteMetrics extends StatelessWidget {
  const ShareRouteMetrics({required this.summary, super.key});
  final RunSummarySnapshot summary;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      _Metric('Distance', '${summary.distanceKm} km'),
      const _Divider(),
      _Metric('Pace', '${summary.avgPace} / km'),
      const _Divider(),
      _Metric('Time', summary.duration),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: RuniacColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: RuniacColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 34,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: RuniacColors.border,
  );
}

class _FeedPreviewAction extends StatelessWidget {
  const _FeedPreviewAction({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: RuniacColors.textSecondary, size: 20),
      const SizedBox(width: 5),
      Text(
        value,
        style: const TextStyle(
          color: RuniacColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
