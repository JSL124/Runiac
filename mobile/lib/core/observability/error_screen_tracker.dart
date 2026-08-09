import 'package:flutter/widgets.dart';

/// Tracks the name of the currently active route so the error reporter can
/// attach a real `screen` label to captured errors without any manual
/// instrumentation at each call site.
///
/// Only ever reflects a *named* route (`RouteSettings.name`). This app
/// currently navigates almost entirely through unnamed `MaterialPageRoute`s,
/// so [currentScreen] is `null` far more often than not in practice —
/// `RuniacErrorReporter.resolveErrorReportScreen` (in
/// `runiac_error_reporter.dart`) is what falls back to a stack-frame-derived
/// label when that is the case, so a `null` here never reaches the network
/// as the `screen` payload field.
///
/// Deliberately has no Firebase dependency: it is attached to the app's
/// `MaterialApp` via `navigatorObservers` and is safe to construct in any
/// widget test.
class ErrorScreenTracker extends NavigatorObserver {
  String? _currentScreen;

  /// Best-effort label for the active screen. `null` until the first named
  /// route has been pushed — see the class doc for how often that is.
  String? get currentScreen => _currentScreen;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateScreen(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _updateScreen(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _updateScreen(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _updateScreen(newRoute);
  }

  void _updateScreen(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty) {
      _currentScreen = name;
    }
  }
}

/// Shared instance attached to the app's `MaterialApp` (see `app.dart`) and
/// read by the globally installed error hooks in `main.dart`. It carries no
/// Firebase state, so sharing it as a singleton keeps both wiring sites free
/// of a constructor-injection seam that would otherwise have to thread
/// through `RuniacApp`.
final ErrorScreenTracker runiacErrorScreenTracker = ErrorScreenTracker();
