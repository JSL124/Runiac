import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/characters/runner_character.dart';
import '../../../core/haptics/runiac_haptics_scope.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../../../core/widgets/runner_character_sprite.dart';
import '../../home/presentation/stage_map/home_stage_map.dart'
    show homeStageGuideAssetPath;
import '../domain/app_tour_steps.dart';
import '../domain/models/tutorial_step.dart';
import 'spotlight_scrim_painter.dart';

/// One-time, character-led spotlight overlay for the app tour.
///
/// Purely presentational: it receives an already-resolved [step] and an
/// already-measured [hole], dims the rest of the screen, and narrates the
/// step with the chosen [character]. It does no measuring of its own, owns no
/// tour state, and knows nothing about bottom-nav tabs — advancing between
/// steps and resolving anchors is entirely the caller's responsibility.
class AppTourOverlay extends StatefulWidget {
  const AppTourOverlay({
    required this.step,
    required this.hole,
    required this.useFallbackCopy,
    required this.character,
    required this.stepIndex,
    required this.stepCount,
    required this.onNext,
    required this.onSkip,
    this.isRestDay,
    super.key,
  });

  /// The step currently being narrated.
  final TutorialStep step;

  /// The already-measured anchor bounds to spotlight, in screen coordinates.
  /// `null` means no anchor resolved for this step: the overlay dims the
  /// whole screen and pins the guide to the bottom safe area.
  final Rect? hole;

  /// When true, [TutorialStep.effectiveFallbackMessage] is shown instead of
  /// [TutorialStep.message] (e.g. the anchor candidates failed to resolve).
  final bool useFallbackCopy;

  /// Whether today is a scheduled rest day on the caller's plan, republished
  /// from the same signal the Home guide bubble uses
  /// (`HomeGuideRequest.isRestDay`, itself derived from today's stage-map
  /// stone's `HomeStageStoneKind`) rather than re-derived here. `null` means
  /// unknown — no active plan, the signal not yet resolved, or the overlay
  /// composed without a Home layer (previews, most widget tests) — and is
  /// treated the same as `false`: [TutorialStep.effectiveMessage] never
  /// guesses at rest-day copy from an unresolved signal.
  final bool? isRestDay;

  /// The runner character guiding the tour.
  final RunnerCharacter character;

  /// Zero-based index of [step] within the tour script.
  final int stepIndex;

  /// Total number of steps in the tour script.
  final int stepCount;

  /// Invoked when the user taps the primary "Next"/"Done" control.
  final VoidCallback onNext;

  /// Invoked when the user taps "Skip tour".
  final VoidCallback onSkip;

  @override
  State<AppTourOverlay> createState() => _AppTourOverlayState();
}

