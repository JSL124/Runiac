import 'dart:typed_data';

import '../../domain/models/feed_display_models.dart';
import 'feed_data_port.dart';

/// Explicit deterministic QA fake; it is never selected by production wiring.
class FeedTestDataPort implements FeedDataPort {
  FeedTestDataPort.withContinuationDeniedAuthor() {
    friends = <String>['denied-author', 'other-author'];
    _posts
      ..addAll(
        List<FeedPostDocument>.generate(
          21,
          (index) => _post('denied-author', index, 100 - index),
        ),
      )
      ..add(_post('other-author', 0, 101));
    continuationDeniedAuthors.add('denied-author');
  }

  FeedTestDataPort.withInterleavedContinuationDeniedAuthor() {
    friends = <String>['denied-author', 'other-author'];
    _posts
      ..addAll(
        List<FeedPostDocument>.generate(
          25,
          (index) => _post('denied-author', index, 100 - index),
        ),
      )
      ..addAll(
        List<FeedPostDocument>.generate(
          4,
          (index) => _post('other-author', index, 200 - index),
        ),
      );
    continuationDeniedAuthors.add('denied-author');
  }

  FeedTestDataPort.withUnevenAuthors() {
    friends = List<String>.generate(35, _friendId);
    for (var index = 0; index < friends.length; index++) {
      for (var item = 0; item < (index == 0 ? 45 : (index % 4) + 1); item++) {
        _posts.add(_post(friends[index], item, index * 3 + item ~/ 2));
      }
    }
    _posts.add(_post('viewer', 0, 1000));
    hidden.addAll(
      List<String>.generate(
        31,
        (index) => 'hidden-${index.toString().padLeft(2, '0')}',
      ),
    );
    hidden.add(_posts[4].postId);
  }

  /// A minimal, deterministic single-author fixture for author-level overlay
  /// tests, where pagination composition doesn't matter. [storedAvatarUrl]
  /// seeds the post's stored `authorAvatarUrl` (empty by default, matching
  /// every real `feedPosts` document) so a test can prove the live overlay's
  /// never-erase-a-stored-value contract for that field too.
  FeedTestDataPort.withSingleFriend(
    String friendUid, {
    String storedAvatarUrl = '',
  }) {
    friends = <String>[friendUid];
    _posts.add(_post(friendUid, 0, 100, authorAvatarUrl: storedAvatarUrl));
  }

  late List<String> friends;
  final List<FeedPostDocument> _posts = <FeedPostDocument>[];
  final Set<String> hidden = <String>{}, deniedAuthors = <String>{};
  final Set<String> continuationDeniedAuthors = <String>{};
  final List<String?> friendCursors = <String?>[], hiddenCursors = <String?>[];
  final List<FeedTestAuthorQuery> authorQueries = <FeedTestAuthorQuery>[];
  final List<String> mutations = <String>[], likeWrites = <String>[];
  final List<FeedCommentDocument> comments = <FeedCommentDocument>[];
  final List<FeedCommentCursor?> commentCursors = <FeedCommentCursor?>[];
  bool cached = false;

  /// Configurable resolved live levels, keyed by author uid. A uid absent
  /// here mirrors a backend that has no snapshot for that author.
  final Map<String, FeedAuthorLevel> authorLevels = <String, FeedAuthorLevel>{};
  final List<List<String>> authorLevelQueries = <List<String>>[];

  /// The `postId` scope handed to each [fetchAuthorLevels] call, positionally
  /// aligned with [authorLevelQueries]. `null` means the uid-only form.
  final List<String?> authorLevelPostIds = <String?>[];

  /// Set to make [fetchAuthorLevels] throw, simulating an offline device or
  /// a not-yet-deployed callable.
  Object? authorLevelsError;

  List<FeedPostDocument> get visiblePosts =>
      _posts.where((post) => !hidden.contains(post.postId)).toList()
        ..sort(_compare);

  @override
  Future<FeedIdPage> pageAcceptedFriends({
    required String viewerUid,
    String? afterDocumentId,
  }) => _ids(friends..sort(), afterDocumentId, friendCursors);

  @override
  Future<FeedIdPage> pageHiddenPostIds({
    required String viewerUid,
    String? afterDocumentId,
  }) => _ids(hidden.toList()..sort(), afterDocumentId, hiddenCursors);

  @override
  Future<FeedPostPage> pagePublishedPosts({
    required String authorUid,
    required String viewerUid,
    FeedPostCursor? after,
  }) async {
    authorQueries.add(FeedTestAuthorQuery(authorUid, 'published', 20, after));
    if (deniedAuthors.contains(authorUid)) {
      throw FeedAuthorPermissionDenied(authorUid);
    }
    if (after != null && continuationDeniedAuthors.contains(authorUid)) {
      throw FeedAuthorPermissionDenied(authorUid);
    }
    final posts = _posts.where((post) => post.authorUid == authorUid).toList()
      ..sort(_compare);
    final start = after == null
        ? 0
        : posts.indexWhere((post) => post.postId == after.postId) + 1;
    final page = posts.skip(start).take(20).toList();
    final next = start + page.length < posts.length && page.isNotEmpty
        ? FeedPostCursor(
            createdAt: page.last.createdAt,
            postId: page.last.postId,
          )
        : null;
    return FeedPostPage(posts: page, fromCache: cached, nextCursor: next);
  }

