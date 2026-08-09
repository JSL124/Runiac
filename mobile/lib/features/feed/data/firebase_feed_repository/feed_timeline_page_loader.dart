import '../../domain/models/feed_display_models.dart';
import 'feed_author_buffers.dart';
import 'feed_author_level_resolver.dart';
import 'feed_post_display_mapper.dart';
import 'feed_timeline_state_mutator.dart';

/// Owns one viewer's buffered Feed lifecycle, paging, and access reconciliation.
class FeedTimelinePagingSession {
  FeedTimelinePagingSession(
    this.buffers,
    this.viewerUid,
    this.state,
    this.levelResolver,
  );

  final FeedAuthorBuffers buffers;
  final String viewerUid;
  final FeedAuthorLevelResolver levelResolver;
  final Set<String> _hiddenPostIds = <String>{}, _emittedPostIds = <String>{};
  FeedTimelineState state;

  Future<void> discover(bool Function() isDisposed) async {
    final friends = await buffers.loadAcceptedFriendIds(isDisposed);
    if (isDisposed()) return;
    _hiddenPostIds.addAll(await buffers.loadHiddenPostIds(isDisposed));
    if (isDisposed()) return;
    buffers.replaceAuthors(<String>{viewerUid, ...friends});
  }

  Future<void> loadNext(bool Function() isDisposed) async {
    if (isDisposed()) return;
    final page = <FeedPostReadModel>[];
    while (page.length < 20) {
      final selected = buffers.takeNewest();
      if (selected == null) {
        if (!await buffers.fetchEmptyAuthors()) break;
        _discardRevoked(page, _evictRevoked());
        continue;
      }
      if (buffers.isEmpty(selected.authorUid)) {
        await buffers.fetch(selected.authorUid);
        _discardRevoked(page, _evictRevoked());
        if (isDisposed() || !buffers.containsAuthor(selected.authorUid)) {
          continue;
        }
      }
      if (_hiddenPostIds.contains(selected.post.postId) ||
          !_emittedPostIds.add(selected.post.postId)) {
        continue;
      }
      page.add(FeedPostDisplayMapper.map(selected.post, viewerUid));
    }
    await _overlayAuthorLevels(page, isDisposed);
    if (isDisposed()) return;
    state = FeedTimelineState(
      posts: <FeedPostReadModel>[...state.posts, ...page],
      source: buffers.usedCachedSnapshot
          ? FeedTimelineSource.cachedOffline
          : FeedTimelineSource.server,
      refreshing: false,
      exhausted: buffers.exhausted,
    );
  }

  Future<void> reconcileAccess(bool Function() isDisposed) async {
    final previous = Set<String>.from(buffers.authorIds);
    try {
      final permitted = <String>{
        viewerUid,
        ...await buffers.loadAcceptedFriendIds(isDisposed),
      };
      if (isDisposed()) {
        return;
      }
      for (final author in previous.difference(permitted)) {
        _evict(author);
      }
    } catch (_) {
      state = FeedTimelineStateMutator.failure(
        state,
        buffers.usedCachedSnapshot,
      );
    }
  }

  void hide(String postId) => _hiddenPostIds.add(postId);

  void evictRevoked() => _evictRevoked();
  Set<String> _evictRevoked() {
    final revoked = buffers.takeRevokedAuthors();
    for (final author in revoked) {
      _evict(author);
    }
    return revoked;
  }

  void _discardRevoked(List<FeedPostReadModel> page, Set<String> revoked) {
    final removed = page
        .where((post) => revoked.contains(post.authorUserId))
        .map((post) => post.postId);
    _emittedPostIds.removeAll(removed);
    page.removeWhere((post) => revoked.contains(post.authorUserId));
  }

  void _evict(String author) {
    buffers.evict(author);
    final removed = state.posts
        .where((post) => post.authorUserId == author)
        .map((post) => post.postId);
    _emittedPostIds.removeAll(removed);
    state = FeedTimelineStateMutator.withoutAuthor(state, author);
  }

  /// Overlays the live, backend-resolved author identity and level onto every
  /// post in [page] that has one, in place.
  ///
  /// A post's `authorDisplayName`, `authorAvatarInitials`, and
  /// `authorLevelLabel` are all frozen at publish time, and `feedPosts` is
  /// closed to client writes, so this overlay is the only thing that shows a
  /// renamed author under their current name on posts they already published.
  /// See [FeedAuthorLevelResolver.overlay] for the never-erase-a-stored-value
  /// contract this applies per post; a direct single-post read (feed
  /// notification tap-through) shares that same helper.
  Future<void> _overlayAuthorLevels(
    List<FeedPostReadModel> page,
    bool Function() isDisposed,
  ) async {
    if (page.isEmpty) return;
    final authorUids = {for (final post in page) post.authorUserId};
    await levelResolver.ensureResolved(authorUids);
    if (isDisposed()) return;
    for (var index = 0; index < page.length; index++) {
      page[index] = levelResolver.overlay(page[index]);
    }
  }
}
