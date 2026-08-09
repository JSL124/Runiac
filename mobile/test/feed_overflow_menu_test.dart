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

  testWidgets('Author options use a bottom sheet and can delete the post', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester);

    await tester.tap(find.bySemanticsLabel('Post options').first);
    await tester.pumpAndSettle();

    expect(find.text('Post options'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
    expect(find.byType(PopupMenuButton<void>), findsNothing);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('feed-post-divider-feed-current-001')),
      findsNothing,
    );
    expect(find.text('Runiac Runner'), findsNothing);
  });

  testWidgets('Friend options report without deleting the post', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester);

    await tester.tap(find.bySemanticsLabel('Post options').at(1));
    await tester.pumpAndSettle();

    expect(find.text('Post options'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.text('Report submitted'), findsOneWidget);
    expect(find.text('Jamie Tan'), findsOneWidget);
  });

  test('Feed interaction store mutates local display posts only', () {
    final store = CurrentSessionFeedStore(ownerUid: 'runner-current');
    addTearDown(store.dispose);
    store.shareRunSummary(defaultRunSummarySnapshot);

    expect(store.toggleLike('feed-session-1'), isTrue);
    expect(store.sessionPosts.single.likeCount, 1);
    expect(store.addComment('feed-session-1'), isTrue);
    expect(store.sessionPosts.single.commentCount, 1);
    expect(store.removePost('feed-session-1'), isTrue);
    expect(store.sessionPosts, isEmpty);
  });
}
