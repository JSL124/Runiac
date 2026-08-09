import '../domain/models/feed_display_models.dart';
import '../domain/repositories/feed_repository.dart';

class StaticFeedRepository implements FeedRepository {
  const StaticFeedRepository();

  static const _demoPosts = <FeedPostReadModel>[
    FeedPostReadModel(
      postId: 'feed-current-001',
      authorUserId: 'runner-current',
      authorDisplayName: 'Runiac Runner',
      authorAvatarInitials: 'RR',
      authorLevelLabel: 'Level 6',
      relativeTimeLabel: 'Today',
      distanceLabel: '3.2 km',
      paceLabel: '7:20 / km',
      durationLabel: '23 min',
      likeCount: 4,
      commentCount: 1,
      isLikedByViewer: false,
      hasViewerCommented: false,
      canComment: true,
      showsOwnerMenu: true,
      routeThumbnail: FeedRouteThumbnailReadModel(
        thumbnailKey: 'marina-bay-easy-loop',
        accessibilityLabel: 'A simplified route preview',
      ),
    ),
    FeedPostReadModel(
      postId: 'feed-friend-001',
      authorUserId: 'runner-friend',
      authorDisplayName: 'Jamie Tan',
      authorAvatarInitials: 'JT',
      authorLevelLabel: 'Level 4',
      relativeTimeLabel: 'Yesterday',
      distanceLabel: '4.0 km',
      paceLabel: '7:05 / km',
      durationLabel: '28 min',
      likeCount: 8,
      commentCount: 2,
      isLikedByViewer: true,
      hasViewerCommented: true,
      canComment: true,
      showsOwnerMenu: false,
      routeThumbnail: FeedRouteThumbnailReadModel(
        thumbnailKey: 'east-coast-easy-loop',
        accessibilityLabel: 'A simplified route preview',
      ),
    ),
    FeedPostReadModel(
      postId: 'feed-pending-001',
      authorUserId: 'runner-pending',
      authorDisplayName: 'Pending Connection',
      authorAvatarInitials: 'PC',
      authorLevelLabel: '',
      relativeTimeLabel: 'Yesterday',
      distanceLabel: '2.5 km',
      paceLabel: '7:45 / km',
      durationLabel: '19 min',
      likeCount: 1,
      commentCount: 0,
      isLikedByViewer: false,
      hasViewerCommented: false,
      canComment: false,
      showsOwnerMenu: false,
      routeThumbnail: FeedRouteThumbnailReadModel(
        thumbnailKey: 'pending-preview',
        accessibilityLabel: 'A simplified route preview',
      ),
    ),
    FeedPostReadModel(
      postId: 'feed-blocked-001',
      authorUserId: 'runner-blocked',
      authorDisplayName: 'Blocked Connection',
      authorAvatarInitials: 'BC',
      authorLevelLabel: '',
      relativeTimeLabel: '2 days ago',
      distanceLabel: '5.0 km',
      paceLabel: '6:55 / km',
      durationLabel: '35 min',
      likeCount: 6,
      commentCount: 3,
      isLikedByViewer: false,
      hasViewerCommented: false,
      canComment: false,
      showsOwnerMenu: false,
      routeThumbnail: FeedRouteThumbnailReadModel(
        thumbnailKey: 'blocked-preview',
        accessibilityLabel: 'A simplified route preview',
      ),
    ),
    FeedPostReadModel(
      postId: 'feed-unknown-001',
      authorUserId: 'runner-unknown',
      authorDisplayName: 'Unknown Runner',
      authorAvatarInitials: 'UR',
      authorLevelLabel: '',
      relativeTimeLabel: '3 days ago',
      distanceLabel: '3.0 km',
      paceLabel: '7:30 / km',
      durationLabel: '22 min',
      likeCount: 2,
      commentCount: 1,
      isLikedByViewer: false,
      hasViewerCommented: false,
      canComment: false,
      showsOwnerMenu: false,
      routeThumbnail: FeedRouteThumbnailReadModel(
        thumbnailKey: 'unknown-preview',
        accessibilityLabel: 'A simplified route preview',
      ),
    ),
  ];

  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) async {
    final visibleAuthorIds = <String>{
      viewerContext.currentUserId,
      ...viewerContext.acceptedFriendUserIds,
    };

    return FeedReadModel(
      posts: _demoPosts
          .where((post) => visibleAuthorIds.contains(post.authorUserId))
          .toList(growable: false),
    );
  }
}
