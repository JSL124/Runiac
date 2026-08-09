import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/app_tour_steps.dart';
import '../domain/models/tutorial_step.dart';
import 'tutorial_anchor_registry.dart';

/// Drives the one-time app tour's state machine: which step is showing,
/// which bottom-nav tab it needs, and the resolved spotlight [hole] for that
/// step.
///
/// Pure state/orchestration — it knows nothing about `AppTourSeenStore`
/// persistence or how it is composed into the widget tree; [AppTourHost] owns
/// both of those.
class AppTourController extends ChangeNotifier {
  AppTourController({
    this.steps = runiacAppTourSteps,
    required this.onRequestTab,
    TutorialAnchorRegistry? anchors,
    this.anchorPollInterval = const Duration(milliseconds: 100),
    this.anchorPollBudget = const Duration(seconds: 2),
    this.preferredAnchorWindow = const Duration(milliseconds: 800),
    this.settleDelay = const Duration(milliseconds: 300),
  }) : anchors = anchors ?? TutorialAnchorRegistry();

  /// The tour script. Defaults to the shipped 9-step Runiac app tour.
  final List<TutorialStep> steps;

  /// Registry of live anchor positions, shared with the [AppTourHost]'s
  /// `TutorialAnchorScope`.
  final TutorialAnchorRegistry anchors;

  /// Requests the shell switch its visible bottom-nav tab. Never called with
  /// `2` (Run): no step targets the Run tab, since Run is a pushed route, not
  /// a tab — the run-button step stays on Home and spotlights the nav item
  /// geometrically instead (see [TutorialStep.bottomNavItemIndex]).
  final void Function(int tabIndex) onRequestTab;

  /// How often to re-check [anchors] while waiting for a step's anchor to
  /// mount (async content: a loading leaderboard, a post-frame stage-map
  /// scroll, feed/you hydrating from session stores).
  final Duration anchorPollInterval;

  /// Total time to keep polling before giving up and falling back to
  /// no-hole/fallback-copy mode for the step.
  final Duration anchorPollBudget;

  /// How long, at the start of a step's poll, only the single
  /// highest-priority candidate in [TutorialStep.anchorCandidates] is
  /// eligible to resolve.
  ///
  /// A lower-priority fallback anchor can be mounted well before a primary
  /// one that is simply waiting on an async load (e.g. `feed`'s whole-list
  /// container mounts on the first frame, while its first-post anchor only
  /// exists once posts finish loading). Without this window, [_pollAnchor]
  /// would settle for the fallback on its very first tick and never give the
  /// primary a chance. Clamped to never exceed [anchorPollBudget] so the
  /// "any candidate" remainder phase in [_pollAnchor] is never starved out by
  /// a misconfigured window. See [_pollAnchor] for the two-phase poll this
  /// drives.
  final Duration preferredAnchorWindow;

  /// Extra settle time the host waits after a blocking modal route/sheet
  /// leaves, on top of one frame, before resuming or starting the tour —
  /// long enough for the sheet's exit animation to finish.
  final Duration settleDelay;

  int _stepIndex = 0;

  /// Zero-based index of the step currently being narrated.
  int get stepIndex => _stepIndex;

  /// The step currently being narrated.
  TutorialStep get currentStep => steps[_stepIndex];

  /// Total number of steps in the tour script.
  int get stepCount => steps.length;

  bool _running = false;

  /// True from [start]/[restart] until the tour finishes or is [skip]ped.
  bool get running => _running;

  bool _paused = false;

  /// True while a blocking modal route/sheet sits above the shell. The
  /// overlay must be hidden (but the step index preserved) while this is true
  /// — see [AppTourHost]'s modal-sequencing rule.
  bool get paused => _paused;

  Rect? _hole;

  /// The already-measured, screen-space spotlight bounds for [currentStep],
  /// or `null` when no anchor resolved (the step renders in no-hole mode).
  Rect? get hole => _hole;

