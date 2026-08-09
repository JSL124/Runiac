import 'package:flutter/widgets.dart';

import 'runiac_haptics.dart';

/// Exposes the app-wide [RuniacHaptics] instance to descendants, mounted at
/// the app root above `MaterialApp` so every route/screen can reach it.
class RuniacHapticsScope extends InheritedWidget {
  const RuniacHapticsScope({
    super.key,
    required this.haptics,
    required super.child,
  });

  final RuniacHaptics haptics;

  static RuniacHaptics? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RuniacHapticsScope>()
        ?.haptics;
  }

  static RuniacHaptics of(BuildContext context) {
    final haptics = maybeOf(context);
    assert(haptics != null, 'No RuniacHapticsScope found.');
    return haptics!;
  }

  @override
  bool updateShouldNotify(RuniacHapticsScope oldWidget) {
    return haptics != oldWidget.haptics;
  }
}
