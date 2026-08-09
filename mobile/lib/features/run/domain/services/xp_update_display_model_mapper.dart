import '../models/progression_display_model.dart';
import '../models/xp_update_display_model.dart';

/// Builds the XP & Streak display model purely from backend-owned
/// progression values. The client never calculates XP, level, streak, or
/// progress fractions; fractions are backend percents divided by 100.
///
/// This mapper is shared by every code path that turns a
/// [ProgressionDisplayModel] into renderable copy: the run-completion
/// response, the cool-down XP bonus response, and the merged result produced
/// when a cool-down bonus is folded into a run's progression display.
class XpUpdateDisplayModelMapper {
  const XpUpdateDisplayModelMapper._();

  static XpUpdateDisplayModel fromProgression(
    ProgressionDisplayModel progression,
  ) {
    const runnerName = 'Runiac Runner';
    final status = progression.status;
    final reason = progression.reason;
    final xpDelta = progression.xpDelta;
    final totalXpValue = progression.totalXp;
    final previousTotalXpValue = progression.previousTotalXp;
    final hasProgressionNumbers =
        totalXpValue != null && previousTotalXpValue != null;

    if (status == 'deferred' || !hasProgressionNumbers) {
      return const XpUpdateDisplayModel(
        runnerName: runnerName,
        earnedXpLabel: '+0 XP',
        totalXpLabel: 'Saved',
        levelLabel: '--',
        nextLevelLabel: '--',
        progressTargetLabel: 'Progression pending',
        xpRemainingLabel: 'Finalizing',
        previousProgressFraction: 0,
        currentProgressFraction: 0,
        streakChangeLabel: 'Streak saved',
        streakNote: 'Saved',
        didLevelUp: false,
        xpAwardState: XpAwardState.deferred,
        heroMessage: 'This run is saved. XP is being finalized.',
      );
    }

    final totalXp = totalXpValue;
    final previousTotalXp = previousTotalXpValue;
    final level = progression.level ?? 0;
    final previousLevel = progression.previousLevel ?? level;
    final previousPercent = progression.previousLevelProgressPercent ?? 0;
    final currentPercent = progression.levelProgressPercent ?? 0;
    final streak = progression.streak ?? 0;
    final previousStreak = progression.previousStreak ?? streak;
    final xpToNextLevel = progression.xpToNextLevel;
    final isMaxLevel = xpToNextLevel == null;
    final didLevelUp = level > previousLevel;
    final awarded = status == 'awarded' && xpDelta > 0;
    final nextLevel = level + 1;

    return XpUpdateDisplayModel(
      runnerName: runnerName,
      earnedXpLabel: '+${_formatThousands(xpDelta)} XP',
      totalXpLabel: '${_formatThousands(totalXp)} XP',
      levelLabel: '$level',
      nextLevelLabel: isMaxLevel ? '$level' : '$nextLevel',
      progressTargetLabel: isMaxLevel
          ? 'Max level reached'
          : 'Progress to Level $nextLevel',
      xpRemainingLabel: isMaxLevel
          ? 'Max level reached'
          : '${_formatThousands(xpToNextLevel)} XP to Level $nextLevel',
      previousProgressFraction: previousPercent / 100.0,
      currentProgressFraction: currentPercent / 100.0,
      streakChangeLabel: _streakChangeLabel(previousStreak, streak),
      streakNote: streak > previousStreak ? 'Keep it going' : 'Nice work',
      didLevelUp: didLevelUp,
      xpAwardState: awarded ? XpAwardState.awarded : XpAwardState.notAwarded,
      heroMessage: awarded
          ? (didLevelUp
                ? 'You reached Level $level. Keep it up.'
                : 'Earned from this run')
          : _notAwardedMessage(reason),
      earnedXp: xpDelta,
      totalXp: totalXp,
      previousTotalXp: previousTotalXp,
      level: level,
      previousLevel: previousLevel,
      streakCount: streak,
      previousStreakCount: previousStreak,
    );
  }

  static String _streakChangeLabel(int previousStreak, int streak) {
    if (streak <= 0) {
      return 'Streak saved';
    }
    final unit = streak == 1 ? 'day' : 'days';
    if (streak > previousStreak) {
      return '$previousStreak → $streak $unit';
    }
    return '$streak $unit';
  }

  static String _notAwardedMessage(String reason) {
    switch (reason) {
      case 'low_data_no_xp':
        return 'Run a little longer to earn XP';
      case 'daily_cap_reached':
      case 'cool_down_daily_cap_reached':
        return 'Daily XP cap reached — great effort today';
      case 'premium_no_progression':
        return 'Premium runs stay off the XP board — enjoy the run';
      default:
        return 'This run didn\'t earn XP';
    }
  }

  static String _formatThousands(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index += 1) {
      if (index != 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return '${value < 0 ? '-' : ''}$buffer';
  }
}
