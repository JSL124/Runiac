/// Backend-produced leaderboard display contract.
///
/// Rank, score, XP, monthly XP, level, division, and region values are
/// read-only backend outputs for the Flutter client.
enum LeaderboardReadStatus {
  data,
  empty,
  unranked,
  regionRequired,
  ineligiblePremium,
  ineligibleMinRuns,
  updating,
}

class LeaderboardReadModel {
  LeaderboardReadModel({
    this.status = LeaderboardReadStatus.data,
    this.regionId = '',
    this.homeRegionId = '',
    required this.regionLabel,
    this.divisionKey = 'tier_01',
    this.divisionLabel = 'Iron League',
    this.isHomeRegion = true,
    required this.currentRunnerRankLabel,
    required List<LeaderboardRowReadModel> entries,
    List<LeaderboardRowReadModel> nearbyEntries =
        const <LeaderboardRowReadModel>[],
    this.periodEndsAt,
    this.periodLabel,
    this.refreshLabel,
  }) : entries = List.unmodifiable(entries),
       nearbyEntries = List.unmodifiable(nearbyEntries);

  final LeaderboardReadStatus status;
  final String regionId;
  final String homeRegionId;
  final String regionLabel;
  final String divisionKey;
  final String divisionLabel;
  final bool isHomeRegion;
  final String currentRunnerRankLabel;
  final List<LeaderboardRowReadModel> entries;
  final List<LeaderboardRowReadModel> nearbyEntries;
  final DateTime? periodEndsAt;
  final String? periodLabel;
  final String? refreshLabel;
}

/// Backend-produced leaderboard row display contract.
class LeaderboardRowReadModel {
  const LeaderboardRowReadModel({
    required this.userId,
    required this.displayName,
    required this.rankLabel,
    required this.scoreLabel,
    this.levelLabel = '',
    this.divisionLabel = '',
    this.regionLabel = '',
    this.isCurrentUser = false,
    this.snapshotId = '',
    this.buildId = '',
    this.avatarUrl = '',
    this.levelProgressFraction = 0,
  });

  final String userId;
  final String displayName;
  final String rankLabel;
  final String scoreLabel;
  final String levelLabel;
  final String divisionLabel;
  final String regionLabel;
  final bool isCurrentUser;

  /// Raw, not-yet-sanitised avatar photo URL relayed from the snapshot/rank
  /// row (`entry['avatarUrl']`). Empty when the runner has no photo set.
  final String avatarUrl;

  /// Backend-owned progress toward the next level, already converted from the
  /// row's 0..100 `levelProgressPercent` into 0.0..1.0 and clamped. Drives the
  /// XP ring around the row's avatar. Never computed on the client: it is not
  /// derived from [scoreLabel], and `0` (an empty ring) is what a row written
  /// before the backend published this field resolves to.
  final double levelProgressFraction;

  /// The board this row was read from, taken from its own source document —
  /// the snapshot for a top row, the rank projection for a nearby row. A
  /// refresh rewrites those documents (and the current view that names them)
  /// in separate batches, so a board-level id could pair a stale board with a
  /// fresh row.
  final String snapshotId;

  /// Backend-owned id of the aggregation run that produced that same document.
  ///
  /// Together with [rankLabel] these three fields are one self-describing
  /// handle: `getRunnerPublicProfile` resolves the owner from them
  /// server-side, and a row read across a refresh resolves to nobody instead
  /// of to whoever inherited its rank.
  final String buildId;
}