class _AppTourOverlayState extends State<AppTourOverlay>
    with TickerProviderStateMixin {
  /// A hole covering more than this fraction of the screen's area cannot act
  /// as a spotlight: dimming "everything except everything" highlights
  /// nothing. Anchors this large (e.g. a `Positioned.fill` background that
  /// spans an entire tab) degrade to the same plain full-screen dim and
  /// bottom-pinned block used by the no-hole `welcome`/`finish` steps. A
  /// normal bottom-nav-sized or card-sized anchor sits far below this ratio,
  /// so their placement is unaffected.
  static const double _oversizedHoleAreaFraction = 0.7;

  /// Minimum vertical clearance the block needs on one side of the hole to
  /// render without being clipped. Derived from `_TourBubble.maxHeight`
  /// (the same hard cap `_TourBubble` imposes on its own `ConstrainedBox`)
  /// rather than an independent guess — the previous constant (190) could
  /// disagree with that cap, so a gap this code judged "usable" could still
  /// be shorter than what the bubble was actually allowed to render up to,
  /// letting the `Stack` clip the footer (Skip tour / Next) out of reach.
  /// Using the bubble's own ceiling means a gap is only ever treated as
  /// usable when the block is guaranteed to fit inside it. When neither the
  /// space above nor below the hole reaches this, no side can fit the block,
  /// so the step also degrades to the no-hole presentation.
  static const double _minBlockClearance = _TourBubble.maxHeight;

  late final AnimationController _type;
  late Animation<int> _typedLength;
  late final AnimationController _bob;
  late final AnimationController _ringPulse;
  late final AnimationController _nudge;
  late String _copy;
  bool _motionInitialized = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _copy = _resolveCopy();
    _type = AnimationController(vsync: this, duration: _typeDuration(_copy));
    _typedLength = IntTween(
      begin: 0,
      end: _copy.length,
    ).animate(CurvedAnimation(parent: _type, curve: Curves.easeOut));
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _ringPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _nudge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInitialized) {
      return;
    }
    _motionInitialized = true;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _type.value = 1;
    } else {
      _type.forward();
      _bob.repeat(reverse: true);
      _ringPulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant AppTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stepChanged =
        oldWidget.step.id != widget.step.id ||
        oldWidget.useFallbackCopy != widget.useFallbackCopy ||
        oldWidget.isRestDay != widget.isRestDay ||
        oldWidget.character != widget.character;
    if (!stepChanged) {
      return;
    }
    _copy = _resolveCopy();
    _type.duration = _typeDuration(_copy);
    _typedLength = IntTween(
      begin: 0,
      end: _copy.length,
    ).animate(CurvedAnimation(parent: _type, curve: Curves.easeOut));
    if (_reduceMotion) {
      _type.value = 1;
    } else {
      _type
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _type.dispose();
    _bob.dispose();
    _ringPulse.dispose();
    _nudge.dispose();
    super.dispose();
  }

  String _resolveCopy() {
    final template = widget.useFallbackCopy
        ? widget.step.effectiveFallbackMessage
        : widget.step.effectiveMessage(isRestDay: widget.isRestDay ?? false);
    return resolveTutorialCopy(template, widget.character);
  }

  Duration _typeDuration(String copy) {
    final millis = (copy.length * 14).clamp(300, 2200);
    return Duration(milliseconds: millis);
  }

  void _handleNext() {
    RuniacHapticsScope.maybeOf(context)?.selection();
    widget.onNext();
  }

  void _handleSkip() {
    RuniacHapticsScope.maybeOf(context)?.selection();
    widget.onSkip();
  }

  /// A mis-tap on the scrim must never silently eat a step, so this only
  /// gives the bubble a small visual nudge — it never fires [onNext] or
  /// [onSkip].
  void _handleScrimTap() {
    if (_reduceMotion) {
      return;
    }
    _nudge
      ..value = 0
      ..forward();
  }

  Rect _padAndClamp(Rect rect, Size screen) {
    final inflated = rect.inflate(widget.step.holePadding);
    final left = inflated.left.clamp(0.0, screen.width);
    final top = inflated.top.clamp(0.0, screen.height);
    final right = inflated.right.clamp(0.0, screen.width);
    final bottom = inflated.bottom.clamp(0.0, screen.height);
    return Rect.fromLTRB(
      math.min(left, right),
      math.min(top, bottom),
      math.max(left, right),
      math.max(top, bottom),
    );
  }

  double _radiusFor(Rect hole) {
    return widget.step.holeShape == TutorialHoleShape.circle
        ? hole.shortestSide / 2
        : 16;
  }

  /// A hole this large (by area) or this poorly placed (neither space above
  /// nor below fits the block) is not a usable spotlight target. See
  /// [_oversizedHoleAreaFraction] and [_minBlockClearance].
  bool _isOversizedHole(
    Rect hole,
    Size size,
    double safeTop,
    double safeBottom,
  ) {
    final screenArea = size.width * size.height;
    if (screenArea > 0) {
      final holeArea = hole.width * hole.height;
      if (holeArea >= screenArea * _oversizedHoleAreaFraction) {
        return true;
      }
    }
    final spaceAbove = hole.top - safeTop;
    final spaceBelow = size.height - safeBottom - hole.bottom;
    return spaceAbove < _minBlockClearance && spaceBelow < _minBlockClearance;
  }

  Widget _buildScrim(Rect? hole, Size size) {
    return AnimatedBuilder(
      animation: _ringPulse,
      builder: (context, _) {
        final ringOpacity = _reduceMotion
            ? 1.0
            : 0.55 + _ringPulse.value * 0.45;
        return CustomPaint(
          size: size,
          painter: SpotlightScrimPainter(
            hole: hole,
            holeRadius: hole == null ? 16 : _radiusFor(hole),
            dimColor: const Color(0x9E0B1220),
            ringColor: RuniacColors.primaryBlue,
            ringOpacity: ringOpacity,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final rawHole = widget.hole;
    final paddedHole = rawHole == null ? null : _padAndClamp(rawHole, size);
    final safeTop = mq.padding.top + 12;
    final safeBottom = mq.padding.bottom + 12;

    // A hole that covers (almost) the whole screen — e.g. a full-tab
    // `Positioned.fill` anchor — is not a spotlight target, so it degrades to
    // the same no-hole presentation as `welcome`/`finish` steps rather than
    // silently placing the block off-screen.
    final isOversizedHole =
        paddedHole != null &&
        _isOversizedHole(paddedHole, size, safeTop, safeBottom);
    final effectiveHole = isOversizedHole ? null : paddedHole;

    final effectiveSide = effectiveHole == null
        ? widget.step.preferredSide
        : (effectiveHole.center.dx <= size.width / 2
              ? TutorialCharacterSide.right
              : TutorialCharacterSide.left);
    final facing = effectiveSide == TutorialCharacterSide.left
        ? RunnerCharacterFacing.right
        : RunnerCharacterFacing.left;
    final isLastStep = widget.stepIndex >= widget.stepCount - 1;

    // The overlay is a sibling of the shell's `Scaffold`, so it has no
    // `Material` ancestor of its own. Without one, every `Text` in the bubble
    // renders with Flutter's yellow "unstyled text" debug underline.
    final block = Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _bob,
        builder: (context, child) {
          final bob = _reduceMotion ? 0.0 : (_bob.value - 0.5) * 4;
          return Transform.translate(offset: Offset(0, bob), child: child);
        },
        child: _TourBlock(
          character: widget.character,
          facing: facing,
          side: effectiveSide,
          copy: _copy,
          typedLength: _typedLength,
          stepIndex: widget.stepIndex,
          stepCount: widget.stepCount,
          isLastStep: isLastStep,
          onNext: _handleNext,
          onSkip: _handleSkip,
          nudge: _nudge,
        ),
      ),
    );

    Widget positioned;
    if (effectiveHole == null) {
      // Even in no-hole mode, cap the block to the actual room between the
      // safe-area edges rather than leaving it unbounded — on a very short
      // screen a maxed-out bubble could otherwise still grow past the top.
      final maxHeight = math.max(0.0, size.height - safeTop - safeBottom);
      positioned = Positioned(
        left: 16,
        right: 16,
        bottom: safeBottom,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: block,
        ),
      );
    } else {
      final spaceAbove = effectiveHole.top - safeTop;
      final spaceBelow = size.height - safeBottom - effectiveHole.bottom;
      final placeBelow =
          spaceBelow >= _minBlockClearance || spaceBelow > spaceAbove;
      // Clamp defensively: whatever the hole geometry, the block's anchor
      // must always land within the safe area rather than being pushed
      // beyond either edge.
      //
      // The block is also hard-capped to the room actually left between its
      // anchor and the opposite safe-area edge (`maxHeight` below). Picking
      // a side via `_minBlockClearance` already guarantees that room is
      // enough for the block, but this cap is what makes the `Stack`
      // physically unable to clip it, rather than relying solely on the two
      // thresholds continuing to agree.
      if (placeBelow) {
        final top = (effectiveHole.bottom + 12).clamp(
          safeTop,
          size.height - safeBottom,
        );
        final maxHeight = math.max(0.0, (size.height - safeBottom) - top);
        positioned = Positioned(
          left: 16,
          right: 16,
          top: top,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: block,
          ),
        );
      } else {
        final bottom = (size.height - effectiveHole.top + 12).clamp(
          safeBottom,
          size.height - safeTop,
        );
        final maxHeight = math.max(0.0, (size.height - bottom) - safeTop);
        positioned = Positioned(
          left: 16,
          right: 16,
          bottom: bottom,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: block,
          ),
        );
      }
    }

    return SizedBox.expand(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'App tour',
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleScrimTap,
                  // TweenAnimationBuilder requires a non-null `end`, so the
                  // no-hole (fully-dimmed) state is rendered directly and
                  // only the hole-to-hole transition is animated. An
                  // oversized hole is treated the same as no hole: it never
                  // reads as a usable spotlight, so it skips straight to the
                  // plain full-screen dim instead of animating toward a
                  // cut-out that would just cover the whole screen.
                  child: rawHole == null || isOversizedHole
                      ? _buildScrim(null, size)
                      : TweenAnimationBuilder<Rect?>(
                          tween: RectTween(end: rawHole),
                          duration: _reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          builder: (context, animatedRawHole, _) {
                            final resolvedRawHole = animatedRawHole ?? rawHole;
                            return _buildScrim(
                              _padAndClamp(resolvedRawHole, size),
                              size,
                            );
                          },
                        ),
                ),
              ),
            ),
            positioned,
          ],
        ),
      ),
    );
  }
}

