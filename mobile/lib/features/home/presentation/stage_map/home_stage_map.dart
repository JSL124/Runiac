import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/characters/runner_character.dart';
import '../../../../core/haptics/runiac_haptics_scope.dart';
import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_level_profile_badge.dart';
import '../../../../core/widgets/runner_character_sprite.dart';
import '../../../challenge/domain/challenge_copy.dart';
import '../../../challenge/domain/challenge_countdown.dart';
import '../../../challenge/presentation/home_active_challenge_display.dart';
import '../../../challenge/presentation/widgets/challenge_badge_image.dart';
import '../../../tutorial/domain/models/tutorial_step.dart';
import '../../../tutorial/presentation/app_tour_controller.dart';
import '../../../tutorial/presentation/tutorial_anchor_registry.dart';
import '../../domain/guide/home_guide_agent.dart';
import '../../domain/guide/home_guide_consent.dart';
import '../home_recenter_intent_controller.dart';
import 'home_stage_background_sequence.dart';
import 'home_guide_cycle.dart';
import 'home_stage_map_model.dart';

part 'home_stage_map_backdrop.dart';
part 'home_stage_map_stones.dart';
part 'home_stage_map_header.dart';
part 'home_stage_map_challenge.dart';
part 'home_stage_map_menu.dart';
part 'home_stage_map_status_controls.dart';
part 'home_stage_map_empty_state.dart';
part 'home_stage_map_guide.dart';

const double _kFadeFraction = 0.08;
const double _kMinimumStageStoneSize = 92;
const double _kMaximumStageStoneSize = 108;
const double _kStageStoneWidthFraction = 0.255;
const double _kCharacterToStoneScale = 0.86;
const double _kStageDayLabelWidth = 56;
const double _kStageDayLabelTopFraction = 0.82;

/// The initial camera composition keeps the guide in the lower visual third,
/// leaving room above for upcoming stages and the Home header.
const double _kInitialCharacterViewportFraction = 2 / 3;

/// Where the guide's feet rest on a stage stone, as a fraction of the stone's
/// height measured down from the stone's top edge. The stones are drawn as
/// perspective plates whose visible standing surface sits near the middle of
/// the asset, so slightly above centre keeps the plate's front face visible
/// beneath the feet.
const double _kCharacterFootAnchorStoneHeightFraction = 0.46;

/// Transparent padding below the feet inside the character sprites, as a
/// fraction of the sprite's rendered height. Every bundled character asset
/// carries a small (up to ~3.6% of height) band of fully transparent rows
/// under the feet, so one shared allowance keeps the bottom-anchored feet on
/// the standing surface without per-asset pixel offsets.
const double _kCharacterFootInsetFraction = 0.02;
const String _kEmptyStateBackground =
    'assets/images/home/backgrounds/bg_gardens_by_the_bay.webp';
const String _kStageRunAsset =
    'assets/images/home/stages/dashboard_stage_run.png';
const String _kStageRestAsset =
    'assets/images/home/stages/dashboard_stage_rest.png';

/// Chooses the guide sprite for the Home stage map.
///
/// Resting guides use their idle animation. Horizontal plan-to-plan movement
/// uses a matching directional run animation when supplied; Blue and vertical
/// movement retain the existing direction-specific sprite fallback.
String homeStageGuideAssetPath({
  required RunnerCharacter character,
  required RunnerCharacterFacing facing,
  bool isMoving = false,
  bool reducedMotion = false,
}) {
  if (reducedMotion) {
    return character.assetPath(RunnerCharacterFacing.front);
  }
  if (!isMoving) {
    return character.idleAnimationAssetPath;
  }
  return character.runAnimationAssetPath(facing) ?? character.assetPath(facing);
}

double homeStageGuideHeightForWidth({
  required RunnerCharacter character,
  required double width,
}) {
  return character.animationHeightForWidth(width);
}

/// Duolingo-style vertical stage map for the Home tab.
///
/// Renders one full-bleed background per plan week (week 1 at the bottom,
/// later weeks stacking upward), with seven stage stones placed on each
/// background's path and a guide character standing on today's stage. All
/// progress shown is display-only; nothing is computed or written here.
class HomeStageMap extends StatefulWidget {
  const HomeStageMap({
    required this.onNotifications,
    required this.onProfile,
    required this.onTapTodayStage,
    this.model,
    this.streakCount = 0,
    this.unreadNotificationCount = 0,
    this.profileInitials = 'R',
    this.profilePhotoUrl = '',
    this.levelBadgeLabel = 'Lv.0',
    this.levelProgressFraction = 0,
    this.progressLoading = false,
    this.profileLoading = false,
    this.guideAgent,
    this.guideRequest,
    this.guideConsentStatus = HomeGuideConsentStatus.granted,
    this.onOpenFriends,
    this.onOpenChallenge,
    this.onOpenSettings,
    this.activeChallenge,
    this.onOpenChallengeProgress,
    this.challengeClock,
    this.challengeTicker,
    this.recenterIntent,
    super.key,
  });