  bool _useFallbackCopy = false;

  /// True when [currentStep] should render
  /// [TutorialStep.effectiveFallbackMessage] instead of
  /// [TutorialStep.message].
  ///
  /// This is true both when nothing in [TutorialStep.anchorCandidates]
  /// resolved (rule 6: a step is never silently skipped — it renders in
  /// no-hole mode with the fallback copy so the "N of 9" counter stays
  /// truthful) and when only a *non-primary* candidate resolved. The latter
  /// matters for steps like `leaderboard`, whose second candidate
  /// (`leaderboardStateMessage`) is itself the "you're not in a ranked state
  /// yet" widget — spotlighting it while still narrating the primary "you're
  /// ranked here" copy would contradict what's on screen, so reaching a
  /// fallback candidate is treated the same as reaching no candidate at all.
  bool get useFallbackCopy => _useFallbackCopy;

  int _currentTab = 0;

  /// The bottom-nav tab index the controller currently believes is showing.
  int get currentTab => _currentTab;

  bool _disposed = false;
  int _resolveSerial = 0;

  /// True while [next] is advancing and its anchor resolution has not settled.
  ///
  /// Anchor resolution awaits a frame and can then poll for up to
  /// [anchorPollBudget], so a second tap on Next arriving in that window would
  /// otherwise pass the running check and increment the step a second time,
  /// silently skipping a step. Extra taps are absorbed rather than queued —
  /// queuing would just defer the same skip. [skip] is deliberately NOT gated
  /// on this, so a user can always leave a slow-resolving step.
  bool _advancing = false;

  /// Starts the tour from the first step.
  Future<void> start() async {
    if (_disposed || steps.isEmpty) {
      return;
    }
    _stepIndex = 0;
    _running = true;
    _paused = false;
    _hole = null;
    _useFallbackCopy = false;
    _advancing = false;
    notifyListeners();
    await _resolveCurrentStep();
  }

  /// Restarts the tour from the first step, forcing tab 0 unconditionally
  /// (unlike [start], which only switches tab when [currentTab] disagrees
  /// with the step). Used by manual replay (e.g. a Home menu "App tour" row)
  /// where the shell's actual selected tab may have drifted since the last
  /// time the controller ran.
  Future<void> restart() async {
    if (_disposed || steps.isEmpty) {
      return;
    }
    _stepIndex = 0;
    _running = true;
    _paused = false;
    _hole = null;
    _useFallbackCopy = false;
    _advancing = false;
    onRequestTab(0);
    _currentTab = 0;
    notifyListeners();
    await _resolveCurrentStep();
  }

  /// Hides the overlay without losing tour progress, e.g. while a modal
  /// route/sheet is on top of the shell.
  void pause() {
    if (_disposed || !_running || _paused) {
      return;
    }
    _paused = true;
    notifyListeners();
  }

  /// Un-hides the overlay and re-resolves the current step's anchor, since
  /// layout may have changed while paused.
  Future<void> resume() async {
    if (_disposed || !_running || !_paused) {
      return;
    }
    _paused = false;
    notifyListeners();
    await _resolveCurrentStep();
  }

  /// Advances to the next step, or finishes the tour from the last step.
  Future<void> next() async {
    if (_disposed || !_running || _advancing) {
      return;
    }
    if (_stepIndex >= steps.length - 1) {
      _stop();
      return;
    }
    _advancing = true;
    _stepIndex += 1;
    // Drop the previous step's resolved anchor before announcing the new one.
    // `_resolveCurrentStep` may switch tabs and then poll for up to
    // `anchorPollBudget`, so publishing the new step while `_hole` still holds
    // the old coordinates would narrate one thing while spotlighting another —
    // e.g. the Leaderboard copy over the Feed card's cutout. The step renders
    // in no-hole mode until its own anchor resolves.
    _hole = null;
    _useFallbackCopy = false;
    notifyListeners();
    try {
      await _resolveCurrentStep();
    } finally {
      _advancing = false;
    }
  }

