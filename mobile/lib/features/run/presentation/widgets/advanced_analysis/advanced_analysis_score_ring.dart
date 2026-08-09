import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'advanced_analysis_theme.dart';

class AdvancedAnalysisScoreRing extends StatelessWidget {
  const AdvancedAnalysisScoreRing({
    super.key,
    required this.value,
    required this.size,
    required this.stroke,
    required this.color,
    this.percentOnly = false,
    this.valueLabel,
  });

  final int value;
  final double size;
  final double stroke;
  final Color color;
  final bool percentOnly;
  final String? valueLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            painter: _AdvancedAnalysisRingPainter(
              value: value,
              stroke: stroke,
              color: color,
            ),
            child: const SizedBox.expand(),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                valueLabel ?? (percentOnly ? '$value%' : '$value'),
                style: TextStyle(
                  color: advancedAnalysisInk,
                  fontSize: percentOnly ? 20 : 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                ),
              ),
              if (!percentOnly && valueLabel == null)
                const Text(
                  '/ 100',
                  style: TextStyle(
                    color: advancedAnalysisBlue45,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdvancedAnalysisRingPainter extends CustomPainter {
  const _AdvancedAnalysisRingPainter({
    required this.value,
    required this.stroke,
    required this.color,
  });

  final int value;
  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = stroke / 2;
    final arcRect = rect.deflate(inset);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = advancedAnalysisBlue10;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas
      ..drawArc(arcRect, 0, math.pi * 2, false, track)
      ..drawArc(arcRect, -math.pi / 2, math.pi * 2 * value / 100, false, arc);
  }

  @override
  bool shouldRepaint(covariant _AdvancedAnalysisRingPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.stroke != stroke ||
        oldDelegate.color != color;
  }
}
