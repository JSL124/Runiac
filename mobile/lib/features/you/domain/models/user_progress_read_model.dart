/// Backend-produced user progress display contract.
///
/// XP, streak, level, rank, leaderboard score, and subscription privilege
/// state are backend-owned outputs, not client-side trusted state.
class UserProgressReadModel {
  const UserProgressReadModel({
    required this.userId,
    required this.officialStreakLabel,
    required this.levelLabel,
    required this.totalXpLabel,
    required this.weeklyXpLabel,
    required this.monthlyXpLabel,
    required this.weeklyDistanceLabel,
    required this.goalProgressLabel,
    this.longestStreakLabel = '',
    this.totalDistanceLabel = '',
    this.level = 0,
    this.levelProgressFraction = 0,
    this.totalXp,
    this.nextLevelXp,
    this.xpToNextLevel,
    this.divisionKey = '',
    this.divisionLabel = '',
    this.isMaxLevel = false,
    this.officialStreakCount,
    this.lastStreakRunDate,
  });

  final String userId;
  final String officialStreakLabel;
  final String levelLabel;
  final String totalXpLabel;
  final String weeklyXpLabel;
  final String monthlyXpLabel;
  final String weeklyDistanceLabel;
  final String goalProgressLabel;

  /// Backend-computed longest streak the runner has ever reached, displayed
  /// as-is such as '14 days'. Empty when the backend has not published the
  /// value for this user yet.
  final String longestStreakLabel;

  /// Backend-computed lifetime total distance the runner has run so far,
  /// displayed as-is such as '148.6 km'. Empty when the backend has not
  /// published the value for this user yet.
  final String totalDistanceLabel;
  final int level;
  final double levelProgressFraction;

  /// Backend-computed lifetime XP total, displayed as-is.
  /// `null` when the backend has not published the value for this user yet.
  final int? totalXp;

  /// Backend-computed total XP threshold that unlocks the next level,
  /// displayed as-is. `null` when unpublished or at max level.
  final int? nextLevelXp;

  /// Backend-computed XP remaining before the next level, displayed as-is.
  /// `null` when the backend has not published the value for this user yet.
  final int? xpToNextLevel;

  /// Backend-owned division key used for profile badge display.
  final String divisionKey;

  /// Backend-owned division label used for profile badge display.
  final String divisionLabel;

  /// True only when the backend explicitly reported the max level was reached.
  final bool isMaxLevel;
  final int? officialStreakCount;
  final String? lastStreakRunDate;

  String get levelBadgeLabel => 'Lv.$level';
}
