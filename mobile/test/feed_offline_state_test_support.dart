import 'dart:async';
import 'dart:typed_data';

import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/feed/domain/repositories/feed_repository.dart';

class ScreenFeedRepository implements FeedTimelineRepository {
  ScreenFeedRepository({
    this.source = FeedTimelineSource.server,
    int postCount = 1,
  }) : _posts = List<FeedPostReadModel>.generate(postCount, _post);

  FeedTimelineSource source;
  final List<FeedPostReadModel> _posts;
  Completer<void>? deleteCompleter, likeCompleter, reportCompleter;
  Completer<FeedTimelineState>? loadMoreCompleter;
  Completer<FeedTimelineState>? refreshCompleter;
  Completer<Uint8List>? thumbnailCompleter;
  Uint8List thumbnailBytes = Uint8List(0);
  int thumbnailReads = 0, likeCalls = 0, reportCalls = 0, loadMoreCalls = 0;

  @override
  FeedTimelineState get currentState => FeedTimelineState(
    posts: _posts,
    source: source,
    refreshing: false,
    exhausted: false,
  );

  void addPost() => _posts.add(_post(_posts.length));

  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) =>
      loadInitial(viewerContext);

  @override
  Future<FeedTimelineState> loadInitial(
    FeedViewerContext viewerContext,
  ) async => currentState;

  @override
  Future<FeedTimelineState> loadMore() async {
    loadMoreCalls += 1;
    return loadMoreCompleter?.future ?? currentState;
  }

  @override
  Future<FeedTimelineState> refresh() async =>
      refreshCompleter?.future ?? currentState;

  @override
  Future<FeedTimelineState> reconcileAccess() async => currentState;

  @override
  Future<void> setLike({required String postId, required bool isLiked}) async {
    likeCalls += 1;
    await likeCompleter?.future;
    _replace(postId, (post) => post.copyWith(isLikedByViewer: isLiked));
  }

  @override
  Future<void> reportPost(String postId) async {
    reportCalls += 1;
    await reportCompleter?.future;
    _posts.removeWhere((post) => post.postId == postId);
  }

  @override
  Future<void> deletePost(String postId) async {
    await deleteCompleter?.future;
    _posts.removeWhere((post) => post.postId == postId);
  }

  @override
  Future<FeedPostReadModel?> readPost(String postId) async {
    for (final post in _posts) {
      if (post.postId == postId) return post;
    }
    return null;
  }

  void _replace(
    String postId,
    FeedPostReadModel Function(FeedPostReadModel) change,
  ) {
    final index = _posts.indexWhere((post) => post.postId == postId);
    _posts[index] = change(_posts[index]);
  }

  @override
  Future<void> createComment(FeedCommentMutation mutation) async {}

  @override
  Future<void> updateComment(FeedCommentMutation mutation) async {}

  @override
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {}

  @override
  Future<Uint8List> readThumbnail(String postId) async {
    thumbnailReads += 1;
    return thumbnailCompleter?.future ?? thumbnailBytes;
  }

  @override
  void dispose() {}
}

FeedPostReadModel _post(int index) => FeedPostReadModel(
  postId: 'post-$index',
  authorUserId: 'friend',
  authorDisplayName: 'Friend Runner $index',
  authorAvatarInitials: 'FR',
  authorLevelLabel: 'Level 3',
  relativeTimeLabel: 'Now',
  distanceLabel: '2.0 km',
  paceLabel: '7:00 / km',
  durationLabel: '14 min',
  likeCount: 0,
  commentCount: 0,
  isLikedByViewer: false,
  hasViewerCommented: false,
  canComment: true,
  showsOwnerMenu: false,
  routeThumbnail: const FeedRouteThumbnailReadModel(
    thumbnailKey: 'screen-state',
    accessibilityLabel: 'Private route preview',
  ),
);
