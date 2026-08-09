import 'package:shared_preferences/shared_preferences.dart';

import '../domain/plan_completion_seen_store.dart';

/// Durable per-user implementation of the one-shot plan-completion marker,
/// backed by the app's existing `shared_preferences` dependency — the same
/// local-flag pattern as [SharedPreferencesChallengeResultSeenStore]. The
/// marker is scoped by uid so the idempotent celebration survives an app
/// restart without re-presenting.
///
/// This adapter stores only a single integer millis high-water mark per user —
/// no trusted plan state, no Firestore access.
class SharedPreferencesPlanCompletionSeenStore
    implements PlanCompletionSeenStore {
  SharedPreferencesPlanCompletionSeenStore({
    required this.uidProvider,
    this.keyPrefix = 'runiac.plan.lastSeenCompletedAtMs',
  });

  /// Resolves the signed-in uid; `null` when signed out (no marker read/write).
  final String? Function() uidProvider;
  final String keyPrefix;

  String? _key() {
    final uid = uidProvider();
    if (uid == null || uid.isEmpty) {
      return null;
    }
    return '$keyPrefix.$uid';
  }

  @override
  Future<int?> lastSeenPlanCompletedAtMs() async {
    final key = _key();
    if (key == null) {
      return null;
    }
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(key);
  }

  @override
  Future<void> recordSeenPlanCompletion(int completedAtMs) async {
    final key = _key();
    if (key == null) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getInt(key);
    if (existing != null && completedAtMs <= existing) {
      return;
    }
    await preferences.setInt(key, completedAtMs);
  }
}
