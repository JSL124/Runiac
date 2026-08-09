part of 'weekly_workout_detail_screen.dart';

class _EditScheduleActionIcon extends StatelessWidget {
  const _EditScheduleActionIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 34,
      child: CustomPaint(painter: _EditScheduleActionIconPainter()),
    );
  }
}

class _EditScheduleActionIconPainter extends CustomPainter {
  const _EditScheduleActionIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 34;
    final scaleY = size.height / 34;
    canvas.scale(scaleX, scaleY);

    final framePaint = Paint()
      ..color = const Color(0xFFBDD3F1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final framePath = Path()
      ..moveTo(11.2, 7.6)
      ..cubicTo(6.6, 7.6, 4.2, 10.6, 4.2, 14.6)
      ..lineTo(4.2, 25.2)
      ..cubicTo(4.2, 29.1, 7.2, 31.5, 11.2, 31.5)
      ..lineTo(25.4, 31.5)
      ..cubicTo(29.3, 31.5, 31.6, 28.7, 31.6, 24.9)
      ..lineTo(31.6, 20.5);
    canvas.drawPath(framePath, framePaint);

    final pencilPaint = Paint()
      ..color = RuniacColors.primaryBlue
      ..style = PaintingStyle.fill;

    final bodyPath = Path()
      ..moveTo(13.4, 18.3)
      ..lineTo(23.6, 9.4)
      ..lineTo(28.8, 15.3)
      ..lineTo(18.4, 24.3)
      ..close();
    canvas.drawPath(bodyPath, pencilPaint);

    final capPath = Path()
      ..moveTo(24.7, 8.4)
      ..lineTo(27.3, 6.2)
      ..cubicTo(28.4, 5.2, 30, 5.4, 30.9, 6.5)
      ..lineTo(33.1, 9)
      ..cubicTo(34.1, 10.1, 34, 11.7, 32.9, 12.7)
      ..lineTo(30.2, 15)
      ..close();
    canvas.drawPath(capPath, pencilPaint);

    final tipPath = Path()
      ..moveTo(8.8, 28.3)
      ..lineTo(12.3, 19)
      ..lineTo(17.1, 24.7)
      ..close();
    canvas.drawPath(tipPath, pencilPaint);
  }

  @override
  bool shouldRepaint(covariant _EditScheduleActionIconPainter oldDelegate) {
    return false;
  }
}
