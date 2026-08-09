import '../../domain/models/feed_display_models.dart';
import 'feed_data_port.dart';

/// Owns the independent author buffers and their deterministic cursors.
class FeedAuthorBuffers {
  factory FeedAuthorBuffers({
    required FeedDataPort port,
    required String viewerUid,
  }) => FeedAuthorBuffers._(port, viewerUid);

  FeedAuthorBuffers._(this._port, this._viewerUid);

  final FeedDataPort _port;
  final String _viewerUid;
  final Map<String, _AuthorBuffer> _buffers = <String, _AuthorBuffer>{};
  final Set<String> _revokedAuthors = <String>{};
  bool usedCachedSnapshot = false;

  Iterable<String> get authorIds => _buffers.keys;
  bool get exhausted => _buffers.values.every(
    (buffer) => buffer.exhausted && buffer.posts.isEmpty,
  );
  bool containsAuthor(String authorUid) => _buffers.containsKey(authorUid);
  bool isEmpty(String authorUid) => _buffers[authorUid]?.posts.isEmpty ?? false;

  void replaceAuthors(Set<String> authorUids) {
    _buffers
      ..clear()
      ..addEntries(authorUids.map((uid) => MapEntry(uid, _AuthorBuffer(uid))));
  }

  void evict(String authorUid) => _buffers.remove(authorUid);

  Set<String> takeRevokedAuthors() {
    final result = Set<String>.from(_revokedAuthors);
    _revokedAuthors.clear();
    return result;
  }

  Future<void> fetchEveryAuthorOnce() async {
    for (final authorUid in List<String>.from(_buffers.keys)) {
      await fetch(authorUid);
    }
  }

  Future<Set<String>> loadAcceptedFriendIds(bool Function() isDisposed) =>
      _loadIds(
        (cursor) => _port.pageAcceptedFriends(
          viewerUid: _viewerUid,
          afterDocumentId: cursor,
        ),
        isDisposed,
      );

  Future<Set<String>> loadHiddenPostIds(bool Function() isDisposed) => _loadIds(
    (cursor) =>
        _port.pageHiddenPostIds(viewerUid: _viewerUid, afterDocumentId: cursor),
    isDisposed,
  );

  Future<bool> fetchEmptyAuthors() async {
    var fetched = false;
    for (final authorUid in List<String>.from(_buffers.keys)) {
      final buffer = _buffers[authorUid];
      if (buffer != null && !buffer.exhausted && buffer.posts.isEmpty) {
        await fetch(authorUid);
        fetched = true;
      }
    }
    return fetched;
  }

  Future<void> fetch(String authorUid) async {
    final buffer = _buffers[authorUid];
    if (buffer == null || buffer.exhausted) return;
    try {
      final page = await _port.pagePublishedPosts(
        authorUid: authorUid,
        viewerUid: _viewerUid,
        after: buffer.cursor,
      );
      usedCachedSnapshot = usedCachedSnapshot || page.fromCache;
      buffer.posts.addAll(page.posts);
      buffer.cursor = page.nextCursor;
      buffer.exhausted = page.nextCursor == null;
    } on FeedAuthorPermissionDenied {
      _revokedAuthors.add(authorUid);
      evict(authorUid);
    }
  }

  Future<Set<String>> _loadIds(
    Future<FeedIdPage> Function(String?) load,
    bool Function() isDisposed,
  ) async {
    final ids = <String>{};
    String? cursor;
    do {
      final page = await load(cursor);
      if (isDisposed()) return ids;
      usedCachedSnapshot = usedCachedSnapshot || page.fromCache;
      ids.addAll(page.ids);
      cursor = page.nextDocumentId;
    } while (cursor != null);
    return ids;
  }

  FeedSelectedPost? takeNewest() {
    _AuthorBuffer? selected;
    for (final buffer in _buffers.values) {
      if (buffer.posts.isEmpty) continue;
      if (selected == null ||
          _newer(buffer.posts.first, selected.posts.first)) {
        selected = buffer;
      }
    }
    return selected == null
        ? null
        : FeedSelectedPost(selected.authorUid, selected.posts.removeAt(0));
  }

  bool _newer(FeedPostDocument left, FeedPostDocument right) {
    final timestamp = left.createdAt.compareTo(right.createdAt);
    return timestamp != 0
        ? timestamp > 0
        : left.postId.compareTo(right.postId) > 0;
  }
}

class FeedSelectedPost {
  const FeedSelectedPost(this.authorUid, this.post);

  final String authorUid;
  final FeedPostDocument post;
}

class _AuthorBuffer {
  _AuthorBuffer(this.authorUid);

  final String authorUid;
  final List<FeedPostDocument> posts = <FeedPostDocument>[];
  FeedPostCursor? cursor;
  bool exhausted = false;
}
