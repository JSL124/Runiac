part of 'xp_update_screen.dart';

class _XpStage {
  const _XpStage({required this.t, required this.model});

  final double t;
  final XpUpdateDisplayModel model;

  double _iv(double a, double b, [Curve curve = Curves.linear]) {
    return Interval(a, b, curve: curve).transform(t);
  }

  double get entrance => _iv(0.0, 0.15, Curves.easeOut);
  double get confetti => _iv(0.10, 0.45, Curves.easeOut);
  double get earned => _iv(0.15, 0.55, Curves.easeOutCubic);
  double get earnedPop => math.sin(_iv(0.42, 0.58, Curves.easeInOut) * math.pi);
  double get ring => _iv(0.45, 0.85, Curves.easeInOutCubic);
  double get total => _iv(0.70, 1.0, Curves.easeOutCubic);
  double get streakTick => _iv(0.72, 0.95, Curves.easeOut);
  double get streakPulse =>
      math.sin(_iv(0.78, 0.96, Curves.easeInOut) * math.pi);

  int get earnedXpShown => _lerp(0, model.earnedXp.toDouble(), earned).round();
  int get totalXpShown => _lerp(
    model.previousTotalXp.toDouble(),
    model.totalXp.toDouble(),
    total,
  ).round();

  /// Ring / bar fill fraction. Level-up fills to full then restarts into the
  /// new level's remainder inside the same fill window.
  double get progressFraction {
    final prev = model.previousProgressFraction;
    final cur = model.currentProgressFraction;
    if (!model.didLevelUp) {
      return _lerp(prev, cur, ring);
    }
    if (ring < 0.6) {
      return _lerp(prev, 1.0, ring / 0.6);
    }
    return _lerp(0.0, cur, (ring - 0.6) / 0.4);
  }

  bool get showNewLevelBadge => model.didLevelUp && ring >= 0.6;

  double get levelBadgeScale {
    if (!model.didLevelUp || ring < 0.6) {
      return 1;
    }
    final p = ((ring - 0.6) / 0.4).clamp(0.0, 1.0);
    return 1 + 0.22 * math.sin(p * math.pi);
  }

  double get levelUpChipOpacity {
    if (!model.didLevelUp) {
      return 0;
    }
    return ((ring - 0.6) / 0.18).clamp(0.0, 1.0);
  }
}
