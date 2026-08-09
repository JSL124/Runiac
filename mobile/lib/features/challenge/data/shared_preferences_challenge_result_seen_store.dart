import 'package:shared_preferences/shared_preferences.dart';

import '../domain/challenge_result_seen_store.dart';

/// Device-local mirror of the one-shot Result marker, backed by the app's
/// existing `shared_preferences` dependency (the same local-flag pattern used
/// by notification-center settings). The marker is scoped by uid so the
/// idempotent presentation survives an app restart without re-presenting.
///
/// This copy answers instantly and works offline, but it dies with the
/// installation — which is why it is paired with the account-scoped
/// [FirestoreChallengeResultSeenStore] inside
/// [DurableChallengeResultSeenStore] rather than used on its own.
///
/// This adapter stores only a single integer millis high-water mark per user —
/// no trusted challenge state, no Firestore access.
class SharedPreferencesChallengeResultSeenStore
    implements ChallengeResultSeenStore {
  SharedPreferencesChallengeResultSeenStore({
    required this.uidProvider,
    this.keyPrefix = 'runiac.challenge.lastSeenResultMs',
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
  Future<int?> lastSeenResultEndedAtMs() async {
    final key = _key();
    if (key == null) {
      return null;
    }
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(key);
  }

  @override
  Future<void> recordSeenResult(int endedAtMs) async {
    final key = _key();
    if (key == null) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getInt(key);
    if (existing != null && endedAtMs <= existing) {
      return;
    }
    await preferences.setInt(key, endedAtMs);
  }
}
