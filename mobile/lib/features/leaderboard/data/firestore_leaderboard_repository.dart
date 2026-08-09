import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/regions/singapore_planning_area_catalog.dart';
import '../../auth/domain/runiac_auth_service.dart';
import '../domain/models/leaderboard_league_catalog.dart';
import '../domain/models/leaderboard_read_model.dart';
import '../domain/repositories/leaderboard_repository.dart';

abstract interface class LeaderboardDocumentReader {
  Future<Map<String, Object?>?> readCurrentPeriod();

  Future<Map<String, Object?>?> readCurrentView({required String uid});

  Future<Map<String, Object?>?> readProfile({required String uid});

  Future<Map<String, Object?>?> readSnapshot({required String snapshotId});

  Future<Map<String, Object?>?> readRank({required String rankId});
}

abstract interface class LiveLeaderboardDocumentReader
    implements LeaderboardDocumentReader {
  Stream<void> watchLeaderboardDocuments({required String uid});
}

class FirestoreLeaderboardDocumentReader
    implements LiveLeaderboardDocumentReader {
  FirestoreLeaderboardDocumentReader({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<Map<String, Object?>?> readCurrentPeriod() {
    return _readDocument('leaderboardPeriods/monthly_current');
  }

  @override
  Future<Map<String, Object?>?> readCurrentView({required String uid}) {
    return _readDocument('leaderboardCurrentViews/$uid');
  }

  @override
  Future<Map<String, Object?>?> readProfile({required String uid}) {
    return _readDocument('userProfiles/$uid');
  }

  @override
  Future<Map<String, Object?>?> readRank({required String rankId}) {
    return _readDocument('leaderboardUserRanks/$rankId');
  }

  @override
  Future<Map<String, Object?>?> readSnapshot({required String snapshotId}) {
    return _readDocument('leaderboardSnapshots/$snapshotId');
  }

  Future<Map<String, Object?>?> _readDocument(String path) async {
    final snapshot = await _firestore.doc(path).get();
    final data = snapshot.data();
    return data == null ? null : Map<String, Object?>.from(data);
  }

  @override
  Stream<void> watchLeaderboardDocuments({required String uid}) {
    late StreamController<void> controller;
    final subscriptions = <StreamSubscription<DocumentSnapshot<Object?>>>[];
    controller = StreamController<void>(
      onListen: () {
        void notify(DocumentSnapshot<Object?> _) => controller.add(null);
        subscriptions.addAll([
          _firestore
              .doc('leaderboardPeriods/monthly_current')
              .snapshots()
              .listen(notify),
          _firestore
              .doc('leaderboardCurrentViews/$uid')
              .snapshots()
              .listen(notify),
          _firestore.doc('userProfiles/$uid').snapshots().listen(notify),
        ]);
      },
      onCancel: () async {
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );
      },
    );
    return controller.stream;
  }
}

class FirestoreLeaderboardRepository
    implements LeaderboardRepository, LiveLeaderboardRepository {
  FirestoreLeaderboardRepository({
    required this.authRepository,
    LeaderboardDocumentReader? reader,
  }) : _reader = reader ?? FirestoreLeaderboardDocumentReader();

  final RuniacAuthRepository authRepository;
  final LeaderboardDocumentReader _reader;

  @override
  Future<LeaderboardReadModel> loadLeaderboard() {
    return _load();
  }

  @override
  Future<LeaderboardReadModel> loadRegion({required String regionId}) {
    final area = singaporePlanningAreaForRegionId(regionId);
    if (area == null) {
      throw ArgumentError.value(regionId, 'regionId', 'Unsupported region');
    }
    return _load(selectedRegionId: area.regionId);
  }

  @override
  Stream<LeaderboardReadModel> watchLeaderboard() {
    final currentUser = authRepository.currentUser;
    final reader = _reader;
    if (currentUser == null || reader is! LiveLeaderboardDocumentReader) {
      return Stream.fromFuture(loadLeaderboard());
    }
    return reader
        .watchLeaderboardDocuments(uid: currentUser.uid)
        .asyncMap((_) => loadLeaderboard());
  }

  Future<LeaderboardReadModel> _load({String? selectedRegionId}) async {
    final currentUser = authRepository.currentUser;
    if (currentUser == null) {
      throw StateError('Authentication is required to load Leaderboard.');
    }
    final documents = await Future.wait([
      _reader.readCurrentPeriod(),
      _reader.readCurrentView(uid: currentUser.uid),
      _reader.readProfile(uid: currentUser.uid),
    ]);
    final period = documents[0];
    final currentView = documents[1];
    final profile = documents[2];
    final homeArea =
        singaporePlanningAreaForRegionId(
          _firstString([
            currentView?['homeRegionId'],
            currentView?['regionId'],
          ]),
        ) ??
        singaporePlanningAreaForLocationLabel(
          _string(profile?['locationLabel']),
        );
    if (homeArea == null) {
      return LeaderboardReadModel(
        status: LeaderboardReadStatus.regionRequired,
        regionLabel: '',
        currentRunnerRankLabel: '',
        entries: const [],
      );
    }
    final selectedArea =
        singaporePlanningAreaForRegionId(
          selectedRegionId ?? homeArea.regionId,
        ) ??
        homeArea;
    final league =
        leaderboardLeagueForKey(
          _firstString([currentView?['divisionKey'], profile?['divisionKey']]),
        ) ??
        leaderboardLeagueDefinitions.first;
    final periodKey = _string(period?['periodKey']);
    final periodLabel = _stringOrNull(period?['periodLabel']);
    final periodEndsAt = _dateTimeOrNull(period?['refreshesAt']);
    if (periodKey.isEmpty) {
      return LeaderboardReadModel(
        status: LeaderboardReadStatus.updating,
        regionId: selectedArea.regionId,
        homeRegionId: homeArea.regionId,
        regionLabel: selectedArea.regionName,
        divisionKey: league.key,
        divisionLabel: league.label,
        isHomeRegion: selectedArea.regionId == homeArea.regionId,
        currentRunnerRankLabel: '',
        entries: const [],
        periodLabel: periodLabel,
        periodEndsAt: periodEndsAt,
      );
    }
    final isHomeRegion = selectedArea.regionId == homeArea.regionId;
    final deterministicSnapshotId =
        'monthly_${selectedArea.regionId}_${league.key}_$periodKey';
    final activeSnapshotId = isHomeRegion
        ? _firstString([
            currentView?['activeSnapshotId'],
            currentView?['snapshotId'],
          ])
        : '';
    final snapshotId = activeSnapshotId.isEmpty
        ? deterministicSnapshotId
        : activeSnapshotId;
    final rankId = isHomeRegion
        ? _firstString([
            currentView?['activeRankProjectionId'],
            currentView?['rankId'],
          ])
        : '';
    final loaded = await Future.wait([
      _reader.readSnapshot(snapshotId: snapshotId),
      rankId.isEmpty ? Future.value(null) : _reader.readRank(rankId: rankId),
    ]);
    final snapshot = loaded[0];
    final rank = loaded[1];
    final currentEntry = _map(rank?['currentEntry']);
    // Each row carries the board and build of the document it came from, and
    // never the board-level ones. The refresh job rewrites snapshots, rank
    // projections, and current views in separate batches, so a single load can
    // legitimately see any mix of them: a new snapshot beside an old rank
    // projection, or a stale `activeSnapshotId` beside a rank projection that
    // has already moved to another division. Either mismatch, paired up, would
    // resolve a public profile against a rank some other runner now holds.
    final topEntries = _rowsFromList(
      snapshot?['topEntries'],
      currentEntry: currentEntry,
      snapshotId: snapshotId,
      buildId: _string(snapshot?['buildId']),
    );
    final nearbyEntries = _rowsFromList(
      rank?['nearbyEntries'],
      currentEntry: currentEntry,
      snapshotId: _string(rank?['snapshotId']),
      buildId: _string(rank?['buildId']),
    );
    final currentRankLabel = _string(rank?['rankLabel']);
    final backendStatus = currentView == null
        ? LeaderboardReadStatus.unranked
        : _status(currentView['status']);
    final status = selectedRegionId != null && !isHomeRegion
        ? (topEntries.isEmpty
              ? LeaderboardReadStatus.empty
              : LeaderboardReadStatus.data)
        : backendStatus == LeaderboardReadStatus.data && topEntries.isEmpty
        ? LeaderboardReadStatus.unranked
        : backendStatus;
    return LeaderboardReadModel(
      status: status,
      regionId: selectedArea.regionId,
      homeRegionId: homeArea.regionId,
      regionLabel: selectedArea.regionName,
      divisionKey: league.key,
      divisionLabel: _string(snapshot?['divisionLabel']).isEmpty
          ? league.label
          : _string(snapshot?['divisionLabel']),
      isHomeRegion: isHomeRegion,
      currentRunnerRankLabel: currentRankLabel,
      entries: topEntries,
      nearbyEntries: _withCurrentEntry(
        nearbyEntries,
        currentEntry: currentEntry,
        snapshotId: _string(rank?['snapshotId']),
        buildId: _string(rank?['buildId']),
      ),
      periodEndsAt: periodEndsAt,
      periodLabel: periodLabel,
    );
  }

  List<LeaderboardRowReadModel> _rowsFromList(
    Object? value, {
    required Map<Object?, Object?>? currentEntry,
    required String snapshotId,
    required String buildId,
  }) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final rawEntry in value)
        if (_map(rawEntry) case final entry?)
          LeaderboardRowReadModel(
            userId: '',
            displayName: _string(entry['publicAlias']).isEmpty
                ? 'Runiac Runner'
                : _string(entry['publicAlias']),
            rankLabel: _string(entry['rankLabel']),
            scoreLabel: _string(entry['scoreLabel']),
            levelLabel: _string(entry['levelLabel']),
            divisionLabel: _string(entry['divisionLabel']),
            regionLabel: _string(entry['regionLabel']),
            avatarUrl: _string(entry['avatarUrl']),
            levelProgressFraction: _progressFraction(
              entry['levelProgressPercent'],
            ),
            isCurrentUser:
                currentEntry != null &&
                _string(entry['rankLabel']) ==
                    _string(currentEntry['rankLabel']) &&
                _string(entry['publicAlias']) ==
                    _string(currentEntry['publicAlias']),
            snapshotId: snapshotId,
            buildId: buildId,
          ),
    ];
  }

  List<LeaderboardRowReadModel> _withCurrentEntry(
    List<LeaderboardRowReadModel> entries, {
    required Map<Object?, Object?>? currentEntry,
    required String snapshotId,
    required String buildId,
  }) {
    if (currentEntry == null || entries.any((entry) => entry.isCurrentUser)) {
      return entries;
    }
    return [
      ...entries,
      LeaderboardRowReadModel(
        userId: '',
        displayName: _string(currentEntry['publicAlias']).isEmpty
            ? 'Runiac Runner'
            : _string(currentEntry['publicAlias']),
        rankLabel: _string(currentEntry['rankLabel']),
        scoreLabel: _string(currentEntry['scoreLabel']),
        levelLabel: _string(currentEntry['levelLabel']),
        divisionLabel: _string(currentEntry['divisionLabel']),
        regionLabel: _string(currentEntry['regionLabel']),
        avatarUrl: _string(currentEntry['avatarUrl']),
        levelProgressFraction: _progressFraction(
          currentEntry['levelProgressPercent'],
        ),
        isCurrentUser: true,
        snapshotId: snapshotId,
        buildId: buildId,
      ),
    ];
  }

  LeaderboardReadStatus _status(Object? value) {
    return switch (_string(value)) {
      'ranked' => LeaderboardReadStatus.data,
      'unranked' => LeaderboardReadStatus.unranked,
      'region_required' => LeaderboardReadStatus.regionRequired,
      'ineligible_premium' => LeaderboardReadStatus.ineligiblePremium,
      'ineligible_min_runs' => LeaderboardReadStatus.ineligibleMinRuns,
      _ => LeaderboardReadStatus.empty,
    };
  }

  Map<Object?, Object?>? _map(Object? value) {
    return value is Map ? value : null;
  }

  String _string(Object? value) {
    return value is String ? value.trim() : '';
  }

  /// Converts the row's backend-owned 0..100 `levelProgressPercent` into the
  /// 0.0..1.0 the XP ring paints, matching how Friends and Feed rows read the
  /// same backend field. A row published before the backend carried this
  /// field, or any non-numeric value, resolves to 0 — an empty ring, which is
  /// exactly what every leaderboard row drew before.
  double _progressFraction(Object? value) {
    if (value is! num || !value.isFinite) {
      return 0;
    }
    return (value / 100).clamp(0.0, 1.0).toDouble();
  }

  String _firstString(List<Object?> values) {
    for (final value in values) {
      final parsed = _string(value);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }
    return '';
  }

  String? _stringOrNull(Object? value) {
    final parsed = _string(value);
    return parsed.isEmpty ? null : parsed;
  }

  DateTime? _dateTimeOrNull(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return value is String ? DateTime.tryParse(value) : null;
  }
}
