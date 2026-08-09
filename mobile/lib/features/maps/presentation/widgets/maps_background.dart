import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';

class MapsBackground extends StatelessWidget {
  const MapsBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _MapsBackgroundPainter())),
        Positioned(left: 52, top: 124, child: _MapPinPlaceholder()),
        Positioned(right: 64, top: 188, child: _MapPinPlaceholder()),
        Positioned(left: 126, top: 296, child: _MapPinPlaceholder()),
        Positioned(right: 92, top: 338, child: _MapFocusDot()),
      ],
    );
  }
}

class _MapPinPlaceholder extends StatelessWidget {
  const _MapPinPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RuniacColors.primaryBlue, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24172033),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(
        Icons.place,
        color: RuniacColors.accentOrange,
        size: 17,
      ),
    );
  }
}

class _MapFocusDot extends StatelessWidget {
  const _MapFocusDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33FC6818), width: 2),
      ),
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: RuniacColors.accentOrange,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _MapsBackgroundPainter extends CustomPainter {
  const _MapsBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE9ECE8),
    );

    final blockPaint = Paint()..color = const Color(0xFFF1F3EF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-20, 92, size.width * 0.48, size.height * 0.34),
        const Radius.circular(18),
      ),
      blockPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.56,
          110,
          size.width * 0.5,
          size.height * 0.32,
        ),
        const Radius.circular(18),
      ),
      blockPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(28, size.height * 0.5, size.width * 0.44, 118),
        const Radius.circular(18),
      ),
      blockPaint,
    );

    final roadPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    final softRoadPaint = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas
      ..drawLine(
        Offset(-size.width * 0.08, 120),
        Offset(size.width * 0.96, size.height * 0.52),
        roadPaint,
      )
      ..drawLine(
        Offset(size.width * 0.66, 0),
        Offset(size.width * 0.38, size.height * 0.74),
        roadPaint,
      )
      ..drawLine(
        Offset(-20, size.height * 0.62),
        Offset(size.width * 0.78, size.height * 0.58),
        softRoadPaint,
      )
      ..drawLine(
        Offset(size.width * 0.1, size.height * 0.22),
        Offset(size.width * 0.92, size.height * 0.78),
        softRoadPaint,
      );

    final routePaint = Paint()
      ..color = RuniacColors.primaryBlue
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final routePath = Path()
      ..moveTo(size.width * 0.18, size.height * 0.38)
      ..cubicTo(
        size.width * 0.35,
        size.height * 0.30,
        size.width * 0.42,
        size.height * 0.50,
        size.width * 0.57,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.34,
        size.width * 0.78,
        size.height * 0.52,
        size.width * 0.64,
        size.height * 0.60,
      );
    canvas.drawPath(routePath, routePaint);

    final routeStartPaint = Paint()..color = RuniacColors.accentOrange;
    final routeEndPaint = Paint()..color = RuniacColors.primaryBlue;
    canvas
      ..drawCircle(
        Offset(size.width * 0.18, size.height * 0.38),
        6,
        routeStartPaint,
      )
      ..drawCircle(
        Offset(size.width * 0.64, size.height * 0.60),
        6,
        routeEndPaint,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
