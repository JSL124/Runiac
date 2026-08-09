import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../domain/models/challenge_enums.dart';
import 'widgets/challenge_badge_image.dart';

/// Plays the "badge shrinks and flies into the Account page" flourish.
///
/// A single earned badge is drawn on the root overlay and animated from
/// [source] (where the ceremony badge rested on the result screen) to [target]
/// (roughly where the Account badge case sits), shrinking and fading as it
/// lands — so it reads as the badge being deposited into the collection while
/// the Account page opens underneath. Pointer-transparent and self-removing;
/// callers just fire and forget.
void flyChallengeBadgeToAccount({
  required OverlayState overlay,
  required ChallengeTierId tierId,
  required Rect source,
  required Rect target,
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _BadgeFlightView(
      tierId: tierId,
      source: source,
      target: target,
      onComplete: () {
        if (entry.mounted) {
          entry.remove();
        }
      },
    ),
  );
  overlay.insert(entry);
}

class _BadgeFlightView extends StatefulWidget {
  const _BadgeFlightView({
    required this.tierId,
    required this.source,
    required this.target,
    required this.onComplete,
  });

  final ChallengeTierId tierId;
  final Rect source;
  final Rect target;
  final VoidCallback onComplete;

  @override
  State<_BadgeFlightView> createState() => _BadgeFlightViewState();
}

class _BadgeFlightViewState extends State<_BadgeFlightView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Defer removal out of the animation/build phase.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          widget.onComplete();
        });
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final glide = Curves.easeInOutCubic.transform(_controller.value);
          final rect = Rect.lerp(widget.source, widget.target, glide)!;
          // Slight upward arc so the flight feels tossed into the collection.
          final arc = -28.0 * (glide - glide * glide) * 4;
          // Hold opaque, then fade out over the final quarter as it lands.
          final fade = _controller.value < 0.72
              ? 1.0
              : (1 - (_controller.value - 0.72) / 0.28);
          return Stack(
            children: [
              Positioned(
                left: rect.left,
                top: rect.top + arc,
                width: rect.width,
                height: rect.height,
                child: Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: ChallengeBadgeImage(
                    tierId: widget.tierId,
                    size: rect.width,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