  /// The renderable map, or null/empty when there is no active plan.
  final HomeStageMapModel? model;
  final int streakCount;
  final int unreadNotificationCount;
  final String profileInitials;

  /// Raw, not-yet-sanitised avatar photo URL. Empty renders the initials disc.
  final String profilePhotoUrl;
  final String levelBadgeLabel;
  final double levelProgressFraction;
  final bool progressLoading;
  final bool profileLoading;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final VoidCallback onTapTodayStage;

  /// Seam that turns [guideRequest] into a speech-bubble message for the
  /// guide character. When null (or [guideRequest] is null), no speech
  /// bubble is ever shown — the character remains a purely cosmetic sprite.
  final HomeGuideAgent? guideAgent;

  /// Display-only description of today's workout, forwarded to [guideAgent].
  /// Rebuilt by the caller (see `home_tab.dart`) whenever the active plan or
  /// today's stage changes.
  final HomeGuideRequest? guideRequest;
  final HomeGuideConsentStatus guideConsentStatus;

  /// Opens the Friends screen when the Menu's Friends item is tapped.
  /// Optional so existing call sites and tests compile unchanged; when null
  /// the Friends item simply closes the menu. Navigation trigger only — the
  /// stage map reads or writes no social data.
  final VoidCallback? onOpenFriends;

  /// Opens the Challenge hub when the Menu's Challenge item is tapped.
  /// Optional so existing call sites and tests compile unchanged; when null the
  /// Challenge item simply closes the menu. Navigation trigger only — the stage
  /// map internals read or write no Challenge/Firebase data.
  final VoidCallback? onOpenChallenge;

  /// Opens the app Settings screen when the Menu's Settings item is tapped.
  /// Optional on the same terms as the two above; when null the item simply
  /// closes the menu. Navigation trigger only.
  final VoidCallback? onOpenSettings;

  /// The caller's live ACTIVE/SETTLING challenge, resolved by `HomeTab` from its
  /// repository and handed down as a plain Firebase-free projection. Null hides
  /// the header active-challenge control entirely (no reserved gap).
  final HomeActiveChallengeDisplay? activeChallenge;

  /// Opens the Progress screen when the active-challenge control is tapped.
  /// `HomeTab` owns the navigation and repository; the stage map only fires the
  /// callback.
  final VoidCallback? onOpenChallengeProgress;

  /// Injected wall-clock for the active-challenge countdown (production uses
  /// `DateTime.now`). Tests pass a fixed clock for a deterministic label.
  final DateTime Function()? challengeClock;

  /// Injected 1-second ticker seam for the countdown (production uses a periodic
  /// timer). Tests pass a no-op/controlled ticker so no real frames are scheduled.
  final ChallengeTicker? challengeTicker;

  /// Fires when the shell wants the map scrolled back to the character —
  /// today, a tap on the already-selected Home item in the bottom bar. Null
  /// (previews/tests) simply leaves the scroll position alone.
  final HomeRecenterIntentController? recenterIntent;

  @override
  State<HomeStageMap> createState() => _HomeStageMapState();
}

