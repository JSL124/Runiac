import 'package:flutter/material.dart';

/// Paints the dimmed screen scrim with a cut-out spotlight hole for the app
/// tour overlay.
///
/// Purely presentational: it never measures widgets or owns tour state, it
/// only draws the [hole] rectangle it is given, dimming everything else with
/// [dimColor] and outlining the cut-out with a thin [ringColor] ring.
class SpotlightScrimPainter extends CustomPainter {
  const SpotlightScrimPainter({
    required this.hole,
    required this.holeRadius,
    required this.dimColor,
    required this.ringColor,
    this.ringOpacity = 1,
  });

  /// The spotlight cut-out, in the painter's local (canvas) coordinates.
  /// `null` means no hole: the whole canvas is dimmed.
  final Rect? hole;

  /// Corner radius used to round the cut-out.
  final double holeRadius;

  /// Fill colour for the dimmed area surrounding the hole.
  final Color dimColor;

  /// Stroke colour for the thin ring drawn around the hole.
  final Color ringColor;

  /// Opacity multiplier applied to [ringColor] when stroking the ring.
  final double ringOpacity;

  static const double _ringStrokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = dimColor;
    final screenRect = Offset.zero & size;
    final hole = this.hole;

    if (hole == null) {
      canvas.drawRect(screenRect, dimPaint);
      return;
    }

    final rrect = RRect.fromRectAndRadius(hole, Radius.circular(holeRadius));
    final scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(screenRect),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(scrimPath, dimPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStrokeWidth
      ..color = ringColor.withValues(
        alpha: (ringColor.a * ringOpacity).clamp(0.0, 1.0),
      );
    canvas.drawRRect(rrect, ringPaint);
  }

  @override
  bool shouldRepaint(covariant SpotlightScrimPainter oldDelegate) {
    return hole != oldDelegate.hole ||
        holeRadius != oldDelegate.holeRadius ||
        dimColor != oldDelegate.dimColor ||
        ringColor != oldDelegate.ringColor ||
        ringOpacity != oldDelegate.ringOpacity;
  }
}
