import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/leaderboard/domain/models/leaderboard_read_model.dart';
import 'package:runiac_app/features/leaderboard/presentation/leaderboard_read_model_display_adapter.dart';
import 'package:runiac_app/features/leaderboard/presentation/models/leaderboard_display_models.dart';

void main() {
  final now = DateTime.utc(2026, 7, 10);

  LeaderboardRowReadModel row({
    String userId = 'runner',
    String displayName = 'Runner',
    String rankLabel = '#1',
    String scoreLabel = '100 XP',
    bool isCurrentUser = false,
    String snapshotId = '',
    String buildId = '',
  }) {
    return LeaderboardRowReadModel(
      userId: userId,
      displayName: displayName,
      rankLabel: rankLabel,
      scoreLabel: scoreLabel,
      isCurrentUser: isCurrentUser,
      snapshotId: snapshotId,
      buildId: buildId,
    );
  }

  LeaderboardReadModel model({
    LeaderboardReadStatus status = LeaderboardReadStatus.data,
    String currentRunnerRankLabel = '',
    List<LeaderboardRowReadModel> entries = const <LeaderboardRowReadModel>[],
    List<LeaderboardRowReadModel> nearbyEntries =
        const <LeaderboardRowReadModel>[],
  }) {
    return LeaderboardReadModel(
      status: status,
      regionLabel: 'Jurong East',
      currentRunnerRankLabel: currentRunnerRankLabel,
      entries: entries,
      nearbyEntries: nearbyEntries,
    );
  }

  group('status passthrough', () {
    for (final status in LeaderboardReadStatus.values) {
      test('passes through $status verbatim', () {
        final snapshot = leaderboardDisplaySnapshotFromReadModel(
          model(status: status),
          now,
        );

        expect(snapshot.status, status);
      });
    }
  });

  group('hasCurrentUserRank', () {
    test(
      'is true when a current-user nearby row and rank label are present',
      () {
        final snapshot = leaderboardDisplaySnapshotFromReadModel(
          model(
            currentRunnerRankLabel: '#12',
            nearbyEntries: [
              row(userId: 'me', displayName: 'Me', isCurrentUser: true),
            ],
          ),
          now,
        );

        expect(snapshot.hasCurrentUserRank, isTrue);
      },
    );

    test('is false when the current runner rank label is empty', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(
        model(
          currentRunnerRankLabel: '',
          nearbyEntries: [
            row(userId: 'me', displayName: 'Me', isCurrentUser: true),
          ],
        ),
        now,
      );

      expect(snapshot.hasCurrentUserRank, isFalse);
    });

    test('is false when no nearby row belongs to the current user', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(
        model(
          currentRunnerRankLabel: '#12',
          nearbyEntries: [row(userId: 'other', displayName: 'Other')],
        ),
        now,
      );

      expect(snapshot.hasCurrentUserRank, isFalse);
    });
  });

  group('ordinal medal tones', () {
    test('map by list position regardless of rank label format', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(
        model(
          entries: [
            row(userId: 'a', rankLabel: '12th'),
            row(userId: 'b', rankLabel: '5th'),
            row(userId: 'c', rankLabel: '99th'),
            row(userId: 'd', rankLabel: '#1'),
          ],
        ),
        now,
      );

      expect(snapshot.topRanks[0].medalTone, RegionPreviewMedalTone.gold);
      expect(snapshot.topRanks[0].trophy, isTrue);
      expect(snapshot.topRanks[1].medalTone, RegionPreviewMedalTone.silver);
      expect(snapshot.topRanks[1].trophy, isFalse);
      expect(snapshot.topRanks[2].medalTone, RegionPreviewMedalTone.bronze);
      expect(snapshot.topRanks[2].trophy, isFalse);
      expect(snapshot.topRanks[3].medalTone, isNull);
      expect(snapshot.topRanks[3].trophy, isFalse);
    });
  });

  group('nearby rows', () {
    test('never receive a medal tone or trophy', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(
        model(
          nearbyEntries: [
            row(userId: 'a', rankLabel: '#1'),
            row(userId: 'b', rankLabel: '#2'),
            row(userId: 'c', rankLabel: '#3'),
          ],
        ),
        now,
      );

      for (final nearbyRow in snapshot.nearbyRanks) {
        expect(nearbyRow.medalTone, isNull);
        expect(nearbyRow.trophy, isFalse);
      }
    });

    test('nearby section title reads "Ranks near you"', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(model(), now);

      expect(snapshot.nearbyRanksTitle, 'Ranks near you');
    });
  });

  group('runner profile snapshot', () {
    test('splits rank and region into separate profile labels', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(
        model(
          entries: [row(userId: 'runner-a', rankLabel: '#7')],
        ),
        now,
      );
      final profile = snapshot.topRanks.single.profile;

      expect(profile.regionRankLabel, '#7 Jurong East, Singapore');
      expect(profile.rankLabel, '#7');
      expect(profile.regionLabel, 'Jurong East, Singapore');
      expect(profile.uid, 'runner-a');
    });

    test('drops the unranked rank placeholder instead of showing it', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(
        model(entries: [row(rankLabel: '#--')]),
        now,
      );

      expect(snapshot.topRanks.single.profile.rankLabel, '');
      expect(
        snapshot.topRanks.single.profile.regionLabel,
        'Jurong East, Singapore',
      );
    });

    test('relays the backend division name for the profile badge', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(
        model(
          entries: [
            LeaderboardRowReadModel(
              userId: 'runner-a',
              displayName: 'Runner',
              rankLabel: '#1',
              scoreLabel: '100 XP',
              levelLabel: 'Level 8',
              divisionLabel: 'Silver',
            ),
          ],
        ),
        now,
      );
      final profile = snapshot.topRanks.single.profile;

      expect(profile.divisionLabel, 'Silver');
      expect(profile.divisionLevelLabel, 'Silver \u00b7 Level 8');
      expect(profile.levelBadgeLabel, 'Lv.8');
    });

    test('carries the snapshot and build id onto top and nearby profiles', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(
        model(
          entries: [
            row(
              userId: 'a',
              rankLabel: '#1',
              snapshotId: 'monthly_jurong-east_tier_03_2026-07',
              buildId: 'build-2026-07-26T09',
            ),
          ],
          nearbyEntries: [
            row(
              userId: 'b',
              rankLabel: '#7',
              snapshotId: 'monthly_jurong-east_tier_01_2026-07',
              buildId: 'build-2026-07-26T08',
            ),
          ],
        ),
        now,
      );

      // Snapshot + build + rank is how the profile screen addresses a runner
      // whose uid the board deliberately never publishes. The build id is what
      // stops a stale row from resolving to whoever inherited its rank.
      expect(
        snapshot.topRanks.single.profile.snapshotId,
        'monthly_jurong-east_tier_03_2026-07',
      );
      expect(snapshot.topRanks.single.profile.rankLabel, '#1');
      expect(snapshot.topRanks.single.profile.buildId, 'build-2026-07-26T09');
      // The nearby row keeps its own board too: the rank projection can move
      // to another division before the current view naming it catches up.
      expect(
        snapshot.nearbyRanks.single.profile.snapshotId,
        'monthly_jurong-east_tier_01_2026-07',
      );
      expect(snapshot.nearbyRanks.single.profile.rankLabel, '#7');
      // The nearby row keeps its own source build, not the board's: it comes
      // from the rank projection, which a refresh rewrites separately.
      expect(
        snapshot.nearbyRanks.single.profile.buildId,
        'build-2026-07-26T08',
      );
    });

    test('states that only public running achievements are shown', () {
      final snapshot = leaderboardDisplaySnapshotFromReadModel(
        model(entries: [row()]),
        now,
      );

      expect(
        snapshot.topRanks.single.profile.privacyNote,
        'Only public running achievements are shown.',
      );
    });
  });
}