/// Character sprite + speech-bubble row, ordered by [side] so the character
/// never sits on top of the spotlight hole.
class _TourBlock extends StatelessWidget {
  const _TourBlock({
    required this.character,
    required this.facing,
    required this.side,
    required this.copy,
    required this.typedLength,
    required this.stepIndex,
    required this.stepCount,
    required this.isLastStep,
    required this.onNext,
    required this.onSkip,
    required this.nudge,
  });

  final RunnerCharacter character;
  final RunnerCharacterFacing facing;
  final TutorialCharacterSide side;
  final String copy;
  final Animation<int> typedLength;
  final int stepIndex;
  final int stepCount;
  final bool isLastStep;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final Animation<double> nudge;

  /// The sprite's width on ample-width screens. Below
  /// [_narrowBlockWidthThreshold] it shrinks to [_spriteNarrowWidth] so the
  /// bubble (and in turn its footer row of Skip tour / step counter /
  /// Next-or-Done) keeps more of the available width on narrow phones —
  /// easing, though not by itself eliminating, how much those controls must
  /// shrink to fit. See `_TourBubble` for the fix that actually guarantees no
  /// overflow regardless of width or text scale.
  static const double _spriteBaseWidth = 84;
  static const double _spriteNarrowWidth = 68;
  static const double _narrowBlockWidthThreshold = 400;

