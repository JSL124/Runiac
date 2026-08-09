import 'package:flutter/widgets.dart';

/// Lets a run-flow screen sitting on top of the shell send the runner to the
/// Home dashboard when a server-recorded plan completion is still waiting to be
/// celebrated there.
///
/// The ceremony is deliberately Home-only: `HomeTab` holds it while Home is not
/// frontmost so it never lands on the cool-down, summary or XP-update screen.
/// But a run can be started from any tab, and the run flow pops back to
/// whichever tab was selected when it began — so a runner who started from
/// Feed, Leaderboard or You returns to that tab, Home stays covered, and the
/// held celebration is never released. The XP-update screen's "Home" action
/// therefore asks the shell to select the Home dashboard *before* it pops, but
/// only when a celebration is actually pending, so an ordinary run still leaves
/// the runner on the tab they came from.
///
/// The router is provided above the app's navigator, because the run-flow
/// routes are pushed onto that navigator and are therefore siblings of the
/// shell rather than its descendants.
class PlanCompletionCelebrationRouter {
  PlanCompletionCelebrationRouter({required this.isCelebrationPending});

  /// Whether the backend has recorded a completion for the active plan that the
  /// local one-shot marker says has not been celebrated yet.
  ///
  /// Read-only by construction: it never advances the marker. Only `HomeTab`
  /// does that, and only once it is committed to opening the overlay — so a
  /// check here can never swallow the celebration it is checking for.
  final Future<bool> Function() isCelebrationPending;

  VoidCallback? _showHomeDashboard;

  /// Registers the shell's Home-tab selection. The shell owns tab state, so it
  /// attaches on mount and detaches on dispose.
  void attachHomeDashboard(VoidCallback handler) {
    _showHomeDashboard = handler;
  }

  /// Detaches [handler] only if it is still the attached one, so a shell being
  /// disposed after a replacement has already attached cannot unhook it.
  /// Compared with `==` rather than `identical`, because Dart guarantees
  /// equality — not identity — for repeated tear-offs of the same instance
  /// method on the same object.
  void detachHomeDashboard(VoidCallback handler) {
    if (_showHomeDashboard == handler) {
      _showHomeDashboard = null;
    }
  }

  /// Selects the Home dashboard tab. A no-op when no shell is listening — QA
  /// surfaces and widget tests pump these screens without one.
  void showHomeDashboard() {
    _showHomeDashboard?.call();
  }
}

class PlanCompletionCelebrationScope extends InheritedWidget {
  const PlanCompletionCelebrationScope({
    super.key,
    required this.router,
    required super.child,
  });

  final PlanCompletionCelebrationRouter router;

  static PlanCompletionCelebrationRouter? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PlanCompletionCelebrationScope>()
        ?.router;
  }

  @override
  bool updateShouldNotify(PlanCompletionCelebrationScope oldWidget) {
    return router != oldWidget.router;
  }
}
