part of 'cool_down_guide_screen.dart';

class _CoolDownTimerRing extends StatelessWidget {
  const _CoolDownTimerRing({
    required this.secondsLeft,
    required this.totalSeconds,
    required this.status,
    required this.compact,
  });

  final int secondsLeft;
  final int totalSeconds;
  final _CoolDownStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 150.0 : 190.0;
    final minutes = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (secondsLeft % 60).toString().padLeft(2, '0');
    final isPaused = status == _CoolDownStatus.paused;
    final isComplete = status == _CoolDownStatus.complete;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            painter: _TimerRingPainter(
              progress: isComplete
                  ? 1
                  : (totalSeconds == 0 ? 0 : secondsLeft / totalSeconds),
              status: status,
            ),
            child: const SizedBox.expand(),
          ),
          if (isComplete)
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _navy,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x332F51C8),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(
                      Icons.check_rounded,
                      color: _pureWhite,
                      size: 30,
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'DONE',
                  style: TextStyle(
                    color: _navy45,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
              ],
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$minutes:$seconds',
                  style: TextStyle(
                    color: isPaused ? _navy45 : _navy,
                    fontSize: compact ? 32 : 46,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  isPaused ? 'PAUSED' : 'REMAINING',
                  style: TextStyle(
                    color: isPaused ? _orange : _navy45,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  const _TimerRingPainter({required this.progress, required this.status});

  final double progress;
  final _CoolDownStatus status;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.shortestSide / 190;
    final radius = 83 * scale;
    final strokeWidth = 12 * scale;
    final clampedProgress = progress.clamp(0.0, 1.0);
    final isPaused = status == _CoolDownStatus.paused;
    final isComplete = status == _CoolDownStatus.complete;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _navy12
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (isComplete) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = _navy
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth,
      );
      return;
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * clampedProgress,
      false,
      Paint()
        ..color = isPaused ? _navy30 : _navy
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth,
    );

    if (!isPaused && clampedProgress > 0.01 && clampedProgress < 0.995) {
      final angle = -math.pi / 2 + (1 - clampedProgress) * 2 * math.pi;
      final dotCenter = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas
        ..drawCircle(dotCenter, 9 * scale, Paint()..color = _pureWhite)
        ..drawCircle(dotCenter, 6.5 * scale, Paint()..color = _orange);
    }
  }

  @override
  bool shouldRepaint(covariant _TimerRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.status != status;
  }
}
