import 'package:flutter/material.dart';

import '../../../../core/haptics/runiac_haptics_scope.dart';
import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_level_profile_badge.dart';
import '../../../profile/presentation/widgets/runner_profile_avatar_link.dart';
import '../../../you/presentation/widgets/you_surface_primitives.dart';
import '../../domain/models/feed_display_models.dart';
import '../feed_timeline_screen_controller.dart';
import 'feed_engagement_action.dart';
import 'feed_route_thumbnail.dart';

class FeedPostSection extends StatelessWidget {
  const FeedPostSection({
    required this.post,
    required this.controller,
    super.key,
  });

  final FeedPostReadModel post;
  final FeedTimelineScreenController controller;

  @override
  Widget build(BuildContext context) {
    final authorProfile = post.authorProfileFor(
      controller.currentAuthorProfile,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
          child: Row(
            children: [
              RunnerProfileAvatarLink(
                uid: post.authorUserId,
                displayName: post.authorDisplayName,
                avatarInitials: authorProfile.avatarInitials,
                avatarUrl: authorProfile.avatarUrl,
                levelBadgeLabel: authorProfile.compactLevelLabel,
                // A null viewer uid means this build cannot tell whose post
                // this is (the demo/no-viewer-context path), so it must not
                // guess: linking then risks handing the runner their own
                // read-only profile, and those rows carry fixture uids the
                // backend would reject anyway.
                enabled:
                    controller.viewerUserId != null &&
                    post.authorUserId != controller.viewerUserId,
                child: RuniacLevelProfileBadge.row(
                  key: ValueKey('feed-author-profile-${post.postId}'),
                  initials: authorProfile.avatarInitials,
                  levelLabel: authorProfile.compactLevelLabel,
                  progressFraction: authorProfile.levelProgressFraction,
                  photoUrl: authorProfile.avatarUrl,
                  size: 44,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorDisplayName,
                      style: YouTextStyles.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      post.relativeTimeLabel,
                      style: YouTextStyles.smallBody,
                    ),
                  ],
                ),
              ),
              _FeedPostOptions(
                onPressed: controller.mutationsEnabled
                    ? () => controller.showOptions(context, post)
                    : null,
              ),
            ],
          ),
        ),
        if (post.activityTitle != null || post.routeName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.activityTitle != null)
                  Text(post.activityTitle!, style: YouTextStyles.bodyStrong),
                if (post.routeName != null) ...[
                  const SizedBox(height: 2),
                  Text(post.routeName!, style: YouTextStyles.smallBody),
                ],
              ],
            ),
          ),
        FeedRouteThumbnail(thumbnail: post.routeThumbnail),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: _FeedMetricsRow(post: post),
        ),
        const Divider(
          height: 28,
          thickness: 1,
          indent: 16,
          endIndent: 16,
          color: RuniacColors.border,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FeedEngagementAction(
                label: 'Like ${post.likeCountLabel}',
                icon: post.isLikedByViewer
                    ? Icons.favorite
                    : Icons.favorite_border,
                value: post.likeCountLabel,
                highlighted: post.isLikedByViewer,
                enabled: controller.mutationsEnabled,
                onPressed: () => _likePressed(context),
                actionKey: ValueKey('feed-like-action-${post.postId}'),
              ),
              const SizedBox(width: 22),
              FeedEngagementAction(
                label: 'Comment ${post.commentCountLabel}',
                icon: post.hasViewerCommented
                    ? Icons.mode_comment
                    : Icons.mode_comment_outlined,
                value: post.commentCountLabel,
                highlighted: post.hasViewerCommented,
                enabled: controller.mutationsEnabled && post.canComment,
                onPressed: () => _commentPressed(context),
                actionKey: ValueKey('feed-comment-action-${post.postId}'),
              ),
            ],
          ),
        ),
        Container(
          key: ValueKey('feed-post-divider-${post.postId}'),
          height: 1,
          color: RuniacColors.border,
        ),
      ],
    );
  }

  /// Confirms the tap in the hand before the optimistic like lands on screen.
  ///
  /// Adding a like is the affirmative action, so it gets the stronger light
  /// impact; taking one back is a quieter selection change. The haptic fires
  /// for the tap itself, not for the server round trip, so an offline or
  /// rolled-back like still feels answered rather than dead.
  void _likePressed(BuildContext context) {
    final haptics = RuniacHapticsScope.maybeOf(context);
    if (post.isLikedByViewer) {
      haptics?.selection();
    } else {
      haptics?.impactLight();
    }
    controller.toggleLike(post.postId);
  }

  void _commentPressed(BuildContext context) {
    RuniacHapticsScope.maybeOf(context)?.selection();
    controller.openComments(context, post);
  }
}

class _FeedPostOptions extends StatelessWidget {
  const _FeedPostOptions({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Post options',
      button: onPressed != null,
      enabled: onPressed != null,
      container: true,
      child: ExcludeSemantics(
        child: IconButton(
          icon: const Icon(Icons.more_horiz),
          tooltip: 'Post options',
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _FeedMetricsRow extends StatelessWidget {
  const _FeedMetricsRow({required this.post});

  final FeedPostReadModel post;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FeedMetric(label: 'Distance', value: post.distanceLabel),
        const _FeedMetricDivider(),
        _FeedMetric(label: 'Pace', value: post.paceLabel),
        const _FeedMetricDivider(),
        _FeedMetric(label: 'Time', value: post.durationLabel),
      ],
    );
  }
}

class _FeedMetric extends StatelessWidget {
  const _FeedMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: YouTextStyles.smallBody),
          const SizedBox(height: 3),
          Text(value, style: YouTextStyles.bodyStrong),
        ],
      ),
    );
  }
}

class _FeedMetricDivider extends StatelessWidget {
  const _FeedMetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: RuniacColors.border,
    );
  }
}
