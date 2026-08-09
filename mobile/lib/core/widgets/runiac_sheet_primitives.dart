import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';
import '../../features/you/presentation/widgets/you_surface_primitives.dart';
import 'runiac_buttons.dart';

/// One tappable action row inside a [RuniacSheetScaffold]: a tinted icon
/// medallion, a title/caption pair, and a trailing affordance. Extracted from
/// the Friends "..." action sheet so every Runiac action sheet reads the same.
///
/// Visual styling only — the caller owns what [onTap] does. Passing a null
/// [onTap] renders the row as inert (used while a sheet action is in flight),
/// and [trailing] replaces the default chevron so callers can show progress.
class RuniacSheetActionTile extends StatelessWidget {
  const RuniacSheetActionTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
    this.tint = RuniacColors.primaryBlue,
    this.titleColor = RuniacColors.textPrimary,
    this.trailing,
    super.key,
  });

  final IconData icon;

  /// Drives both the icon colour and the medallion's 10% wash behind it.
  final Color tint;
  final Color titleColor;
  final String title;
  final String caption;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: RuniacTappableSurface(
        onTap: onTap,
        height: 56,
        borderRadius: BorderRadius.circular(youInnerRadius),
        decoration: BoxDecoration(
          color: RuniacColors.white,
          borderRadius: BorderRadius.circular(youInnerRadius),
          border: Border.all(color: RuniacColors.cardBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tint, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: YouTextStyles.bodyStrong.copyWith(color: titleColor),
                  ),
                  const SizedBox(height: 2),
                  Text(caption, style: YouTextStyles.smallBody),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  color: RuniacColors.textSecondary,
                ),
          ],
        ),
      ),
    );
  }
}

/// Trailing spinner used by a [RuniacSheetActionTile] whose action is running.
class RuniacSheetTileSpinner extends StatelessWidget {
  const RuniacSheetTileSpinner({
    this.color = RuniacColors.primaryBlue,
    super.key,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// Dismiss row shared by Runiac action sheets.
///
/// `shrinkWrap` + explicit padding: the default 48dp tap-target box would
/// leave a visible band of dead space under the label.
class RuniacSheetCancelButton extends StatelessWidget {
  const RuniacSheetCancelButton({
    this.label = 'Cancel',
    this.enabled = true,
    this.onPressed,
    super.key,
  });

  final String label;

  /// Set false while a sheet action is in flight, so dismissing cannot race it.
  final bool enabled;

  /// Defaults to popping the sheet.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: !enabled
          ? null
          : (onPressed ?? () => Navigator.of(context).pop()),
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(vertical: 11),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: YouTextStyles.bodyStrong),
    );
  }
}

/// Red-tinted banner used inside a sheet to surface a genuine failure.
class RuniacSheetErrorBanner extends StatelessWidget {
  const RuniacSheetErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: RuniacColors.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(youInnerRadius),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: RuniacColors.errorRed,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: RuniacColors.errorRed,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
