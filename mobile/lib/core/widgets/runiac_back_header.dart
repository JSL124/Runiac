import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';

class RuniacBackHeader extends StatelessWidget {
  const RuniacBackHeader({
    required this.title,
    this.onBack,
    this.tooltip = 'Back',
    this.subtitle,
    this.trailing,
    this.titleKey,
    this.titleStyle,
    this.subtitleStyle,
    this.titleMaxLines = 1,
    this.titleOverflow = TextOverflow.ellipsis,
    this.scaleTitleToFit = false,
    this.height = 56,
    this.trailingWidth = 48,
    super.key,
  });

  final String title;
  final VoidCallback? onBack;
  final String tooltip;
  final String? subtitle;
  final Widget? trailing;
  final Key? titleKey;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final int titleMaxLines;
  final TextOverflow titleOverflow;
  final bool scaleTitleToFit;
  final double height;
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    final actionSlotWidth = trailing == null ? 48.0 : trailingWidth;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SizedBox(
              width: actionSlotWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  label: tooltip,
                  button: true,
                  child: IconButton(
                    tooltip: tooltip,
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: RuniacColors.primaryBlue,
                      size: 30,
                    ),
                    onPressed: onBack ?? () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _RuniacBackHeaderTitle(
                title: title,
                subtitle: subtitle,
                titleKey: titleKey,
                titleStyle: titleStyle,
                subtitleStyle: subtitleStyle,
                titleMaxLines: titleMaxLines,
                titleOverflow: titleOverflow,
                scaleTitleToFit: scaleTitleToFit,
              ),
            ),
            SizedBox(
              width: actionSlotWidth,
              child: trailing == null
                  ? null
                  : Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuniacBackHeaderTitle extends StatelessWidget {
  const _RuniacBackHeaderTitle({
    required this.title,
    required this.subtitle,
    required this.titleKey,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.titleMaxLines,
    required this.titleOverflow,
    required this.scaleTitleToFit,
  });

  final String title;
  final String? subtitle;
  final Key? titleKey;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final int titleMaxLines;
  final TextOverflow titleOverflow;
  final bool scaleTitleToFit;

  @override
  Widget build(BuildContext context) {
    final effectiveTitleStyle = titleStyle ?? _defaultTitleStyle;
    final subtitle = this.subtitle;

    if (subtitle == null) {
      return Center(child: _titleText(effectiveTitleStyle));
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _titleText(effectiveTitleStyle),
        const SizedBox(height: 1),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: subtitleStyle ?? _defaultSubtitleStyle,
        ),
      ],
    );
  }

  Widget _titleText(TextStyle effectiveTitleStyle) {
    final text = Text(
      title,
      key: titleKey,
      textAlign: TextAlign.center,
      maxLines: titleMaxLines,
      overflow: scaleTitleToFit ? null : titleOverflow,
      style: effectiveTitleStyle,
    );
    if (!scaleTitleToFit) {
      return text;
    }
    return SizedBox(
      height: 19,
      child: FittedBox(fit: BoxFit.scaleDown, child: text),
    );
  }
}

const _defaultTitleStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 16,
  fontWeight: FontWeight.w900,
);

const _defaultSubtitleStyle = TextStyle(
  color: RuniacColors.textSecondary,
  fontSize: 12.5,
  fontWeight: FontWeight.w600,
  height: 1.15,
);
