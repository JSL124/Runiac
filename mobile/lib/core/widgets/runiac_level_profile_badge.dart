import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';
import 'runiac_avatar_photo.dart';

class RuniacLevelProfileBadge extends StatelessWidget {
  const RuniacLevelProfileBadge({
    required this.initials,
    required this.levelLabel,
    required this.progressFraction,
    this.size = 96,
    this.badgeHeight = 30,
    this.badgeMinWidth = 72,
    this.badgeHorizontalPadding = 13,
    this.badgeFontSize = 13,
    this.ringStrokeWidth,
    this.discColor,
    this.discBorderColor,
    this.initialsColor,
    this.photoUrl,
    super.key,
  });

  /// Preset sizing for the compact avatar+ring+pill badge used inline in a
  /// list row (Friends, Feed author/comment rows, challenge invite picker and
  /// lobby roster rows, etc.). Only identity, progress, and the current-user
  /// highlight colors vary per call site — keeping the row geometry here in
  /// one place means every row-style usage renders identically and stays in
  /// sync when the preset changes.
  const RuniacLevelProfileBadge.row({
    required this.initials,
    required this.levelLabel,
    required this.progressFraction,
    this.size = 42,
    this.discColor = RuniacColors.primaryBlue,
    this.discBorderColor = RuniacColors.white,
    this.initialsColor = RuniacColors.white,
    this.photoUrl,
    super.key,
  })  : badgeHeight = 16,
        badgeMinWidth = 42,
        badgeHorizontalPadding = 6,
        badgeFontSize = 9,
        ringStrokeWidth = 4;

  final String initials;
  final String levelLabel;
  final double progressFraction;
  final double size;
  final double badgeHeight;
  final double badgeMinWidth;
  final double badgeHorizontalPadding;
  final double badgeFontSize;
  final double? ringStrokeWidth;
  final Color? discColor;
  final Color? discBorderColor;
  final Color? initialsColor;

  /// Raw, not-yet-sanitised avatar photo URL. Renders the initials disc
  /// when absent, when it fails the client-side sanitiser in
  /// `runiac_avatar_photo.dart`, or if the image fails to load.
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final avatarSize = size * 0.74;
    final ringStroke = ringStrokeWidth ?? (size < 80 ? 7.0 : 8.0);
    final badgeTop = size - (badgeHeight * 0.85);
    return Semantics(
      label: levelLabel.isEmpty
          ? 'Runner profile'
          : 'Runner profile $levelLabel',
      button: false,
      child: SizedBox(
        width: size,
        height: size + (badgeHeight * 0.12),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _RuniacLevelRingPainter(
                progress: progressFraction,
                strokeWidth: ringStroke,
              ),
            ),
            Positioned(
              top: (size - avatarSize) / 2,
              child: _ProfileInitialsDisc(
                initials: initials,
                size: avatarSize,
                fontSize: size < 80 ? 24 : 30,
                fillColor:
                    discColor ??
                    RuniacColors.primaryBlue.withValues(alpha: 0.06),
                borderColor:
                    discBorderColor ??
                    RuniacColors.primaryBlue.withValues(alpha: 0.10),
                textColor: initialsColor ?? RuniacColors.primaryBlue,
                photoUrl: photoUrl,
              ),
            ),
            if (levelLabel.isNotEmpty)
              Positioned(
                top: badgeTop,
                child: _LevelPill(
                  label: levelLabel,
                  height: badgeHeight,
                  minWidth: badgeMinWidth,
                  horizontalPadding: badgeHorizontalPadding,
                  fontSize: badgeFontSize,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileInitialsDisc extends StatelessWidget {
  const _ProfileInitialsDisc({
    required this.initials,
    required this.size,
    required this.fontSize,
    required this.fillColor,
    required this.borderColor,
    required this.textColor,
    this.photoUrl,
  });

  final String initials;
  final double size;
  final double fontSize;
  final Color fillColor;
  final Color borderColor;
  final Color textColor;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fillColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: RuniacAvatarPhotoDisc(
        photoUrl: photoUrl,
        fallback: Padding(
          padding: EdgeInsets.all(size * 0.10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _initialLabel(initials),
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _initialLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'R';
    }
    return trimmed.characters.take(2).toString().toUpperCase();
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({
    required this.label,
    required this.height,
    required this.minWidth,
    required this.horizontalPadding,
    required this.fontSize,
  });

  final String label;
  final double height;
  final double minWidth;
  final double horizontalPadding;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      constraints: BoxConstraints(minWidth: minWidth),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: RuniacColors.accentOrange,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RuniacColors.accentOrange, width: 2),
        boxShadow: [
          BoxShadow(
            color: RuniacColors.accentOrange.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: RuniacColors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _RuniacLevelRingPainter extends CustomPainter {
  const _RuniacLevelRingPainter({
    required this.progress,
    required this.strokeWidth,
  });

  static const _startAngle = math.pi * 5 / 6;
  static const _sweepAngle = math.pi * 4 / 3;

  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2;
    final trackPaint = Paint()
      ..color = RuniacColors.primaryBlue.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    final progressPaint = Paint()
      ..color = RuniacColors.accentOrange
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    final ringRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(ringRect, _startAngle, _sweepAngle, false, trackPaint);

    final clampedProgress = progress.clamp(0.0, 1.0);
    if (clampedProgress > 0) {
      canvas.drawArc(
        ringRect,
        _startAngle,
        _sweepAngle * clampedProgress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RuniacLevelRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
