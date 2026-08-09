/// Local high-water marker for the one-shot plan-completion ceremony.
///
/// The presentation is idempotent: a backend-recorded plan completion is
/// celebrated exactly once, then never again on resume/replay/restart. The
/// marker is the `completedAt` epoch-millis of the most recent completion the
/// user has already been shown; a completion is "unseen" only when it is
/// strictly newer than the stored marker.
///
/// This port carries no Firestore or trusted-state access — it is purely a
/// local per-user flag, mirroring [ChallengeResultSeenStore].
abstract interface class PlanCompletionSeenStore {
  /// The `completedAt` millis of the last celebrated plan completion, or
  /// `null` when nothing has been celebrated yet for this user.
  Future<int?> lastSeenPlanCompletedAtMs();

  /// Records that a plan completion at [completedAtMs] has been celebrated.
  Future<void> recordSeenPlanCompletion(int completedAtMs);
}

/// Session-scoped in-memory marker. Used by tests and by any non-persistent
/// composition path. Because it is not durable, a full app restart may
/// re-present the newest completion once — acceptable for the in-memory seam.
class InMemoryPlanCompletionSeenStore implements PlanCompletionSeenStore {
  InMemoryPlanCompletionSeenStore({int? initialCompletedAtMs})
    : _lastSeenCompletedAtMs = initialCompletedAtMs;

  int? _lastSeenCompletedAtMs;

  @override
  Future<int?> lastSeenPlanCompletedAtMs() async => _lastSeenCompletedAtMs;

  @override
  Future<void> recordSeenPlanCompletion(int completedAtMs) async {
    if (_lastSeenCompletedAtMs == null ||
        completedAtMs > _lastSeenCompletedAtMs!) {
      _lastSeenCompletedAtMs = completedAtMs;
    }
  }
}
