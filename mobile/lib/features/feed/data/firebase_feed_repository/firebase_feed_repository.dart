import 'dart:typed_data';
import '../../domain/models/feed_display_models.dart';
import '../../domain/repositories/feed_repository.dart';
import '../comments/feed_comment_page_loader.dart';
import 'feed_author_buffers.dart';
import 'feed_author_level_resolver.dart';
import 'feed_data_port.dart';
import 'feed_post_display_mapper.dart';
import 'feed_timeline_lifecycle.dart';
import 'feed_timeline_page_loader.dart';
import 'feed_timeline_state_mutator.dart';

class FirebaseFeedRepository
    implements FeedTimelineRepository, FeedCommentsRepository {
  FirebaseFeedRepository({required this.port})
    : _levelResolver = FeedAuthorLevelResolver(port);
  final FeedDataPort port;
  final FeedAuthorLevelResolver _levelResolver;
  FeedTimelinePagingSession? _session;
  final FeedTimelineLifecycle _lifecycle = FeedTimelineLifecycle();
  FeedViewerContext? _viewer;
  FeedTimelineState _state = FeedTimelineStateMutator.empty();
  @override
  FeedTimelineState get currentState => _state;
  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) =>
      loadInitial(viewerContext);
  @override
  Future<FeedTimelineState> loadInitial(FeedViewerContext viewerContext) =>
      _lifecycle.enqueue(() => _loadInitial(viewerContext));

  Future<FeedTimelineState> _loadInitial(
    FeedViewerContext viewerContext,
  ) async {
    if (_lifecycle.isDisposed) return _state;
    _viewer = viewerContext;
    _reset();
    final buffers = FeedAuthorBuffers(
      port: port,
      viewerUid: viewerContext.currentUserId,
    );
    _session = FeedTimelinePagingSession(
      buffers,
      viewerContext.currentUserId,
      _state,
      _levelResolver,
    );
    _state = FeedTimelineStateMutator.copy(
      _state,
      refreshing: true,
      exhausted: false,
    );
    try {
      await _session!.discover(() => _lifecycle.isDisposed);
      if (_lifecycle.isDisposed) return _state;
      await buffers.fetchEveryAuthorOnce();
      if (_lifecycle.isDisposed) return _state;
      _session!.evictRevoked();
      _state = _session!.state;
      return _loadNextPage();
    } catch (error) {
      return FeedTimelineStateMutator.failure(
        _state,
        _session?.buffers.usedCachedSnapshot == true,
      );
    }
  }

  @override
  Future<FeedTimelineState> loadMore() => _lifecycle.enqueue(_loadMore);

  Future<FeedTimelineState> _loadMore() async {
    if (_lifecycle.isDisposed) return _state;
    if (_viewer == null || _state.exhausted || _state.refreshing) return _state;
    _state = FeedTimelineStateMutator.copy(_state, refreshing: true);
    try {
      return _loadNextPage();
    } catch (error) {
      return FeedTimelineStateMutator.failure(
        _state,
        _session?.buffers.usedCachedSnapshot == true,
      );
    }
  }

  @override
  Future<FeedTimelineState> refresh() => _lifecycle.enqueue(() async {
    if (_lifecycle.isDisposed) return _state;
    final viewer = _viewer;
    if (viewer == null) return _state;
    _levelResolver.invalidate();
    return _loadInitial(viewer);
  });

  @override
  Future<void> setLike({required String postId, required bool isLiked}) =>
      _lifecycle.enqueue(() => _setLike(postId: postId, isLiked: isLiked));

  @override
  Future<FeedCommentPage> loadComments({
    required String postId,
    FeedCommentCursor? startAfter,
  }) => _lifecycle.enqueue(() async {
    if (_lifecycle.isDisposed || _viewer == null) {
      return FeedCommentPage(
        comments: const [],
        source: _state.source,
        exhausted: true,
      );
    }
    return FeedCommentPageLoader.load(
      port: port,
      postId: postId,
      levelResolver: _levelResolver,
      startAfter: startAfter,
    );
  });

  Future<void> _setLike({required String postId, required bool isLiked}) async {
    if (_lifecycle.isDisposed) return;
    final viewer = _viewer;
    if (viewer == null || !_state.mutationsEnabled) return;
    await port.setViewerLike(
      viewerUid: viewer.currentUserId,
      postId: postId,
      isLiked: isLiked,
    );
    if (_lifecycle.isDisposed) return;
    _state = FeedTimelineStateMutator.replacePost(
      _state,
      postId,
      (post) => post.copyWith(isLikedByViewer: isLiked),
    );
  }

  @override
  Future<void> createComment(FeedCommentMutation mutation) =>
      _lifecycle.enqueue(
        () => _withMutation(
          (viewer) => port.createComment(
            viewerUid: viewer.currentUserId,
            mutation: mutation,
          ),
        ),
      );

  @override
  Future<void> updateComment(FeedCommentMutation mutation) =>
      _lifecycle.enqueue(
        () => _withMutation(
          (viewer) => port.updateComment(
            viewerUid: viewer.currentUserId,
            mutation: mutation,
          ),
        ),
      );

  @override
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) => _lifecycle.enqueue(
    () => _withMutation(
      (viewer) => port.deleteComment(
        viewerUid: viewer.currentUserId,
        postId: postId,
        commentId: commentId,
      ),
    ),
  );

  @override
  Future<void> reportPost(String postId) =>
      _lifecycle.enqueue(() => _postAction('reportFeedPost', postId));

  @override
  Future<void> deletePost(String postId) =>
      _lifecycle.enqueue(() => _postAction('deleteFeedPost', postId));

  Future<void> _postAction(String action, String postId) async {
    if (_lifecycle.isDisposed) return;
    if (_viewer == null || !_state.mutationsEnabled) return;
    await port.callPostAction(action: action, postId: postId);
    if (_lifecycle.isDisposed) return;
    if (action == 'reportFeedPost') {
      _session?.hide(postId);
    }
    _state = FeedTimelineStateMutator.withoutPost(_state, postId);
  }

  @override
  Future<Uint8List> readThumbnail(String postId) => _lifecycle.isDisposed
      ? Future<Uint8List>.error(StateError('Feed repository is disposed.'))
      : port.readThumbnail(postId);

  @override
  Future<FeedPostReadModel?> readPost(String postId) =>
      _lifecycle.enqueue(() => _readPost(postId));

  /// Resolves [postId] directly through [FeedDataPort.readPublishedPost] —
  /// no paging — then runs it through the exact same display mapper and
  /// author-level overlay every paged post gets, so the result cannot be
  /// told apart from a timeline row. Deliberately does not catch a port
  /// failure: it propagates so [readPost]'s caller can tell "the read itself
  /// failed" apart from "resolved to nothing", which the author-level
  /// overlay step never needs to make since [FeedAuthorLevelResolver]
  /// already swallows its own errors.
  Future<FeedPostReadModel?> _readPost(String postId) async {
    if (_lifecycle.isDisposed) return null;
    final viewer = _viewer;
    if (viewer == null) return null;
    final document = await port.readPublishedPost(postId);
    if (_lifecycle.isDisposed || document == null) return null;
    final mapped = FeedPostDisplayMapper.map(document, viewer.currentUserId);
    await _levelResolver.ensureResolved(<String>{mapped.authorUserId});
    return _lifecycle.isDisposed ? null : _levelResolver.overlay(mapped);
  }

  @override
  Future<FeedTimelineState> reconcileAccess() =>
      _lifecycle.enqueue(_reconcileAccess);

  Future<FeedTimelineState> _reconcileAccess() async {
    final viewer = _viewer;
    final session = _session;
    if (_lifecycle.isDisposed || viewer == null || session == null) {
      return _state;
    }
    await session.reconcileAccess(() => _lifecycle.isDisposed);
    if (_lifecycle.isDisposed) return _state;
    _state = session.state;
    return _state;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _viewer = null;
    _reset();
  }

  Future<FeedTimelineState> _loadNextPage() async {
    final session = _session;
    if (session == null || _viewer == null) return _state;
    session.state = _state;
    await session.loadNext(() => _lifecycle.isDisposed);
    _state = session.state;
    return _state;
  }

  Future<void> _withMutation(Future<void> Function(FeedViewerContext) action) {
    final viewer = _viewer;
    return _lifecycle.isDisposed || viewer == null || !_state.mutationsEnabled
        ? Future<void>.value()
        : action(viewer);
  }

  void _reset() {
    _session = null;
    _state = FeedTimelineStateMutator.empty();
    // Author levels are authorized per viewer, so a cache built for one
    // signed-in user must never survive into another's session: the same
    // repository instance can be re-loaded with a different viewer, and
    // `ensureResolved` skips uids it already holds. Clearing here keeps the
    // cache scoped to a single initial load.
    _levelResolver.invalidate();
  }
}
