import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';

class LeaderboardVisualCta extends StatelessWidget {
  const LeaderboardVisualCta({
    super.key,
    required this.label,
    required this.filled,
    this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            height: 36,
            decoration: BoxDecoration(
              color: filled ? RuniacColors.textPrimary : RuniacColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: filled
                    ? RuniacColors.textPrimary
                    : RuniacColors.textSecondary.withValues(alpha: 0.48),
              ),
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: filled ? RuniacColors.white : RuniacColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
