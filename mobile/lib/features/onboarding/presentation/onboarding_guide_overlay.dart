import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/characters/runner_character.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runner_character_sprite.dart';

/// Animated guide overlay shown when the user stalls on an onboarding step.
///
/// A guide with matching running art enters from a random horizontal direction,
/// then settles into its idle animation before the speech bubble appears. On
/// dismissal, it leaves through whichever horizontal edge is farther from its
/// current position. Blue retains the static directional fallback because it
/// does not yet have a matching run animation.
///
/// Display-only: the overlay renders sprites and hint copy and never touches
/// XP, level, rank, streak, or leaderboard values.
class OnboardingGuideOverlay extends StatefulWidget {
  const OnboardingGuideOverlay({
    required this.character,
    required this.message,
    required this.onDismiss,
    this.enterFromLeft,
    super.key,
  });

  final RunnerCharacter character;
  final String message;
  final VoidCallback onDismiss;

  /// Test seam for a deterministic entrance direction. Production uses a
  /// random side for each newly shown guide.
  final bool? enterFromLeft;

  @override
  State<OnboardingGuideOverlay> createState() => _OnboardingGuideOverlayState();
}

/// Long enough for the running GIF to read as movement without delaying help.
const onboardingGuideRunInDuration = Duration(milliseconds: 800);

/// Keeps dismissal responsive while letting the run-out direction read.
const onboardingGuideRunOutDuration = Duration(milliseconds: 620);

