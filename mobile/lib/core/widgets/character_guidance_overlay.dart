import 'package:flutter/material.dart';

import '../characters/runner_character.dart';
import '../theme/runiac_colors.dart';
import 'runner_character_sprite.dart';

/// Shared blocking overlay in which a Runiac character runs in from the right
/// and delivers paged guidance in a speech bubble.
///
/// Extracted from the Activity Summary feedback overlay so the planned-workout
/// briefing can reuse the same motion, reduced-motion handling, and close
/// semantics. Callers supply their own step list, loading copy, tooltips, and
/// widget-key prefix; nothing in here knows about agents, Firebase, or any
/// particular feature's domain model.
const characterGuidanceRunDuration = Duration(milliseconds: 800);

/// One page of guidance copy rendered inside the speech bubble.
class CharacterGuidanceStep {
  const CharacterGuidanceStep({required this.title, required this.body});

  final String title;
  final String body;
}

/// Returns [steps] with [notice] prepended to the FIRST page's body.
///
/// Used by the agent surfaces to state why the copy that follows is generic
/// (see `agentQuotaResetNotice`). It leads the first page rather than adding a
/// page of its own so the runner cannot page past the explanation without
/// seeing it, and so the surfaces keep the four-page shape their manual test
/// scripts describe.
///
/// A null or blank notice, or an empty step list, returns [steps] unchanged —
/// callers can pass the notice through unconditionally.
List<CharacterGuidanceStep> guidanceStepsWithLeadingNotice(
  List<CharacterGuidanceStep> steps,
  String? notice,
) {
  if (notice == null || notice.trim().isEmpty || steps.isEmpty) {
    return steps;
  }
  return <CharacterGuidanceStep>[
    CharacterGuidanceStep(
      title: steps.first.title,
      body: '$notice\n\n${steps.first.body}',
    ),
    ...steps.skip(1),
  ];
}

class CharacterGuidanceOverlay extends StatefulWidget {
  const CharacterGuidanceOverlay({
    required this.character,
    required this.loadSteps,
    required this.onClose,
    required this.loadingCopy,
    required this.closeTooltip,
    required this.previousTooltip,
    required this.nextTooltip,
    this.keyPrefix = 'activity_feedback',
    super.key,
  });

  final RunnerCharacter character;

  /// Started once in [initState] so the network call overlaps the run-in.
  final Future<List<CharacterGuidanceStep>> Function() loadSteps;
  final VoidCallback onClose;
  final String loadingCopy;
  final String closeTooltip;
  final String previousTooltip;
  final String nextTooltip;

  /// Prefix for every widget key this overlay exposes, so two features can be
  /// driven independently from tests.
  final String keyPrefix;

  @override
  State<CharacterGuidanceOverlay> createState() =>
      _CharacterGuidanceOverlayState();
}

