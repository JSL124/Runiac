/// Local, device-only record of whether the one-time app tour has been
/// armed (queued to run on next eligible screen) and/or completed for a
/// user.
///
/// This is a UI-nudge flag only: it decides whether to auto-present the
/// spotlight tour after onboarding. It never grants entitlement and never
/// influences any backend-owned value (XP, level, rank, streak, leaderboard
/// score, or subscription privilege state).
abstract interface class AppTourSeenStore {
  /// True when the tour has been armed (queued to run) for [uid].
  Future<bool> isArmed({required String? uid});

  /// Sets whether the tour is armed for [uid]. Passing `false` disarms the
  /// tour, e.g. once it has been shown or dismissed.
  Future<void> setArmed({required String? uid, required bool armed});

  /// True when the tour has already been completed for [uid].
  Future<bool> isCompleted({required String? uid});

  /// Records that the tour has been completed for [uid].
  Future<void> markCompleted({required String? uid});
}

/// Builds the per-user "armed" preference key. Falls back to an anonymous
/// key when the user has no uid.
String appTourArmedPreferenceKey(String? uid) {
  final scope = (uid == null || uid.isEmpty) ? 'anonymous' : uid;
  return 'app_tour_armed_$scope';
}

/// Builds the per-user "completed" preference key. Falls back to an
/// anonymous key when the user has no uid.
String appTourCompletedPreferenceKey(String? uid) {
  final scope = (uid == null || uid.isEmpty) ? 'anonymous' : uid;
  return 'app_tour_completed_$scope';
}

/// In-memory implementation for tests and previews.
class InMemoryAppTourSeenStore implements AppTourSeenStore {
  InMemoryAppTourSeenStore();

  final Map<String, bool> _values = <String, bool>{};

  @override
  Future<bool> isArmed({required String? uid}) async =>
      _values[appTourArmedPreferenceKey(uid)] ?? false;

  @override
  Future<void> setArmed({required String? uid, required bool armed}) async {
    _values[appTourArmedPreferenceKey(uid)] = armed;
  }

  @override
  Future<bool> isCompleted({required String? uid}) async =>
      _values[appTourCompletedPreferenceKey(uid)] ?? false;

  @override
  Future<void> markCompleted({required String? uid}) async {
    _values[appTourCompletedPreferenceKey(uid)] = true;
  }
}
