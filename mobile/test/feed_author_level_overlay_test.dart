import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_data_port.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_test_data_port.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/firebase_feed_repository.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';

void main() {
  const viewer = FeedViewerContext(
    currentUserId: 'viewer',
    acceptedFriendUserIds: <String>{},
  );

  test(
    'a resolved live author level overrides a post\'s stored label and progress',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-01');
      port.authorLevels['friend-01'] = const FeedAuthorLevel(
        levelLabel: 'Level 12',
        levelProgressFraction: 0.75,
      );
      final repository = FirebaseFeedRepository(port: port);

      final state = await repository.loadInitial(viewer);

      final post = state.posts.singleWhere(
        (post) => post.authorUserId == 'friend-01',
      );
      expect(post.authorLevelLabel, 'Level 12');
      expect(post.authorLevelProgressFraction, 0.75);
      expect(port.authorLevelQueries, hasLength(1));
    },
  );

  test(
    'an author the resolver has nothing for leaves the stored label intact '
    'and the progress fraction unresolved',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-02');
      final repository = FirebaseFeedRepository(port: port);

      final state = await repository.loadInitial(viewer);

      final post = state.posts.single;
      expect(post.authorLevelLabel, 'Level 3');
      expect(post.authorLevelProgressFraction, isNull);
    },
  );

  test(
    'a port failure leaves the stored label intact and never throws out of '
    'the loader, and leaves the progress fraction unresolved',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-03');
      port.authorLevels['friend-03'] = const FeedAuthorLevel(
        levelLabel: 'Level 99',
        levelProgressFraction: 0.99,
      );
      port.authorLevelsError = Exception('offline');
      final repository = FirebaseFeedRepository(port: port);

      final state = await repository.loadInitial(viewer);

      expect(state.recoverableError, isNull);
      final post = state.posts.single;
      expect(post.authorLevelLabel, 'Level 3');
      expect(post.authorLevelProgressFraction, isNull);
    },
  );

  test(
    'a resolved empty levelLabel leaves the stored label intact and the '
    'progress fraction unresolved',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-07');
      port.authorLevels['friend-07'] = const FeedAuthorLevel(
        levelLabel: '',
        levelProgressFraction: 0.42,
      );
      final repository = FirebaseFeedRepository(port: port);

      final state = await repository.loadInitial(viewer);

      final post = state.posts.single;
      expect(post.authorLevelLabel, 'Level 3');
      expect(post.authorLevelProgressFraction, isNull);
    },
  );

  // A post freezes authorDisplayName at publish time and feedPosts is closed
  // to client writes, so without this overlay a runner who renames themselves
  // keeps appearing under the old name on every run they already shared.
  test(
    'a renamed author\'s current name and initials replace the stored ones',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-10');
      port.authorLevels['friend-10'] = const FeedAuthorLevel(
        levelLabel: 'Level 12',
        levelProgressFraction: 0.75,
        displayName: 'Renamed Runner',
        avatarInitials: 'RR',
      );
      final repository = FirebaseFeedRepository(port: port);

      final state = await repository.loadInitial(viewer);

      final post = state.posts.single;
      expect(post.authorDisplayName, 'Renamed Runner');
      expect(post.authorAvatarInitials, 'RR');
    },
  );

  test(
    'an author resolved with no identity keeps the name stored on the post',
    () async {
      // What an older backend deployment returns: a level, no identity.
      final port = FeedTestDataPort.withSingleFriend('friend-11');
      port.authorLevels['friend-11'] = const FeedAuthorLevel(
        levelLabel: 'Level 12',
        levelProgressFraction: 0.75,
      );
      final repository = FirebaseFeedRepository(port: port);

      final state = await repository.loadInitial(viewer);

      final post = state.posts.single;
      expect(post.authorDisplayName, 'friend-11');
      expect(post.authorAvatarInitials, 'FR');
      expect(post.authorLevelLabel, 'Level 12');
    },
  );

  test(
    'a resolved avatarUrl replaces the stored one',
    () async {
      final port = FeedTestDataPort.withSingleFriend(
        'friend-15',
        storedAvatarUrl:
            'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fold.png?alt=media&token=old-tok',
      );
      port.authorLevels['friend-15'] = const FeedAuthorLevel(
        levelLabel: 'Level 12',
        levelProgressFraction: 0.75,
        avatarUrl:
            'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fnew.png?alt=media&token=new-tok',
      );
      final repository = FirebaseFeedRepository(port: port);

      final state = await repository.loadInitial(viewer);

      final post = state.posts.single;
      expect(
        post.authorAvatarUrl,
        'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fnew.png?alt=media&token=new-tok',
      );
    },
  );

  test(
    'a resolved empty avatarUrl leaves the stored one intact',
    () async {
      final port = FeedTestDataPort.withSingleFriend(
        'friend-16',
        storedAvatarUrl:
            'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fold.png?alt=media&token=old-tok',
      );
      port.authorLevels['friend-16'] = const FeedAuthorLevel(
        levelLabel: 'Level 12',
        levelProgressFraction: 0.75,
        avatarUrl: '',
      );
      final repository = FirebaseFeedRepository(port: port);

      final state = await repository.loadInitial(viewer);

      final post = state.posts.single;
      expect(
        post.authorAvatarUrl,
        'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fold.png?alt=media&token=old-tok',
        reason:
            'an empty resolved avatarUrl must never erase a stored photo',
      );
    },
  );

  test(
    'a resolved identity is applied even when the level label resolves empty',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-12');
      port.authorLevels['friend-12'] = const FeedAuthorLevel(
        levelLabel: '',
        levelProgressFraction: 0.5,
        displayName: 'Renamed Runner',
        avatarInitials: 'RR',
      );
      final repository = FirebaseFeedRepository(port: port);

      final state = await repository.loadInitial(viewer);

      final post = state.posts.single;
      expect(post.authorDisplayName, 'Renamed Runner');
      expect(post.authorLevelLabel, 'Level 3');
      expect(post.authorLevelProgressFraction, isNull);
    },
  );

  test(
    'the same identity overlay applies to a comment\'s stored author name',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-13')
        ..addTiedComments(2);
      port.authorLevels['friend'] = const FeedAuthorLevel(
        levelLabel: 'Level 20',
        levelProgressFraction: 0.9,
        displayName: 'Renamed Runner',
        avatarInitials: 'RR',
      );
      final repository = FirebaseFeedRepository(port: port);
      await repository.loadInitial(viewer);

      final page = await repository.loadComments(postId: 'post-1');

      final resolved = page.comments.firstWhere(
        (comment) => comment.authorUserId == 'friend',
      );
      expect(resolved.authorDisplayName, 'Renamed Runner');
      expect(resolved.authorAvatarInitials, 'RR');

      final unresolved = page.comments.firstWhere(
        (comment) => comment.authorUserId == 'viewer',
      );
      expect(unresolved.authorDisplayName, 'Runner');
      expect(unresolved.authorAvatarInitials, 'RU');
    },
  );

  // firestore.rules authorizes a comment through its POST, not its commenter,
  // so a viewer reads comments from runners they are not friends with. The
  // backend can only resolve those authors if the client says which post made
  // them readable; the timeline has no such need and must keep sending the
  // uid-only payload so an older backend still answers it.
  test(
    'a comment page resolves scoped to its post, the timeline unscoped',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-14')
        ..addTiedComments(2);
      final repository = FirebaseFeedRepository(port: port);

      await repository.loadInitial(viewer);
      expect(port.authorLevelPostIds, <String?>[null]);

      await repository.loadComments(postId: 'post-1');
      expect(port.authorLevelPostIds.last, 'post-1');
    },
  );

  test('pull-to-refresh invalidates the cache and re-resolves', () async {
    final port = FeedTestDataPort.withSingleFriend('friend-04');
    port.authorLevels['friend-04'] = const FeedAuthorLevel(
      levelLabel: 'Level 1',
      levelProgressFraction: 0.1,
    );
    final repository = FirebaseFeedRepository(port: port);
    await repository.loadInitial(viewer);
    expect(port.authorLevelQueries, hasLength(1));

    port.authorLevels['friend-04'] = const FeedAuthorLevel(
      levelLabel: 'Level 2',
      levelProgressFraction: 0.2,
    );
    final refreshed = await repository.refresh();

    expect(port.authorLevelQueries, hasLength(2));
    expect(refreshed.posts.single.authorLevelLabel, 'Level 2');
  });

  test('a viewer switch on the same repository re-resolves author levels', () async {
    // Author levels are authorized per viewer, so a level cached for one
    // signed-in user must never be reused for another: the second viewer may
    // not be permitted to see that author at all, in which case the callable
    // would omit the uid and the row must fall back rather than render the
    // first viewer's cached value.
    final port = FeedTestDataPort.withSingleFriend('friend-09');
    port.authorLevels['friend-09'] = const FeedAuthorLevel(
      levelLabel: 'Level 8',
      levelProgressFraction: 0.8,
    );
    final repository = FirebaseFeedRepository(port: port);
    await repository.loadInitial(viewer);
    expect(port.authorLevelQueries, hasLength(1));

    const otherViewer = FeedViewerContext(
      currentUserId: 'other-viewer',
      acceptedFriendUserIds: <String>{},
    );
    port.authorLevels.remove('friend-09');
    final second = await repository.loadInitial(otherViewer);

    expect(
      port.authorLevelQueries,
      hasLength(2),
      reason: 'the second viewer must not reuse the first viewer\'s cache',
    );
    expect(second.posts.single.authorLevelLabel, isNot('Level 8'));
  });

  test(
    'the same live-level overlay applies to a comment\'s stored label and progress',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-05')
        ..addTiedComments(2);
      port.authorLevels['friend'] = const FeedAuthorLevel(
        levelLabel: 'Level 20',
        levelProgressFraction: 0.9,
      );
      final repository = FirebaseFeedRepository(port: port);
      await repository.loadInitial(viewer);

      final page = await repository.loadComments(postId: 'post-1');

      final resolvedComment = page.comments.firstWhere(
        (comment) => comment.authorUserId == 'friend',
      );
      expect(resolvedComment.authorLevelLabel, 'Level 20');
      expect(resolvedComment.authorLevelProgressFraction, 0.9);

      final unresolvedComment = page.comments.firstWhere(
        (comment) => comment.authorUserId == 'viewer',
      );
      expect(unresolvedComment.authorLevelLabel, 'Level 3');
      expect(unresolvedComment.authorLevelProgressFraction, isNull);
    },
  );

  test(
    'a comment author the resolver has nothing for keeps its stored label '
    'and leaves the progress fraction unresolved',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-06')
        ..addTiedComments(2)
        ..authorLevelsError = Exception('not deployed yet');
      final repository = FirebaseFeedRepository(port: port);
      await repository.loadInitial(viewer);

      final page = await repository.loadComments(postId: 'post-1');

      expect(page.comments, hasLength(2));
      for (final comment in page.comments) {
        expect(comment.authorLevelLabel, 'Level 3');
        expect(comment.authorLevelProgressFraction, isNull);
      }
    },
  );

  test(
    'a comment with a resolved empty levelLabel keeps its stored label and '
    'leaves the progress fraction unresolved',
    () async {
      final port = FeedTestDataPort.withSingleFriend('friend-08')
        ..addTiedComments(2);
      port.authorLevels['friend'] = const FeedAuthorLevel(
        levelLabel: '',
        levelProgressFraction: 0.5,
      );
      final repository = FirebaseFeedRepository(port: port);
      await repository.loadInitial(viewer);

      final page = await repository.loadComments(postId: 'post-1');

      final comment = page.comments.firstWhere(
        (comment) => comment.authorUserId == 'friend',
      );
      expect(comment.authorLevelLabel, 'Level 3');
      expect(comment.authorLevelProgressFraction, isNull);
    },
  );
}