class _CharacterGuidanceOverlayState extends State<CharacterGuidanceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  late final Future<List<CharacterGuidanceStep>> _steps;
  var _stepIndex = 0;
  var _arrived = false;
  var _closing = false;
  var _reducedMotion = false;
  var _closeNotified = false;
  var _motionInitialized = false;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: characterGuidanceRunDuration,
    );
    _motion.addListener(_handleMotionValue);
    _motion.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_closing && mounted) {
        setState(() {
          _arrived = true;
        });
      }
      if (status == AnimationStatus.dismissed && _closing && mounted) {
        _notifyClose();
      }
    });
    _steps = widget.loadSteps();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInitialized) {
      return;
    }
    _motionInitialized = true;
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      _motion.value = 1;
      _arrived = true;
      return;
    }
    _motion.forward();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) {
      return;
    }
    _closing = true;

    if (_reducedMotion) {
      if (mounted) {
        setState(() {});
      }
      _notifyClose();
      return;
    }

    // A close tap during the entrance still starts the exit from the stable
    // resting position, so the running-left asset always travels out through
    // the left edge instead of changing direction mid-flight.
    _motion.stop();
    _motion.value = 1;
    _arrived = true;
    if (mounted) {
      setState(() {});
    }
    await _motion.reverse();
    if (mounted) {
      _notifyClose();
    }
  }

  void _handleMotionValue() {
    if (_closing && _motion.value <= 0 && mounted) {
      _notifyClose();
    }
  }

  void _notifyClose() {
    if (_closeNotified) {
      return;
    }
    _closeNotified = true;
    widget.onClose();
  }

  void _showNext(int stepCount) {
    if (_stepIndex < stepCount - 1) {
      setState(() {
        _stepIndex += 1;
      });
    }
  }

  void _showPrevious() {
    if (_stepIndex > 0) {
      setState(() {
        _stepIndex -= 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefix = widget.keyPrefix;
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: ModalBarrier(
              key: ValueKey('${prefix}_barrier'),
              color: Colors.black.withValues(alpha: 0.58),
              dismissible: false,
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  top: 20,
                  bottom: 20,
                  child: FutureBuilder<List<CharacterGuidanceStep>>(
                    future: _steps,
                    builder: (context, snapshot) {
                      final steps = snapshot.data;
                      return AnimatedBuilder(
                        animation: _motion,
                        builder: (context, _) {
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final runDistance = constraints.maxWidth + 120;
                              final progress = Curves.easeOutCubic.transform(
                                _motion.value.clamp(0.0, 1.0),
                              );
                              final offsetX = _closing
                                  ? -runDistance * (1 - progress)
                                  : runDistance * (1 - progress);
                              final arrivedForFrame =
                                  _arrived || (!_closing && _motion.value >= 1);
                              return Transform.translate(
                                key: ValueKey('${prefix}_motion'),
                                offset: Offset(offsetX, 0),
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  child: _GuidanceRow(
                                    character: widget.character,
                                    steps: steps,
                                    stepIndex: _stepIndex,
                                    keyPrefix: prefix,
                                    loadingCopy: widget.loadingCopy,
                                    closeTooltip: widget.closeTooltip,
                                    previousTooltip: widget.previousTooltip,
                                    nextTooltip: widget.nextTooltip,
                                    maxBubbleHeight: constraints.maxHeight
                                        .clamp(0.0, 480.0),
                                    showIdle: arrivedForFrame && !_closing,
                                    reducedMotion: _reducedMotion,
                                    bubbleVisible: arrivedForFrame && !_closing,
                                    onNext: () => _showNext(steps?.length ?? 0),
                                    onPrevious: _showPrevious,
                                    onClose: _close,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidanceRow extends StatelessWidget {
  const _GuidanceRow({
    required this.character,
    required this.steps,
    required this.stepIndex,
    required this.keyPrefix,
    required this.loadingCopy,
    required this.closeTooltip,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.maxBubbleHeight,
    required this.showIdle,
    required this.reducedMotion,
    required this.bubbleVisible,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });

  final RunnerCharacter character;
  final List<CharacterGuidanceStep>? steps;
  final int stepIndex;
  final String keyPrefix;
  final String loadingCopy;
  final String closeTooltip;
  final String previousTooltip;
  final String nextTooltip;
  final double maxBubbleHeight;
  final bool showIdle;
  final bool reducedMotion;
  final bool bubbleVisible;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final resolved = steps;
    final step = resolved == null || resolved.isEmpty
        ? null
        : resolved[stepIndex.clamp(0, resolved.length - 1)];
    final assetPath = reducedMotion
        ? character.assetPath(RunnerCharacterFacing.front)
        : showIdle
        ? character.idleAnimationAssetPath
        : character.runAnimationAssetPath(RunnerCharacterFacing.left) ??
              character.assetPath(RunnerCharacterFacing.left);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        RunnerCharacterSprite(
          key: ValueKey('${keyPrefix}_character_footprint'),
          character: character,
          assetPath: assetPath,
          width: 96,
          imageKey: ValueKey(
            showIdle
                ? '${keyPrefix}_idle_character'
                : '${keyPrefix}_running_character',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: IgnorePointer(
            ignoring: !bubbleVisible,
            child: AnimatedOpacity(
              key: ValueKey('${keyPrefix}_bubble'),
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              opacity: bubbleVisible ? 1 : 0,
              child: _GuidanceBubble(
                step: step,
                stepIndex: stepIndex,
                stepCount: resolved?.length ?? 0,
                loadingCopy: loadingCopy,
                closeTooltip: closeTooltip,
                previousTooltip: previousTooltip,
                nextTooltip: nextTooltip,
                maxHeight: maxBubbleHeight,
                onNext: onNext,
                onPrevious: onPrevious,
                onClose: onClose,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GuidanceBubble extends StatelessWidget {
  const _GuidanceBubble({
    required this.step,
    required this.stepIndex,
    required this.stepCount,
    required this.loadingCopy,
    required this.closeTooltip,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.maxHeight,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });

  final CharacterGuidanceStep? step;
  final int stepIndex;
  final int stepCount;
  final String loadingCopy;
  final String closeTooltip;
  final String previousTooltip;
  final String nextTooltip;
  final double maxHeight;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final resolved = step;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: RuniacColors.softCardShadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: resolved == null
                        ? _LoadingCopy(copy: loadingCopy)
                        : Text(
                            resolved.title,
                            style: const TextStyle(
                              color: RuniacColors.primaryBlue,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                  ),
                  IconButton(
                    tooltip: closeTooltip,
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    color: RuniacColors.textSecondary,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (resolved != null) ...[
                const SizedBox(height: 6),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      resolved.body,
                      style: const TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${stepIndex + 1}/$stepCount',
                      style: const TextStyle(
                        color: RuniacColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: previousTooltip,
                      onPressed: stepIndex == 0 ? null : onPrevious,
                      icon: const Icon(Icons.chevron_left_rounded),
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: nextTooltip,
                      onPressed: stepIndex >= stepCount - 1 ? null : onNext,
                      icon: const Icon(Icons.chevron_right_rounded),
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCopy extends StatelessWidget {
  const _LoadingCopy({required this.copy});

  final String copy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Text(
        copy,
        style: const TextStyle(
          color: RuniacColors.primaryBlue,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
    );
  }
}
