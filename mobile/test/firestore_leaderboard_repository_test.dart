import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/leaderboard/data/firestore_leaderboard_repository.dart';
import 'package:runiac_app/features/leaderboard/domain/models/leaderboard_read_model.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  test('loads bounded live top and owner-nearby monthly projections', () async {
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'runner-1');
    final reader = _FakeLeaderboardDocumentReader(
      period: const {
        'periodKey': '2026-07',
        'periodLabel': 'July 2026',
        'refreshesAt': '2026-07-31T16:00:00.000Z',
      },
      currentView: const {
        'homeRegionId': 'jurong-east',
        'divisionKey': 'tier_02',
        'status': 'ranked',
        'activeSnapshotId': 'monthly_jurong-east_tier_02_2026-07',
        'activeRankProjectionId': 'runner-1_monthly_2026-07',
      },
      profile: const {
        'locationLabel': 'Jurong East, Singapore',
        'divisionKey': 'tier_02',
      },
      snapshots: const {
        'monthly_jurong-east_tier_02_2026-07': {
          'regionLabel': 'Jurong East',
          'divisionLabel': 'Bronze League',
          'buildId': 'build-2026-07-26T09',
          'topEntries': [
            {
              'publicAlias': 'Ari S.',
              'rankLabel': '#1',
              'scoreLabel': '1,480 XP',
              'levelLabel': 'Level 19',
              'divisionLabel': 'Bronze League',
              'regionLabel': 'Jurong East',
              'avatarUrl':
                  'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fari.png?alt=media&token=tok',
              'levelProgressPercent': 64,
            },
          ],
        },
      },
      ranks: const {
        'runner-1_monthly_2026-07': {
          'rankLabel': '#12',
          'snapshotId': 'monthly_jurong-east_tier_01_2026-07',
          'buildId': 'build-2026-07-26T08',
          'currentEntry': {'publicAlias': 'Jinseo', 'rankLabel': '#12'},
          'nearbyEntries': [
            {
              'publicAlias': 'Jinseo',
              'rankLabel': '#12',
              'scoreLabel': '1,320 XP',
              'levelLabel': 'Level 18',
              'divisionLabel': 'Bronze League',
              'regionLabel': 'Jurong East',
              // No avatar and no level progress on record for this row — both
              // must default, never null or a throw.
            },
          ],
        },
      },
    );
    final repository = FirestoreLeaderboardRepository(
      authRepository: authRepository,
      reader: reader,
    );

    final leaderboard = await repository.loadLeaderboard();

    expect(leaderboard.status, LeaderboardReadStatus.data);
    expect(leaderboard.regionId, 'jurong-east');
    expect(leaderboard.divisionLabel, 'Bronze League');
    expect(leaderboard.currentRunnerRankLabel, '#12');
    expect(leaderboard.entries.single.displayName, 'Ari S.');
    expect(
      leaderboard.entries.single.avatarUrl,
      'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fari.png?alt=media&token=tok',
    );
    // The backend's 0..100 percent becomes the XP ring's 0.0..1.0 here; the
    // client never derives it from the score.
    expect(leaderboard.entries.single.levelProgressFraction, closeTo(0.64, 1e-9));
    expect(leaderboard.nearbyEntries.single.displayName, 'Jinseo');
    // No avatar on record for this row — must default to empty, never null
    // or a throw.
    expect(leaderboard.nearbyEntries.single.avatarUrl, '');
    // Likewise a row from a snapshot published before the backend carried the
    // percent: an empty ring, not a crash.
    expect(leaderboard.nearbyEntries.single.levelProgressFraction, 0);
    expect(leaderboard.nearbyEntries.single.isCurrentUser, isTrue);
    expect(leaderboard.periodLabel, 'July 2026');
    expect(leaderboard.periodEndsAt, DateTime.utc(2026, 7, 31, 16));
    // Both halves of the handle the public profile callable resolves a runner
    // by. An empty build id would leave every row unopenable.
    expect(
      leaderboard.entries.single.snapshotId,
      'monthly_jurong-east_tier_02_2026-07',
    );
    expect(
      leaderboard.nearbyEntries.single.snapshotId,
      'monthly_jurong-east_tier_01_2026-07',
    );
    // Each row keeps the build of the document it came from. The refresh job
    // rewrites snapshots and rank projections in separate batches, so a load
    // can see a new snapshot beside an older rank projection — stamping the
    // snapshot's build on a stale nearby row would let it resolve against
    // whoever inherited that rank.
    expect(leaderboard.entries.single.buildId, 'build-2026-07-26T09');
    expect(leaderboard.nearbyEntries.single.buildId, 'build-2026-07-26T08');
  });

  test(
    'stamps the rank build on a current entry the nearby list omits',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'runner-1');
      final reader = _FakeLeaderboardDocumentReader(
        period: const {'periodKey': '2026-07'},
        currentView: const {
          'homeRegionId': 'jurong-east',
          'divisionKey': 'tier_02',
          'status': 'ranked',
          'activeSnapshotId': 'monthly_jurong-east_tier_02_2026-07',
          'activeRankProjectionId': 'runner-1_monthly_2026-07',
        },
        profile: const {'locationLabel': 'Jurong East, Singapore'},
        snapshots: const {
          'monthly_jurong-east_tier_02_2026-07': {
            'buildId': 'build-2026-07-26T09',
            'topEntries': [],
          },
        },
        ranks: const {
          'runner-1_monthly_2026-07': {
            'rankLabel': '#12',
            'snapshotId': 'monthly_jurong-east_tier_01_2026-07',
            'buildId': 'build-2026-07-26T08',
            'currentEntry': {'publicAlias': 'Jinseo', 'rankLabel': '#12'},
            'nearbyEntries': [],
          },
        },
      );
      final repository = FirestoreLeaderboardRepository(
        authRepository: authRepository,
        reader: reader,
      );

      final leaderboard = await repository.loadLeaderboard();

      expect(leaderboard.nearbyEntries.single.buildId, 'build-2026-07-26T08');
    },
  );

  test(
    'leaves the build id empty when the snapshot has not published one',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'runner-1');
      final reader = _FakeLeaderboardDocumentReader(
        period: const {'periodKey': '2026-07'},
        currentView: const {
          'homeRegionId': 'jurong-east',
          'divisionKey': 'tier_02',
          'status': 'ranked',
          'activeSnapshotId': 'monthly_jurong-east_tier_02_2026-07',
        },
        profile: const {'locationLabel': 'Jurong East, Singapore'},
        snapshots: const {
          'monthly_jurong-east_tier_02_2026-07': {'topEntries': []},
        },
        ranks: const {},
      );
      final repository = FirestoreLeaderboardRepository(
        authRepository: authRepository,
        reader: reader,
      );

      final leaderboard = await repository.loadLeaderboard();

      expect(leaderboard.entries, isEmpty);
      expect(
        leaderboard.nearbyEntries.every((entry) => entry.buildId.isEmpty),
        isTrue,
      );
    },
  );

  test(
    'shows the current rank when nearby projections omit its entry',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'runner-1');
      final reader = _FakeLeaderboardDocumentReader(
        period: const {'periodKey': '2026-07'},
        currentView: const {
          'homeRegionId': 'jurong-east',
          'divisionKey': 'tier_02',
          'status': 'ranked',
          'activeSnapshotId': 'monthly_jurong-east_tier_02_2026-07',
          'activeRankProjectionId': 'runner-1_monthly_2026-07',
        },
        profile: const {'locationLabel': 'Jurong East, Singapore'},
        snapshots: const {
          'monthly_jurong-east_tier_02_2026-07': {'topEntries': []},
        },
        ranks: const {
          'runner-1_monthly_2026-07': {
            'rankLabel': '#12',
            'currentEntry': {
              'publicAlias': 'Jinseo',
              'rankLabel': '#12',
              'scoreLabel': '1,320 XP',
              'levelLabel': 'Level 18',
              'divisionLabel': 'Bronze League',
              'regionLabel': 'Jurong East',
            },
            'nearbyEntries': [],
          },
        },
      );
      final repository = FirestoreLeaderboardRepository(
        authRepository: authRepository,
        reader: reader,
      );

      final leaderboard = await repository.loadLeaderboard();

      expect(leaderboard.currentRunnerRankLabel, '#12');
      expect(leaderboard.nearbyEntries, hasLength(1));
      expect(leaderboard.nearbyEntries.single.displayName, 'Jinseo');
      expect(leaderboard.nearbyEntries.single.isCurrentUser, isTrue);
    },
  );

  test('uses selected profile planning area for an unranked owner', () async {
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'runner-1');
    final reader = _FakeLeaderboardDocumentReader(
      period: const {'periodKey': '2026-07', 'periodLabel': 'July 2026'},
      currentView: null,
      profile: const {
        'locationLabel': 'Tampines, Singapore',
        'divisionKey': 'tier_01',
      },
      snapshots: const {
        'monthly_tampines_tier_01_2026-07': {
          'divisionLabel': 'Iron League',
          'topEntries': [],
        },
      },
    );
    final repository = FirestoreLeaderboardRepository(
      authRepository: authRepository,
      reader: reader,
    );

    final leaderboard = await repository.loadLeaderboard();

    expect(leaderboard.status, LeaderboardReadStatus.unranked);
    expect(leaderboard.homeRegionId, 'tampines');
    expect(leaderboard.regionLabel, 'Tampines');
    expect(leaderboard.entries, isEmpty);
  });

  test('returns region-required without demo fallback', () async {
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'runner-1');
    final repository = FirestoreLeaderboardRepository(
      authRepository: authRepository,
      reader: const _FakeLeaderboardDocumentReader(
        period: {'periodKey': '2026-07'},
        currentView: null,
        profile: {'locationLabel': 'Tuas, Singapore'},
      ),
    );

    final leaderboard = await repository.loadLeaderboard();

    expect(leaderboard.status, LeaderboardReadStatus.regionRequired);
    expect(leaderboard.entries, isEmpty);
    expect(leaderboard.regionLabel, isEmpty);
  });

  test('loads a tapped supported region from the live snapshot path', () async {
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'runner-1');
    final reader = _FakeLeaderboardDocumentReader(
      period: const {'periodKey': '2026-07'},
      currentView: const {
        'homeRegionId': 'jurong-east',
        'divisionKey': 'tier_01',
        'status': 'ranked',
      },
      profile: const {'locationLabel': 'Jurong East, Singapore'},
      snapshots: const {
        'monthly_tampines_tier_01_2026-07': {
          'divisionLabel': 'Iron League',
          'topEntries': [
            {
              'publicAlias': 'Tampines Runner',
              'rankLabel': '#1',
              'scoreLabel': '900 XP',
              'levelLabel': 'Level 3',
              'divisionLabel': 'Iron League',
              'regionLabel': 'Tampines',
            },
          ],
        },
      },
    );
    final repository = FirestoreLeaderboardRepository(
      authRepository: authRepository,
      reader: reader,
    );

    final leaderboard = await repository.loadRegion(regionId: 'tampines');

    expect(leaderboard.regionId, 'tampines');
    expect(leaderboard.isHomeRegion, isFalse);
    expect(leaderboard.entries.single.displayName, 'Tampines Runner');
    expect(reader.snapshotReads, contains('monthly_tampines_tier_01_2026-07'));
  });

  test('requires authentication instead of returning static people', () async {
    final repository = FirestoreLeaderboardRepository(
      authRepository: FakeRuniacAuthRepository(),
      reader: const _FakeLeaderboardDocumentReader(
        period: {'periodKey': '2026-07'},
        currentView: null,
      ),
    );

    await expectLater(repository.loadLeaderboard(), throwsStateError);
  });

  test(
    'emits the promoted division after its Firestore documents change',
    () async {
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'runner-1');
      final reader = _LiveLeaderboardDocumentReader();
      addTearDown(reader.dispose);
      final repository = FirestoreLeaderboardRepository(
        authRepository: authRepository,
        reader: reader,
      );
      final promoted = repository.watchLeaderboard().first;

      reader.publishBronzePromotion();

      final leaderboard = await promoted;
      expect(leaderboard.divisionKey, 'tier_02');
      expect(leaderboard.divisionLabel, 'Bronze League');
      expect(leaderboard.currentRunnerRankLabel, '#1');
    },
  );
}

