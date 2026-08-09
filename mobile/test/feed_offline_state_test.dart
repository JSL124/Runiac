import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/feed/presentation/current_session_feed.dart';
import 'package:runiac_app/features/feed/presentation/feed_timeline_screen_controller.dart';

import 'feed_offline_state_test_support.dart';

void main() {
  testWidgets(
    'cached Feed is visibly read-only and recovers from server state',
    (tester) async {
      final repository = ScreenFeedRepository(
        source: FeedTimelineSource.cachedOffline,
      );
      await _pump(tester, repository);

      expect(
        find.text('Offline — cached feed. Actions are disabled.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Private route preview unavailable'),
        findsOneWidget,
      );
      expect(_isEnabled(tester, 'feed-like-action-post-0'), isFalse);
      await tester.tap(find.byKey(const ValueKey('feed-like-action-post-0')));
      await tester.tap(find.bySemanticsLabel('Post options'));
      await tester.pumpAndSettle();
      expect(repository.likeCalls, 0);
      expect(repository.reportCalls, 0);
      expect(find.text('Post options'), findsNothing);

      repository.source = FeedTimelineSource.server;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();

      expect(
        find.text('Offline — cached feed. Actions are disabled.'),
        findsNothing,
      );
      expect(_isEnabled(tester, 'feed-like-action-post-0'), isTrue);
      expect(find.text('Friend Runner 0'), findsOneWidget);
    },
  );

  testWidgets('report removes only the reporter row after repository success', (
    tester,
  ) async {
    final repository = ScreenFeedRepository();
    final report = Completer<void>();
    repository.reportCompleter = report;
    await _pump(tester, repository);

    await tester.tap(find.bySemanticsLabel('Post options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pump();
    expect(find.text('Friend Runner 0'), findsOneWidget);
    expect(repository.reportCalls, 1);

    report.complete();
    await tester.pumpAndSettle();
    expect(find.text('Friend Runner 0'), findsNothing);
  });

  testWidgets('like count changes on the first frame before remote success', (
    tester,
  ) async {
    final repository = ScreenFeedRepository()
      ..likeCompleter = Completer<void>();
    await _pump(tester, repository);

    await tester.tap(find.byKey(const ValueKey('feed-like-action-post-0')));
    await tester.pump();

    expect(find.text('1 like'), findsOneWidget);
    expect(repository.likeCalls, 1);

    repository.likeCompleter!.complete();
    await tester.pumpAndSettle();
    expect(find.text('1 like'), findsOneWidget);
  });

  testWidgets('load-more preserves scroll offset while server state updates', (
    tester,
  ) async {
    final repository = ScreenFeedRepository(postCount: 28);
    await _pump(tester, repository);
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('feed-post-list')),
    );
    final controller = list.controller!;

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final offset = controller.offset;
    expect(repository.loadMoreCalls, greaterThan(0));

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(controller.offset, offset);
  });

  testWidgets('delayed thumbnail completion after disposal is ignored', (
    tester,
  ) async {
    final repository = ScreenFeedRepository();
    final thumbnail = Completer<Uint8List>();
    repository.thumbnailCompleter = thumbnail;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrentSessionFeed(
            repository: repository,
            viewerContext: const FeedViewerContext(
              currentUserId: 'viewer',
              acceptedFriendUserIds: <String>{'friend'},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(repository.thumbnailReads, 1);

    await tester.pumpWidget(const SizedBox());
    thumbnail.complete(Uint8List(8));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh retries a thumbnail after a failed read', (
    tester,
  ) async {
    final repository = ScreenFeedRepository();
    await _pump(tester, repository);
    expect(repository.thumbnailReads, 1);

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();

    expect(repository.thumbnailReads, 2);
  });

  test('liking a post preserves its loaded thumbnail bytes', () async {
    final repository = ScreenFeedRepository()
      ..thumbnailBytes = Uint8List.fromList(const <int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]);
    final controller = FeedTimelineScreenController(
      repository,
      const FeedViewerContext(
        currentUserId: 'viewer',
        acceptedFriendUserIds: <String>{'friend'},
      ),
    );
    await controller.refresh();
    await Future<void>.delayed(Duration.zero);
    final loadedBytes = controller.posts.single.routeThumbnail.pngBytes;
    expect(loadedBytes, isNotNull);

    await controller.toggleLike('post-0');

    expect(controller.posts.single.routeThumbnail.pngBytes, same(loadedBytes));
    controller.dispose();
  });

  test('like count updates before the remote write completes', () async {
    final repository = ScreenFeedRepository()
      ..likeCompleter = Completer<void>();
    final controller = FeedTimelineScreenController(
      repository,
      const FeedViewerContext(
        currentUserId: 'viewer',
        acceptedFriendUserIds: <String>{'friend'},
      ),
    );
    await controller.refresh();

    final mutation = controller.toggleLike('post-0');

    expect(controller.posts.single.isLikedByViewer, isTrue);
    expect(controller.posts.single.likeCount, 1);
    repository.likeCompleter!.complete();
    await mutation;
    expect(controller.posts.single.likeCount, 1);
    controller.dispose();
  });

  test('failed optimistic like restores the previous state', () async {
    final repository = ScreenFeedRepository()
      ..likeCompleter = Completer<void>();
    final controller = FeedTimelineScreenController(
      repository,
      const FeedViewerContext(
        currentUserId: 'viewer',
        acceptedFriendUserIds: <String>{'friend'},
      ),
    );
    await controller.refresh();

    final mutation = controller.toggleLike('post-0');
    expect(controller.posts.single.likeCount, 1);
    repository.likeCompleter!.completeError(StateError('write failed'));
    await mutation;

    expect(controller.posts.single.isLikedByViewer, isFalse);
    expect(controller.posts.single.likeCount, 0);
    controller.dispose();
  });

  test('pending optimistic like survives a stale refresh completion', () async {
    final repository = ScreenFeedRepository()
      ..likeCompleter = Completer<void>();
    final controller = FeedTimelineScreenController(
      repository,
      const FeedViewerContext(
        currentUserId: 'viewer',
        acceptedFriendUserIds: <String>{'friend'},
      ),
    );
    await controller.refresh();
    repository.refreshCompleter = Completer<FeedTimelineState>();

    final refresh = controller.refresh();
    final mutation = controller.toggleLike('post-0');
    repository.refreshCompleter!.complete(repository.currentState);
    await refresh;

    expect(controller.posts.single.isLikedByViewer, isTrue);
    expect(controller.posts.single.likeCount, 1);
    repository.likeCompleter!.complete();
    await mutation;
    controller.dispose();
  });

  test(
    'like rollback preserves a thumbnail that loaded while pending',
    () async {
      final repository = ScreenFeedRepository()
        ..thumbnailCompleter = Completer<Uint8List>()
        ..likeCompleter = Completer<void>();
      final controller = FeedTimelineScreenController(
        repository,
        const FeedViewerContext(
          currentUserId: 'viewer',
          acceptedFriendUserIds: <String>{'friend'},
        ),
      );
      await controller.refresh();

      final mutation = controller.toggleLike('post-0');
      final bytes = Uint8List.fromList(const <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      repository.thumbnailCompleter!.complete(bytes);
      await Future<void>.delayed(Duration.zero);
      repository.likeCompleter!.completeError(StateError('write failed'));
      await mutation;

      expect(controller.posts.single.routeThumbnail.pngBytes, same(bytes));
      expect(controller.posts.single.likeCount, 0);
      controller.dispose();
    },
  );

  test('rapid duplicate like sends only one pending write', () async {
    final repository = ScreenFeedRepository()
      ..likeCompleter = Completer<void>();
    final controller = FeedTimelineScreenController(
      repository,
      const FeedViewerContext(
        currentUserId: 'viewer',
        acceptedFriendUserIds: <String>{'friend'},
      ),
    );
    await controller.refresh();

    final first = controller.toggleLike('post-0');
    await controller.toggleLike('post-0');

    expect(repository.likeCalls, 1);
    expect(controller.posts.single.likeCount, 1);
    repository.likeCompleter!.complete();
    await first;
    controller.dispose();
  });

  test('session thumbnail cache survives Feed controller recreation', () async {
    final bytes = Uint8List.fromList(const <int>[1, 2, 3, 4, 5, 6, 7, 8]);
    final store = CurrentSessionFeedStore(ownerUid: 'viewer')
      ..cachePublishedThumbnail('post-0', bytes);
    final repository = ScreenFeedRepository();

    for (var visit = 0; visit < 2; visit++) {
      final controller = FeedTimelineScreenController(
        repository,
        const FeedViewerContext(
          currentUserId: 'viewer',
          acceptedFriendUserIds: <String>{'friend'},
        ),
      )..attachSession(store);
      await controller.refresh();
      expect(controller.posts.single.routeThumbnail.pngBytes, same(bytes));
      controller.dispose();
    }

    expect(repository.thumbnailReads, 0);
    store.dispose();
  });

  test('session thumbnail cache is bounded and clears when owner changes', () {
    final bytes = Uint8List.fromList(const <int>[1, 2, 3, 4, 5, 6, 7, 8]);
    final store = CurrentSessionFeedStore(ownerUid: 'viewer');
    for (var index = 0; index < 21; index++) {
      store.cachePublishedThumbnail('post-$index', bytes);
    }

    expect(store.thumbnailFor('post-0'), isNull);
    expect(store.thumbnailFor('post-20'), same(bytes));

    store.syncOwner('other-viewer');
    expect(store.thumbnailFor('post-20'), isNull);
    store.dispose();
  });

  for (final operation in _DelayedOperation.values) {
    testWidgets(
      '${operation.name} ignores delayed completion after controller disposal',
      (tester) => _expectDisposedOperationIgnored(tester, operation),
    );
  }
}

Future<void> _expectDisposedOperationIgnored(
  WidgetTester tester,
  _DelayedOperation operation,
) async {
  final repository = ScreenFeedRepository();
  final controller = FeedTimelineScreenController(
    repository,
    const FeedViewerContext(
      currentUserId: 'viewer',
      acceptedFriendUserIds: <String>{'friend'},
    ),
  );
  await controller.refresh();
  final beforePosts = controller.posts.map((post) => post.postId).toList();
  final beforeState = controller.timelineState;
  var notifications = 0;
  controller.addListener(() => notifications++);

  final pending = _startDelayedOperation(operation, controller, repository);
  controller.dispose();
  _completeDelayedOperation(operation, repository);
  await pending;
  await tester.pump();

  expect(controller.posts.map((post) => post.postId), beforePosts);
  expect(controller.timelineState, same(beforeState));
  expect(
    notifications,
    operation == _DelayedOperation.toggleLike ? 1 : 0,
    reason: operation.name,
  );
  expect(tester.takeException(), isNull, reason: operation.name);
}

Future<void> _pump(WidgetTester tester, ScreenFeedRepository repository) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CurrentSessionFeed(
          repository: repository,
          viewerContext: const FeedViewerContext(
            currentUserId: 'viewer',
            acceptedFriendUserIds: <String>{'friend'},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _isEnabled(WidgetTester tester, String key) =>
    tester.widget<Semantics>(find.byKey(ValueKey(key))).properties.enabled ==
    true;

enum _DelayedOperation { loadMore, toggleLike, deletePost, reportPost }

Future<void> _startDelayedOperation(
  _DelayedOperation operation,
  FeedTimelineScreenController controller,
  ScreenFeedRepository repository,
) async {
  switch (operation) {
    case _DelayedOperation.loadMore:
      repository.loadMoreCompleter = Completer<FeedTimelineState>();
      await controller.loadMore();
    case _DelayedOperation.toggleLike:
      repository.likeCompleter = Completer<void>();
      await controller.toggleLike('post-0');
    case _DelayedOperation.deletePost:
      repository.deleteCompleter = Completer<void>();
      await controller.deletePost('post-0');
    case _DelayedOperation.reportPost:
      repository.reportCompleter = Completer<void>();
      await controller.reportPost('post-0');
  }
}

void _completeDelayedOperation(
  _DelayedOperation operation,
  ScreenFeedRepository repository,
) {
  switch (operation) {
    case _DelayedOperation.loadMore:
      repository.addPost();
      repository.loadMoreCompleter!.complete(repository.currentState);
    case _DelayedOperation.toggleLike:
      repository.likeCompleter!.complete();
    case _DelayedOperation.deletePost:
      repository.deleteCompleter!.complete();
    case _DelayedOperation.reportPost:
      repository.reportCompleter!.complete();
  }
}
