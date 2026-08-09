/// The three level-gauge labels, composed from backend-owned progression
/// numbers only. Shared by the signed-in runner's own account screen and the
/// public profile of another runner so both gauges read identically and the
/// formatting rules live in exactly one place.
///
/// This composes labels; it never derives progression. Every input is a value
/// a Cloud Function already computed and published.
class LevelProgressLabels {
  const LevelProgressLabels({
    required this.nextLevelBadge,
    required this.levelUpCaption,
    required this.levelXpSummary,
  });

  static const empty = LevelProgressLabels(
    nextLevelBadge: '',
    levelUpCaption: '',
    levelXpSummary: '',
  );

  final String nextLevelBadge;
  final String levelUpCaption;
  final String levelXpSummary;
}

/// Resolves the gauge labels. [hasProgress] is false while the backend
/// progression read is still unresolved, which blanks every label rather than
/// showing a guessed level or XP figure.
LevelProgressLabels resolveLevelProgressLabels({
  required bool hasProgress,
  required int level,
  required bool isMaxLevel,
  required int? totalXp,
  required int? nextLevelXp,
  required int? xpToNextLevel,
}) {
  if (!hasProgress) {
    return LevelProgressLabels.empty;
  }
  return LevelProgressLabels(
    nextLevelBadge: isMaxLevel ? '' : 'Lv.${level + 1}',
    levelUpCaption: _levelUpCaption(
      isMaxLevel: isMaxLevel,
      xpToNextLevel: xpToNextLevel,
    ),
    levelXpSummary: _levelXpSummary(
      isMaxLevel: isMaxLevel,
      totalXp: totalXp,
      nextLevelXp: nextLevelXp,
    ),
  );
}

// Displays the backend-owned XP-to-next-level value only; the client never
// derives it from other XP fields.
String _levelUpCaption({
  required bool isMaxLevel,
  required int? xpToNextLevel,
}) {
  if (isMaxLevel) {
    return 'Max level reached';
  }
  if (xpToNextLevel == null) {
    return '';
  }
  return '${formatXpThousands(xpToNextLevel)} XP to level up';
}

// Joins the backend-owned lifetime XP total and next-level XP target;
// the client never derives either value.
String _levelXpSummary({
  required bool isMaxLevel,
  required int? totalXp,
  required int? nextLevelXp,
}) {
  if (totalXp == null) {
    return '';
  }
  if (isMaxLevel) {
    return '${formatXpThousands(totalXp)} XP';
  }
  if (nextLevelXp == null) {
    return '';
  }
  return '${formatXpThousands(totalXp)} / ${formatXpThousands(nextLevelXp)} XP';
}

String formatXpThousands(int value) {
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
