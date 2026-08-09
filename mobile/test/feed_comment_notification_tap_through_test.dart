import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/feed/domain/repositories/feed_repository.dart';
import 'package:runiac_app/features/feed/presentation/current_session_feed.dart';
import 'package:runiac_app/features/feed/presentation/feed_comment_intent_controller.dart';
import 'package:runiac_app/features/feed/presentation/feed_timeline_screen_controller.dart';

void main() {
  testWidgets(
    'a notification intent for an already-loaded post opens its comment '
    'sheet without a direct read, refresh, or paging',
    (WidgetTester tester) async {
      final repository = _FakeFeedTimelineRepository(
        initialPosts: [_post('visible-post')],
      );
      final intent = FeedCommentIntentController();
      addTearDown(intent.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: repository,
              viewerContext: const FeedViewerContext(
                currentUserId: 'runner-current',
                acceptedFriendUserIds: <String>{},
              ),
              commentIntent: intent,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      intent.request('visible-post');
      await tester.pumpAndSettle();

      expect(find.text('Comments'), findsOneWidget);
      expect(repository.readPostCalls, isEmpty);
      expect(repository.refreshCalls, 0);
      expect(repository.loadMoreCalls, 0);
      expect(intent.pendingPostId, isNull);
    },
  );

  testWidgets(
    'a notification intent for a post absent from the loaded page is '
    'resolved by exactly one direct read, with no refresh or paging',
    (WidgetTester tester) async {
      final repository = _FakeFeedTimelineRepository(
        initialPosts: [_post('other-post')],
        readablePosts: [_post('notified-post')],
      );
      final intent = FeedCommentIntentController();
      addTearDown(intent.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: repository,
              viewerContext: const FeedViewerContext(
                currentUserId: 'runner-current',
                acceptedFriendUserIds: <String>{},
              ),
              commentIntent: intent,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      intent.request('notified-post');
      await tester.pumpAndSettle();

      expect(find.text('Comments'), findsOneWidget);
      // This is the regression guard for the reported defect: resolving a
      // notified post that fell out of the loaded page must cost exactly one
      // direct read, never a refresh or any amount of paging.
      expect(repository.readPostCalls, <String>['notified-post']);
      expect(repository.refreshCalls, 0);
      expect(repository.loadMoreCalls, 0);
      expect(intent.pendingPostId, isNull);
    },
  );

  testWidgets(
    'a notification intent whose direct read resolves to nothing shows the '
    'not-found message and opens no sheet',
    (WidgetTester tester) async {
      final repository = _FakeFeedTimelineRepository(
        initialPosts: [_post('other-post')],
      );
      final intent = FeedCommentIntentController();
      addTearDown(intent.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: repository,
              viewerContext: const FeedViewerContext(
                currentUserId: 'runner-current',
                acceptedFriendUserIds: <String>{},
              ),
              commentIntent: intent,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      intent.request('missing-post');
      await tester.pumpAndSettle();

      expect(repository.readPostCalls, <String>['missing-post']);
      expect(repository.refreshCalls, 0);
      expect(repository.loadMoreCalls, 0);
      expect(
        find.text('That post is no longer in your feed.'),
        findsOneWidget,
      );
      expect(find.text('Comments'), findsNothing);
      expect(intent.pendingPostId, isNull);
    },
  );

  testWidgets(
    'a notification intent whose direct read resolves to a post that can no '
    'longer be commented on shows the unavailable message and opens no sheet',
    (WidgetTester tester) async {
      final repository = _FakeFeedTimelineRepository(
        initialPosts: [_post('other-post')],
        readablePosts: [_post('notified-post', canComment: false)],
      );
      final intent = FeedCommentIntentController();
      addTearDown(intent.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: repository,
              viewerContext: const FeedViewerContext(
                currentUserId: 'runner-current',
                acceptedFriendUserIds: <String>{},
              ),
              commentIntent: intent,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      intent.request('notified-post');
      await tester.pumpAndSettle();

      expect(repository.readPostCalls, <String>['notified-post']);
      expect(repository.refreshCalls, 0);
      expect(repository.loadMoreCalls, 0);
      expect(
        find.text('Comments are unavailable right now.'),
        findsOneWidget,
      );
      expect(find.text('Comments'), findsNothing);
      expect(intent.pendingPostId, isNull);
    },
  );

  testWidgets(
    'a notification intent whose direct read fails offline shows the '
    'unavailable message rather than claiming the post left the feed',
    (WidgetTester tester) async {
      // The direct read is server-only, so offline it throws instead of
      // quietly resolving a stale cached post with commenting still enabled.
      // The user must not be told the post is gone — we simply could not
      // check.
      final repository = _FakeFeedTimelineRepository(
        initialPosts: [_post('other-post')],
        readPostThrows: true,
      );
      final intent = FeedCommentIntentController();
      addTearDown(intent.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: repository,
              viewerContext: const FeedViewerContext(
                currentUserId: 'runner-current',
                acceptedFriendUserIds: <String>{},
              ),
              commentIntent: intent,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      intent.request('notified-post');
      await tester.pumpAndSettle();

      expect(repository.readPostCalls, <String>['notified-post']);
      expect(repository.refreshCalls, 0);
      expect(repository.loadMoreCalls, 0);
      expect(
        find.text('Comments are unavailable right now.'),
        findsOneWidget,
      );
      expect(
        find.text('That post is no longer in your feed.'),
        findsNothing,
      );
      expect(find.text('Comments'), findsNothing);
      expect(intent.pendingPostId, isNull);
    },
  );

  test(
    'a pending intent is cleared when the signed-in owner changes, so it '
    'cannot auto-open a sheet for the previous account\'s post',
    () {
      final intent = FeedCommentIntentController();
      addTearDown(intent.dispose);
      final sessionStore = CurrentSessionFeedStore(ownerUid: 'runner-a');
      addTearDown(sessionStore.dispose);
      final controller = FeedTimelineScreenController(
        _FakeFeedTimelineRepository(initialPosts: const []),
        null,
        null,
        intent,
      );
      addTearDown(controller.dispose);
      controller.attachSession(sessionStore);

      intent.request('post-owned-by-runner-a');
      expect(intent.pendingPostId, 'post-owned-by-runner-a');

      sessionStore.syncOwner('runner-b');
      final cleared = controller.clearForOwnerChange();

      expect(cleared, isTrue);
      expect(intent.pendingPostId, isNull);
    },
  );
}

FeedPostReadModel _post(String postId, {bool canComment = true}) =>
    FeedPostReadModel(
      postId: postId,
      authorUserId: 'friend',
      authorDisplayName: 'Friend Runner',
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
      canComment: canComment,
      showsOwnerMenu: false,
      routeThumbnail: const FeedRouteThumbnailReadModel(
        thumbnailKey: 'notification-tap-through',
        accessibilityLabel: 'Private route preview',
      ),
    );

/// A minimal production-shaped [FeedTimelineRepository] whose [readPost]
/// resolves only from [readablePosts] — a stand-in for a post that fell out
/// of the loaded page but is still directly readable by id, the way a feed
/// engagement notification's own post always is. `loadMore`/`refresh` are
/// counted so every test above can assert the paging ladder this defect fix
/// removed is never exercised again.
class _FakeFeedTimelineRepository implements FeedTimelineRepository {
  _FakeFeedTimelineRepository({
    required List<FeedPostReadModel> initialPosts,
    List<FeedPostReadModel> readablePosts = const [],
    this.readPostThrows = false,
  }) : _posts = List<FeedPostReadModel>.of(initialPosts),
       _readablePosts = {
         for (final post in readablePosts) post.postId: post,
       };

  final List<FeedPostReadModel> _posts;
  final Map<String, FeedPostReadModel> _readablePosts;

  /// Simulates the server-only direct read failing, which is what happens
  /// offline: `readPublishedPost` uses `Source.server` precisely so a cached
  /// hit cannot resolve a stale post, so being offline throws instead.
  final bool readPostThrows;
  int refreshCalls = 0;
  int loadMoreCalls = 0;
  final List<String> readPostCalls = <String>[];

  @override
  FeedTimelineState get currentState => FeedTimelineState(
    posts: _posts,
    source: FeedTimelineSource.server,
    refreshing: false,
    exhausted: false,
  );

  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) =>
      loadInitial(viewerContext);

  @override
  Future<FeedTimelineState> loadInitial(
    FeedViewerContext viewerContext,
  ) async => currentState;

  @override
  Future<FeedTimelineState> refresh() async {
    refreshCalls += 1;
    return currentState;
  }

  @override
  Future<FeedTimelineState> loadMore() async {
    loadMoreCalls += 1;
    return currentState;
  }

  @override
  Future<FeedTimelineState> reconcileAccess() async => currentState;

  @override
  Future<void> setLike({
    required String postId,
    required bool isLiked,
  }) async {}

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
  Future<void> reportPost(String postId) async {}

  @override
  Future<void> deletePost(String postId) async {}

  @override
  Future<Uint8List> readThumbnail(String postId) async => Uint8List(0);

  @override
  Future<FeedPostReadModel?> readPost(String postId) async {
    readPostCalls.add(postId);
    if (readPostThrows) {
      // Stands in for the `unavailable` FirebaseException a server-only read
      // raises offline. The controller catches anything, so a plain exception
      // exercises the same path without dragging Firebase into this suite.
      throw Exception('unavailable');
    }
    return _readablePosts[postId];
  }

  @override
  void dispose() {}
}
