import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../domain/models/feed_display_models.dart';
import '../domain/repositories/feed_repository.dart';
import 'current_session_feed_fallback.dart';
import 'current_session_feed_store.dart';
import 'current_session_feed_timeline.dart';
import 'feed_comment_intent_controller.dart';
import 'widgets/feed_sheets.dart';

/// Result of [FeedTimelineScreenController.openCommentsForPostId].
enum FeedCommentOpenOutcome {
  /// The post was found and its comment sheet was opened.
  opened,

  /// The post could not be found in the timeline, nor by a direct
  /// [FeedTimelineRepository.readPost] lookup.
  notFound,

  /// The post could not be conclusively resolved (the direct lookup itself
  /// failed, e.g. offline), or it was found but cannot be commented on right
  /// now (deleted, reported, or mutations are disabled for the current
  /// timeline source).
  unavailable,
}

class FeedTimelineScreenController extends ChangeNotifier {
  FeedTimelineScreenController(
    this._repository,
    this._viewerContext, [
    this._currentAuthorProfile,
    this._commentIntent,
  ]) {
    scrollController.addListener(_loadMoreNearEnd);
  }

  final FeedRepository _repository;
  final FeedViewerContext? _viewerContext;

  /// Notification tap-through intent, cleared when the signed-in owner
  /// changes so a stale request never auto-opens a sheet for the previous
  /// account's post. `null` outside the composition root (previews/tests).
  final FeedCommentIntentController? _commentIntent;
  final ScrollController scrollController = ScrollController();
  final _fallback = CurrentSessionFeedFallback();
  final Set<String> _requestedThumbnails = <String>{};
  final Map<String, _OptimisticLike> _pendingLikes =
      <String, _OptimisticLike>{};
  List<FeedPostReadModel> _posts = const [];
  CurrentSessionFeedStore? _sessionStore;
  FeedAuthorProfileSnapshot? _currentAuthorProfile;
  FeedTimelineState? _state;
  int _ownerRevision = 0, _refreshGeneration = 0;
  bool _hasLoaded = false, _loadingMore = false, _commentSheetOpen = false;
  bool _disposed = false;
  String? _loadError;
  CurrentSessionFeedTimeline get _timeline =>
      CurrentSessionFeedTimeline(_repository);
  bool get isProduction => _timeline.isProduction;
  bool get hasLoaded => _hasLoaded;
  FeedTimelineState? get timelineState => _state;
  String? get loadError => _loadError;
  bool get commentSheetOpen => _commentSheetOpen;
  String? get viewerUserId => _viewerContext?.currentUserId;
  FeedAuthorProfileSnapshot? get currentAuthorProfile =>
      _currentAuthorProfile ?? _sessionStore?.authorProfile;
  List<FeedPostReadModel> get posts => <FeedPostReadModel>[
    if (!isProduction) ...?_sessionStore?.sessionPosts,
    ..._posts,
  ];

  void attachSession(CurrentSessionFeedStore? store) {
    _sessionStore = store;
    _ownerRevision = store?.ownerRevision ?? 0;
  }

  void updateCurrentAuthorProfile(FeedAuthorProfileSnapshot? profile) {
    if (_currentAuthorProfile == profile) return;
    _currentAuthorProfile = profile;
    _notify();
  }

  bool clearForOwnerChange() {
    if (_disposed) return false;
    final nextRevision = _sessionStore?.ownerRevision ?? 0;
    if (nextRevision == _ownerRevision) return false;
    _ownerRevision = nextRevision;
    _fallback.clear();
    _commentIntent?.clear();
    _notify();
    return true;
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    final viewer =
        _viewerContext ??
        (!isProduction
            ? const FeedViewerContext(
                currentUserId: 'runner-current',
                acceptedFriendUserIds: <String>{'runner-friend'},
              )
            : null);
    if (viewer == null) return _showEmpty();
    try {
      final feed = await _timeline.load(
        viewerContext: viewer,
        hasLoaded: _hasLoaded,
      );
      if (!_disposed && generation == _refreshGeneration) _apply(feed);
    } catch (_) {
      if (!_disposed && generation == _refreshGeneration) _showError();
    }
  }

