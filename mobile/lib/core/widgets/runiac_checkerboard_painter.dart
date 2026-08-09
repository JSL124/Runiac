import 'package:flutter/widgets.dart';

/// Draws a light checkerboard, the conventional "transparent background"
/// indicator, behind a transparent share card's components in preview. Used
/// only as the on-screen preview backdrop; it is hidden during PNG capture so
/// the exported image keeps true alpha.
class RuniacCheckerboardPainter extends CustomPainter {
  const RuniacCheckerboardPainter();

  static const double _cell = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFFF4F5F7);
    final dark = Paint()..color = const Color(0xFFD3D7DE);
    canvas.drawRect(Offset.zero & size, light);
    for (var row = 0; row * _cell < size.height; row++) {
      for (var col = 0; col * _cell < size.width; col++) {
        if ((row + col).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(col * _cell, row * _cell, _cell, _cell),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(RuniacCheckerboardPainter oldDelegate) => false;
}
