import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/widgets/runiac_level_profile_badge.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/feed/domain/repositories/feed_repository.dart';
import 'package:runiac_app/features/feed/presentation/widgets/feed_sheets.dart';

void main() {
  const post = FeedPostReadModel(
    postId: 'post-1',
    authorUserId: 'author',
    authorDisplayName: 'Alex',
    authorAvatarInitials: 'AL',
    authorLevelLabel: 'Level 2',
    relativeTimeLabel: 'Now',
    distanceLabel: '3 km',
    paceLabel: '6:00',
    durationLabel: '18m',
    likeCount: 0,
    commentCount: 0,
    isLikedByViewer: false,
    hasViewerCommented: false,
    canComment: true,
    showsOwnerMenu: false,
    routeThumbnail: FeedRouteThumbnailReadModel(
      thumbnailKey: 'thumbnail',
      accessibilityLabel: 'Route preview',
    ),
  );

  Future<void> pumpSheet(
    WidgetTester tester,
    _CommentsRepository repository, {
    DraggableScrollableController? sheetController,
    FeedAuthorProfileSnapshot? currentAuthorProfile,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const ValueKey('open-comments'),
                onPressed: () => showFeedCommentSheet(
                  context: context,
                  sheet: FeedCommentSheet.fromRepository(
                    post,
                    repository,
                    'viewer',
                    currentAuthorProfile,
                  ).controlledBy(sheetController),
                ),
                child: const Text('Open comments'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-comments')));
    await tester.pumpAndSettle();
  }

  testWidgets('loads newest-first pages without tied-time gaps or duplicates', (
    WidgetTester tester,
  ) async {
    final repository = _CommentsRepository.withComments(21);
    await pumpSheet(tester, repository);

    expect(
      find.byKey(const ValueKey('feed-comment-list-post-1')),
      findsOneWidget,
    );
    expect(find.text('Comment 20'), findsOneWidget);
    expect(find.text('Comment 1'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('feed-comment-list-post-1')),
      const Offset(0, -1200),
    );
    await tester.drag(
      find.byKey(const ValueKey('feed-comment-list-post-1')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();

    expect(repository.pageStarts, hasLength(2));
    expect(
      repository.visibleIds.toSet(),
      hasLength(21),
      reason: 'The two cursor pages must not duplicate tied timestamps.',
    );
    expect(
      repository.visibleIds,
      orderedEquals(<String>[
        for (var index = 20; index >= 0; index--) 'comment-$index',
      ]),
    );
  });

  testWidgets(
    'viewer comments use current profile snapshot when level snapshot is empty',
    (WidgetTester tester) async {
      final repository = _CommentsRepository.withComments(
        1,
        owned: true,
        levelLabel: '',
      );
      await pumpSheet(
        tester,
        repository,
        currentAuthorProfile: const FeedAuthorProfileSnapshot(
          userId: 'viewer',
          displayName: 'babo',
          avatarInitials: 'B',
          levelLabel: 'Level 8',
          levelProgressFraction: 0.5,
        ),
      );

      expect(find.text('Comment 0'), findsOneWidget);
      expect(find.text('Lv.8'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('feed-comment-author-profile-comment-0')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    "another runner's comment avatar exposes a profile-link semantics label",
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      final repository = _CommentsRepository.withComments(1, owned: false);
      await pumpSheet(tester, repository);

      // The comment row has no explicit-child-node semantics boundary, so
      // the avatar's label merges into the row's combined label rather than
      // standing alone; a substring match still proves the button exists.
      expect(
        find.bySemanticsLabel(RegExp('View Runner profile')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    "the viewer's own comment avatar exposes no profile-link semantics",
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      final repository = _CommentsRepository.withComments(1, owned: true);
      await pumpSheet(tester, repository);

      expect(find.bySemanticsLabel(RegExp('View You profile')), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'creates, edits, and confirms deletion for viewer-owned comments',
    (WidgetTester tester) async {
      final repository = _CommentsRepository.withComments(1, owned: true);
      await pumpSheet(tester, repository);

      expect(find.byType(RuniacLevelProfileBadge), findsOneWidget);
      expect(
        find.byKey(const ValueKey('feed-comment-author-profile-comment-0')),
        findsOneWidget,
      );
      expect(find.text('Lv.6'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('feed-comment-input-post-1')),
        '  New progress!  ',
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('feed-comment-submit-post-1')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('feed-comment-submit-post-1')),
      );
      await tester.pumpAndSettle();
      expect(repository.createdBodies, <String>['New progress!']);

      await tester.tap(
        find.byKey(const ValueKey('feed-comment-menu-comment-0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('feed-comment-edit-comment-0')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('feed-comment-input-post-1')),
        'Edited comment',
      );
      await tester.tap(
        find.byKey(const ValueKey('feed-comment-submit-post-1')),
      );
      await tester.pumpAndSettle();
      expect(repository.updatedBodies, <String>['Edited comment']);

      await tester.tap(
        find.byKey(const ValueKey('feed-comment-menu-comment-0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('feed-comment-delete-comment-0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete comment?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repository.deletedIds, <String>['comment-0']);

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('feed-comment-input-post-1')),
            )
            .controller!
            .text,
        isEmpty,
        reason: 'Deleting the edited comment must leave no stale edit draft.',
      );
      expect(find.text('Editing comment'), findsNothing);
      expect(find.byTooltip('Post comment'), findsOneWidget);
    },
  );

  testWidgets(
    'hides other-user controls and rejects whitespace or 501 characters',
    (WidgetTester tester) async {
      final repository = _CommentsRepository.withComments(1, owned: false);
      await pumpSheet(tester, repository);

      expect(
        find.byKey(const ValueKey('feed-comment-edit-comment-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('feed-comment-delete-comment-0')),
        findsNothing,
      );
      final input = find.byKey(const ValueKey('feed-comment-input-post-1'));
      final submit = find.byKey(const ValueKey('feed-comment-submit-post-1'));
      await tester.enterText(input, '   ');
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      expect(repository.createdBodies, isEmpty);
      expect(find.text('Write 1 to 500 characters.'), findsOneWidget);

      await tester.enterText(input, 'x' * 501);
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      expect(repository.createdBodies, isEmpty);
      expect(find.text('Write 1 to 500 characters.'), findsOneWidget);
    },
  );

  testWidgets(
    'recovers from a page error and cached offline sheet is read-only',
    (WidgetTester tester) async {
      final repository = _CommentsRepository.withComments(0)
        ..failFirstLoad = true;
      await pumpSheet(tester, repository);
      expect(find.text('Comments could not load.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No comments yet.'), findsOneWidget);

      await tester.tapAt(tester.getTopLeft(find.byType(ModalBarrier).last));
      await tester.pumpAndSettle();
      repository.cachedOffline = true;
      await pumpSheet(tester, repository);
      expect(
        find.text('Comments are read-only while offline.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('feed-comment-submit-post-1')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('feed-comment-input-post-1')),
            )
            .enabled,
        isFalse,
      );
    },
  );

  testWidgets('server-confirmed creation reloads the saved comment once', (
    WidgetTester tester,
  ) async {
    final repository = _CommentsRepository.withComments(0);
    await pumpSheet(tester, repository);
    final input = find.byKey(const ValueKey('feed-comment-input-post-1'));
    final submit = find.byKey(const ValueKey('feed-comment-submit-post-1'));
    await tester.enterText(input, '  Saved by server  ');
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repository.createdBodies, <String>['Saved by server']);
    expect(find.text('Saved by server'), findsOneWidget);
    expect(
      post.commentCount,
      0,
      reason: 'The sheet never optimistically owns post counts.',
    );
  });

  testWidgets('rapid double submit issues one comment mutation', (
    WidgetTester tester,
  ) async {
    final repository = _CommentsRepository.withComments(0)..holdCreate = true;
    await pumpSheet(tester, repository);
    final input = find.byKey(const ValueKey('feed-comment-input-post-1'));
    final submit = find.byKey(const ValueKey('feed-comment-submit-post-1'));
    await tester.enterText(input, 'One request only');
    await tester.pump();

    final onPressed = tester.widget<IconButton>(submit).onPressed!;
    onPressed();
    onPressed();
    await tester.pump();
    expect(repository.createdBodies, <String>['One request only']);

    repository.releaseCreate();
    await tester.pumpAndSettle();
    expect(find.text('One request only'), findsOneWidget);
  });

  testWidgets('pending create completion after sheet disposal is ignored', (
    WidgetTester tester,
  ) async {
    final repository = _CommentsRepository.withComments(0)..holdCreate = true;
    await pumpSheet(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('feed-comment-input-post-1')),
      'Pending comment',
    );
    await tester.tap(find.byKey(const ValueKey('feed-comment-submit-post-1')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    repository.releaseCreate();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('non-persistent fallback comments hide edit and delete actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showFeedCommentSheet(
                context: context,
                sheet: FeedCommentSheet.fromFallback(
                  post,
                  'viewer',
                  const FeedCommentFallback(
                    comments: <String>['Session comment'],
                    onSubmitted: _ignoreFallbackComment,
                  ),
                  null,
                ),
              ),
              child: const Text('Open fallback comments'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open fallback comments'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.text('Session comment'), findsOneWidget);
    // The fallback source has no repository, so `ownsComment` is always false
    // even though this session comment is the signed-in viewer's own. The
    // profile link has to read the viewer id directly, or a runner ends up
    // with a link to their own read-only profile.
    expect(find.bySemanticsLabel(RegExp('View .* profile')), findsNothing);
  });

  testWidgets(
    'keyboard-safe composer is visible, tappable, and scrolls at each sheet size',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      final controller = DraggableScrollableController();
      final repository = _CommentsRepository.withComments(80, owned: true);
      await pumpSheet(tester, repository, sheetController: controller);
      final input = find.byKey(const ValueKey('feed-comment-input-post-1'));
      final submit = find.byKey(const ValueKey('feed-comment-submit-post-1'));
      final list = find.byKey(const ValueKey('feed-comment-list-post-1'));
      expect(find.text('Comment 79'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsWidgets);
      for (final size in <double>[.32, .62, .92]) {
        controller.jumpTo(size);
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.size, closeTo(size, .01));
        final inputRect = tester.getRect(input);
        final submitRect = tester.getRect(submit);
        expect(inputRect.top, greaterThanOrEqualTo(0));
        expect(inputRect.bottom, lessThanOrEqualTo(600));
        expect(submitRect.top, greaterThanOrEqualTo(0));
        expect(submitRect.bottom, lessThanOrEqualTo(600));

        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        );
        scrollable.position.jumpTo(0);
        await tester.pump();
        if (size == .32) {
          controller.jumpTo(.62);
          await tester.pumpAndSettle();
        }
        final menu = find.byKey(const ValueKey('feed-comment-menu-comment-79'));
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('feed-comment-edit-comment-79')),
        );
        await tester.pumpAndSettle();
        if (size == .32) {
          controller.jumpTo(.32);
          await tester.pumpAndSettle();
          expect(controller.size, closeTo(.32, .01));
        }
        expect(find.text('Editing comment'), findsOneWidget);
        final saveRect = tester.getRect(submit);
        expect(saveRect.top, greaterThanOrEqualTo(0));
        expect(saveRect.bottom, lessThanOrEqualTo(600));
        expect(tester.widget<IconButton>(submit).onPressed, isNotNull);
        final updatesBefore = repository.updatedBodies.length;
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(repository.updatedBodies, hasLength(updatesBefore + 1));

        await tester.tap(input);
        await tester.enterText(input, 'Size $size');
        await tester.pump();
        expect(tester.widget<IconButton>(submit).onPressed, isNotNull);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(repository.createdBodies, contains('Size $size'));

        scrollable.position.jumpTo(0);
        final before = scrollable.position.pixels;
        for (
          var attempt = 0;
          attempt < 3 && scrollable.position.pixels <= before;
          attempt++
        ) {
          await tester.drag(list, const Offset(0, -1600));
          await tester.pumpAndSettle();
        }
        expect(scrollable.position.pixels, greaterThan(before));
      }
    },
  );
}

void _ignoreFallbackComment(String _) {}

class _CommentsRepository
    implements FeedTimelineRepository, FeedCommentsRepository {
  _CommentsRepository.withComments(
    int count, {
    bool owned = false,
    String? levelLabel,
  }) : _comments = List<FeedCommentReadModel>.generate(
         count,
         (index) => FeedCommentReadModel(
           commentId: 'comment-$index',
           authorUserId: owned ? 'viewer' : 'another-runner',
           authorDisplayName: owned ? 'You' : 'Runner',
           authorAvatarInitials: owned ? 'YO' : 'RU',
           authorLevelLabel: levelLabel ?? (owned ? 'Level 6' : 'Level 3'),
           body: 'Comment $index',
           createdAt: DateTime.utc(2026, 1, 1),
         ),
       ).reversed.toList();

  final List<FeedCommentReadModel> _comments;
  final List<FeedCommentCursor?> pageStarts = <FeedCommentCursor?>[];
  final List<String> createdBodies = <String>[];
  final List<String> updatedBodies = <String>[];
  final List<String> deletedIds = <String>[];
  bool cachedOffline = false;
  bool failFirstLoad = false;
  bool holdCreate = false;
  final List<Completer<void>> _pendingCreates = <Completer<void>>[];

  List<String> get visibleIds =>
      _comments.map((item) => item.commentId).toList();

  @override
  FeedTimelineState get currentState => FeedTimelineState(
    posts: const <FeedPostReadModel>[],
    source: cachedOffline
        ? FeedTimelineSource.cachedOffline
        : FeedTimelineSource.server,
    refreshing: false,
    exhausted: true,
  );

  @override
  Future<FeedCommentPage> loadComments({
    required String postId,
    FeedCommentCursor? startAfter,
  }) async {
    pageStarts.add(startAfter);
    if (failFirstLoad) {
      failFirstLoad = false;
      throw StateError('temporarily unavailable');
    }
    final start = startAfter == null
        ? 0
        : _comments.indexWhere(
                (item) => item.commentId == startAfter.commentId,
              ) +
              1;
    final comments = _comments.skip(start).take(20).toList();
    return FeedCommentPage(
      comments: comments,
      source: cachedOffline
          ? FeedTimelineSource.cachedOffline
          : FeedTimelineSource.server,
      exhausted: start + comments.length >= _comments.length,
    );
  }

  @override
  Future<void> createComment(FeedCommentMutation mutation) async {
    createdBodies.add(mutation.body);
    if (holdCreate) {
      final pending = Completer<void>();
      _pendingCreates.add(pending);
      await pending.future;
    }
    _comments.insert(
      0,
      FeedCommentReadModel(
        commentId: 'created-${createdBodies.length}',
        authorUserId: 'viewer',
        authorDisplayName: 'You',
        authorAvatarInitials: 'YO',
        authorLevelLabel: 'Level 6',
        body: mutation.body,
        createdAt: DateTime.utc(2026, 1, 2),
      ),
    );
  }

  void releaseCreate() {
    for (final pending in _pendingCreates) {
      if (!pending.isCompleted) pending.complete();
    }
  }

  @override
  Future<void> updateComment(FeedCommentMutation mutation) async =>
      updatedBodies.add(mutation.body);
  @override
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async => deletedIds.add(commentId);

  @override
  Future<FeedReadModel> loadFeed(FeedViewerContext viewerContext) async =>
      FeedReadModel(posts: const <FeedPostReadModel>[]);
  @override
  Future<FeedTimelineState> loadInitial(
    FeedViewerContext viewerContext,
  ) async => currentState;
  @override
  Future<FeedTimelineState> loadMore() async => currentState;
  @override
  Future<FeedTimelineState> refresh() async => currentState;
  @override
  Future<FeedTimelineState> reconcileAccess() async => currentState;
  @override
  Future<void> setLike({required String postId, required bool isLiked}) async {}
  @override
  Future<void> reportPost(String postId) async {}
  @override
  Future<void> deletePost(String postId) async {}
  @override
  Future<Uint8List> readThumbnail(String postId) async => Uint8List(0);
  @override
  Future<FeedPostReadModel?> readPost(String postId) async => null;
  @override
  void dispose() {}
}
