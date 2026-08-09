/// The runner's "keep my running record private" preference, stored in
/// `userProfiles/{uid}.publicStatsHidden`.
///
/// This repository only reads and writes the preference. It decides nothing
/// about what another runner receives: `getRunnerPublicProfile` is the single
/// enforcement point, and it withholds the hidden values server-side. Nothing
/// here — and nothing on any screen — may be the only thing standing between a
/// viewer and another runner's record.
///
/// The preference is display-only. No XP, level, rank, streak, leaderboard
/// score, or entitlement is derived from it in either direction, which is why
/// the owner may write it directly under `firestore.rules` rather than through
/// a callable.
abstract interface class ProfileVisibilityRepository {
  /// True when the runner has chosen to keep their record private.
  Future<bool> loadStatsHidden();

  Future<void> saveStatsHidden({required bool hidden});
}

/// Raised when the preference cannot be read or written — no signed-in runner,
/// or Firebase unreachable. The caller shows the control as unavailable rather
/// than guessing a value, because guessing `false` would tell a runner their
/// record is public when it may not be, and guessing `true` would tell them
/// they are hidden when they are not.
class ProfileVisibilityUnavailable implements Exception {
  const ProfileVisibilityUnavailable();

  @override
  String toString() => 'ProfileVisibilityUnavailable()';
}

/// In-memory stand-in for previews and widget tests. Starts visible and
/// remembers what it was told, so a test can drive the switch without Firebase.
class InMemoryProfileVisibilityRepository
    implements ProfileVisibilityRepository {
  InMemoryProfileVisibilityRepository([this._hidden = false]);

  bool _hidden;

  @override
  Future<bool> loadStatsHidden() async => _hidden;

  @override
  Future<void> saveStatsHidden({required bool hidden}) async {
    _hidden = hidden;
  }
}
