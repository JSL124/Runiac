import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';

class RouteMapPainter extends CustomPainter {
  const RouteMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final gridPaint = Paint()
      ..color = const Color(0xFFE1E7FA)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += size.width / 7) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += size.height / 6) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final roadPaint = Paint()
      ..color = const Color(0xFFC8D3F7)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        Offset(-20, size.height * .18),
        Offset(size.width + 20, size.height * .88),
        roadPaint,
      )
      ..drawLine(
        Offset(size.width * .34, -20),
        Offset(size.width * .65, size.height + 20),
        roadPaint,
      )
      ..drawLine(
        Offset(-20, size.height * .72),
        Offset(size.width + 20, size.height * .18),
        roadPaint,
      );

    final path = Path()
      ..moveTo(size.width * .2, size.height * .75)
      ..cubicTo(
        size.width * .28,
        size.height * .48,
        size.width * .43,
        size.height * .6,
        size.width * .5,
        size.height * .43,
      )
      ..cubicTo(
        size.width * .62,
        size.height * .12,
        size.width * .73,
        size.height * .32,
        size.width * .8,
        size.height * .5,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = RuniacColors.primaryBlue
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    final markerPaint = Paint()..color = RuniacColors.accentOrange;
    final startPaint = Paint()
      ..color = const Color(0xFFF8FAFF)
      ..style = PaintingStyle.fill;
    canvas
      ..drawCircle(
        Offset(size.width * .2, size.height * .75),
        10,
        Paint()..color = RuniacColors.primaryBlue,
      )
      ..drawCircle(Offset(size.width * .2, size.height * .75), 5, startPaint)
      ..drawCircle(Offset(size.width * .5, size.height * .43), 10, markerPaint)
      ..drawCircle(Offset(size.width * .8, size.height * .5), 10, markerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ElevationPainter extends CustomPainter {
  const ElevationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final fillPath = Path()
      ..moveTo(0, size.height * .8)
      ..lineTo(0, size.height * .58)
      ..lineTo(size.width * .14, size.height * .45)
      ..lineTo(size.width * .28, size.height * .54)
      ..lineTo(size.width * .4, size.height * .22)
      ..lineTo(size.width * .53, size.height * .4)
      ..lineTo(size.width * .66, size.height * .15)
      ..lineTo(size.width * .79, size.height * .27)
      ..lineTo(size.width * .92, size.height * .54)
      ..lineTo(size.width, size.height * .46)
      ..lineTo(size.width, size.height * .8)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = const Color(0xFFEFF3FF));

    final linePath = Path()
      ..moveTo(0, size.height * .58)
      ..lineTo(size.width * .14, size.height * .45)
      ..lineTo(size.width * .28, size.height * .54)
      ..lineTo(size.width * .4, size.height * .22)
      ..lineTo(size.width * .53, size.height * .4)
      ..lineTo(size.width * .66, size.height * .15)
      ..lineTo(size.width * .79, size.height * .27)
      ..lineTo(size.width * .92, size.height * .54)
      ..lineTo(size.width, size.height * .46);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = RuniacColors.primaryBlue
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
