import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_level_profile_badge.dart';
import '../models/leaderboard_display_models.dart';

({Color background, Color foreground}) resolveRegionPreviewMedalColors(
  RegionPreviewMedalTone tone,
) {
  return switch (tone) {
    RegionPreviewMedalTone.gold => (
      background: const Color(0xFFFFF2E2),
      foreground: RuniacColors.accentOrange,
    ),
    RegionPreviewMedalTone.silver => (
      background: const Color(0xFFEFF3FB),
      foreground: RuniacColors.textSecondary,
    ),
    RegionPreviewMedalTone.bronze => (
      background: const Color(0xFFFFEBDD),
      foreground: const Color(0xFFB56A36),
    ),
  };
}

class LeaderboardInitialBadge extends StatelessWidget {
  const LeaderboardInitialBadge({
    super.key,
    required this.name,
    required this.levelLabel,
    required this.isCurrentUser,
    this.photoUrl = '',
    this.levelProgressFraction = 0,
  });

  final String name;
  final String levelLabel;
  final bool isCurrentUser;

  /// Raw, not-yet-sanitised avatar photo URL for this row. Empty renders the
  /// initials disc.
  final String photoUrl;

  /// Backend-owned progress toward the next level, 0.0..1.0, painted as the XP
  /// ring around the disc. Defaults to 0 (an empty ring) so a caller with no
  /// backend progress on record renders exactly what this badge drew before.
  final double levelProgressFraction;

  static const double _size = 56;
  static const double _levelPillHeight = 18;

  /// Exact painted height of the badge. `RuniacLevelProfileBadge` paints the
  /// ring across `size` and then hangs the level pill below it, starting at
  /// `size - badgeHeight * 0.85`, so the lowest ink is the pill's bottom edge.
  /// Sizing the box to that instead of rounding up matters: the inner stack is
  /// top-aligned, so any spare height would collect entirely below the badge
  /// and the row's symmetric vertical padding would look bottom-heavy.
  static const double _paintedHeight =
      _size - (_levelPillHeight * 0.85) + _levelPillHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('leaderboard_profile_level_badge'),
      width: _size,
      height: _paintedHeight,
      child: RuniacLevelProfileBadge(
        initials: name,
        levelLabel: levelLabel,
        progressFraction: levelProgressFraction,
        photoUrl: photoUrl,
        size: _size,
        badgeHeight: _levelPillHeight,
        badgeMinWidth: isCurrentUser ? 42 : 34,
        badgeHorizontalPadding: 7,
        badgeFontSize: 10,
        ringStrokeWidth: 4.8,
      ),
    );
  }
}
