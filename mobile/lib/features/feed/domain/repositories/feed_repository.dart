import '../models/feed_display_models.dart';
import 'dart:typed_data';

abstract interface class FeedRepository {
  /// Compatibility read used by the existing static Feed UI.
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext);
}

/// Stateful Feed contract used by the Firebase-backed production path.
abstract interface class FeedTimelineRepository implements FeedRepository {
  FeedTimelineState get currentState;
  Future<FeedTimelineState> loadInitial(FeedViewerContext viewerContext);
  Future<FeedTimelineState> loadMore();
  Future<FeedTimelineState> refresh();
  Future<FeedTimelineState> reconcileAccess();

  /// Resolves [postId] directly, without paging, for a post that may not be
  /// (or may no longer be) in [currentState]. Returns the same shape of
  /// [FeedPostReadModel] the timeline itself would produce for it — same
  /// author-level overlay, same thumbnail seam — or `null` when the post
  /// cannot be found. May throw when the read itself fails (e.g. offline);
  /// callers distinguish that from a genuine not-found result.
  Future<FeedPostReadModel?> readPost(String postId);
  Future<void> setLike({required String postId, required bool isLiked});
  Future<void> createComment(FeedCommentMutation mutation);
  Future<void> updateComment(FeedCommentMutation mutation);
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  });
  Future<void> reportPost(String postId);
  Future<void> deletePost(String postId);
  Future<Uint8List> readThumbnail(String postId);
  void dispose();
}

/// Narrow read boundary for the paginated flat-comments sheet.
abstract interface class FeedCommentsRepository {
  Future<FeedCommentPage> loadComments({
    required String postId,
    FeedCommentCursor? startAfter,
  });
  Future<void> createComment(FeedCommentMutation mutation);
  Future<void> updateComment(FeedCommentMutation mutation);
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  });
}
