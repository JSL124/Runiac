import '../../domain/models/feed_display_models.dart';

class FeedTimelineStateMutator {
  const FeedTimelineStateMutator._();

  static FeedTimelineState empty() => FeedTimelineState(
    posts: const <FeedPostReadModel>[],
    source: FeedTimelineSource.server,
    refreshing: false,
    exhausted: false,
  );

  static FeedTimelineState copy(
    FeedTimelineState state, {
    bool? refreshing,
    bool? exhausted,
  }) => FeedTimelineState(
    posts: state.posts,
    source: state.source,
    refreshing: refreshing ?? state.refreshing,
    exhausted: exhausted ?? state.exhausted,
    recoverableError: state.recoverableError,
  );

  static FeedTimelineState withoutAuthor(FeedTimelineState state, String uid) =>
      FeedTimelineState(
        posts: state.posts.where((post) => post.authorUserId != uid).toList(),
        source: state.source,
        refreshing: false,
        exhausted: state.exhausted,
        recoverableError: state.recoverableError,
      );

  static FeedTimelineState withoutPost(
    FeedTimelineState state,
    String postId,
  ) => FeedTimelineState(
    posts: state.posts.where((post) => post.postId != postId).toList(),
    source: state.source,
    refreshing: false,
    exhausted: state.exhausted,
  );

  static FeedTimelineState replacePost(
    FeedTimelineState state,
    String postId,
    FeedPostReadModel Function(FeedPostReadModel) change,
  ) => FeedTimelineState(
    posts: state.posts
        .map((post) => post.postId == postId ? change(post) : post)
        .toList(),
    source: state.source,
    refreshing: false,
    exhausted: state.exhausted,
  );

  static FeedTimelineState failure(FeedTimelineState state, bool cached) =>
      FeedTimelineState(
        posts: state.posts,
        source: cached
            ? FeedTimelineSource.cachedOffline
            : FeedTimelineSource.server,
        refreshing: false,
        exhausted: state.exhausted,
        recoverableError: const FeedRecoverableError(
          code: 'feed-unavailable',
          message: 'Feed could not be refreshed.',
        ),
      );
}
