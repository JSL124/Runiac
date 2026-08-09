import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../core/assets/runiac_assets.dart';
import '../../../core/haptics/runiac_haptics_scope.dart';
import '../../../core/theme/runiac_colors.dart';
import '../domain/models/challenge_enums.dart';
import 'widgets/challenge_badge_image.dart';

/// The dynamic badge-earned celebration ceremony.
///
/// A single finite (non-looping) timeline so `pumpAndSettle` terminates and the
/// widget always settles on a clean resting state (just the full-colour badge).
/// Layered, in back-to-front order: a radial glow bloom, a rotating sunburst,
/// an expanding impact ring, a confetti burst, and the badge itself popping in
/// with an elastic overshoot. Under reduced motion the whole timeline jumps to
/// its final frame (glow/rays/confetti faded out, badge at full size) so a
/// single frame shows the resting badge.
///
/// Renders exactly ONE [ChallengeBadgeImage] — every other layer is painted, so
/// the tier badge art always routes through the shared PNG widget.
class ChallengeBadgeCeremony extends StatefulWidget {
  const ChallengeBadgeCeremony({
    required this.tierId,
    this.badgeSize = 176,
    super.key,
  });

  final ChallengeTierId tierId;
  final double badgeSize;

  @override
  State<ChallengeBadgeCeremony> createState() => _ChallengeBadgeCeremonyState();
}