  /// Ends the tour early. Produces the same terminal state as finishing the
  /// last step via [next] — [AppTourHost] treats both as "the tour is done"
  /// and records the same seen-store outcome for either.
  void skip() {
    if (_disposed || !_running) {
      return;
    }
    _stop();
  }

  /// Re-resolves [currentStep]'s anchor without changing the step or running
  /// state. Used by [AppTourHost] after app-lifecycle resume, metrics change
  /// (rotation/resize), or a modal route/sheet leaving the foreground.
  Future<void> refreshAnchor() async {
    if (_disposed || !_running || _paused) {
      return;
    }
    await _resolveCurrentStep();
  }

  void _stop() {
    _cancelPendingWait();
    // Abandon any in-flight resolution so a skip taken mid-advance cannot
    // write a hole back onto a stopped tour.
    _resolveSerial += 1;
    _advancing = false;
    _running = false;
    _paused = false;
    _hole = null;
    _useFallbackCopy = false;
    notifyListeners();
  }

  Future<void> _resolveCurrentStep() async {
    _cancelPendingWait();
    final serial = ++_resolveSerial;
    final step = currentStep;

    // Tabs other than Home are not in the widget tree until first visited,
    // and an off-stage tab lays out but never paints or hit-tests, so the
    // requested tab switch must always happen (and be allowed to settle)
    // before any anchor is measured.
    if (step.tabIndex != _currentTab) {
      onRequestTab(step.tabIndex);
      _currentTab = step.tabIndex;
    }

    await WidgetsBinding.instance.endOfFrame;
    if (_disposed || serial != _resolveSerial) {
      return;
    }

    if (step.anchorCandidates.isEmpty && step.bottomNavItemIndex == null) {
      // A step with nothing to spotlight (welcome/finish): render in no-hole
      // mode with its own message — `effectiveFallbackMessage` already
      // degrades to `message` when `fallbackMessage` is empty, so this is not
      // treated as a resolution failure.
      _hole = null;
      _useFallbackCopy = false;
      notifyListeners();
      return;
    }

    final hit = await _pollAnchor(step.anchorCandidates, serial: serial);
    if (_disposed || serial != _resolveSerial) {
      return;
    }

    if (hit == null) {
      _hole = null;
      _useFallbackCopy = true;
      notifyListeners();
      return;
    }

    var rect = hit.rect;
    final anchorContext = anchors.contextFor(hit.id);
    if (anchorContext != null &&
        anchorContext.mounted &&
        Scrollable.maybeOf(anchorContext) != null) {
      try {
        if (anchorContext.mounted) {
          await Scrollable.ensureVisible(anchorContext, alignment: 0.5);
        }
      } catch (_) {
        // Best-effort: keep the pre-scroll rect if this fails.
      }
      if (_disposed || serial != _resolveSerial) {
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (_disposed || serial != _resolveSerial) {
        return;
      }
      rect = anchors.rectFor(hit.id) ?? rect;
    }

    if (step.bottomNavItemIndex != null &&
        hit.id == TutorialAnchorId.bottomNavBar) {
      rect = bottomNavItemRect(rect, step.bottomNavItemIndex!);
    }

    final resolvedIndex = step.anchorCandidates.indexOf(hit.id);
    _hole = rect;
    _useFallbackCopy = resolvedIndex > 0;
    notifyListeners();
  }

  Future<_AnchorHit?> _pollAnchor(
    List<TutorialAnchorId> candidates, {
    required int serial,
  }) async {
    if (candidates.isEmpty) {
      return null;
    }
    // Elapsed time is tracked by accumulating the exact `anchorPollInterval`
    // durations already waited, rather than reading `DateTime.now()`.
    // `Timer`/`Future.delayed` are the only primitives a fake-async widget
    // test zone virtualizes — wall-clock reads are not — so a
    // `DateTime.now()`-based deadline never actually expires under test
    // (real CPU time barely advances across `tester.pump()` calls), leaving
    // the poll running forever on the previous step's stale copy.
    var elapsed = Duration.zero;
    // Clamped so a `preferredAnchorWindow` misconfigured to exceed the whole
    // budget can never make the "any candidate" remainder phase below
    // unreachable.
    final preferredWindow = preferredAnchorWindow > anchorPollBudget
        ? anchorPollBudget
        : preferredAnchorWindow;
    while (true) {
      if (_disposed || serial != _resolveSerial) {
        return null;
      }
      // Preferred window: only the single highest-priority candidate may
      // resolve, so a lower-priority fallback that is already mounted does
      // not win by default over a primary anchor that simply hasn't finished
      // an async load yet. Once the window elapses, every candidate is
      // eligible again, still checked in priority order, for the rest of the
      // budget — a step is never skipped, only degraded to its fallback.
      final eligible = elapsed < preferredWindow
          ? candidates.take(1)
          : candidates;
      for (final id in eligible) {
        final rect = anchors.rectFor(id);
        if (rect != null) {
          return _AnchorHit(id, rect);
        }
      }
      if (elapsed >= anchorPollBudget || anchorPollInterval <= Duration.zero) {
        return null;
      }
      await _wait(anchorPollInterval);
      if (_disposed || serial != _resolveSerial) {
        return null;
      }
      elapsed += anchorPollInterval;
    }
  }

  /// Waits for [duration] via an explicitly cancellable [Timer], rather than
  /// a bare `Future.delayed`. [skip]/[dispose]/a superseding
  /// [_resolveCurrentStep] call cancel [_pendingWaitTimer] immediately, so no
  /// stray timer is ever left ticking once the controller has moved on —
  /// important both for correctness (no anchor writes after teardown) and
  /// because widget tests fail their pending-timer invariant otherwise.
  Timer? _pendingWaitTimer;

  /// The waiter [_pendingWaitTimer] will complete.
  ///
  /// Cancelling must complete it too, not just drop the timer: the awaiting
  /// [_pollAnchor] would otherwise stay suspended forever, so the
  /// [_resolveCurrentStep] that owns it never returns and [next] never reaches
  /// its `finally`. That would leave [_advancing] stuck true and silently
  /// ignore every later Next tap, leaving the tour skippable but not
  /// advanceable. Callers past the wait re-check their serial, so completing
  /// early simply lets a superseded resolve unwind.
  Completer<void>? _pendingWait;

  Future<void> _wait(Duration duration) {
    _cancelPendingWait();
    final completer = Completer<void>();
    _pendingWait = completer;
    _pendingWaitTimer = Timer(duration, () {
      _pendingWaitTimer = null;
      _pendingWait = null;
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  void _cancelPendingWait() {
    _pendingWaitTimer?.cancel();
    _pendingWaitTimer = null;
    final pending = _pendingWait;
    _pendingWait = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPendingWait();
    super.dispose();
  }
}

class _AnchorHit {
  const _AnchorHit(this.id, this.rect);
  final TutorialAnchorId id;
  final Rect rect;
}

/// Exposes the shell's single [AppTourController] to descendants (e.g. the
/// Home menu's "App tour" replay row) without threading it through every
/// intervening widget's constructor.
///
/// Mounted by [AppTourHost] above `widget.child`, so every tab's subtree —
/// including the Home menu panel — can reach the controller via
/// [maybeOf]/[of] the same way it already reaches
/// `SelectedRunnerCharacterScope` and `TutorialAnchorScope`.
class RuniacAppTourScope extends InheritedNotifier<AppTourController> {
  const RuniacAppTourScope({
    required AppTourController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppTourController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RuniacAppTourScope>()
        ?.notifier;
  }

  static AppTourController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No RuniacAppTourScope found.');
    return controller!;
  }
}
