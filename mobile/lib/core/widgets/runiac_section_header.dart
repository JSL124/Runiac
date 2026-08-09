import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';

class RuniacSectionHeader extends StatelessWidget {
  const RuniacSectionHeader({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = EdgeInsets.zero,
    this.titleStyle,
    this.subtitleStyle,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.leadingSpacing = 8,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final CrossAxisAlignment crossAxisAlignment;
  final double leadingSpacing;

  @override
  Widget build(BuildContext context) {
    final effectiveTitleStyle =
        titleStyle ??
        const TextStyle(
          color: RuniacColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          height: 1.2,
        );
    final effectiveSubtitleStyle =
        subtitleStyle ??
        const TextStyle(
          color: RuniacColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.35,
        );

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          if (leading != null) ...[leading!, SizedBox(width: leadingSpacing)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: effectiveTitleStyle),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: effectiveSubtitleStyle),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