  /// Set to make [readPublishedPost] throw for [readPublishedPostThrowsFor],
  /// simulating a read failure distinct from a genuine not-found result.
  String? readPublishedPostThrowsFor;
  final List<String> readPublishedPostCalls = <String>[];

  @override
  Future<FeedPostDocument?> readPublishedPost(String postId) async {
    readPublishedPostCalls.add(postId);
    if (postId == readPublishedPostThrowsFor) {
      throw StateError('Feed post read failed.');
    }
    for (final post in _posts) {
      if (post.postId == postId) return post;
    }
    return null;
  }

  @override
  Future<FeedCommentDocumentPage> pageComments({
    required String postId,
    FeedCommentCursor? startAfter,
  }) async {
    commentCursors.add(startAfter);
    final ordered = List<FeedCommentDocument>.of(comments)
      ..sort((left, right) {
        final time = right.createdAt.compareTo(left.createdAt);
        return time == 0 ? right.commentId.compareTo(left.commentId) : time;
      });
    final start = startAfter == null
        ? 0
        : ordered.indexWhere(
                (comment) => comment.commentId == startAfter.commentId,
              ) +
              1;
    final page = ordered.skip(start).take(20).toList(growable: false);
    final hasMore = start + page.length < ordered.length;
    final last = page.isEmpty ? null : page.last;
    return FeedCommentDocumentPage(
      comments: page,
      fromCache: cached,
      nextCursor: hasMore && last != null
          ? FeedCommentCursor(
              createdAt: last.createdAt,
              commentId: last.commentId,
            )
          : null,
    );
  }

  void addTiedComments(int count) {
    for (var index = 0; index < count; index++) {
      comments.add(
        FeedCommentDocument(
          commentId: 'comment-${index.toString().padLeft(2, '0')}',
          authorUid: index.isEven ? 'viewer' : 'friend',
          authorDisplayName: 'Runner',
          authorAvatarInitials: 'RU',
          authorLevelLabel: 'Level 3',
          body: 'Comment $index',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }
  }

  @override
  Future<void> callPostAction({
    required String action,
    required String postId,
  }) async => mutations.add('$action:$postId');

  @override
  Future<Uint8List> readThumbnail(String postId) async =>
      Uint8List.fromList(<int>[137, 80, 78, 71]);

  @override
  Future<Map<String, FeedAuthorLevel>> fetchAuthorLevels(
    List<String> uids, {
    String? postId,
  }) async {
    authorLevelQueries.add(uids);
    authorLevelPostIds.add(postId);
    final error = authorLevelsError;
    if (error != null) {
      throw error;
    }
    return <String, FeedAuthorLevel>{
      for (final uid in uids)
        if (authorLevels.containsKey(uid)) uid: authorLevels[uid]!,
    };
  }

  @override
  Future<void> setViewerLike({
    required String viewerUid,
    required String postId,
    required bool isLiked,
  }) async {
    likeWrites.add(postId);
    mutations.add('like:$postId');
  }

  @override
  Future<void> createComment({
    required String viewerUid,
    required FeedCommentMutation mutation,
  }) async => mutations.add('comment-create:${mutation.postId}');

  @override
  Future<void> updateComment({
    required String viewerUid,
    required FeedCommentMutation mutation,
  }) async => mutations.add('comment-update:${mutation.postId}');

  @override
  Future<void> deleteComment({
    required String viewerUid,
    required String postId,
    required String commentId,
  }) async => mutations.add('comment-delete:$postId');

  void addTopPost(String postId) =>
      _posts.add(_post('viewer', 99, 9999, id: postId));

  Future<FeedIdPage> _ids(
    List<String> ids,
    String? after,
    List<String?> calls,
  ) async {
    calls.add(after);
    final start = after == null ? 0 : ids.indexOf(after) + 1;
    final page = ids.skip(start).take(30).toList();
    return FeedIdPage(
      ids: page,
      fromCache: cached,
      nextDocumentId: page.length == 30 ? page.last : null,
    );
  }

  static String _friendId(int index) =>
      'friend-${index.toString().padLeft(2, '0')}';
  static FeedPostDocument _post(
    String author,
    int item,
    int minute, {
    String? id,
    String authorAvatarUrl = '',
  }) => FeedPostDocument(
    postId: id ?? '$author-$item',
    authorUid: author,
    authorDisplayName: author,
    authorAvatarInitials: 'FR',
    authorAvatarUrl: authorAvatarUrl,
    authorLevelLabel: 'Level 3',
    createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: minute)),
    distanceMeters: 3000,
    durationSeconds: 1500,
    averagePaceSecondsPerKm: 500,
    likeCount: item,
    commentCount: 0,
    viewerLiked: false,
    viewerCommented: false,
  );
}

class FeedTestAuthorQuery {
  const FeedTestAuthorQuery(
    this.authorUid,
    this.status,
    this.limit,
    this.after,
  );
  final String authorUid, status;
  final int limit;
  final FeedPostCursor? after;
}

int _compare(FeedPostDocument left, FeedPostDocument right) {
  final time = right.createdAt.compareTo(left.createdAt);
  return time == 0 ? right.postId.compareTo(left.postId) : time;
}
