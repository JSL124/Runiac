import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_data_port.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/firebase_feed_data_port.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/firebase_feed_repository.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/firebase_feed_post_mapper.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_test_data_port.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';

void main() {
  const viewer = FeedViewerContext(
    currentUserId: 'viewer',
    acceptedFriendUserIds: <String>{},
  );

  test('maps backend ISO createdAt strings into Feed posts', () {
    final post =
        FirebaseFeedPostMapper.fromData('activity-a', <String, Object?>{
          'authorUid': 'viewer',
          'authorDisplayName': 'Runner',
          'authorAvatarInitials': 'R',
          'createdAt': '2026-07-11T21:32:22.329Z',
          'distanceMeters': 6471,
          'durationSeconds': 2738,
          'averagePaceSecondsPerKm': 423,
          'likeCount': 0,
          'commentCount': 0,
        });

    expect(post.createdAt, DateTime.utc(2026, 7, 11, 21, 32, 22, 329));
  });

  test(
    'buffers 35 authors, pages document IDs, and globally merges tied rows',
    () async {
      final port = FeedTestDataPort.withUnevenAuthors();
      final repository = FirebaseFeedRepository(port: port);
      final first = await repository.loadInitial(viewer);
      final second = await repository.loadMore();
      final actual = second.posts.map((post) => post.postId).toList();
      final expected = port.visiblePosts
          .take(40)
          .map((post) => post.postId)
          .toList();

      expect(first.posts, hasLength(20));
      expect(second.posts, hasLength(40));
      expect(actual, expected);
      expect(port.friendCursors, <String?>[null, 'friend-29']);
      expect(port.hiddenCursors, <String?>[null, 'hidden-28']);
      expect(port.authorQueries, everyElement(_isOneAuthorPublishedQuery));
      expect(
        port.authorQueries.map((query) => query.authorUid).toSet(),
        containsAll(port.friends),
      );
      for (
        var page = 0;
        page < 8 &&
            port.authorQueries
                    .where((query) => query.authorUid == 'friend-00')
                    .length <
                2;
        page++
      ) {
        await repository.loadMore();
      }
      expect(
        port.authorQueries
            .where((query) => query.authorUid == 'friend-00')
            .map((query) => query.after)
            .toSet()
            .length,
        greaterThan(1),
      );
    },
  );

  test(
    'uses leftovers before refetch, isolates revocation, and only refresh admits arrivals',
    () async {
      final port = FeedTestDataPort.withUnevenAuthors();
      final repository = FirebaseFeedRepository(port: port);
      await repository.loadInitial(viewer);
      final initialQueries = port.authorQueries.length;
      final continued = await repository.loadMore();
      expect(port.authorQueries.length, initialQueries);
      expect(
        continued.posts.map((post) => post.postId).toSet().length,
        continued.posts.length,
      );

      final beforeRevoke = continued.posts
          .where((post) => post.authorUserId != 'friend-01')
          .map((post) => post.postId)
          .toList();
      port.friends.remove('friend-01');
      final revoked = await repository.reconcileAccess();
      expect(revoked.posts.map((post) => post.postId), beforeRevoke);

      port.addTopPost('fresh-post');
      expect(
        revoked.posts.map((post) => post.postId),
        isNot(contains('fresh-post')),
      );
      final refreshed = await repository.refresh();
      expect(refreshed.posts, hasLength(20));
      expect(
        refreshed.posts.map((post) => post.postId),
        port.visiblePosts.take(20).map((post) => post.postId),
      );
      expect(
        refreshed.posts.map((post) => post.postId),
        contains('fresh-post'),
      );
    },
  );

  test(
    'evicts only a denied author and preserves server-owned counts',
    () async {
      final port = FeedTestDataPort.withUnevenAuthors();
      final repository = FirebaseFeedRepository(port: port);
      final beforeDenied = await repository.loadInitial(viewer);
      final survivingBefore = beforeDenied.posts
          .where((post) => post.authorUserId != 'friend-02')
          .map((post) => post.postId)
          .toList();
      port.deniedAuthors.add('friend-02');
      final denied = await repository.refresh();
      expect(
        denied.posts.where((post) => post.authorUserId == 'friend-02'),
        isEmpty,
      );
      expect(
        denied.posts.where((post) => post.authorUserId == 'viewer'),
        isNotEmpty,
      );
      expect(denied.recoverableError, isNull);
      expect(
        denied.posts.map((post) => post.postId).take(survivingBefore.length),
        survivingBefore,
      );
      final target = denied.posts.first;
      await repository.setLike(
        postId: target.postId,
        isLiked: !target.isLikedByViewer,
      );
      expect(
        repository.currentState.posts
            .firstWhere((post) => post.postId == target.postId)
            .likeCount,
        target.likeCount,
      );
      expect(port.likeWrites, hasLength(1));
    },
  );

  test(
    'continuation denial evicts a selected author before its held row can emit',
    () async {
      final port = FeedTestDataPort.withContinuationDeniedAuthor();
      final repository = FirebaseFeedRepository(port: port);
      const continuationViewer = FeedViewerContext(
        currentUserId: 'viewer',
        acceptedFriendUserIds: <String>{},
      );

      final initial = await repository.loadInitial(continuationViewer);
      final afterDenial = await repository.loadMore();

      expect(
        initial.posts.where((post) => post.authorUserId == 'denied-author'),
        isNotEmpty,
      );
      expect(
        afterDenial.posts.where((post) => post.authorUserId == 'denied-author'),
        isEmpty,
      );
      expect(afterDenial.posts.map((post) => post.authorUserId), <String>[
        'other-author',
      ]);
    },
  );

  test(
    'continuation denial removes every revoked row accumulated in the local page',
    () async {
      final port = FeedTestDataPort.withInterleavedContinuationDeniedAuthor();
      final repository = FirebaseFeedRepository(port: port);
      const continuationViewer = FeedViewerContext(
        currentUserId: 'viewer',
        acceptedFriendUserIds: <String>{},
      );

      final initial = await repository.loadInitial(continuationViewer);
      final afterDenial = await repository.loadMore();

      expect(
        initial.posts.where((post) => post.authorUserId == 'denied-author'),
        hasLength(16),
      );
      expect(
        afterDenial.posts.where((post) => post.authorUserId == 'denied-author'),
        isEmpty,
      );
      expect(afterDenial.posts.map((post) => post.postId), <String>[
        'other-author-0',
        'other-author-1',
        'other-author-2',
        'other-author-3',
      ]);
    },
  );

  test(
    'cached snapshots disable every mutation until a server refresh recovers',
    () async {
      final port = FeedTestDataPort.withUnevenAuthors()..cached = true;
      final repository = FirebaseFeedRepository(port: port);
      final offline = await repository.loadInitial(viewer);
      expect(offline.source, FeedTimelineSource.cachedOffline);
      expect(offline.mutationsEnabled, isFalse);
      await repository.setLike(
        postId: offline.posts.first.postId,
        isLiked: true,
      );
      const comment = FeedCommentMutation(
        postId: 'offline-post',
        commentId: 'comment-1',
        body: 'Nice run',
      );
      await repository.createComment(comment);
      await repository.updateComment(comment);
      await repository.deleteComment(
        postId: comment.postId,
        commentId: 'comment-1',
      );
      await repository.reportPost(offline.posts.first.postId);
      await repository.deletePost(offline.posts.first.postId);
      expect(port.mutations, isEmpty);

      port.cached = false;
      final recovered = await repository.refresh();
      expect(recovered.source, FeedTimelineSource.server);
      await repository.setLike(
        postId: recovered.posts.first.postId,
        isLiked: true,
      );
      expect(port.likeWrites, hasLength(1));
    },
  );

  test('does not mutate before a viewer timeline is initialized', () async {
    final port = FeedTestDataPort.withUnevenAuthors();
    final repository = FirebaseFeedRepository(port: port);

    await repository.reportPost('post-before-viewer');
    await repository.deletePost('post-before-viewer');

    expect(port.mutations, isEmpty);
  });

  test('projection permission denial is isolated to its author', () async {
    await expectLater(
      FirebaseFeedDataPort.guardAuthorPage<String>('denied-author', () async {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      }),
      throwsA(
        isA<FeedAuthorPermissionDenied>().having(
          (error) => error.authorUid,
          'author UID',
          'denied-author',
        ),
      ),
    );
    await expectLater(
      FirebaseFeedDataPort.guardAuthorPage<String>('other-author', () async {
        throw StateError('malformed projection');
      }),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'reconcile and disposed repositories preserve safe empty state',
    () async {
      final port = FeedTestDataPort.withUnevenAuthors();
      final repository = FirebaseFeedRepository(port: port);

      expect(await repository.reconcileAccess(), same(repository.currentState));
      repository.dispose();
      await repository.setLike(postId: 'post-after-disposal', isLiked: true);
      await repository.reportPost('post-after-disposal');
      await repository.deletePost('post-after-disposal');

      expect(repository.currentState.posts, isEmpty);
      expect(await repository.reconcileAccess(), same(repository.currentState));
      expect(port.mutations, isEmpty);
    },
  );

  test(
    'dispose stops paged discovery before later friend or hidden queries',
    () async {
      final port = _DeferredFriendPagePort();
      final repository = FirebaseFeedRepository(port: port);

      final pending = repository.loadInitial(viewer);
      await port.started.future;
      repository.dispose();
      port.release.complete();

      final state = await pending;
      expect(state.posts, isEmpty);
      expect(port.friendCursors, <String?>[null]);
      expect(port.hiddenCursors, isEmpty);
      expect(port.authorQueries, isEmpty);
    },
  );

  test('dispose performs zero queued comment reads', () async {
    final port = _DeferredFriendPagePort();
    final repository = FirebaseFeedRepository(port: port);

    final initial = repository.loadInitial(viewer);
    await port.started.future;
    final queuedComments = repository.loadComments(postId: 'post-1');
    repository.dispose();
    port.release.complete();

    await initial;
    final page = await queuedComments;
    expect(page.comments, isEmpty);
    expect(port.commentCursors, isEmpty);
  });

  test(
    'dispose prevents a delayed access reconciliation from resurrecting rows',
    () async {
      final port = _DeferredReconcilePort();
      final repository = FirebaseFeedRepository(port: port);
      await repository.loadInitial(viewer);
      expect(repository.currentState.posts, isNotEmpty);

      port.deferNextFriendPage = true;
      final pending = repository.reconcileAccess();
      await port.started.future;
      repository.dispose();
      port.release.complete();

      await pending;
      expect(repository.currentState.posts, isEmpty);
    },
  );

  test('pages tied comments newest-first without gaps or duplicates', () async {
    final port = FeedTestDataPort.withUnevenAuthors()..addTiedComments(21);
    final repository = FirebaseFeedRepository(port: port);
    await repository.loadInitial(viewer);

    final first = await repository.loadComments(postId: 'post-1');
    final second = await repository.loadComments(
      postId: 'post-1',
      startAfter: FeedCommentCursor(
        createdAt: first.comments.last.createdAt,
        commentId: first.comments.last.commentId,
      ),
    );
    final ids = <FeedCommentReadModel>[
      ...first.comments,
      ...second.comments,
    ].map((comment) => comment.commentId).toList();

    expect(first.comments, hasLength(20));
    expect(second.comments, hasLength(1));
    expect(ids.toSet(), hasLength(21));
    expect(ids, <String>[
      for (var index = 20; index >= 0; index--)
        'comment-${index.toString().padLeft(2, '0')}',
    ]);
    expect(port.commentCursors, hasLength(2));
  });
}

class _DeferredFriendPagePort extends FeedTestDataPort {
  _DeferredFriendPagePort() : super.withUnevenAuthors();

  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  var _deferred = false;

  @override
  Future<FeedIdPage> pageAcceptedFriends({
    required String viewerUid,
    String? afterDocumentId,
  }) async {
    if (!_deferred) {
      _deferred = true;
      started.complete();
      await release.future;
    }
    return super.pageAcceptedFriends(
      viewerUid: viewerUid,
      afterDocumentId: afterDocumentId,
    );
  }
}

class _DeferredReconcilePort extends FeedTestDataPort {
  _DeferredReconcilePort() : super.withUnevenAuthors();

  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  var deferNextFriendPage = false;

  @override
  Future<FeedIdPage> pageAcceptedFriends({
    required String viewerUid,
    String? afterDocumentId,
  }) async {
    if (deferNextFriendPage) {
      deferNextFriendPage = false;
      started.complete();
      await release.future;
    }
    return super.pageAcceptedFriends(
      viewerUid: viewerUid,
      afterDocumentId: afterDocumentId,
    );
  }
}

final _isOneAuthorPublishedQuery = isA<FeedTestAuthorQuery>()
    .having((query) => query.status, 'status', 'published')
    .having((query) => query.limit, 'limit', lessThanOrEqualTo(20))
    .having((query) => query.authorUid, 'author uid', isNotEmpty);
