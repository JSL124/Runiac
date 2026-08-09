part of 'xp_update_screen.dart';

class _LevelRing extends StatelessWidget {
  const _LevelRing({
    required this.model,
    required this.progress,
    required this.ringSize,
    required this.avatarSize,
    required this.showBadge,
    required this.badgeLabel,
    required this.badgeScale,
  });

  final XpUpdateDisplayModel model;
  final double progress;
  final double ringSize;
  final double avatarSize;
  final bool showBadge;
  final String badgeLabel;
  final double badgeScale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(ringSize),
            painter: _LevelRingPainter(progress: progress),
          ),
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              color: _blue06,
              shape: BoxShape.circle,
              border: Border.all(color: _blue10),
            ),
            child: Center(
              child: Text(
                model.runnerName.characters.first,
                style: TextStyle(
                  color: _blue,
                  fontSize: ringSize < 100 ? 26 : 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          if (showBadge)
            Positioned(
              bottom: -5,
              child: Transform.scale(
                scale: badgeScale,
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: _orange, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      badgeLabel,
                      style: const TextStyle(
                        color: _pureWhite,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LevelRingPainter extends CustomPainter {
  const _LevelRingPainter({required this.progress});

  static const _startAngle = math.pi * 0.68;

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final strokeWidth = size.width < 100 ? 7.0 : 8.0;
    final radius = (size.width - strokeWidth) / 2;
    final trackPaint = Paint()
      ..color = _blue12
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final progressPaint = Paint()
      ..color = _orange
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LevelRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
