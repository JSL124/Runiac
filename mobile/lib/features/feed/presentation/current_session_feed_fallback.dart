import '../domain/models/feed_display_models.dart';

/// Test-only session behavior retained outside the Firebase timeline path.
class CurrentSessionFeedFallback {
  final Map<String, List<String>> _comments = <String, List<String>>{};

  List<String> commentsFor(String postId) => _comments[postId] ?? const [];

  void clear() => _comments.clear();

  void clearForPosts(List<FeedPostReadModel> posts) {
    for (final post in posts) {
      _comments.remove(post.postId);
    }
  }

  void addComment(String postId, String comment) {
    _comments[postId] = <String>[...commentsFor(postId), comment];
  }

  void removePost(String postId) => _comments.remove(postId);

  List<FeedPostReadModel> toggleLike({
    required List<FeedPostReadModel> posts,
    required String postId,
  }) => posts
      .map((post) {
        if (post.postId != postId) {
          return post;
        }
        final isLiked = !post.isLikedByViewer;
        return post.copyWith(
          isLikedByViewer: isLiked,
          likeCount: post.likeCount + (isLiked ? 1 : -1),
        );
      })
      .toList(growable: false);

  List<FeedPostReadModel> addCommentCount({
    required List<FeedPostReadModel> posts,
    required String postId,
  }) => posts
      .map(
        (post) => post.postId != postId
            ? post
            : post.copyWith(
                commentCount: post.commentCount + 1,
                hasViewerCommented: true,
              ),
      )
      .toList(growable: false);

  List<FeedPostReadModel> removeFrom(
    List<FeedPostReadModel> posts,
    String postId,
  ) => posts.where((post) => post.postId != postId).toList(growable: false);
}
