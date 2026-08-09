import '../../domain/models/feed_display_models.dart';
import '../firebase_feed_repository/feed_author_level_resolver.dart';
import '../firebase_feed_repository/feed_data_port.dart';

/// Maps the constrained repository boundary into display-safe comment pages.
class FeedCommentPageLoader {
  const FeedCommentPageLoader._();

  static Future<FeedCommentPage> load({
    required FeedDataPort port,
    required String postId,
    required FeedAuthorLevelResolver levelResolver,
    FeedCommentCursor? startAfter,
  }) async {
    final page = await port.pageComments(
      postId: postId,
      startAfter: startAfter,
    );
    final authorUids = {
      for (final comment in page.comments) comment.authorUid,
    };
    // Scoped to this post: a commenter the viewer is not friends with is only
    // resolvable through the post that made their comment readable.
    await levelResolver.ensureResolved(authorUids, postId: postId);
    return FeedCommentPage(
      comments: page.comments
          .map((comment) {
            final resolved = levelResolver[comment.authorUid];
            final hasResolvedLabel =
                resolved != null && resolved.levelLabel.trim().isNotEmpty;
            // A comment freezes its author's name the same way a post does, so
            // the live identity wins whenever the backend resolved one; an
            // empty value keeps the stored copy rather than blanking the row.
            final resolvedName = resolved?.displayName.trim() ?? '';
            final resolvedInitials = resolved?.avatarInitials.trim() ?? '';
            // Comments never store an avatar URL at write time (only
            // `authorAvatarInitials` is frozen there), so there is no stored
            // copy to keep — an unresolved uid simply renders no photo.
            final resolvedAvatarUrl = resolved?.avatarUrl.trim() ?? '';
            return FeedCommentReadModel(
              commentId: comment.commentId,
              authorUserId: comment.authorUid,
              authorDisplayName: resolvedName.isEmpty
                  ? comment.authorDisplayName
                  : resolvedName,
              authorAvatarInitials: resolvedInitials.isEmpty
                  ? comment.authorAvatarInitials
                  : resolvedInitials,
              authorAvatarUrl: resolvedAvatarUrl,
              authorLevelLabel: hasResolvedLabel
                  ? resolved.levelLabel
                  : comment.authorLevelLabel,
              authorLevelProgressFraction: hasResolvedLabel
                  ? resolved.levelProgressFraction
                  : null,
              body: comment.body,
              createdAt: comment.createdAt,
            );
          })
          .toList(growable: false),
      source: page.fromCache
          ? FeedTimelineSource.cachedOffline
          : FeedTimelineSource.server,
      exhausted: page.nextCursor == null,
    );
  }
}
