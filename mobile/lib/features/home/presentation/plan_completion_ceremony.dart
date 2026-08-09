import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../core/assets/runiac_assets.dart';
import '../../../core/haptics/runiac_haptics_scope.dart';

/// Shows a non-interactive "Plan Completed!" celebration overlay: a gauge
/// animation fills first, then once full, a second celebration animation and
/// a congrats message reveal above it. A black semi-transparent backdrop
/// blocks all interaction except the top-right close button.
///
/// Under reduced motion the overlay opens already in its fully-revealed
/// state, matching the pattern used by [showRuniacSuccessCheckOverlay] and
/// [ChallengeBadgeCeremony].
///
/// Triggered from `HomeTab` when the backend records the active plan as
/// finished (`planProgress/{uid}.planCompletions[planId].completedAt`, written
/// by the `completeRun` Cloud Function). The client never derives completion
/// itself. The celebration is one-shot per completion, guarded by a local
/// `PlanCompletionSeenStore` marker.
///
/// The signal arrives while the runner is still inside the run flow, so
/// `HomeTab` holds the celebration until Home is frontmost rather than opening
/// it over the cool-down, summary or XP-update screen — this route is pushed
/// onto the shared root navigator and would otherwise sit on top of whatever
/// the runner is actually looking at.
Future<void> showPlanCompletionCeremony(BuildContext context) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Plan completed',
    barrierColor: Colors.black.withValues(alpha: 0.75),
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _PlanCompletionOverlay(revealedOnOpen: reduceMotion),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _PlanCompletionOverlay extends StatefulWidget {
  const _PlanCompletionOverlay({required this.revealedOnOpen});

  final bool revealedOnOpen;

  @override
  State<_PlanCompletionOverlay> createState() =>
      _PlanCompletionOverlayState();
}

class _PlanCompletionOverlayState extends State<_PlanCompletionOverlay>
    with TickerProviderStateMixin {
  // How long the build-up runs before the payoff lands. This is the single
  // knob for the ceremony's pace: [_sequence] both plays the gauge and fires
  // the reveal, so the bar cannot finish early or late relative to the badge
  // no matter what this is set to. Shorten it to make the gauge fill faster.
  //
  // `plan_complete_gauge.lottie` is authored at 3.43s (35 fps × 120 frames),
  // which felt slow, so it is driven at roughly half speed here — the
  // controller remaps the whole composition onto this duration.
  //
  // Fixed rather than adopted from the loaded composition, so the sequence
  // runs identically whether or not the Lottie loads (and so `pumpAndSettle`
  // always terminates) — the same approach as
  // `runiac_success_check_overlay.dart`.
  static const _gaugeFillDuration = Duration(milliseconds: 1800);

  // Drives the gauge Lottie *and* the reveal. Note the composition finishes
  // its fill at frame 110 of 120, so the bar reads full for the last ~8% of
  // this duration before the badge and headline arrive — the hold the asset
  // was authored with, preserved at whatever speed is set above.
  late final AnimationController _sequence;

  // Drives the shared dotLottie fireworks — the same asset `ChallengeBadgeCeremony`
  // fires when a badge is won — adopting its duration from the loaded
  // composition.
  //
  // Played once from the reveal rather than looped the way the challenge
  // ceremony does. Two reasons: the run has to start at the payoff, not when
  // the overlay opens, or the 5s composition would be most of the way through
  // by the time the gauge finishes at 3.14s; and an endlessly repeating
  // animation means this overlay never goes idle, so `pumpAndSettle` hangs for
  // anyone who writes a test that reaches Home with a completion pending. The
  // challenge ceremony can afford the loop because it owns a whole screen the
  // runner lingers on; this is a modal they dismiss.
  late final AnimationController _fireworks = AnimationController(vsync: this);

  var _revealed = false;
  var _hapticFired = false;
  var _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _revealed = widget.revealedOnOpen;
    _reduceMotion = widget.revealedOnOpen;
    _sequence = AnimationController(
      vsync: this,
      duration: _gaugeFillDuration,
      value: widget.revealedOnOpen ? 1 : 0,
    );
    if (!widget.revealedOnOpen) {
      _sequence
        ..addStatusListener(_handleSequenceStatus)
        ..forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `initState` cannot legally read an InheritedWidget, so the entrance
    // haptic fires here instead, guarded to fire exactly once for the whole
    // life of this overlay.
    if (!_hapticFired) {
      _hapticFired = true;
      RuniacHapticsScope.maybeOf(context)?.impactHeavy();
    }
  }

  void _handleSequenceStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _revealed = true);
      _startFireworks();
    }
  }

  /// Runs the fireworks from their first frame, whichever of the two inputs
  /// lands last: the reveal, or the composition finishing loading (a cold
  /// asset read can easily outlast the 3.14s gauge). A null duration means the
  /// composition is not in yet, so [_handleFireworksLoaded] will start it.
  void _startFireworks() {
    if (_fireworks.duration != null) {
      _fireworks.forward(from: 0);
    }
  }

  void _handleFireworksLoaded(LottieComposition composition) {
    _fireworks.duration = composition.duration;
    if (_revealed) {
      _fireworks.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sequence
      ..removeStatusListener(_handleSequenceStatus)
      ..dispose();
    _fireworks.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Stack(
          children: [
            // Fireworks fill the whole overlay behind the payoff — the same
            // asset, fit and looping treatment the challenge badge ceremony
            // uses, so finishing a plan reads as the same class of moment as
            // winning a badge. It joins at the reveal rather than on open, so
            // the gauge fill stays the quiet build-up it is choreographed as,
            // and it is skipped entirely under reduced motion.
            if (!_reduceMotion)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _revealed ? 1 : 0,
                    duration: const Duration(milliseconds: 260),
                    child: Lottie.asset(
                      RuniacAssets.challengeCelebrationLottie,
                      controller: _fireworks,
                      fit: BoxFit.cover,
                      onLoaded: _handleFireworksLoaded,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: _close,
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close',
              ),
            ),
            Center(
              child: IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 132,
                      child: AnimatedOpacity(
                        opacity: _revealed ? 1 : 0,
                        duration: const Duration(milliseconds: 260),
                        child: Lottie.asset(
                          RuniacAssets.planCompleteBurstLottie,
                          fit: BoxFit.contain,
                          repeat: false,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedOpacity(
                      opacity: _revealed ? 1 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: const Text(
                        'Plan Completed!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 280,
                      height: 70,
                      child: Lottie.asset(
                        RuniacAssets.planCompleteGaugeLottie,
                        // Driven by the same controller that fires the reveal,
                        // so the fill is remapped onto [_gaugeFillDuration] and
                        // the two stay in lockstep by construction rather than
                        // by two constants agreeing.
                        controller: _sequence,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