  static double _spriteWidthFor(double blockWidth) =>
      blockWidth < _narrowBlockWidthThreshold
      ? _spriteNarrowWidth
      : _spriteBaseWidth;

  @override
  Widget build(BuildContext context) {
    // The block's width is fixed by its `Positioned(left: 16, right: 16, ...)`
    // ancestor, so `LayoutBuilder` here reports that real budget rather than
    // an unbounded one — safe to size the sprite from directly.
    return LayoutBuilder(
      builder: (context, constraints) {
        final spriteWidth = _spriteWidthFor(constraints.maxWidth);
        final sprite = _TourCharacterSprite(
          character: character,
          facing: facing,
          width: spriteWidth,
        );
        final bubble = Expanded(
          child: AnimatedBuilder(
            animation: nudge,
            builder: (context, child) {
              final wobble = math.sin(nudge.value * math.pi) * 0.02;
              return Transform.scale(scale: 1 - wobble, child: child);
            },
            child: _TourBubble(
              character: character,
              copy: copy,
              typedLength: typedLength,
              stepIndex: stepIndex,
              stepCount: stepCount,
              isLastStep: isLastStep,
              onNext: onNext,
              onSkip: onSkip,
            ),
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: side == TutorialCharacterSide.left
              ? [sprite, const SizedBox(width: 8), bubble]
              : [bubble, const SizedBox(width: 8), sprite],
        );
      },
    );
  }
}

/// The runner sprite shown alongside the tour bubble.
///
/// Uses the same selected-character idle asset and stable sizing contract as
/// the Home stage map.
class _TourCharacterSprite extends StatelessWidget {
  const _TourCharacterSprite({
    required this.character,
    required this.facing,
    required this.width,
  });

  final RunnerCharacter character;
  final RunnerCharacterFacing facing;

  /// Sprite width in logical pixels, chosen by the caller (see
  /// `_TourBlock._spriteWidthFor`) so it can shrink on narrow screens.
  final double width;

