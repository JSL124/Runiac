class ProgressionDisplayModel {
  const ProgressionDisplayModel({
    required this.xpDelta,
    required this.countsTowardLeaderboard,
    required this.status,
    required this.reason,
    this.totalXp,
    this.level,
    this.divisionKey,
    this.previousTotalXp,
    this.previousLevel,
    this.previousLevelProgressPercent,
    this.levelProgressPercent,
    this.xpToNextLevel,
    this.nextLevelXp,
    this.streak,
    this.previousStreak,
  });

  final int xpDelta;
  final bool countsTowardLeaderboard;
  final String status;
  final String reason;

  /// Optional backend-owned progression numbers. These mirror the fields the
  /// server may include on a `ProgressionDisplay` response (for example after
  /// a run completion or a cool-down XP bonus). The client only displays or
  /// merges these values — it never derives new numbers from them beyond
  /// summing two server-returned deltas or copying server-returned totals.
  final int? totalXp;
  final int? level;
  final String? divisionKey;
  final int? previousTotalXp;
  final int? previousLevel;
  final int? previousLevelProgressPercent;
  final int? levelProgressPercent;
  final int? xpToNextLevel;
  final int? nextLevelXp;
  final int? streak;
  final int? previousStreak;
}
