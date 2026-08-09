import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/feed/presentation/current_session_feed.dart';
import 'package:runiac_app/features/run/presentation/data/run_completion_demo_snapshots.dart';

void main() {
  Future<void> pumpFeed(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CurrentSessionFeed())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Feed likes toggle the visible count idempotently', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester);

    await tester.tap(find.bySemanticsLabel('Like 4 likes'));
    await tester.pump();

    expect(find.bySemanticsLabel('Like 5 likes'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Like 5 likes'));
    await tester.pump();

    expect(find.bySemanticsLabel('Like 4 likes'), findsOneWidget);
  });

  testWidgets(
    'Feed comment sheet rejects empty submissions and adds one comment',
    (WidgetTester tester) async {
      await pumpFeed(tester);

      await tester.tap(find.bySemanticsLabel('Comment 1 comment'));
      await tester.pumpAndSettle();

      expect(find.text('Comments'), findsOneWidget);

      final submit = find.byKey(
        const ValueKey('feed-comment-submit-feed-current-001'),
      );
      expect(
        tester.widget<IconButton>(submit).onPressed,
        isNull,
        reason: 'Empty comments must not submit.',
      );

      await tester.enterText(
        find.byKey(const ValueKey('feed-comment-input-feed-current-001')),
        'Nice work!',
      );
      await tester.pump();
      expect(tester.widget<IconButton>(submit).onPressed, isNotNull);

      await tester.tap(submit);
      await tester.pumpAndSettle();

      final commentAction = tester.widget<Semantics>(
        find.byKey(const ValueKey('feed-comment-action-feed-current-001')),
      );
      expect(commentAction.properties.label, 'Comment 2 comments');
      expect(find.text('Nice work!'), findsOneWidget);
      expect(
        tester.widget<IconButton>(submit).onPressed,
        isNull,
        reason: 'The cleared field prevents a duplicate submission.',
      );
    },
  );

  testWidgets('pull-to-refresh clears comments overlay for refreshed posts', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester);

    await tester.tap(find.bySemanticsLabel('Comment 1 comment'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('feed-comment-input-feed-current-001')),
      'Refresh should clear this.',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('feed-comment-submit-feed-current-001')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Refresh should clear this.'), findsOneWidget);
    Navigator.of(tester.element(find.text('Comments'))).pop();
    await tester.pumpAndSettle();

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();

    final commentAction = tester.widget<Semantics>(
      find.byKey(const ValueKey('feed-comment-action-feed-current-001')),
    );
    expect(commentAction.properties.label, 'Comment 1 comment');

    await tester.tap(find.bySemanticsLabel('Comment 1 comment'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh should clear this.'), findsNothing);
  });

  testWidgets(
    'shared session Feed posts can be liked, commented, and deleted',
    (WidgetTester tester) async {
      final feedStore = CurrentSessionFeedStore(ownerUid: 'runner-current');
      addTearDown(feedStore.dispose);
      feedStore.shareRunSummary(defaultRunSummarySnapshot);

      await tester.pumpWidget(
        CurrentSessionFeedScope(
          store: feedStore,
          child: const MaterialApp(home: Scaffold(body: CurrentSessionFeed())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saturday Morning Run'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Like 0 likes'));
      await tester.pump();
      expect(find.bySemanticsLabel('Like 1 like'), findsOneWidget);
      expect(feedStore.sessionPosts.single.likeCount, 1);

      await tester.tap(find.bySemanticsLabel('Comment No comments'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('feed-comment-input-feed-session-1')),
        'Shared route looks good.',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('feed-comment-submit-feed-session-1')),
      );
      await tester.pumpAndSettle();
      expect(feedStore.sessionPosts.single.commentCount, 1);
      expect(find.text('Shared route looks good.'), findsOneWidget);

      Navigator.of(tester.element(find.text('Comments'))).pop();
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('feed-post-divider-feed-session-1')),
      );
      await tester.tap(find.bySemanticsLabel('Post options').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(feedStore.sessionPosts, isEmpty);
      expect(find.text('Saturday Morning Run'), findsNothing);
    },
  );

  testWidgets('session comments clear when the Feed owner resets', (
    WidgetTester tester,
  ) async {
    final feedStore = CurrentSessionFeedStore(ownerUid: 'runner-a');
    addTearDown(feedStore.dispose);
    feedStore.shareRunSummary(defaultRunSummarySnapshot);

    await tester.pumpWidget(
      CurrentSessionFeedScope(
        store: feedStore,
        child: const MaterialApp(home: Scaffold(body: CurrentSessionFeed())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Comment No comments'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('feed-comment-input-feed-session-1')),
      'First user comment',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('feed-comment-submit-feed-session-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('First user comment'), findsOneWidget);

    feedStore.syncOwner('runner-b');
    feedStore.shareRunSummary(defaultRunSummarySnapshot);
    await tester.pumpAndSettle();

    expect(find.text('Comments'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Comment No comments'));
    await tester.pumpAndSettle();

    expect(find.text('No new comments yet.'), findsOneWidget);
    expect(find.text('First user comment'), findsNothing);
  });

  testWidgets('stale comment submit after owner reset is ignored', (
    WidgetTester tester,
  ) async {
    final feedStore = CurrentSessionFeedStore(ownerUid: 'runner-a');
    addTearDown(feedStore.dispose);
    feedStore.shareRunSummary(defaultRunSummarySnapshot);

    await tester.pumpWidget(
      CurrentSessionFeedScope(
        store: feedStore,
        child: const MaterialApp(home: Scaffold(body: CurrentSessionFeed())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Comment No comments'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('feed-comment-input-feed-session-1')),
      'Late stale comment',
    );
    await tester.pump();
    final staleSubmit = tester
        .widget<IconButton>(
          find.byKey(const ValueKey('feed-comment-submit-feed-session-1')),
        )
        .onPressed;
    expect(staleSubmit, isNotNull);

    feedStore.syncOwner('runner-b');
    feedStore.shareRunSummary(defaultRunSummarySnapshot);
    await tester.pumpAndSettle();

    staleSubmit!();
    await tester.pumpAndSettle();

    expect(feedStore.sessionPosts.single.commentCount, 0);
    await tester.tap(find.bySemanticsLabel('Comment No comments'));
    await tester.pumpAndSettle();
    expect(find.text('Late stale comment'), findsNothing);
    expect(find.text('No new comments yet.'), findsOneWidget);
  });
}
