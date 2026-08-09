/// Local high-water marker for the one-shot foreground Result presentation.
///
/// The presentation is idempotent: a terminal Challenge result is auto-presented
/// exactly once, then never again on resume/replay. The marker is the
/// `endedAt` epoch-millis of the most recent result the user has already been
/// shown. A history entry is "unseen" only when it is strictly newer than the
/// stored marker. This port carries no Firestore or trusted-state access; it is
/// purely a local per-user flag, mirroring how other features persist small
/// local markers.
abstract interface class ChallengeResultSeenStore {
  /// The `endedAt` millis of the last auto-presented result, or `null` when
  /// nothing has been presented yet for this user.
  Future<int?> lastSeenResultEndedAtMs();

  /// Records that a result ending at [endedAtMs] has been presented.
  Future<void> recordSeenResult(int endedAtMs);
}

/// Session-scoped in-memory marker. Used by tests and by any non-persistent
/// composition path. Because it is not durable, a full app restart may
/// re-present the newest result once — acceptable for the in-memory seam.
class InMemoryChallengeResultSeenStore implements ChallengeResultSeenStore {
  InMemoryChallengeResultSeenStore({int? initialEndedAtMs})
      : _lastSeenEndedAtMs = initialEndedAtMs;

  int? _lastSeenEndedAtMs;

  @override
  Future<int?> lastSeenResultEndedAtMs() async => _lastSeenEndedAtMs;

  @override
  Future<void> recordSeenResult(int endedAtMs) async {
    if (_lastSeenEndedAtMs == null || endedAtMs > _lastSeenEndedAtMs!) {
      _lastSeenEndedAtMs = endedAtMs;
    }
  }
}
