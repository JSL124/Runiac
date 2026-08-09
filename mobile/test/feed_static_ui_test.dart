import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/core/widgets/runiac_level_profile_badge.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_data_port.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_test_data_port.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/firebase_feed_repository.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/feed/domain/repositories/feed_repository.dart';
import 'package:runiac_app/features/feed/presentation/current_session_feed.dart';
import 'package:runiac_app/features/you/presentation/widgets/you_surface_primitives.dart';

void main() {
  Future<SemanticsHandle> pumpFeed(WidgetTester tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CurrentSessionFeed())),
    );
    await tester.pumpAndSettle();
    return semantics;
  }

  testWidgets(
    'Feed uses the shared header treatment without a refresh button',
    (WidgetTester tester) async {
      final semantics = await pumpFeed(tester);

      expect(find.text('Feed'), findsOneWidget);
      expect(find.byType(YouHeaderAccentStrip), findsOneWidget);
      expect(find.byTooltip('Refresh'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('Feed shows static posts as full-width divider sections', (
    WidgetTester tester,
  ) async {
    final semantics = await pumpFeed(tester);

    expect(find.text('Runiac Runner'), findsOneWidget);
    expect(find.text('Jamie Tan'), findsOneWidget);
    expect(find.text('3.2 km'), findsOneWidget);
    expect(find.text('7:20 / km'), findsOneWidget);
    expect(find.text('23 min'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Private route preview unavailable'),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('feed-post-divider-feed-current-001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('feed-post-divider-feed-friend-001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('feed-author-profile-feed-current-001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('feed-author-profile-feed-friend-001')),
      findsOneWidget,
    );
    expect(find.text('Lv.6'), findsOneWidget);
    expect(find.text('Lv.4'), findsOneWidget);
    expect(find.bySemanticsLabel('Runner profile'), findsNothing);
    expect(find.byType(Card), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'Feed post passes a resolved avatarUrl to the level profile badge',
    (WidgetTester tester) async {
      const photoUrl =
          'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok';
      final port = FeedTestDataPort.withSingleFriend('friend-photo');
      port.authorLevels['friend-photo'] = const FeedAuthorLevel(
        levelLabel: 'Level 5',
        levelProgressFraction: 0.5,
        avatarUrl: photoUrl,
      );
      final repository = FirebaseFeedRepository(port: port);
      const viewer = FeedViewerContext(
        currentUserId: 'viewer',
        acceptedFriendUserIds: <String>{},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: repository,
              viewerContext: viewer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final badge = tester.widget<RuniacLevelProfileBadge>(
        find.byType(RuniacLevelProfileBadge),
      );
      expect(badge.photoUrl, photoUrl);
    },
  );

  testWidgets(
    "Feed post avatar is tappable for another runner but not for the "
    "viewer's own post",
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: _TwoAuthorsFeedRepository(),
              viewerContext: const FeedViewerContext(
                currentUserId: 'viewer',
                acceptedFriendUserIds: <String>{'other-runner'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The rows merge the avatar's Semantics into the post's shared
      // container node (there is no explicit-child-node boundary between
      // the avatar and the surrounding text), so the profile-link label is
      // a substring of that node's combined label rather than an exact
      // match.
      expect(
        find.bySemanticsLabel(RegExp('View Other Runner profile')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('View Viewer Runner profile')),
        findsNothing,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'Feed uses current profile snapshot when own post level snapshot is empty',
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: _ViewerMissingLevelRepository(),
              viewerContext: const FeedViewerContext(
                currentUserId: 'viewer',
                acceptedFriendUserIds: <String>{'viewer'},
              ),
              currentAuthorProfile: const FeedAuthorProfileSnapshot(
                userId: 'viewer',
                displayName: 'babo',
                avatarInitials: 'B',
                levelLabel: 'Level 7',
                levelProgressFraction: 0.4,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('babo'), findsOneWidget);
      expect(find.text('Lv.7'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('feed-author-profile-viewer-post')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('Feed exposes pull-to-refresh and read-only engagement actions', (
    WidgetTester tester,
  ) async {
    final semantics = await pumpFeed(tester);

    final refreshIndicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );

    expect(refreshIndicator.onRefresh, isNotNull);
    expect(find.bySemanticsLabel('Like 4 likes'), findsOneWidget);
    expect(find.bySemanticsLabel('Comment 1 comment'), findsOneWidget);
    expect(find.bySemanticsLabel('Post options'), findsNWidgets(2));
    semantics.dispose();
  });

  testWidgets('Feed shows an empty state after a successful empty load', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrentSessionFeed(repository: _EmptyFeedRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No shared runs yet.'), findsOneWidget);
    expect(
      find.text('Runs shared by you and accepted friends will appear here.'),
      findsOneWidget,
    );
    expect(find.byType(RefreshIndicator), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Feed error state can retry and recover', (
    WidgetTester tester,
  ) async {
    final repository = _RecoveringFeedRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CurrentSessionFeed(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Feed could not refresh.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(repository.loadCount, 2);
    expect(find.text('Recovered Runner'), findsOneWidget);
    expect(find.text('Feed could not refresh.'), findsNothing);
  });

  testWidgets(
    'Feed disables comments when a visible post cannot be commented',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: _NonCommentableFeedRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quiet Runner'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('feed-comment-action-feed-quiet-001')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Comments'), findsNothing);
    },
  );

  testWidgets(
    'Feed timeline uses the injected viewer and delegates likes to the repository',
    (WidgetTester tester) async {
      final port = FeedTestDataPort.withUnevenAuthors();
      final repository = FirebaseFeedRepository(port: port);
      const viewer = FeedViewerContext(
        currentUserId: 'viewer',
        acceptedFriendUserIds: <String>{},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: repository,
              viewerContext: viewer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        port.authorQueries.map((query) => query.authorUid),
        contains('viewer'),
      );
      expect(
        port.authorQueries.map((query) => query.authorUid),
        isNot(contains('runner-current')),
      );

      await tester.tap(find.byKey(const ValueKey('feed-like-action-viewer-0')));
      await tester.pumpAndSettle();

      expect(port.likeWrites, <String>['viewer-0']);
      expect(repository.currentState.posts.first.likeCount, 0);
      expect(find.text('1 like'), findsOneWidget);
    },
  );

  testWidgets(
    'Feed ignores an older viewer load after the authenticated viewer changes',
    (WidgetTester tester) async {
      final repository = _ControlledTimelineRepository();
      const firstViewer = FeedViewerContext(
        currentUserId: 'first-viewer',
        acceptedFriendUserIds: <String>{},
      );
      const secondViewer = FeedViewerContext(
        currentUserId: 'second-viewer',
        acceptedFriendUserIds: <String>{},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: repository,
              viewerContext: firstViewer,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentSessionFeed(
              repository: repository,
              viewerContext: secondViewer,
            ),
          ),
        ),
      );
      await tester.pump();

      repository.complete(
        'second-viewer',
        _timelineFor(authorUid: 'second-viewer', displayName: 'Second Viewer'),
      );
      await tester.pumpAndSettle();
      repository.complete(
        'first-viewer',
        _timelineFor(authorUid: 'first-viewer', displayName: 'First Viewer'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Second Viewer'), findsOneWidget);
      expect(find.text('First Viewer'), findsNothing);
    },
  );
}

FeedTimelineState _timelineFor({
  required String authorUid,
  required String displayName,
}) => FeedTimelineState(
  posts: <FeedPostReadModel>[
    FeedPostReadModel(
      postId: '$authorUid-post',
      authorUserId: authorUid,
      authorDisplayName: displayName,
      authorAvatarInitials: 'RV',
      authorLevelLabel: 'Level 5',
      relativeTimeLabel: 'Now',
      distanceLabel: '2.0 km',
      paceLabel: '7:00 / km',
      durationLabel: '14 min',
      likeCount: 0,
      commentCount: 0,
      isLikedByViewer: false,
      hasViewerCommented: false,
      canComment: true,
      showsOwnerMenu: true,
      routeThumbnail: const FeedRouteThumbnailReadModel(
        thumbnailKey: 'viewer-race',
        accessibilityLabel: 'Viewer race route preview',
      ),
    ),
  ],
  source: FeedTimelineSource.server,
  refreshing: false,
  exhausted: true,
);

class _ControlledTimelineRepository implements FeedTimelineRepository {
  final Map<String, Completer<FeedTimelineState>> _pending =
      <String, Completer<FeedTimelineState>>{};
  FeedTimelineState _state = FeedTimelineState(
    posts: const <FeedPostReadModel>[],
    source: FeedTimelineSource.server,
    refreshing: false,
    exhausted: false,
  );

  @override
  FeedTimelineState get currentState => _state;

  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) =>
      loadInitial(viewerContext);

  @override
  Future<FeedTimelineState> loadInitial(FeedViewerContext viewerContext) {
    final completer = Completer<FeedTimelineState>();
    _pending[viewerContext.currentUserId] = completer;
    return completer.future.then((state) {
      _state = state;
      return state;
    });
  }

  void complete(String viewerUid, FeedTimelineState state) {
    _pending.remove(viewerUid)!.complete(state);
  }

  @override
  Future<FeedTimelineState> loadMore() async => _state;

  @override
  Future<FeedTimelineState> refresh() async => _state;

  @override
  Future<FeedTimelineState> reconcileAccess() async => _state;

  @override
  Future<void> setLike({required String postId, required bool isLiked}) async {}

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
    for (final post in _state.posts) {
      if (post.postId == postId) return post;
    }
    return null;
  }

  @override
  void dispose() {}
}

class _EmptyFeedRepository implements FeedRepository {
  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) async {
    return FeedReadModel(posts: const []);
  }
}

class _ViewerMissingLevelRepository implements FeedRepository {
  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) async {
    return FeedReadModel(
      posts: const [
        FeedPostReadModel(
          postId: 'viewer-post',
          authorUserId: 'viewer',
          authorDisplayName: 'babo',
          authorAvatarInitials: 'B',
          authorLevelLabel: '',
          relativeTimeLabel: 'Now',
          distanceLabel: '7.5 km',
          paceLabel: '7:06 / km',
          durationLabel: '53 min',
          likeCount: 1,
          commentCount: 0,
          isLikedByViewer: true,
          hasViewerCommented: false,
          canComment: true,
          showsOwnerMenu: true,
          routeThumbnail: FeedRouteThumbnailReadModel(
            thumbnailKey: 'viewer-preview',
            accessibilityLabel: 'Viewer route preview',
          ),
        ),
      ],
    );
  }
}

class _RecoveringFeedRepository implements FeedRepository {
  var loadCount = 0;

  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) async {
    loadCount += 1;
    if (loadCount == 1) {
      throw StateError('temporary feed failure');
    }
    return FeedReadModel(
      posts: const [
        FeedPostReadModel(
          postId: 'feed-recovered-001',
          authorUserId: 'runner-current',
          authorDisplayName: 'Recovered Runner',
          authorAvatarInitials: 'RR',
          authorLevelLabel: 'Level 6',
          relativeTimeLabel: 'Now',
          distanceLabel: '2.0 km',
          paceLabel: '7:00 / km',
          durationLabel: '14 min',
          likeCount: 0,
          commentCount: 0,
          isLikedByViewer: false,
          hasViewerCommented: false,
          canComment: true,
          showsOwnerMenu: true,
          routeThumbnail: FeedRouteThumbnailReadModel(
            thumbnailKey: 'recovered-preview',
            accessibilityLabel: 'Recovered route preview',
          ),
        ),
      ],
    );
  }
}

class _NonCommentableFeedRepository implements FeedRepository {
  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) async {
    return FeedReadModel(
      posts: const [
        FeedPostReadModel(
          postId: 'feed-quiet-001',
          authorUserId: 'runner-friend',
          authorDisplayName: 'Quiet Runner',
          authorAvatarInitials: 'QR',
          authorLevelLabel: 'Level 2',
          relativeTimeLabel: 'Today',
          distanceLabel: '1.8 km',
          paceLabel: '8:10 / km',
          durationLabel: '15 min',
          likeCount: 0,
          commentCount: 0,
          isLikedByViewer: false,
          hasViewerCommented: false,
          canComment: false,
          showsOwnerMenu: false,
          routeThumbnail: FeedRouteThumbnailReadModel(
            thumbnailKey: 'quiet-preview',
            accessibilityLabel: 'Quiet route preview',
          ),
        ),
      ],
    );
  }
}

class _TwoAuthorsFeedRepository implements FeedRepository {
  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) async {
    return FeedReadModel(
      posts: const [
        FeedPostReadModel(
          postId: 'own-post',
          authorUserId: 'viewer',
          authorDisplayName: 'Viewer Runner',
          authorAvatarInitials: 'VR',
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
          showsOwnerMenu: true,
          routeThumbnail: FeedRouteThumbnailReadModel(
            thumbnailKey: 'own-preview',
            accessibilityLabel: 'Own route preview',
          ),
        ),
        FeedPostReadModel(
          postId: 'other-post',
          authorUserId: 'other-runner',
          authorDisplayName: 'Other Runner',
          authorAvatarInitials: 'OR',
          authorLevelLabel: 'Level 5',
          relativeTimeLabel: 'Now',
          distanceLabel: '3.0 km',
          paceLabel: '6:30 / km',
          durationLabel: '18 min',
          likeCount: 0,
          commentCount: 0,
          isLikedByViewer: false,
          hasViewerCommented: false,
          canComment: true,
          showsOwnerMenu: false,
          routeThumbnail: FeedRouteThumbnailReadModel(
            thumbnailKey: 'other-preview',
            accessibilityLabel: 'Other route preview',
          ),
        ),
      ],
    );
  }
}
