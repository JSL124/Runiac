import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_author_level_resolver.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_data_port.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/feed_test_data_port.dart';
import 'package:runiac_app/features/feed/data/firebase_feed_repository/firebase_feed_data_port.dart';

void main() {
  group('FeedAuthorLevelResolver', () {
    test('resolves and caches only uids missing from the cache', () async {
      final port = FeedTestDataPort.withUnevenAuthors();
      port.authorLevels['friend-00'] = const FeedAuthorLevel(
        levelLabel: 'Level 9',
        levelProgressFraction: 0.5,
      );
      port.authorLevels['friend-01'] = const FeedAuthorLevel(
        levelLabel: 'Level 4',
        levelProgressFraction: 0.1,
      );
      final resolver = FeedAuthorLevelResolver(port);

      await resolver.ensureResolved(<String>['friend-00', 'friend-01']);
      expect(resolver.lookup('friend-00')?.levelLabel, 'Level 9');
      expect(resolver['friend-01']?.levelLabel, 'Level 4');
      expect(port.authorLevelQueries, hasLength(1));
      expect(port.authorLevelQueries.single.toSet(), <String>{
        'friend-00',
        'friend-01',
      });

      await resolver.ensureResolved(<String>['friend-00', 'friend-02']);
      expect(port.authorLevelQueries, hasLength(2));
      expect(port.authorLevelQueries.last, <String>['friend-02']);
    });

    test('a uid absent from the response has no cached lookup', () async {
      final port = FeedTestDataPort.withUnevenAuthors();
      final resolver = FeedAuthorLevelResolver(port);

      await resolver.ensureResolved(<String>['friend-00']);

      expect(resolver.lookup('friend-00'), isNull);
      expect(port.authorLevelQueries, hasLength(1));
    });

    test('swallows a port failure and caches nothing', () async {
      final port = FeedTestDataPort.withUnevenAuthors();
      port.authorLevels['friend-00'] = const FeedAuthorLevel(
        levelLabel: 'Level 9',
        levelProgressFraction: 0.5,
      );
      port.authorLevelsError = Exception('offline');
      final resolver = FeedAuthorLevelResolver(port);

      await expectLater(
        resolver.ensureResolved(<String>['friend-00']),
        completes,
      );
      expect(resolver.lookup('friend-00'), isNull);

      port.authorLevelsError = null;
      await resolver.ensureResolved(<String>['friend-00']);
      expect(resolver.lookup('friend-00')?.levelLabel, 'Level 9');
    });

    test('invalidate clears the cache so a later call re-resolves', () async {
      final port = FeedTestDataPort.withUnevenAuthors();
      port.authorLevels['friend-00'] = const FeedAuthorLevel(
        levelLabel: 'Level 9',
        levelProgressFraction: 0.5,
      );
      final resolver = FeedAuthorLevelResolver(port);

      await resolver.ensureResolved(<String>['friend-00']);
      expect(resolver.lookup('friend-00'), isNotNull);

      resolver.invalidate();
      expect(resolver.lookup('friend-00'), isNull);

      await resolver.ensureResolved(<String>['friend-00']);
      expect(port.authorLevelQueries, hasLength(2));
    });

    test('does nothing when every uid is already cached', () async {
      final port = FeedTestDataPort.withUnevenAuthors();
      final resolver = FeedAuthorLevelResolver(port);

      await resolver.ensureResolved(<String>[]);
      expect(port.authorLevelQueries, isEmpty);
    });
  });

  group('FirebaseFeedDataPort author-level parsing', () {
    test('chunks uids at 50 per call', () {
      final uids = List<String>.generate(120, (index) => 'author-$index');

      final chunks = FirebaseFeedDataPort.chunkFeedAuthorUids(uids);

      expect(chunks, hasLength(3));
      expect(chunks[0], hasLength(50));
      expect(chunks[1], hasLength(50));
      expect(chunks[2], hasLength(20));
      expect(chunks.expand((chunk) => chunk).toList(), uids);
    });

    test('exactly 50 uids issues a single chunk', () {
      final uids = List<String>.generate(50, (index) => 'author-$index');
      expect(FirebaseFeedDataPort.chunkFeedAuthorUids(uids), hasLength(1));
    });

    test('51 uids issues more than one chunk', () {
      final uids = List<String>.generate(51, (index) => 'author-$index');
      final chunks = FirebaseFeedDataPort.chunkFeedAuthorUids(uids);
      expect(chunks.length, greaterThan(1));
    });

    test('converts a 0..100 percent into a clamped 0.0..1.0 fraction', () {
      final result = FirebaseFeedDataPort.parseFeedAuthorLevelsResponse(
        <String, Object?>{
          'levels': <String, Object?>{
            'uid-normal': <String, Object?>{
              'levelLabel': 'Level 7',
              'levelProgressPercent': 42,
            },
            'uid-over': <String, Object?>{
              'levelLabel': 'Level 8',
              'levelProgressPercent': 150,
            },
            'uid-under': <String, Object?>{
              'levelLabel': 'Level 1',
              'levelProgressPercent': -10,
            },
          },
        },
      );

      expect(result['uid-normal']?.levelProgressFraction, closeTo(0.42, 1e-9));
      expect(result['uid-over']?.levelProgressFraction, 1.0);
      expect(result['uid-under']?.levelProgressFraction, 0.0);
    });

    test('parses the author identity and defaults it to empty when absent', () {
      final result = FirebaseFeedDataPort.parseFeedAuthorLevelsResponse(
        <String, Object?>{
          'levels': <String, Object?>{
            'uid-named': <String, Object?>{
              'levelLabel': 'Level 7',
              'levelProgressPercent': 42,
              'displayName': 'Renamed Runner',
              'avatarInitials': 'RR',
              'avatarUrl':
                  'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok',
            },
            // What an older backend deployment returns.
            'uid-level-only': <String, Object?>{
              'levelLabel': 'Level 7',
              'levelProgressPercent': 42,
            },
            'uid-malformed-name': <String, Object?>{
              'levelLabel': 'Level 7',
              'levelProgressPercent': 42,
              'displayName': 7,
            },
          },
        },
      );

      expect(result['uid-named']?.displayName, 'Renamed Runner');
      expect(result['uid-named']?.avatarInitials, 'RR');
      expect(
        result['uid-named']?.avatarUrl,
        'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok',
      );
      expect(result['uid-level-only']?.displayName, '');
      expect(result['uid-level-only']?.avatarInitials, '');
      expect(result['uid-level-only']?.avatarUrl, '');
      expect(result['uid-malformed-name']?.displayName, '');
    });

    test('defaults a missing or malformed field defensively', () {
      final result = FirebaseFeedDataPort.parseFeedAuthorLevelsResponse(
        <String, Object?>{
          'levels': <String, Object?>{
            'uid-missing-percent': <String, Object?>{'levelLabel': 'Level 3'},
            'uid-missing-label': <String, Object?>{
              'levelProgressPercent': 55,
            },
            'uid-non-string-label': <String, Object?>{
              'levelLabel': 42,
              'levelProgressPercent': 10,
            },
            'uid-non-num-percent': <String, Object?>{
              'levelLabel': 'Level 2',
              'levelProgressPercent': 'lots',
            },
          },
        },
      );

      expect(result['uid-missing-percent']?.levelLabel, 'Level 3');
      expect(result['uid-missing-percent']?.levelProgressFraction, 0.0);
      expect(result['uid-missing-label']?.levelLabel, '');
      expect(result['uid-missing-label']?.levelProgressFraction, 0.55);
      expect(result['uid-non-string-label']?.levelLabel, '');
      expect(result['uid-non-num-percent']?.levelProgressFraction, 0.0);
    });

    test('skips a malformed entry instead of throwing', () {
      final result = FirebaseFeedDataPort.parseFeedAuthorLevelsResponse(
        <Object?, Object?>{
          'levels': <Object?, Object?>{
            'uid-good': <Object?, Object?>{
              'levelLabel': 'Level 5',
              'levelProgressPercent': 20,
            },
            'uid-bad': 'not a map',
            42: <Object?, Object?>{'levelLabel': 'Level 9'},
          },
        },
      );

      expect(result.keys, <String>['uid-good']);
    });

    test('an entirely malformed response yields an empty map, never throws', () {
      expect(
        FirebaseFeedDataPort.parseFeedAuthorLevelsResponse(null),
        isEmpty,
      );
      expect(
        FirebaseFeedDataPort.parseFeedAuthorLevelsResponse('not a map'),
        isEmpty,
      );
      expect(
        FirebaseFeedDataPort.parseFeedAuthorLevelsResponse(
          <String, Object?>{'levels': 'not a map'},
        ),
        isEmpty,
      );
    });
  });
}