class _OnboardingGuideOverlayState extends State<OnboardingGuideOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _runIn;
  late final AnimationController _runOut;
  late final AnimationController _bob;
  late final AnimationController _type;
  late final Animation<int> _typedLength;
  late final bool _entersFromLeft;
  final _characterKey = GlobalKey();
  bool _hasArrived = false;
  bool _isExiting = false;
  bool _exitsToRight = true;
  bool _motionInitialized = false;

  @override
  void initState() {
    super.initState();
    _entersFromLeft = widget.enterFromLeft ?? Random().nextBool();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _runIn = AnimationController(
      vsync: this,
      duration: onboardingGuideRunInDuration,
    );
    _runOut = AnimationController(
      vsync: this,
      duration: onboardingGuideRunOutDuration,
    );
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    final typeMillis = (widget.message.length * 18).clamp(500, 2600);
    _type = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: typeMillis),
    );
    _typedLength = IntTween(
      begin: 0,
      end: widget.message.length,
    ).animate(CurvedAnimation(parent: _type, curve: Curves.easeOut));
    _bob.repeat(reverse: true);
    _type.forward();
    _hasArrived = !widget.character.hasRunAnimation;
    _runIn.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _hasArrived = true;
        });
      }
    });
    _runOut.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInitialized) {
      return;
    }
    _motionInitialized = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _bob
        ..stop()
        ..value = 0.5;
    } else if (!_bob.isAnimating) {
      _bob.repeat(reverse: true);
    }
    if (!widget.character.hasRunAnimation) {
      if (reduceMotion) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
      return;
    }
    if (reduceMotion) {
      _runIn.value = 1;
      _hasArrived = true;
      return;
    }
    _runIn.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _runIn.dispose();
    _runOut.dispose();
    _bob.dispose();
    _type.dispose();
    super.dispose();
  }

  void _beginDismiss() {
    if (_isExiting) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onDismiss();
      return;
    }

    final characterBox =
        _characterKey.currentContext?.findRenderObject() as RenderBox?;
    final characterCenterX = characterBox == null
        ? MediaQuery.sizeOf(context).width / 2
        : characterBox
              .localToGlobal(
                Offset(
                  characterBox.size.width / 2,
                  characterBox.size.height / 2,
                ),
              )
              .dx;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final spaceToLeft = characterCenterX;
    final spaceToRight = screenWidth - characterCenterX;

    _runIn.stop();
    _entrance.stop();
    _type.stop();
    setState(() {
      _isExiting = true;
      _exitsToRight = spaceToRight >= spaceToLeft;
    });
    _runOut.forward();
  }

  @override
  Widget build(BuildContext context) {
    final hasRunAnimation = widget.character.hasRunAnimation;
    final runIn = CurvedAnimation(parent: _runIn, curve: Curves.easeOutCubic);
    return Stack(
      children: [
        // Tap-away dismiss layer behind the guide card.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _beginDismiss,
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: hasRunAnimation
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedBuilder(
                      animation: Listenable.merge([_runIn, _runOut, _bob]),
                      builder: (context, _) {
                        final horizontalDistance = constraints.maxWidth + 112;
                        final entranceDirection = _entersFromLeft ? -1.0 : 1.0;
                        final exitDirection = _exitsToRight ? 1.0 : -1.0;
                        final bob = _hasArrived ? (_bob.value - 0.5) * 4 : 0.0;
                        return Transform.translate(
                          offset: Offset(
                            entranceDirection *
                                    (1 - runIn.value) *
                                    horizontalDistance +
                                exitDirection *
                                    Curves.easeInCubic.transform(
                                      _runOut.value,
                                    ) *
                                    horizontalDistance,
                            bob,
                          ),
                          child: _GuideCard(
                            characterKey: _characterKey,
                            character: widget.character,
                            message: widget.message,
                            typedLength: _typedLength,
                            enterFromLeft: _entersFromLeft,
                            hasArrived: _hasArrived,
                            isExiting: _isExiting,
                            exitsToRight: _exitsToRight,
                            onDismiss: _beginDismiss,
                          ),
                        );
                      },
                    );
                  },
                )
              : AnimatedBuilder(
                  animation: Listenable.merge([_entrance, _runOut, _bob]),
                  builder: (context, _) {
                    final entrance = Curves.easeOutBack.transform(
                      _entrance.value,
                    );
                    final bob = (_bob.value - 0.5) * 6;
                    final exitDirection = _exitsToRight ? 1.0 : -1.0;
                    final horizontalDistance =
                        MediaQuery.sizeOf(context).width + 112;
                    return Opacity(
                      opacity: _entrance.value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(
                          exitDirection *
                              Curves.easeInCubic.transform(_runOut.value) *
                              horizontalDistance,
                          (1 - entrance) * 120 + bob,
                        ),
                        child: Transform.scale(
                          scale: 0.9 + entrance * 0.1,
                          alignment: Alignment.bottomCenter,
                          child: _GuideCard(
                            characterKey: _characterKey,
                            character: widget.character,
                            message: widget.message,
                            typedLength: _typedLength,
                            enterFromLeft: true,
                            hasArrived: true,
                            isExiting: _isExiting,
                            exitsToRight: _exitsToRight,
                            onDismiss: _beginDismiss,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.characterKey,
    required this.character,
    required this.message,
    required this.typedLength,
    required this.enterFromLeft,
    required this.hasArrived,
    required this.isExiting,
    required this.exitsToRight,
    required this.onDismiss,
  });

  final Key characterKey;
  final RunnerCharacter character;
  final String message;
  final Animation<int> typedLength;
  final bool enterFromLeft;
  final bool hasArrived;
  final bool isExiting;
  final bool exitsToRight;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final character = _GuideCharacter(
      key: characterKey,
      character: this.character,
      facing: isExiting
          ? exitsToRight
                ? RunnerCharacterFacing.right
                : RunnerCharacterFacing.left
          : enterFromLeft
          ? RunnerCharacterFacing.right
          : RunnerCharacterFacing.left,
      isRunning: !hasArrived || isExiting,
    );
    final bubble = _GuideBubble(
      character: this.character,
      message: message,
      typedLength: typedLength,
      visible: hasArrived && !isExiting,
      onDismiss: onDismiss,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: enterFromLeft
          ? [character, const SizedBox(width: 8), bubble]
          : [bubble, const SizedBox(width: 8), character],
    );
  }
}

class _GuideCharacter extends StatelessWidget {
  const _GuideCharacter({
    required this.character,
    required this.facing,
    required this.isRunning,
    super.key,
  });

  final RunnerCharacter character;
  final RunnerCharacterFacing facing;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final assetPath = reducedMotion
        ? character.assetPath(RunnerCharacterFacing.front)
        : isRunning
        ? character.runAnimationAssetPath(facing) ?? character.assetPath(facing)
        : character.idleAnimationAssetPath;
    return RunnerCharacterSprite(
      key: ValueKey('onboarding_guide_character_${facing.name}'),
      character: character,
      assetPath: assetPath,
      width: 92,
      imageKey: ValueKey(
        isRunning
            ? 'onboarding_guide_running_character'
            : 'onboarding_guide_idle_character',
      ),
    );
  }
}

class _GuideBubble extends StatelessWidget {
  const _GuideBubble({
    required this.character,
    required this.message,
    required this.typedLength,
    required this.visible,
    required this.onDismiss,
  });

  final RunnerCharacter character;
  final String message;
  final Animation<int> typedLength;
  final bool visible;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          key: const ValueKey('onboarding_guide_bubble'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          opacity: visible ? 1 : 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                          final count = typedLength.value.clamp(
                            0,
                            message.length,
                          );
                          return Text(
                            message.substring(0, count),
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
                GestureDetector(
                  onTap: onDismiss,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4, top: 2),
                    child: Tooltip(
                      message: 'Dismiss',
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: RuniacColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