  Future<void> loadMore() async {
    final state = _state;
    if (!isProduction ||
        state == null ||
        state.exhausted ||
        state.refreshing ||
        _loadingMore) {
      return;
    }
    _loadingMore = true;
    try {
      _apply(await _timeline.loadMore());
    } catch (_) {
      _showError();
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> toggleLike(String postId) async {
    if (isProduction) {
      if (!mutationsEnabled || _pendingLikes.containsKey(postId)) return;
      final index = _posts.indexWhere((post) => post.postId == postId);
      if (index < 0) {
        return;
      }
      final previous = _posts[index];
      final isLiked = !previous.isLikedByViewer;
      final optimistic = _OptimisticLike(
        previousIsLiked: previous.isLikedByViewer,
        previousCount: previous.likeCount,
        isLiked: isLiked,
        count: isLiked
            ? previous.likeCount + 1
            : previous.likeCount > 0
            ? previous.likeCount - 1
            : 0,
      );
      _pendingLikes[postId] = optimistic;
      _posts = List<FeedPostReadModel>.of(_posts)
        ..[index] = previous.copyWith(
          isLikedByViewer: optimistic.isLiked,
          likeCount: optimistic.count,
        );
      _notify();
      final next = await _timeline.toggleLike(postId: postId, isLiked: isLiked);
      if (next != null && !_disposed) {
        _posts = _preserveLoadedThumbnails(next);
        _notify();
      } else if (!_disposed) {
        _pendingLikes.remove(postId);
        final rollbackIndex = _posts.indexWhere(
          (post) => post.postId == postId,
        );
        if (rollbackIndex >= 0) {
          final current = _posts[rollbackIndex];
          _posts = List<FeedPostReadModel>.of(_posts)
            ..[rollbackIndex] = current.copyWith(
              isLikedByViewer: optimistic.previousIsLiked,
              likeCount: optimistic.previousCount,
            );
          _notify();
        }
      }
      _pendingLikes.remove(postId);
      return;
    }
    if (_sessionStore?.toggleLike(postId) ?? false) return;
    _posts = _fallback.toggleLike(posts: _posts, postId: postId);
    _notify();
  }

  Future<void> openComments(BuildContext context, FeedPostReadModel post) {
    if (!post.canComment || !mutationsEnabled) return Future<void>.value();
    _commentSheetOpen = true;
    final comments = _timeline.comments;
    return showFeedCommentSheet(
      context: context,
      sheet: comments == null
          ? FeedCommentSheet.fromFallback(
              post,
              _viewerContext?.currentUserId,
              FeedCommentFallback(
                comments: _fallback.commentsFor(post.postId),
                onSubmitted: (body) => _addComment(post.postId, body),
              ),
              currentAuthorProfile,
            )
          : FeedCommentSheet.fromRepository(
              post,
              comments,
              _viewerContext?.currentUserId,
              currentAuthorProfile,
            ),
    ).whenComplete(() => _commentSheetOpen = false);
  }

  bool get mutationsEnabled => _state?.mutationsEnabled ?? true;

  /// Opens the comment sheet for [postId] the same way a normal tap on an
  /// already-visible post does, resolving the post first when it is not
  /// (yet) loaded.
  ///
  /// Resolution order: the already-loaded [posts] first (zero network);
  /// otherwise one direct [CurrentSessionFeedTimeline.readPost] call. Paging
  /// (`refresh`/`loadMore`) is deliberately NOT used to resolve a notified
  /// post: the feed is ordered by post creation time, so an engagement
  /// notification (a friend liked or commented today) can arrive for a post
  /// arbitrarily far back — someone commenting on a run shared months ago —
  /// which paging-until-found could never bound. Worse, this timeline fans
  /// out one query per friend per page, so paging on a single notification
  /// tap could cost hundreds or thousands of reads for a user with many
  /// friends. A direct read is O(1) and `firestore.rules`-permitted, because
  /// a feed-engagement notification is only ever delivered to the post's own
  /// owner.
  ///
  /// Returns [FeedCommentOpenOutcome.notFound] when the post genuinely
  /// cannot be resolved, [FeedCommentOpenOutcome.unavailable] when the read
  /// itself fails (offline, etc.), when it resolves but can no longer be
  /// commented on (deleted/reported), or when mutations are disabled for the
  /// current timeline source, and [FeedCommentOpenOutcome.opened] once
  /// [openComments] has been invoked for it.
  Future<FeedCommentOpenOutcome> openCommentsForPostId(
    BuildContext context,
    String postId,
  ) async {
    var found = _findPost(postId);
    if (found == null) {
      try {
        found = await _timeline.readPost(postId);
      } catch (_) {
        return FeedCommentOpenOutcome.unavailable;
      }
      if (!context.mounted) return FeedCommentOpenOutcome.notFound;
    }
    if (found == null) {
      return FeedCommentOpenOutcome.notFound;
    }
    if (!found.canComment || !mutationsEnabled) {
      return FeedCommentOpenOutcome.unavailable;
    }
    await openComments(context, found);
    return FeedCommentOpenOutcome.opened;
  }

  FeedPostReadModel? _findPost(String postId) {
    for (final post in posts) {
      if (post.postId == postId) {
        return post;
      }
    }
    return null;
  }

  Future<void> showOptions(BuildContext context, FeedPostReadModel post) =>
      showCurrentSessionFeedPostOptions(
        context,
        post.showsOwnerMenu
            ? FeedPostOptionsSheet.owner(() => deletePost(post.postId))
            : FeedPostOptionsSheet.reporter(
                isProduction ? () => reportPost(post.postId) : null,
              ),
      );

  Future<void> _addComment(String postId, String body) async {
    if (isProduction) {
      await _timeline.createComment(
        FeedCommentMutation(postId: postId, commentId: null, body: body),
      );
      return;
    }
    _fallback.addComment(postId, body);
    if (!(_sessionStore?.addComment(postId) ?? false)) {
      _posts = _fallback.addCommentCount(posts: _posts, postId: postId);
    }
    _notify();
  }

  Future<bool> deletePost(String postId) async {
    if (isProduction) return _applyMutation(await _timeline.deletePost(postId));
    if (_sessionStore?.removePost(postId) ?? false) {
      _fallback.removePost(postId);
    } else {
      _posts = _fallback.removeFrom(_posts, postId);
      _fallback.removePost(postId);
    }
    notifyListeners();
    return true;
  }

  Future<bool> reportPost(String postId) async =>
      _applyMutation(await _timeline.reportPost(postId));

  bool _applyMutation(List<FeedPostReadModel>? next) {
    if (_disposed || next == null) return false;
    _posts = _preserveLoadedThumbnails(next);
    _notify();
    return true;
  }

  void _apply(FeedReadModel feed) {
    if (_disposed) return;
    _posts = _preserveLoadedThumbnails(feed.posts);
    _state = feed is FeedTimelineState ? feed : null;
    _fallback.clearForPosts(feed.posts);
    _loadError = null;
    _hasLoaded = true;
    _notify();
    if (_state?.source == FeedTimelineSource.server) {
      for (final post in _posts) {
        _requestThumbnail(post);
      }
    }
  }

  void _showEmpty() {
    if (_disposed) return;
    _posts = const [];
    _state = null;
    _hasLoaded = true;
    _notify();
  }

  void _showError() {
    if (_disposed) return;
    _loadError = 'Feed could not refresh.';
    _hasLoaded = true;
    _notify();
  }

  void _loadMoreNearEnd() {
    if (scrollController.hasClients &&
        scrollController.position.extentAfter < 240) {
      unawaited(loadMore());
    }
  }

  void _requestThumbnail(FeedPostReadModel post) {
    if (post.routeThumbnail.pngBytes == null &&
        _requestedThumbnails.add(post.postId)) {
      unawaited(_readThumbnail(post.postId));
    }
  }

  Future<void> _readThumbnail(String postId) async {
    final Uint8List? bytes = await _timeline.readThumbnail(postId);
    if (_disposed) return;
    if (bytes == null || bytes.lengthInBytes < 8) {
      _requestedThumbnails.remove(postId);
      return;
    }
    _posts = _posts
        .map(
          (post) => post.postId == postId
              ? post.copyWith(
                  routeThumbnail: post.routeThumbnail.copyWith(pngBytes: bytes),
                )
              : post,
        )
        .toList(growable: false);
    _sessionStore?.cachePublishedThumbnail(postId, bytes);
    _notify();
  }

  List<FeedPostReadModel> _preserveLoadedThumbnails(
    List<FeedPostReadModel> next,
  ) {
    final loaded = <String, FeedRouteThumbnailReadModel>{
      for (final post in _posts)
        if (post.routeThumbnail.pngBytes != null)
          post.postId: post.routeThumbnail,
    };
    return next
        .map((post) {
          var merged = post;
          if (post.routeThumbnail.pngBytes == null) {
            final previous = loaded[post.postId];
            if (previous != null) {
              merged = post.copyWith(routeThumbnail: previous);
            } else {
              final cached = _sessionStore?.thumbnailFor(post.postId);
              if (cached != null) {
                merged = post.copyWith(
                  routeThumbnail: post.routeThumbnail.copyWith(
                    pngBytes: cached,
                  ),
                );
              }
            }
          }
          final optimistic = _pendingLikes[post.postId];
          return optimistic == null
              ? merged
              : merged.copyWith(
                  isLikedByViewer: optimistic.isLiked,
                  likeCount: optimistic.count,
                );
        })
        .toList(growable: false);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    scrollController.removeListener(_loadMoreNearEnd);
    scrollController.dispose();
    super.dispose();
  }
}

class _OptimisticLike {
  const _OptimisticLike({
    required this.previousIsLiked,
    required this.previousCount,
    required this.isLiked,
    required this.count,
  });

  final bool previousIsLiked;
  final int previousCount;
  final bool isLiked;
  final int count;
}
