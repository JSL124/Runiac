import '../domain/models/leaderboard_read_model.dart';
import '../domain/repositories/leaderboard_repository.dart';
import '../presentation/data/leaderboard_demo_snapshots.dart';
import '../presentation/models/leaderboard_display_models.dart';

class StaticLeaderboardRepository implements LeaderboardRepository {
  const StaticLeaderboardRepository();

  @override
  Future<LeaderboardReadModel> loadLeaderboard() async {
    return LeaderboardReadModel(
      regionId: leaderboardDetailDemoSnapshot.regionId,
      homeRegionId: leaderboardDetailDemoSnapshot.regionId,
      regionLabel: leaderboardDetailDemoSnapshot.regionName,
      divisionKey: 'tier_02',
      divisionLabel: leaderboardDetailDemoSnapshot.divisionLabel,
      currentRunnerRankLabel:
          leaderboardDetailDemoSnapshot.currentUser.rankLabel,
      entries: _rowsFromDisplaySnapshots(
        leaderboardDetailDemoSnapshot.topRanks,
      ),
      nearbyEntries: _rowsFromDisplaySnapshots(
        leaderboardDetailDemoSnapshot.nearbyRanks,
      ),
      periodLabel: leaderboardDetailDemoSnapshot.periodLabel,
      // A real period end anchors the live refresh countdown so the demo board
      // ticks down in real time; leaving refreshLabel null selects the derived
      // live label instead of a frozen static string.
      periodEndsAt: _monthlyPeriodEnd(DateTime.now()),
    );
  }

  @override
  Future<LeaderboardReadModel> loadRegion({required String regionId}) async {
    final snapshot = leaderboardRegionRankingSnapshotById(regionId);
    return LeaderboardReadModel(
      regionId: snapshot.regionId,
      homeRegionId: leaderboardDetailDemoSnapshot.regionId,
      regionLabel: snapshot.regionName,
      divisionKey: 'tier_02',
      divisionLabel: snapshot.divisionLabel,
      isHomeRegion: snapshot.isUserRegion,
      currentRunnerRankLabel: snapshot.isUserRegion
          ? snapshot.currentUser.rankLabel
          : '',
      entries: _rowsFromDisplaySnapshots(snapshot.topRanks),
      nearbyEntries: _rowsFromDisplaySnapshots(snapshot.nearbyRanks),
      periodLabel: snapshot.periodLabel,
      periodEndsAt: _monthlyPeriodEnd(DateTime.now()),
    );
  }
}

/// Start of the next calendar month in local time — the instant the monthly
/// board resets. Used only to drive the demo live countdown.
DateTime _monthlyPeriodEnd(DateTime now) {
  return DateTime(now.year, now.month + 1, 1);
}

List<LeaderboardRowReadModel> _rowsFromDisplaySnapshots(
  List<LeaderboardRankRowDisplaySnapshot> snapshots,
) {
  return [
    for (final snapshot in snapshots)
      LeaderboardRowReadModel(
        userId: _userIdFromDisplayName(snapshot.name),
        displayName: snapshot.name,
        rankLabel: snapshot.rankLabel,
        scoreLabel: snapshot.xpLabel,
        levelLabel: snapshot.levelLabel,
        divisionLabel: leaderboardDetailDemoSnapshot.divisionLabel,
        regionLabel: leaderboardDetailDemoSnapshot.regionName,
        isCurrentUser: snapshot.isCurrentUser,
      ),
  ];
}

String _userIdFromDisplayName(String displayName) {
  final normalized = displayName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'leaderboard-$normalized';
}
