import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';

/// Friendly, non-error empty/placeholder card for leaderboard states.
///
/// Display-only. Renders a soft blue-tinted disc, a bold title, and a
/// secondary body line. It never encodes backend-owned rank or score values
/// and carries no error styling. Set [compact] for a tighter layout suitable
/// for a bottom sheet.
class LeaderboardEmptyState extends StatelessWidget {
  const LeaderboardEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.compact = false,
  });

  final String title;
  final String body;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final verticalPadding = compact ? 18.0 : 28.0;
    final discSize = compact ? 54.0 : 72.0;
    final iconSize = compact ? 26.0 : 34.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: verticalPadding),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE3F8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: discSize,
            height: discSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: RuniacColors.primaryBlue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_run_rounded,
              color: RuniacColors.primaryBlue,
              size: iconSize,
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: RuniacColors.textPrimary,
              fontSize: compact ? 15 : 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