  @override
  Widget build(BuildContext context) {
    final assetPath = homeStageGuideAssetPath(
      character: character,
      facing: facing,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    );
    return RunnerCharacterSprite(
      character: character,
      assetPath: assetPath,
      width: width,
    );
  }
}

/// The white speech-bubble card: speaker name, typewriter-revealed copy, and
/// the Skip tour / step counter / Next-or-Done controls.
class _TourBubble extends StatelessWidget {
  const _TourBubble({
    required this.character,
    required this.copy,
    required this.typedLength,
    required this.stepIndex,
    required this.stepCount,
    required this.isLastStep,
    required this.onNext,
    required this.onSkip,
  });

  final RunnerCharacter character;
  final String copy;
  final Animation<int> typedLength;
  final int stepIndex;
  final int stepCount;
  final bool isLastStep;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  /// Hard cap on the bubble's own height, regardless of copy length or text
  /// scale. `_AppTourOverlayState` reads this same constant (as
  /// `_minBlockClearance`) to decide whether a gap beside the spotlight hole
  /// is tall enough to hold the block, so the two can never disagree about
  /// how tall the block is allowed to grow.
  static const double maxHeight = 340;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: RuniacColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RuniacColors.cardBorder, width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: RuniacColors.softCardShadow,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        // The name + typed copy scroll internally (`Flexible` +
        // `shrinkWrap: true` lets that region shrink to short copy but cap
        // at whatever height is left under the 340 `maxHeight` above), while
        // the footer row is a fixed sibling below it rather than part of
        // the same scrollable — otherwise a long message at a large text
        // scale can grow tall enough to scroll the Skip/Next controls out
        // of view, making them present in the tree but untappable.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.displayName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: RuniacColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedBuilder(
                      animation: typedLength,
                      builder: (context, _) {
                        final count = typedLength.value.clamp(0, copy.length);
                        return Text(
                          copy.substring(0, count),
                          key: const ValueKey('appTourBubbleBody'),
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: RuniacColors.textPrimary,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // A quiet orientation cue, not a control: mirrors the step
            // progress idiom from `OnboardingProgressHeader`, condensed to a
            // slim segmented track sized to fit inside the bubble footer
            // rather than a full-width header. It carries no visible digits
            // of its own; the "N of M" phrasing it used to render as plain
            // text is preserved for assistive tech via `Semantics` below.
            _TourStepProgress(stepIndex: stepIndex, stepCount: stepCount),
            const SizedBox(height: 10),
            // `Skip tour` and Next/Done are a primary/secondary action pair,
            // the same kind `OnboardingBottomActions` renders for its
            // primary CTA + ghost secondary action, so they share that
            // widget's `RuniacButtonStyles` shape and text-style family
            // rather than the raw `TextButton`/`ElevatedButton` this footer
            // used before. Both sides stay `Flexible` so a shrunk font under
            // a large text-scale setting still fits instead of overflowing.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('appTourSkipButton'),
                      style: RuniacButtonStyles.ghost(
                        foregroundColor: RuniacColors.primaryBlue.withValues(
                          alpha: 0.65,
                        ),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: onSkip,
                      child: const Text('Skip tour'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const ValueKey('appTourNextButton'),
                      style: RuniacButtonStyles.primary(
                        shape: const StadiumBorder(),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        textStyle: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: onNext,
                      child: Text(isLastStep ? 'Done' : 'Next'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet, compact step tracker for the bubble footer: one rounded segment
/// per step, filled up to and including [stepIndex]. Sized to sit inline in
/// a speech bubble rather than the bolder full-width bar
/// `OnboardingProgressHeader` uses for a whole screen.
///
/// It renders no digits of its own — it is an orientation cue, not a
/// control — so the "N of M" phrasing this replaced (previously a plain
/// `Text`) is exposed to assistive tech via [Semantics] instead of the
/// render tree.
class _TourStepProgress extends StatelessWidget {
  const _TourStepProgress({required this.stepIndex, required this.stepCount});

  final int stepIndex;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('appTourStepCounter'),
      label: '${stepIndex + 1} of $stepCount',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 4,
          child: Row(
            children: [
              for (var i = 0; i < stepCount; i++)
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i == stepCount - 1 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: i <= stepIndex
                          ? RuniacColors.primaryBlue
                          : RuniacColors.cardBorder,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
