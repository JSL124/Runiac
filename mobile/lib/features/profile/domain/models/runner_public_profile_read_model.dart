import '../../../challenge/domain/models/challenge_enums.dart';

/// Backend-produced public profile contract for a runner other than the
/// signed-in user, as served by the `getRunnerPublicProfile` callable.
///
/// Every value here is a trusted backend output the client only relays. The
/// client never derives level, XP, streak, distance, division, subscription
/// tier, or badge ownership from anything else.
///
/// Deliberately carries no uid: the backend resolves the runner and keeps
/// their uid, so a caller cannot walk a public board's ranks and collect a
/// uid directory.
class RunnerPublicProfileReadModel {
  const RunnerPublicProfileReadModel({
    this.displayName = '',
    this.avatarInitials = '',
    this.avatarUrl = '',
    this.regionLabel = '',
    this.level = 0,
    this.levelProgressFraction = 0,
    this.totalXp,
    this.nextLevelXp,
    this.xpToNextLevel,
    this.isMaxLevel = false,
    this.divisionKey = '',
    this.divisionLabel = '',
    this.longestStreakLabel = '',
    this.totalDistanceLabel = '',
    this.subscriptionStatusLabel = '',
    this.ownedTierIds = const <ChallengeTierId>{},
    this.statsHidden = false,
  });

  final String displayName;
  final String avatarInitials;

  /// Raw, not-yet-sanitised avatar photo URL relayed from
  /// `getRunnerPublicProfile`. Empty when the runner has no photo set.
  final String avatarUrl;
  final String regionLabel;
  final int level;
  final double levelProgressFraction;
  final int? totalXp;
  final int? nextLevelXp;
  final int? xpToNextLevel;

  /// True only when the backend explicitly reported the max level was reached.
  final bool isMaxLevel;
  final String divisionKey;
  final String divisionLabel;
  final String longestStreakLabel;
  final String totalDistanceLabel;

  /// Trusted Basic/Premium tier label. Display only: it never grants access.
  final String subscriptionStatusLabel;

  /// Challenge tiers this runner has earned a badge for.
  final Set<ChallengeTierId> ownedTierIds;

  /// True when this runner keeps their running record private. The record
  /// fields above then hold their empty values because the backend withheld
  /// them, not because this client chose not to ask: the viewer's device never
  /// receives the hidden figures. This flag exists only so the screen can say
  /// "kept private" instead of drawing a runner who appears to have never run.
  final bool statsHidden;

  String get levelBadgeLabel => 'Lv.$level';
}

/// Raised when a runner's public profile cannot be served — the viewer or the
/// runner blocked the other, the runner is suspended, no profile exists, or
/// the backend was unreachable. Carries a message safe to show as-is.
class RunnerPublicProfileFailure implements Exception {
  const RunnerPublicProfileFailure(this.message);

  final String message;

  @override
  String toString() => 'RunnerPublicProfileFailure($message)';
}
