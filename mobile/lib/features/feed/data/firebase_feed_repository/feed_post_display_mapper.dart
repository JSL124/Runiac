import '../../domain/models/feed_display_models.dart';
import 'feed_data_port.dart';

class FeedPostDisplayMapper {
  const FeedPostDisplayMapper._();

  static FeedPostReadModel map(
    FeedPostDocument post,
    String viewerUid,
  ) => FeedPostReadModel(
    postId: post.postId,
    authorUserId: post.authorUid,
    authorDisplayName: post.authorDisplayName,
    authorAvatarInitials: post.authorAvatarInitials,
    authorAvatarUrl: post.authorAvatarUrl,
    authorLevelLabel: post.authorLevelLabel,
    relativeTimeLabel: post.createdAt.toIso8601String(),
    distanceLabel: '${(post.distanceMeters / 1000).toStringAsFixed(1)} km',
    paceLabel:
        '${post.averagePaceSecondsPerKm ~/ 60}:${(post.averagePaceSecondsPerKm % 60).toString().padLeft(2, '0')} / km',
    durationLabel: '${(post.durationSeconds / 60).round()} min',
    likeCount: post.likeCount,
    commentCount: post.commentCount,
    isLikedByViewer: post.viewerLiked,
    hasViewerCommented: post.viewerCommented,
    canComment: true,
    showsOwnerMenu: post.authorUid == viewerUid,
    routeThumbnail: FeedRouteThumbnailReadModel(
      thumbnailKey: post.postId,
      accessibilityLabel: 'Private route preview',
    ),
  );
}
