import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:runiac_app/core/haptics/runiac_haptics_scope.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';

import '../../plan/presentation/plan_completion_celebration_scope.dart';
import '../domain/models/xp_update_display_model.dart';
import 'data/run_completion_demo_snapshots.dart';

part 'xp_update_stage.dart';
part 'xp_update_header.dart';
part 'xp_update_hero.dart';
part 'xp_update_cards.dart';
part 'xp_update_level_ring.dart';
part 'xp_update_shared_widgets.dart';
part 'xp_update_layout.dart';
part 'xp_update_confetti.dart';

const _blue = Color(0xFF2F51C8);
const _orange = Color(0xFFFB6414);
const _pureWhite = Color(0xFFFFFFFF);
const _lightBlue = Color(0xFF7C95E8);
const _blue60 = Color(0x992F51C8);
const _blue45 = Color(0x732F51C8);
const _blue12 = Color(0x1F2F51C8);
const _blue10 = Color(0x1A2F51C8);
const _blue06 = Color(0x0F2F51C8);
const _orange12 = Color(0x1FFB6414);

class XpUpdateScreen extends StatefulWidget {
  const XpUpdateScreen({super.key, this.model = defaultXpUpdateDisplayModel});

  final XpUpdateDisplayModel model;

  @override
  State<XpUpdateScreen> createState() => _XpUpdateScreenState();
}

class _XpUpdateScreenState extends State<XpUpdateScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;
  var _hapticFired = false;
  var _goingHome = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _particles = _ConfettiParticle.deterministicBurst();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
    _fireRevealHapticOnce();
  }

  // Fires exactly once when the reveal screen is shown: a heavy impact for a
  // level-up (the bigger milestone wins), otherwise a medium impact for a
  // standard XP update. This is an accessibility-independent cue, so it
  // fires the same way whether or not reduced motion skipped the animation.
  void _fireRevealHapticOnce() {
    if (_hapticFired) {
      return;
    }
    _hapticFired = true;
    final haptics = RuniacHapticsScope.maybeOf(context);
    if (widget.model.didLevelUp) {
      haptics?.impactHeavy();
    } else {
      haptics?.impactMedium();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Returns the runner to the shell — and, when this run finished their plan,
  /// to the Home dashboard specifically.
  ///
  /// A run can be started from any tab, and popping back to the shell lands on
  /// whichever tab was selected when it began. `HomeTab` holds the
  /// plan-completion ceremony while Home is not frontmost, so a plan finished
  /// on a run started from Feed, Leaderboard or You would leave the celebration
  /// held indefinitely — the runner would have to happen to tap Home. Selecting
  /// the Home tab *before* the pop releases that hold on the same frame the
  /// shell is revealed, and avoids a visible tab switch afterwards.
  ///
  /// Only a pending celebration redirects: an ordinary run still returns the
  /// runner to the tab they came from. The check is read-only and never spends
  /// the one-shot marker, which stays `HomeTab`'s to advance.
  Future<void> _goHome() async {
    // The marker read puts an await between the tap and the pop, so a second
    // tap can land while the first is still resolving.
    if (_goingHome) {
      return;
    }
    _goingHome = true;
    final router = PlanCompletionCelebrationScope.maybeOf(context);
    final navigator = Navigator.of(context);
    // The redirect is a bonus on top of the CTA's real job. A failed marker
    // read (or a missing scope, as on the QA surface) must still leave the
    // runner able to get out of this screen, so it degrades to a plain pop.
    var pending = false;
    if (router != null) {
      try {
        pending = await router.isCelebrationPending();
      } catch (_) {
        pending = false;
      }
    }
    if (!mounted) {
      return;
    }
    if (pending) {
      router!.showHomeDashboard();
    }
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 820;
            final tokens = _XpLayoutTokens.fromCompact(compact);

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final stage = _XpStage(
                      t: _controller.value,
                      model: widget.model,
                    );

                    return Column(
                      children: [
                        _XpHeader(onBack: () => Navigator.of(context).pop()),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              20,
                              compact ? 0 : 4,
                              20,
                              compact ? 12 : 24,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    constraints.maxHeight -
                                    56 -
                                    (compact ? 12 : 28),
                              ),
                              child: IntrinsicHeight(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Opacity(
                                      opacity: stage.entrance,
                                      child: Transform.translate(
                                        offset: Offset(
                                          0,
                                          (1 - stage.entrance) * 18,
                                        ),
                                        child: _HeroRewardCard(
                                          model: widget.model,
                                          stage: stage,
                                          tokens: tokens,
                                          particles: _particles,
                                          reduceMotion: reduceMotion,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: compact ? 10 : 12),
                                    _TotalXpCard(
                                      model: widget.model,
                                      stage: stage,
                                    ),
                                    SizedBox(height: compact ? 10 : 12),
                                    _StreakCard(
                                      model: widget.model,
                                      stage: stage,
                                    ),
                                    SizedBox(height: compact ? 12 : 18),
                                    const Spacer(),
                                    _GoHomeButton(
                                      height: compact ? 52 : 56,
                                      onPressed: _goHome,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Staged animation clock. All sub-stages are derived from a single controller
/// value so the celebration reads as one choreographed sequence.
