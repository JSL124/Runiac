/// Pure routing table from a persisted Feed-engagement notification inbox
/// payload to a client destination.
///
/// The backend writes exactly three client-visible `data` keys for a feed
/// like/comment notification: `kind` (`feed_post_liked` or
/// `feed_post_commented`), `route` (`feedComments`), and `postId` — the
/// `feedPosts` document id. This module inspects that map and decides whether
/// a tap should open the tapped post's comment sheet. It never inspects
/// trusted state and never computes an outcome; it only maps a delivered kind
/// (plus its `postId`) to a destination, mirroring
/// `challenge_notification_routing.dart`.
library;

/// The exact backend feed-engagement notification `kind` wire strings.
abstract final class FeedEngagementNotificationKinds {
  static const liked = 'feed_post_liked';
  static const commented = 'feed_post_commented';
}

/// A resolved navigation intent parsed from a notification `data` map: open
/// the comment sheet for [postId] on the Feed tab.
class FeedEngagementNotificationTarget {
  const FeedEngagementNotificationTarget({required this.postId});

  /// The `feedPosts` document id to open. Always non-empty — see
  /// [feedEngagementNotificationTargetFor].
  final String postId;

  @override
  bool operator ==(Object other) =>
      other is FeedEngagementNotificationTarget && other.postId == postId;

  @override
  int get hashCode => postId.hashCode;
}

/// Resolves a notification inbox `data` map to a feed-engagement destination,
/// or `null` when the payload is not a feed-engagement notification (so
/// non-feed inbox items — including challenge notifications and any
/// unrecognised or legacy payload — keep their existing routing behaviour).
FeedEngagementNotificationTarget? feedEngagementNotificationTargetFor(
  Map<String, Object?> data,
) {
  final kind = data['kind'];
  if (kind is! String ||
      (kind != FeedEngagementNotificationKinds.liked &&
          kind != FeedEngagementNotificationKinds.commented)) {
    return null;
  }
  final postId = data['postId'];
  if (postId is! String || postId.isEmpty) {
    return null;
  }
  return FeedEngagementNotificationTarget(postId: postId);
}