class _ChallengeBadgeCeremonyState extends State<ChallengeBadgeCeremony>
    with TickerProviderStateMixin {
  static const _gold = Color(0xFFFFC24B);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );

  // Continuous ambient loop: drives the orange glow's darken/lighten pulse and
  // the sunburst's rotation for the whole time the ceremony is on screen. This
  // intentionally never settles (unless reduced motion), so anything that
  // mounts the earned ceremony must drive frames with `pump`, not
  // `pumpAndSettle`.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  // Loops the dotLottie fireworks for the whole time on screen; its duration is
  // adopted from the loaded composition.
  late final AnimationController _lottieController = AnimationController(
    vsync: this,
  );

  late final List<_ConfettiParticle> _confetti =
      _ConfettiParticle.deterministicBurst();

  bool _started = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
      _ambient.repeat();
      RuniacHapticsScope.maybeOf(context)?.impactHeavy();
    }
  }

  @override
  void dispose() {
    _lottieController.dispose();
    _ambient.dispose();
    _controller.dispose();
    super.dispose();
  }

  double _interval(double begin, double end, Curve curve) {
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, end, curve: curve),
    ).value;
  }

  @override
  Widget build(BuildContext context) {
    final double stageHeight = widget.badgeSize + 92;
    return SizedBox(
      width: double.infinity,
      height: stageHeight,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_controller, _ambient]),
          builder: (context, child) {
            // Badge: elastic pop-in with a soft settle, then a steady hold.
            final popIn = _interval(0, 0.52, Curves.easeOutBack);
            final badgeOpacity = _interval(0, 0.24, Curves.easeOut);
            final badgeScale = 0.4 + 0.6 * popIn;

            // The orange background fades in once with the entrance, then keeps
            // running via the continuous ambient loop below.
            final entranceFade = _interval(0, 0.4, Curves.easeOut);

            // Continuous ambient loop: darken <-> lighten pulse + steady spin,
            // for the whole time on the ceremony page (disabled under reduced
            // motion, where the background stays hidden).
            final phase = _ambient.value * 2 * math.pi;
            final pulse = 0.5 + 0.5 * math.sin(phase); // 0..1
            final glowOpacity =
                _reduceMotion ? 0.0 : entranceFade * (0.42 + 0.42 * pulse);
            final glowScale = 0.92 + 0.14 * pulse;
            final rayOpacity =
                _reduceMotion ? 0.0 : entranceFade * (0.22 + 0.30 * pulse);
            final rayRotation = phase;

            // Impact ring: snaps out at the pop moment and fades.
            final ringT = _interval(0.28, 0.72, Curves.easeOut);

            // Opening confetti burst travels outward then fades (one-shot; the
            // looping fireworks below carry the sustained celebration).
            final confettiT = _interval(0.16, 1, Curves.easeOut);

            return Stack(
              alignment: Alignment.center,
              children: [
                if (glowOpacity > 0.01)
                  Opacity(
                    opacity: glowOpacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: glowScale,
                      child: Container(
                        width: widget.badgeSize * 1.8,
                        height: widget.badgeSize * 1.8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Color(0x80FC6818),
                              Color(0x40FFC24B),
                              Color(0x00FFFFFF),
                            ],
                            stops: [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (rayOpacity > 0.01)
                  Transform.rotate(
                    angle: rayRotation,
                    child: CustomPaint(
                      size: Size.square(widget.badgeSize * 2.05),
                      painter: _SunburstPainter(
                        opacity: rayOpacity.clamp(0.0, 1.0),
                        color: _gold,
                      ),
                    ),
                  ),
                if (!_reduceMotion)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Lottie.asset(
                        RuniacAssets.challengeCelebrationLottie,
                        controller: _lottieController,
                        fit: BoxFit.cover,
                        onLoaded: (composition) {
                          _lottieController
                            ..duration = composition.duration
                            ..repeat();
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                if (ringT > 0 && ringT < 1)
                  CustomPaint(
                    size: Size.square(widget.badgeSize * 1.9),
                    painter: _ImpactRingPainter(
                      progress: ringT,
                      color: RuniacColors.accentOrange,
                    ),
                  ),
                if (confettiT > 0 && confettiT < 1)
                  CustomPaint(
                    size: Size(double.infinity, stageHeight),
                    painter: _ConfettiPainter(
                      particles: _confetti,
                      progress: confettiT,
                    ),
                  ),
                Opacity(
                  opacity: badgeOpacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: badgeScale.clamp(0.0, 1.4),
                    child: child,
                  ),
                ),
              ],
            );
          },
          child: ChallengeBadgeImage(
            tierId: widget.tierId,
            size: widget.badgeSize,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sunburst rays
// ---------------------------------------------------------------------------

class _SunburstPainter extends CustomPainter {
  const _SunburstPainter({
    required this.opacity,
    required this.color,
  });

  final double opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) {
      return;
    }
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    const rayCount = 12;
    final paint = Paint()..color = color.withValues(alpha: opacity * 0.5);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    for (var i = 0; i < rayCount; i += 1) {
      final angle = (i / rayCount) * math.pi * 2;
      final wedge = (math.pi * 2 / rayCount) * 0.34;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(
          math.cos(angle - wedge) * radius,
          math.sin(angle - wedge) * radius,
        )
        ..lineTo(
          math.cos(angle + wedge) * radius,
          math.sin(angle + wedge) * radius,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter oldDelegate) {
    return oldDelegate.opacity != opacity || oldDelegate.color != color;
  }
}

// ---------------------------------------------------------------------------
// Impact ring
// ---------------------------------------------------------------------------

class _ImpactRingPainter extends CustomPainter {
  const _ImpactRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.clamp(0.0, 1.0);
    final opacity = (1 - t).clamp(0.0, 1.0);
    if (opacity <= 0) {
      return;
    }
    final center = size.center(Offset.zero);
    final radius = size.width * (0.28 + 0.22 * t);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * (1 - t) + 1
      ..color = color.withValues(alpha: opacity * 0.7);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _ImpactRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// ---------------------------------------------------------------------------
// Confetti
// ---------------------------------------------------------------------------

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
    final random = math.Random(0x2F50);
    const colors = [
      RuniacColors.accentOrange,
      RuniacColors.primaryBlue,
      Color(0xFFFFC24B),
      Color(0xFF57C0FF),
    ];
    const count = 34;
    return List<_ConfettiParticle>.generate(count, (index) {
      final angle = (index / count) * math.pi * 2 + random.nextDouble() * 0.4;
      return _ConfettiParticle(
        angle: angle,
        distance: 70 + random.nextDouble() * 92,
        size: 5 + random.nextDouble() * 6,
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
    final travel = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    final opacity = (1 - progress).clamp(0.0, 1.0);
    if (opacity <= 0) {
      return;
    }
    // Reuse one Paint across particles; only the colour changes per particle.
    final paint = Paint();
    for (final particle in particles) {
      final radius = particle.distance * travel;
      final dx = math.cos(particle.angle) * radius;
      final dy = math.sin(particle.angle) * radius + travel * travel * 22;
      final offset = center + Offset(dx, dy);
      paint.color = particle.color.withValues(alpha: opacity);
      if (particle.isRect) {
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        canvas.rotate(particle.spin + travel * 3.4);
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
