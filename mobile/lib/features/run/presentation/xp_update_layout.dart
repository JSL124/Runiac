part of 'xp_update_screen.dart';

class _XpLayoutTokens {
  const _XpLayoutTokens({
    required this.ring,
    required this.avatar,
    required this.heroY,
    required this.titleGap,
    required this.xpTopGap,
    required this.xpGainSize,
  });

  factory _XpLayoutTokens.fromCompact(bool compact) {
    if (compact) {
      return const _XpLayoutTokens(
        ring: 92,
        avatar: 68,
        heroY: 14,
        titleGap: 10,
        xpTopGap: 14,
        xpGainSize: 44,
      );
    }

    return const _XpLayoutTokens(
      ring: 110,
      avatar: 82,
      heroY: 18,
      titleGap: 12,
      xpTopGap: 16,
      xpGainSize: 52,
    );
  }

  final double ring;
  final double avatar;
  final double heroY;
  final double titleGap;
  final double xpTopGap;
  final double xpGainSize;
}

/// A single confetti fleck. The burst is deterministic (seeded) so the
/// animation is stable across rebuilds and reproducible in tests.