class _LiveLeaderboardDocumentReader implements LiveLeaderboardDocumentReader {
  final _changes = StreamController<void>.broadcast();
  Map<String, Object?>? _currentView;
  Map<String, Object?>? _profile = const {
    'locationLabel': 'Jurong East, Singapore',
    'divisionKey': 'tier_01',
  };
  Map<String, Object?>? _snapshot;
  Map<String, Object?>? _rank;

  @override
  Future<Map<String, Object?>?> readCurrentPeriod() async => const {
    'periodKey': '2026-07',
  };

  @override
  Future<Map<String, Object?>?> readCurrentView({required String uid}) async =>
      _currentView;

  @override
  Future<Map<String, Object?>?> readProfile({required String uid}) async =>
      _profile;

  @override
  Future<Map<String, Object?>?> readRank({required String rankId}) async =>
      _rank;

  @override
  Future<Map<String, Object?>?> readSnapshot({
    required String snapshotId,
  }) async => _snapshot;

  @override
  Stream<void> watchLeaderboardDocuments({required String uid}) =>
      _changes.stream;

  void publishBronzePromotion() {
    _currentView = const {
      'homeRegionId': 'jurong-east',
      'divisionKey': 'tier_02',
      'status': 'ranked',
      'snapshotId': 'monthly_jurong-east_tier_02_2026-07',
      'rankId': 'runner-1_monthly_2026-07',
    };
    _profile = const {
      'locationLabel': 'Jurong East, Singapore',
      'divisionKey': 'tier_02',
    };
    _snapshot = const {
      'divisionLabel': 'Bronze League',
      'topEntries': [
        {
          'publicAlias': 'League Runner',
          'rankLabel': '#1',
          'scoreLabel': '85 XP',
          'levelLabel': 'Level 11',
          'divisionLabel': 'Bronze League',
          'regionLabel': 'Jurong East',
        },
      ],
    };
    _rank = const {
      'rankLabel': '#1',
      'currentEntry': {'publicAlias': 'League Runner', 'rankLabel': '#1'},
    };
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

class _FakeLeaderboardDocumentReader implements LeaderboardDocumentReader {
  const _FakeLeaderboardDocumentReader({
    required this.period,
    required this.currentView,
    this.profile,
    this.snapshots = const <String, Map<String, Object?>>{},
    this.ranks = const <String, Map<String, Object?>>{},
  });

  final Map<String, Object?>? period;
  final Map<String, Object?>? currentView;
  final Map<String, Object?>? profile;
  final Map<String, Map<String, Object?>> snapshots;
  final Map<String, Map<String, Object?>> ranks;
  static final List<String> _snapshotReads = [];
  List<String> get snapshotReads => List.unmodifiable(_snapshotReads);

  @override
  Future<Map<String, Object?>?> readCurrentPeriod() async => period;

  @override
  Future<Map<String, Object?>?> readCurrentView({required String uid}) async {
    return currentView;
  }

  @override
  Future<Map<String, Object?>?> readProfile({required String uid}) async {
    return profile;
  }

  @override
  Future<Map<String, Object?>?> readRank({required String rankId}) async {
    return ranks[rankId];
  }

  @override
  Future<Map<String, Object?>?> readSnapshot({
    required String snapshotId,
  }) async {
    _snapshotReads.add(snapshotId);
    return snapshots[snapshotId];
  }
}
