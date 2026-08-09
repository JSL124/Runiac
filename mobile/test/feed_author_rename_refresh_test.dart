import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_test_data_port.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/firebase_feed_repository.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/feed/presentation/current_session_feed.dart';

/// A post stores its author's name frozen at publish time, so a runner who
/// renames themselves only sees the new name once the Feed re-reads the
/// timeline and re-resolves the author overlay. These cover the trigger for
/// that re-read; the overlay itself is covered in
/// `feed_author_level_overlay_test.dart`.
void main() {
  const viewer = FeedViewerContext(
    currentUserId: 'viewer',
    acceptedFriendUserIds: <String>{},
  );

  const before = FeedAuthorProfileSnapshot(
    userId: 'viewer',
    displayName: 'Old Name',
    avatarInitials: 'ON',
    levelLabel: 'Level 3',
    levelProgressFraction: 0.3,
  );

  Future<void> pumpWithProfile(
    WidgetTester tester,
    FeedTestDataPort port,
    ValueNotifier<FeedAuthorProfileSnapshot> profile,
  ) async {
    // One repository instance for the whole harness: rebuilding it would
    // replace the controller and reload for reasons unrelated to a rename.
    final repository = FirebaseFeedRepository(port: port);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<FeedAuthorProfileSnapshot>(
            valueListenable: profile,
            builder: (context, value, child) => CurrentSessionFeed(
              repository: repository,
              viewerContext: viewer,
              currentAuthorProfile: value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a renamed viewer re-reads the timeline', (
    WidgetTester tester,
  ) async {
    final port = FeedTestDataPort.withSingleFriend('friend-01');
    final profile = ValueNotifier<FeedAuthorProfileSnapshot>(before);
    addTearDown(profile.dispose);
    await pumpWithProfile(tester, port, profile);
    final loadsBeforeRename = port.authorLevelQueries.length;

    profile.value = const FeedAuthorProfileSnapshot(
      userId: 'viewer',
      displayName: 'New Name',
      avatarInitials: 'NN',
      levelLabel: 'Level 3',
      levelProgressFraction: 0.3,
    );
    await tester.pumpAndSettle();

    expect(port.authorLevelQueries.length, greaterThan(loadsBeforeRename));
  });

  testWidgets('a level change alone does not pay for a reload', (
    WidgetTester tester,
  ) async {
    final port = FeedTestDataPort.withSingleFriend('friend-02');
    final profile = ValueNotifier<FeedAuthorProfileSnapshot>(before);
    addTearDown(profile.dispose);
    await pumpWithProfile(tester, port, profile);
    final loadsBeforeLevelUp = port.authorLevelQueries.length;

    profile.value = const FeedAuthorProfileSnapshot(
      userId: 'viewer',
      displayName: 'Old Name',
      avatarInitials: 'ON',
      levelLabel: 'Level 4',
      levelProgressFraction: 0.1,
    );
    await tester.pumpAndSettle();

    expect(port.authorLevelQueries.length, loadsBeforeLevelUp);
  });
}
