part of 'xp_update_screen.dart';

class _ConfettiParticle {
  const _ConfettiParticle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
    required this.isRect,
    required this.spin,
  });

  final double angle;
  final double distance;
  final double size;
  final Color color;
  final bool isRect;
  final double spin;

  static List<_ConfettiParticle> deterministicBurst() {
    final random = math.Random(0x8151);
    const colors = [_blue, _orange, _lightBlue];
    const count = 26;
    return List<_ConfettiParticle>.generate(count, (index) {
      final angle = (index / count) * math.pi * 2 + random.nextDouble() * 0.5;
      return _ConfettiParticle(
        angle: angle,
        distance: 46 + random.nextDouble() * 62,
        size: 4 + random.nextDouble() * 5,
        color: colors[index % colors.length],
        isRect: random.nextBool(),
        spin: random.nextDouble() * math.pi,
      );
    });
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.particles, required this.progress});

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final travel = Curves.easeOut.transform(progress.clamp(0, 1));
    final opacity = (1 - progress).clamp(0.0, 1.0);
    if (opacity <= 0) {
      return;
    }

    // Reuse a single Paint across particles; only the color changes per
    // particle. Avoids allocating one Paint per particle on every frame.
    final paint = Paint();

    for (final particle in particles) {
      final radius = particle.distance * travel;
      final dx = math.cos(particle.angle) * radius;
      final dy = math.sin(particle.angle) * radius + travel * travel * 14;
      final offset = center + Offset(dx, dy);
      paint.color = particle.color.withValues(alpha: opacity);

      if (particle.isRect) {
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        canvas.rotate(particle.spin + travel * 3);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: particle.size * 1.6,
              height: particle.size,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(offset, particle.size / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

double _lerp(double from, double to, double value) {
  return from + (to - from) * value.clamp(0, 1);
}

String _formatThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index += 1) {
    if (index != 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return '${value < 0 ? '-' : ''}$buffer';
}
