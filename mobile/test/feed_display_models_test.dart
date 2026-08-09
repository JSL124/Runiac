import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';

void main() {
  group('Feed display models', () {
    test(
      'Feed route preview payload omits raw coordinate-like values',
      () async {
        const feed = StaticFeedRepository();
        final readModel = await feed.loadFeed(
          const FeedViewerContext(
            currentUserId: 'runner-current',
            acceptedFriendUserIds: <String>{'runner-friend'},
          ),
        );
        final coordinatePattern = RegExp(
          r'(-?\d{1,3}\.\d{4,})\s*[,|]\s*(-?\d{1,3}\.\d{4,})',
        );
        final coordinateTerms = RegExp(
          r'\b(lat|latitude|lng|lon|longitude|coordinate|polyline)\b',
          caseSensitive: false,
        );

        for (final post in readModel.posts) {
          final routePreviewPayload = [
            post.routeThumbnail.thumbnailKey,
            post.routeThumbnail.accessibilityLabel,
            post.routeName,
          ].whereType<String>().join(' ');

          expect(
            routePreviewPayload,
            isNot(matches(coordinatePattern)),
            reason: post.postId,
          );
          expect(
            routePreviewPayload,
            isNot(matches(coordinateTerms)),
            reason: post.postId,
          );
        }
      },
    );
  });

  group('FeedPostReadModel.authorProfileFor', () {
    const currentViewer = FeedAuthorProfileSnapshot(
      userId: 'viewer',
      displayName: 'You',
      avatarInitials: 'YR',
      levelLabel: 'Level 5',
      levelProgressFraction: 0.3,
    );

    test(
      'the viewer\'s own post with an empty stored label falls back to the '
      'current viewer profile',
      () {
        final profile = _post(
          authorUserId: 'viewer',
          authorLevelLabel: '',
        ).authorProfileFor(currentViewer);

        expect(profile.levelLabel, 'Level 5');
        expect(profile.levelProgressFraction, 0.3);
      },
    );

    test(
      'a resolved non-empty label on the viewer\'s own post is never '
      'overridden by the viewer fallback',
      () {
        final profile = _post(
          authorUserId: 'viewer',
          authorLevelLabel: 'Level 9',
          authorLevelProgressFraction: 0.6,
        ).authorProfileFor(currentViewer);

        expect(profile.levelLabel, 'Level 9');
        expect(profile.levelProgressFraction, 0.6);
      },
    );

    test('a friend\'s resolved progress renders a real fraction, not 0', () {
      final profile = _post(
        authorUserId: 'friend-1',
        authorLevelLabel: 'Level 7',
        authorLevelProgressFraction: 0.42,
      ).authorProfileFor(currentViewer);

      expect(profile.levelLabel, 'Level 7');
      expect(profile.levelProgressFraction, 0.42);
    });

    test(
      'a friend\'s post with an empty stored label has no viewer fallback '
      'and hides the pill',
      () {
        final profile = _post(
          authorUserId: 'friend-2',
          authorLevelLabel: '',
        ).authorProfileFor(currentViewer);

        expect(profile.levelLabel, '');
        expect(profile.levelProgressFraction, 0);
      },
    );

    test(
      'the viewer\'s own post keeps the current viewer\'s progress fraction '
      'when the overlay resolves nothing',
      () {
        final profile = _post(
          authorUserId: 'viewer',
          authorLevelLabel: 'Level 9',
        ).authorProfileFor(currentViewer);

        expect(profile.levelProgressFraction, 0.3);
      },
    );

    test(
      'a resolved fraction of exactly 0.0 on the viewer\'s own post is '
      'honoured as a real value, not replaced by the viewer fallback',
      () {
        final profile = _post(
          authorUserId: 'viewer',
          authorLevelLabel: 'Level 9',
          authorLevelProgressFraction: 0.0,
        ).authorProfileFor(currentViewer);

        expect(profile.levelProgressFraction, 0.0);
      },
    );

    test(
      'a non-viewer post with no resolution yields a fraction of 0',
      () {
        final profile = _post(
          authorUserId: 'friend-3',
          authorLevelLabel: 'Level 9',
        ).authorProfileFor(currentViewer);

        expect(profile.levelProgressFraction, 0);
      },
    );
  });
}

FeedPostReadModel _post({
  required String authorUserId,
  required String authorLevelLabel,
  double? authorLevelProgressFraction,
}) => FeedPostReadModel(
  postId: 'post-1',
  authorUserId: authorUserId,
  authorDisplayName: 'Runner',
  authorAvatarInitials: 'RU',
  authorLevelLabel: authorLevelLabel,
  authorLevelProgressFraction: authorLevelProgressFraction,
  relativeTimeLabel: '1h',
  distanceLabel: '5.0 km',
  paceLabel: '5:00 / km',
  durationLabel: '25 min',
  likeCount: 0,
  commentCount: 0,
  isLikedByViewer: false,
  hasViewerCommented: false,
  canComment: true,
  showsOwnerMenu: false,
  routeThumbnail: const FeedRouteThumbnailReadModel(
    thumbnailKey: 'k',
    accessibilityLabel: 'a',
  ),
);
