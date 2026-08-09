/// Honest render state for the post-run XP & Streak surface.
///
/// The client never calculates progression. It only renders values the backend
/// returns, and this discriminator keeps the celebration honest: full XP
/// choreography only for [awarded], supportive copy for [notAwarded] and
/// [deferred].
enum XpAwardState { awarded, notAwarded, deferred, syncPending }

class XpUpdateDisplayModel {
  const XpUpdateDisplayModel({
    required this.runnerName,
    required this.earnedXpLabel,
    required this.totalXpLabel,
    required this.levelLabel,
    required this.nextLevelLabel,
    required this.progressTargetLabel,
    required this.xpRemainingLabel,
    required this.previousProgressFraction,
    required this.currentProgressFraction,
    required this.streakChangeLabel,
    required this.streakNote,
    required this.didLevelUp,
    this.xpAwardState = XpAwardState.deferred,
    this.heroMessage = '',
    this.earnedXp = 0,
    this.totalXp = 0,
    this.previousTotalXp = 0,
    this.level = 0,
    this.previousLevel = 0,
    this.streakCount = 0,
    this.previousStreakCount = 0,
  });

  final String runnerName;
  final String earnedXpLabel;
  final String totalXpLabel;
  final String levelLabel;
  final String nextLevelLabel;
  final String progressTargetLabel;
  final String xpRemainingLabel;
  final double previousProgressFraction;
  final double currentProgressFraction;
  final String streakChangeLabel;
  final String streakNote;
  final bool didLevelUp;

  /// Which honest render mode the screen should use.
  final XpAwardState xpAwardState;

  /// Supportive subtitle rendered under the hero. Carries the friendly reason
  /// line for [XpAwardState.notAwarded] / [XpAwardState.deferred] states.
  final String heroMessage;

  /// Backend-owned numeric values used for count-up choreography. These are
  /// only display copies of trusted values; the client never derives them.
  final int earnedXp;
  final int totalXp;
  final int previousTotalXp;
  final int level;
  final int previousLevel;
  final int streakCount;
  final int previousStreakCount;

  bool get isAwarded => xpAwardState == XpAwardState.awarded;
}
