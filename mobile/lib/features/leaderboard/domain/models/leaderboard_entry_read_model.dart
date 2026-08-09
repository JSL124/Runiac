/// Backend-produced leaderboard row contract.
///
/// Rank, score, XP, weekly/monthly XP, level, and division are backend-owned
/// outputs and must not be calculated or mutated by the Flutter client.
class LeaderboardEntryReadModel {
  const LeaderboardEntryReadModel({
    required this.userId,
    required this.displayName,
    required this.rankLabel,
    required this.scoreLabel,
    required this.levelLabel,
    required this.divisionLabel,
    required this.regionLabel,
  });

  final String userId;
  final String displayName;
  final String rankLabel;
  final String scoreLabel;
  final String levelLabel;
  final String divisionLabel;
  final String regionLabel;
}