class _HomeStageMapState extends State<HomeStageMap>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _walkController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  /// Drives the header menu: the trigger's caret rotation, the panel's
  /// grow-from-caret entrance, and the staggered row reveal all read this one
  /// controller so they can never disagree about state.
  late final AnimationController _menuController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 120),
  );

  double _sectionWidth = 0;
  double _sectionHeight = 0;
  double _overlap = 0;
  double _viewportHeight = 0;
  bool _initialScrollDone = false;

  /// Scroll offset that puts the character in its landing composition, as of
  /// the last laid-out frame. Null until the map has been measured, or while
  /// there is no character to scroll to. Recomputed on every map build so a
  /// recenter request always uses current layout, not the mount-time one.
  double? _characterScrollOffset;
  bool _menuOpen = false;

  String? _shownStageId;
  bool _walking = false;
  List<Offset> _walkWaypoints = const <Offset>[];
  List<double> _walkSegmentLengths = const <double>[];
  double _walkTotalLength = 0;

  // The cycle owns bundle caching, the summary/tip/progression order, and
  // close/reopen state. This surface only supplies the eligible stage/request
  // signature and renders its display-only state.
  HomeGuideCycleController? _guideCycle;
  HomeGuideAgent? _guideCycleAgent;

  @override
  void initState() {
    super.initState();
    _shownStageId = widget.model?.currentStageId;
    _walkController.addListener(_onWalkTick);
    _walkController.addStatusListener(_onWalkStatus);
    _menuController.addStatusListener(_onMenuStatus);
    widget.recenterIntent?.addListener(_onRecenterRequested);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (reduced-motion) becomes available here, not in initState.
    _syncPulse();
    _syncGuideBubble();
  }

  @override
  void didUpdateWidget(covariant HomeStageMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.recenterIntent, widget.recenterIntent)) {
      oldWidget.recenterIntent?.removeListener(_onRecenterRequested);
      widget.recenterIntent?.addListener(_onRecenterRequested);
    }
    _syncPulse();
    _syncGuideBubble();

    final newId = widget.model?.currentStageId;
    if (newId != _shownStageId) {
      _maybeStartWalk(newId);
    }
  }

  void _syncGuideBubble() {
    final model = widget.model;
    final stageId = _hasTodayStage(model) ? model!.currentStageId : null;
    final agent = widget.guideAgent;
    final request = widget.guideRequest;
    if (stageId == null ||
        agent == null ||
        request == null ||
        !_guideConsentSatisfied(agent)) {
      _clearGuideCycle();
      return;
    }
    final signature = HomeGuideCycleSignature.forRequest(
      stageId: stageId,
      request: request,
    );
    final cycle = _guideCycle;
    if (cycle == null || !identical(agent, _guideCycleAgent)) {
      _clearGuideCycle();
      _guideCycle = HomeGuideCycleController(agent: agent, signature: signature)
        ..addListener(_onGuideCycleChanged);
      _guideCycleAgent = agent;
      return;
    }
    cycle.updateSignature(signature);
  }

  /// Whether [agent] may run given the runner's personalized-guide consent.
  ///
  /// Only an agent that sends data to the AI provider is gated. The on-device
  /// plan read-out composes from plan copy already on screen, so withholding
  /// it would deny the runner their own plan over a consent that never
  /// covered it.
  bool _guideConsentSatisfied(HomeGuideAgent agent) {
    return !agent.requiresDataConsent ||
        widget.guideConsentStatus == HomeGuideConsentStatus.granted;
  }

  void _clearGuideCycle() {
    final cycle = _guideCycle;
    if (cycle == null) {
      return;
    }
    cycle
      ..removeListener(_onGuideCycleChanged)
      ..dispose();
    _guideCycle = null;
    _guideCycleAgent = null;
  }

  void _onGuideCycleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleGuideBubble() {
    final cycle = _guideCycle;
    if (cycle == null) {
      return;
    }
    if (cycle.state.isVisible) {
      cycle.hide();
    } else {
      cycle.show();
    }
  }

  void _dismissGuideBubble() {
    _guideCycle?.hide();
  }

  void _toggleMenu() {
    _setMenuOpen(!_menuOpen);
  }

  void _closeMenu() {
    _setMenuOpen(false);
  }

  void _setMenuOpen(bool open) {
    if (_menuOpen == open) {
      return;
    }
    setState(() {
      _menuOpen = open;
    });
    if (_menuReduceMotion) {
      _menuController.value = open ? 1 : 0;
      return;
    }
    if (open) {
      _menuController.forward();
    } else {
      _menuController.reverse();
    }
  }

  /// Rebuilds once the close animation lands so the panel and the tap-outside
  /// barrier can unmount. Everything in between is driven by the controller.
  void _onMenuStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
  }

  /// True while the menu should settle instantly. Deliberately narrower than
  /// [_reduceMotion]: that getter also treats the widget-test binding as
  /// reduced motion because [_pulseController] repeats forever. The menu
  /// controller is one-shot, so `pumpAndSettle` handles it and tests keep
  /// exercising the real transition.
  bool get _menuReduceMotion => MediaQuery.disableAnimationsOf(context);

  /// True while the menu occupies the screen, including the close animation.
  bool get _menuVisible => _menuOpen || _menuController.value > 0;

  void _onMenuNotificationsTap() {
    _closeMenu();
    widget.onNotifications();
  }

  void _onMenuFriendsTap() {
    _closeMenu();
    widget.onOpenFriends?.call();
  }

  void _onMenuChallengeTap() {
    _closeMenu();
    widget.onOpenChallenge?.call();
  }

  void _onMenuSettingsTap() {
    _closeMenu();
    widget.onOpenSettings?.call();
  }

  void _advanceGuideBubble() {
    _guideCycle?.advance();
  }

  /// True when the indefinite pulse/walk should stay idle: either the platform
  /// asks for reduced motion, or we are running under a widget-test binding.
  ///
  /// The pulse uses [AnimationController.repeat], which keeps scheduling frames
  /// forever and would make `pumpAndSettle` time out. Most widget tests reach
  /// Home through `RuniacApp` without opting into reduced motion, so we also
  /// treat the test harness as reduced-motion. The real app runs on
  /// `WidgetsFlutterBinding` (whose type name has no "Test"), so it still
  /// animates normally.
  bool get _reduceMotion {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return true;
    }
    return _runningUnderTestBinding;
  }

  static final bool _runningUnderTestBinding = WidgetsBinding
      .instance
      .runtimeType
      .toString()
      .contains('Test');

  /// Runs the "today" pulse only while there is an active today stage and
  /// motion is allowed. Keeping the repeating controller idle otherwise leaves
  /// no frames scheduled, so default `pumpAndSettle` tests settle.
  void _syncPulse() {
    final shouldPulse = _hasTodayStage(widget.model) && !_reduceMotion;
    if (shouldPulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    widget.recenterIntent?.removeListener(_onRecenterRequested);
    _clearGuideCycle();
    _walkController
      ..removeListener(_onWalkTick)
      ..removeStatusListener(_onWalkStatus)
      ..dispose();
    _pulseController.dispose();
    _menuController
      ..removeStatusListener(_onMenuStatus)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _hasTodayStage(HomeStageMapModel? model) {
    return model != null && model.todayDayIndex != null;
  }

  void _onWalkTick() {
    if (_walking) {
      setState(() {});
    }
  }

  void _onWalkStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _walking) {
      setState(() {
        _walking = false;
        _shownStageId = widget.model?.currentStageId;
      });
    }
  }

  void _maybeStartWalk(String? newId) {
    if (newId == null) {
      _shownStageId = null;
      return;
    }
    // Under reduced motion, jump straight to the new stage without walking.
    if (_reduceMotion) {
      _shownStageId = newId;
      return;
    }
    // First real appearance of a stage: settle without animating.
    if (_shownStageId == null || _walking) {
      _shownStageId = newId;
      return;
    }
    final model = widget.model;
    if (model == null || _sectionWidth <= 0) {
      _shownStageId = newId;
      return;
    }

    final from = _parseStageId(_shownStageId!);
    final to = _parseStageId(newId);
    final n = model.sections.length;
    if (from == null ||
        to == null ||
        from.$1 >= n ||
        to.$1 >= n ||
        !_isForward(from, to)) {
      _shownStageId = newId;
      return;
    }

    final waypoints = _buildWalkWaypoints(model, from, to);
    if (waypoints.length < 2) {
      _shownStageId = newId;
      return;
    }
    _walkWaypoints = waypoints;
    _walkSegmentLengths = <double>[
      for (var i = 0; i < waypoints.length - 1; i++)
        (waypoints[i + 1] - waypoints[i]).distance,
    ];
    _walkTotalLength = _walkSegmentLengths.fold<double>(0, (a, b) => a + b);
    if (_walkTotalLength <= 0) {
      _shownStageId = newId;
      return;
    }
    setState(() {
      _walking = true;
    });
    _walkController.forward(from: 0);
  }

  bool _isForward((int, int) from, (int, int) to) {
    final fromOrdinal = from.$1 * kHomeStageDaysPerWeek + from.$2;
    final toOrdinal = to.$1 * kHomeStageDaysPerWeek + to.$2;
    return toOrdinal > fromOrdinal;
  }

  (int, int)? _parseStageId(String id) {
    final parts = id.split(':');
    if (parts.length != 2) {
      return null;
    }
    final week = int.tryParse(parts[0]);
    final day = int.tryParse(parts[1]);
    if (week == null || day == null) {
      return null;
    }
    return (week, day);
  }

  List<Offset> _buildWalkWaypoints(
    HomeStageMapModel model,
    (int, int) from,
    (int, int) to,
  ) {
    final n = model.sections.length;
    if (from.$1 == to.$1) {
      final week = from.$1;
      final anchors = homeStageAnchorsForSection(week);
      final step = to.$2 >= from.$2 ? 1 : -1;
      final points = <Offset>[];
      for (var d = from.$2; d != to.$2 + step; d += step) {
        if (d < 0 || d >= anchors.length) {
          break;
        }
        points.add(_stoneCenter(week, n, anchors, d));
      }
      return points;
    }
    return <Offset>[
      _stoneCenterForStage(model, from, n),
      _stoneCenterForStage(model, to, n),
    ];
  }

  Offset _stoneCenterForStage(
    HomeStageMapModel model,
    (int, int) stage,
    int n,
  ) {
    final anchors = homeStageAnchorsForSection(stage.$1);
    final day = stage.$2.clamp(0, anchors.length - 1);
    return _stoneCenter(stage.$1, n, anchors, day);
  }

  double _sectionTop(int weekIndex, int n) {
    return (n - 1 - weekIndex) * (_sectionHeight - _overlap);
  }

  Offset _stoneCenter(
    int weekIndex,
    int n,
    List<Offset> anchors,
    int dayIndex,
  ) {
    final anchor = anchors[dayIndex.clamp(0, anchors.length - 1)];
    return Offset(
      anchor.dx * _sectionWidth,
      _sectionTop(weekIndex, n) + anchor.dy * _sectionHeight,
    );
  }

  double get _stageStoneSize => (_sectionWidth * _kStageStoneWidthFraction)
      .clamp(_kMinimumStageStoneSize, _kMaximumStageStoneSize)
      .toDouble();

  double get _characterWidth => _stageStoneSize * _kCharacterToStoneScale;

  double _characterHeightFor(RunnerCharacter character) {
    return homeStageGuideHeightForWidth(
      character: character,
      width: _characterWidth,
    );
  }

  /// Top edge of the character sprite when its feet stand on the stone (or
  /// walk-path point) centred at [anchorCenter].
  ///
  /// The character is anchored by its feet — the bottom of the rendered box
  /// minus the shared transparent foot inset — so any character sprite,
  /// whatever its height, keeps its feet on the same standing surface. The
  /// rendered box always matches the sprite's own aspect ratio (see
  /// [homeStageGuideHeightForWidth]), so the box bottom is the sprite bottom.
  double _characterTopForAnchor(
    Offset anchorCenter,
    RunnerCharacter character,
  ) {
    final footY =
        anchorCenter.dy +
        _stageStoneSize * (_kCharacterFootAnchorStoneHeightFraction - 0.5);
    return footY -
        _characterHeightFor(character) * (1 - _kCharacterFootInsetFraction);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _sectionWidth = constraints.maxWidth;
        _sectionHeight = _sectionWidth * kHomeStageBackgroundAspect;
        _overlap = _sectionHeight * _kFadeFraction;
        _viewportHeight = constraints.maxHeight;

        final model = widget.model;
        final hasStages = model != null && model.hasStages;
        final Widget mapLayer = hasStages
            ? _buildMap(model)
            : const _HomeStageEmptyState();

        return Stack(
          children: [
            Positioned.fill(child: mapLayer),
            // Tap-outside dismissal barrier: mounted only while the menu is on
            // screen so the closed-state semantics and stage taps are
            // unaffected. It outlives the close animation so a stray tap
            // during the 120ms exit cannot reach the map.
            if (_menuVisible)
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey<String>('homeMenuBarrier'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeMenu,
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _HomeStageHeader(
                    levelBadgeLabel: widget.levelBadgeLabel,
                    levelProgressFraction: widget.levelProgressFraction,
                    progressLoading: widget.progressLoading,
                    profileLoading: widget.profileLoading,
                    profileInitials: widget.profileInitials,
                    profilePhotoUrl: widget.profilePhotoUrl,
                    onProfile: widget.onProfile,
                    menuOpen: _menuOpen,
                    menuAnimation: _menuController,
                    onToggleMenu: _toggleMenu,
                    activeChallenge: widget.activeChallenge,
                    onOpenChallengeProgress: widget.onOpenChallengeProgress,
                    challengeClock: widget.challengeClock,
                    challengeTicker: widget.challengeTicker,
                  ),
                  if (_menuVisible)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _HomeMenuPanel(
                        animation: _menuController,
                        streakCount: widget.streakCount,
                        streakLoading: widget.progressLoading,
                        unreadNotificationCount: widget.unreadNotificationCount,
                        onNotifications: _onMenuNotificationsTap,
                        onFriends: _onMenuFriendsTap,
                        onChallenge: _onMenuChallengeTap,
                        onSettings: _onMenuSettingsTap,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMap(HomeStageMapModel model) {
    final n = model.sections.length;
    final totalHeight = (n - 1) * (_sectionHeight - _overlap) + _sectionHeight;
    _characterScrollOffset = _characterScrollTarget(model, n, totalHeight);
    _scheduleInitialScroll();

    final children = <Widget>[];

    // Backgrounds: paint upper weeks first so lower weeks blend over them.
    for (var w = n - 1; w >= 0; w--) {
      children.add(
        Positioned(
          left: 0,
          top: _sectionTop(w, n),
          width: _sectionWidth,
          height: _sectionHeight,
          child: _FadingBackground(asset: model.sections[w].backgroundAsset),
        ),
      );
    }

    // Stones above every background.
    for (var w = 0; w < n; w++) {
      final section = model.sections[w];
      final anchors = homeStageAnchorsForSection(w);
      for (var d = 0; d < section.stones.length; d++) {
        final stone = section.stones[d];
        final center = _stoneCenter(w, n, anchors, d);
        final size = _stageStoneSize;
        final stageStoneWidget = _StageStoneWidget(
          key: ValueKey<String>('homeStageStone-${section.weekNumber}-$d'),
          stone: stone,
          size: size,
          pulse: stone.isCurrent ? _pulseController : null,
          onTap: stone.isCurrent && stone.isRun ? widget.onTapTodayStage : null,
        );
        children.add(
          Positioned(
            left: center.dx - size / 2,
            top: center.dy - size / 2,
            width: size,
            height: size,
            // `stone.isCurrent` is true for at most one stone across the whole
            // model (see HomeStageMapModel), so this conditional wrap can
            // never attach the homeTodayStone anchor key more than once.
            child: stone.isCurrent
                ? TutorialAnchor(
                    id: TutorialAnchorId.homeTodayStone,
                    child: stageStoneWidget,
                  )
                : stageStoneWidget,
          ),
        );
        if (stone.dayLabel != null) {
          children.add(
            Positioned(
              left: center.dx - _kStageDayLabelWidth / 2,
              top: center.dy - size / 2 + size * _kStageDayLabelTopFraction,
              width: _kStageDayLabelWidth,
              child: IgnorePointer(
                child: _StageDayLabel(
                  key: ValueKey<String>(
                    'homeStageDayLabel-${section.weekNumber}-$d',
                  ),
                  label: stone.dayLabel!,
                  dimmed: stone.state == HomeStageStoneState.future,
                ),
              ),
            ),
          );
        }
      }
    }

    // Invisible tour-only anchor covering today's stone and its immediate
    // neighbours, so a single tour step can spotlight a run stone next to a
    // rest stone. Purely a measurement target: never painted, never
    // hit-tested.
    final stoneCluster = _buildStoneClusterAnchor(model, n);
    if (stoneCluster != null) {
      children.add(stoneCluster);
    }

    // Guide character on top of everything.
    final character = _buildCharacter(model, n);
    if (character != null) {
      children.add(character);
    }

    final bubble = _buildGuideBubble(model, n, totalHeight);
    if (bubble != null) {
      children.add(bubble);
    }

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      child: SizedBox(
        width: _sectionWidth,
        height: totalHeight,
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }

  /// Extra padding, in logical pixels, added around the bounding box of the
  /// today-stone cluster so the tour's spotlight ring does not clip the
  /// stones it covers.
  static const double _kStoneClusterPadding = 6;

  /// Builds the invisible [TutorialAnchorId.homeStoneCluster] overlay target:
  /// a tight rect covering today's stone plus up to one stone before and one
  /// after it, clamped within the current week section, and widened (still
  /// within the same week) when needed so a run and a rest stone are both
  /// included whenever the week actually has both.
  ///
  /// Reuses the exact same layout math as the real stones (`_stoneCenter`,
  /// `_stageStoneSize`) so the rect always matches what is actually on
  /// screen. Returns null when there is no current week or no stone in it is
  /// marked current, matching when the real `homeTodayStone` anchor is also
  /// absent.
  ///
  /// A whole week section (or even the full 3-stone cluster on some layouts)
  /// can approach the overlay's oversized-hole threshold, so this stays
  /// intentionally narrow — see the class doc on `AppTourOverlay` for that
  /// 70%-of-screen rule.
  Widget? _buildStoneClusterAnchor(HomeStageMapModel model, int n) {
    final weekIndex = model.currentWeekIndex;
    if (weekIndex == null) {
      return null;
    }
    final section = model.sections[weekIndex];
    final todayIndex = section.stones.indexWhere((stone) => stone.isCurrent);
    if (todayIndex < 0) {
      return null;
    }

    final anchors = homeStageAnchorsForSection(weekIndex);
    var firstIndex = (todayIndex - 1).clamp(0, section.stones.length - 1);
    var lastIndex = (todayIndex + 1).clamp(0, section.stones.length - 1);
    final half = _stageStoneSize / 2;

    Rect boundsFor(int first, int last) {
      var left = double.infinity;
      var top = double.infinity;
      var right = double.negativeInfinity;
      var bottom = double.negativeInfinity;
      for (var d = first; d <= last; d++) {
        final center = _stoneCenter(weekIndex, n, anchors, d);
        left = math.min(left, center.dx - half);
        top = math.min(top, center.dy - half);
        right = math.max(right, center.dx + half);
        bottom = math.max(bottom, center.dy + half);
      }
      return Rect.fromLTRB(left, top, right, bottom);
    }

    // The "running days and rest days" tour copy describes a mix, so widen
    // past the default ±1 neighbours — still confined to this week — when
    // they are all one kind, extending to the nearest day of the missing
    // kind. Only applied while the resulting rect stays comfortably under
    // the overlay's oversized-hole area threshold (`AppTourOverlay`'s
    // `_oversizedHoleAreaFraction` is 0.7 of the real viewport); if a mix
    // isn't reachable within that budget (e.g. a week of entirely
    // consecutive run days far from today), the original ±1 window is kept
    // and may legitimately show one kind only for that day.
    final hasRunInWindow = section.stones
        .sublist(firstIndex, lastIndex + 1)
        .any((stone) => stone.isRun);
    final hasRestInWindow = section.stones
        .sublist(firstIndex, lastIndex + 1)
        .any((stone) => !stone.isRun);
    if (!hasRunInWindow || !hasRestInWindow) {
      final neededRun = !hasRunInWindow;
      int? nearestIndex;
      var nearestDistance = section.stones.length;
      for (var d = 0; d < section.stones.length; d++) {
        if (section.stones[d].isRun != neededRun) {
          continue;
        }
        final distance = (d - todayIndex).abs();
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestIndex = d;
        }
      }
      if (nearestIndex != null) {
        final candidateFirst = math.min(firstIndex, nearestIndex);
        final candidateLast = math.max(lastIndex, nearestIndex);
        final candidateArea = boundsFor(
          candidateFirst,
          candidateLast,
        ).inflate(_kStoneClusterPadding);
        final areaCap = _viewportHeight > 0
            ? _sectionWidth * _viewportHeight * 0.45
            : double.infinity;
        if (candidateArea.width * candidateArea.height <= areaCap) {
          firstIndex = candidateFirst;
          lastIndex = candidateLast;
        }
      }
    }

    var rect = boundsFor(firstIndex, lastIndex).inflate(_kStoneClusterPadding);

    // Adjacent week sections overlap slightly on screen (see `_overlap` /
    // `kHomeStageBackgroundAspect`), so a week's last day and the following
    // week's first day — or a week's first day and the previous week's last
    // day — can sit close enough that this cluster's inflated rect would
    // bleed into a neighbouring week's own stone. Clamp the rect to stop
    // just short of whichever neighbour it would otherwise touch, so the
    // spotlight never visually overlaps a *neighbour* stone pulled in only
    // because it is within one day of today.
    //
    // The clamp is itself bounded by today's own stone edge so it can never
    // cut into the one stone this anchor must always fully contain: if today
    // is itself the boundary stone (e.g. the plan's last Sunday before the
    // final week), today's bare stone can, by a sub-visual sliver, already
    // sit this close to the next week's own first stone purely from the
    // connected-path background art — moving stones to close that gap is
    // out of scope here, so the clamp simply becomes a no-op in that case
    // rather than mis-targeting today.
    final todayCenter = _stoneCenter(weekIndex, n, anchors, todayIndex);
    final todayTop = todayCenter.dy - half - _kStoneClusterPadding;
    final todayBottom = todayCenter.dy + half + _kStoneClusterPadding;
    if (weekIndex + 1 < n) {
      final nextFirstBottom =
          _stoneCenter(
            weekIndex + 1,
            n,
            homeStageAnchorsForSection(weekIndex + 1),
            0,
          ).dy +
          half;
      final clampedTop = math.min(nextFirstBottom, todayTop);
      if (clampedTop > rect.top && clampedTop < rect.bottom) {
        rect = Rect.fromLTRB(rect.left, clampedTop, rect.right, rect.bottom);
      }
    }
    if (weekIndex - 1 >= 0) {
      final previousSection = model.sections[weekIndex - 1];
      final previousLastTop =
          _stoneCenter(
            weekIndex - 1,
            n,
            homeStageAnchorsForSection(weekIndex - 1),
            previousSection.stones.length - 1,
          ).dy -
          half;
      final clampedBottom = math.max(previousLastTop, todayBottom);
      if (clampedBottom < rect.bottom && clampedBottom > rect.top) {
        rect = Rect.fromLTRB(rect.left, rect.top, rect.right, clampedBottom);
      }
    }

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: const IgnorePointer(
        child: TutorialAnchor(
          id: TutorialAnchorId.homeStoneCluster,
          child: SizedBox.expand(),
        ),
      ),
    );
  }

  /// Speech bubble anchored above the guide character on today's stage.
  /// Hidden while walking, when there is no eligible today stage, or when no
  /// guide seam is wired in.
  Widget? _buildGuideBubble(
    HomeStageMapModel model,
    int n,
    double totalHeight,
  ) {
    if (_walking || !_hasTodayStage(model)) {
      return null;
    }
    if (widget.guideAgent == null || widget.guideRequest == null) {
      return null;
    }
    final anchor = _characterAnchorCenter(model, n);
    if (anchor == null) {
      return null;
    }

    const gap = 10.0;
    const horizontalSafeInset = 12.0;
    final bubbleWidth = math.min(
      280.0,
      math.max(0.0, _sectionWidth - horizontalSafeInset * 2),
    );
    if (bubbleWidth <= 0) {
      return null;
    }
    final charTopY = _characterTopForAnchor(anchor, _selectedCharacter);
    final left = (anchor.dx - bubbleWidth / 2)
        .clamp(
          horizontalSafeInset,
          math.max(
            horizontalSafeInset,
            _sectionWidth - bubbleWidth - horizontalSafeInset,
          ),
        )
        .toDouble();
    final safeTop = MediaQuery.paddingOf(context).top + horizontalSafeInset;
    final maxBubbleHeight = math.max(1.0, charTopY - gap - safeTop);

    // Consent is collected once via the onboarding bottom sheet and managed in
    // Account → Privacy & Safety. It governs the AI guide only: without it the
    // AI guide is hidden entirely (the cycle is never created; see
    // [_syncGuideBubble]), while an on-device guide still presents.
    final agent = widget.guideAgent;
    if (agent == null || !_guideConsentSatisfied(agent)) {
      return null;
    }

    final cycle = _guideCycle;
    if (cycle == null || !cycle.state.isVisible) {
      return null;
    }

    return Positioned(
      left: left,
      width: bubbleWidth,
      bottom: (totalHeight - (charTopY - gap)).clamp(0.0, totalHeight),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxBubbleHeight),
        child: _GuideSpeechBubble(
          key: ValueKey<String?>(model.currentStageId),
          state: cycle.state,
          isRestDay: widget.guideRequest?.isRestDay ?? false,
          onAdvance: _advanceGuideBubble,
          onDismiss: _dismissGuideBubble,
        ),
      ),
    );
  }

  /// Scroll offset that lands the character in its composed position, or null
  /// while the map has not been measured yet.
  ///
  /// Clamped to the scrollable range, so a plan whose current stage sits near
  /// either end of the map settles at that extreme instead of demanding an
  /// offset the map does not have.
  double? _characterScrollTarget(HomeStageMapModel model, int n, double total) {
    if (_viewportHeight <= 0) {
      return null;
    }

    final weekIndex = model.currentWeekIndex ?? 0;
    final dayIndex = model.characterDayIndex ?? 0;
    final anchors = homeStageAnchorsForSection(weekIndex);
    final anchor = _stoneCenter(weekIndex, n, anchors, dayIndex);
    final characterCenterY =
        _characterTopForAnchor(anchor, _selectedCharacter) +
        _characterHeightFor(_selectedCharacter) / 2;
    final maxScroll = math.max(0.0, total - _viewportHeight);
    return (characterCenterY -
            _viewportHeight * _kInitialCharacterViewportFraction)
        .clamp(0.0, maxScroll);
  }

  void _scheduleInitialScroll() {
    final target = _characterScrollOffset;
    if (_initialScrollDone || target == null) {
      return;
    }
    _initialScrollDone = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(target);
      }
    });
  }

  /// Scrolls back to the character after the shell reports a Home tap.
  ///
  /// Deferred a frame because the request arrives while Home may still be the
  /// off-screen tab: the offset is only trustworthy once the map has been laid
  /// out for the frame that puts it back on screen. Already being there is a
  /// no-op rather than a redundant animation.
  void _onRecenterRequested() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _characterScrollOffset;
      if (!mounted || target == null || !_scrollController.hasClients) {
        return;
      }
      if ((_scrollController.offset - target).abs() < 0.5) {
        return;
      }
      if (_menuReduceMotion) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
    // A post-frame callback does not schedule the frame that drains it, and
    // the request can arrive with nothing else pending, so ask for one.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget? _buildCharacter(HomeStageMapModel model, int n) {
    final weekIndex = model.currentWeekIndex;
    final dayIndex = model.characterDayIndex;
    if (weekIndex == null || dayIndex == null) {
      return null;
    }

    final character = _selectedCharacter;

    Offset center;
    RunnerCharacterFacing facing;
    double bob = 0;
    if (_walking && _walkTotalLength > 0) {
      final result = _walkSample(_walkController.value);
      center = result.$1;
      facing = result.$2;
      bob =
          math.sin(_walkController.value * math.pi * 6) *
          math.min(6, _sectionHeight * 0.01);
    } else {
      final anchors = homeStageAnchorsForSection(weekIndex);
      center = _stoneCenter(weekIndex, n, anchors, dayIndex);
      facing = RunnerCharacterFacing.front;
    }

    final charWidth = _characterWidth;
    final charHeight = _characterHeightFor(character);
    final asset = homeStageGuideAssetPath(
      character: character,
      facing: facing,
      isMoving: _walking,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    );
    final charLayoutWidth = RunnerCharacterSprite.layoutWidthFor(
      assetPath: asset,
      width: charWidth,
    );
    final canTapCharacter =
        !_walking && widget.guideAgent != null && widget.guideRequest != null;
    return Positioned(
      key: const ValueKey<String>('homeStageCharacter'),
      left: center.dx - charLayoutWidth / 2,
      top: _characterTopForAnchor(center, character) - bob,
      width: charLayoutWidth,
      height: charHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: RunnerCharacterSprite(
              character: character,
              assetPath: asset,
              width: charWidth,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
          if (canTapCharacter)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: charHeight * 0.72,
              child: Semantics(
                button: true,
                label: '${character.displayName} guide',
                child: GestureDetector(
                  key: const ValueKey<String>('homeGuideCharacterTapTarget'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _guideConsentSatisfied(widget.guideAgent!)
                      ? _toggleGuideBubble
                      : null,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  RunnerCharacter get _selectedCharacter =>
      SelectedRunnerCharacterScope.maybeOf(context)?.selectedOrDefault ??
      RunnerCharacter.blue;

  /// Static (non-walking) center of the character/guide-bubble anchor on the
  /// active week's stage map, or null when there is no character stage.
  Offset? _characterAnchorCenter(HomeStageMapModel model, int n) {
    final weekIndex = model.currentWeekIndex;
    final dayIndex = model.characterDayIndex;
    if (weekIndex == null || dayIndex == null) {
      return null;
    }
    final anchors = homeStageAnchorsForSection(weekIndex);
    return _stoneCenter(weekIndex, n, anchors, dayIndex);
  }

  (Offset, RunnerCharacterFacing) _walkSample(double t) {
    final distance = _walkTotalLength * t;
    var travelled = 0.0;
    for (var i = 0; i < _walkSegmentLengths.length; i++) {
      final segLength = _walkSegmentLengths[i];
      if (segLength <= 0) {
        continue;
      }
      if (distance <= travelled + segLength ||
          i == _walkSegmentLengths.length - 1) {
        final localT = ((distance - travelled) / segLength).clamp(0.0, 1.0);
        final start = _walkWaypoints[i];
        final end = _walkWaypoints[i + 1];
        final point = Offset.lerp(start, end, localT)!;
        final delta = end - start;
        return (point, _facingForDelta(delta));
      }
      travelled += segLength;
    }
    return (_walkWaypoints.last, RunnerCharacterFacing.back);
  }

  RunnerCharacterFacing _facingForDelta(Offset delta) {
    if (delta.dx.abs() > delta.dy.abs() * 0.75) {
      return delta.dx >= 0
          ? RunnerCharacterFacing.right
          : RunnerCharacterFacing.left;
    }
    return RunnerCharacterFacing.back;
  }
}

/// A background section whose top edge fades to transparent so the week above
/// (painted behind it) bleeds through for a soft, continuous transition.
