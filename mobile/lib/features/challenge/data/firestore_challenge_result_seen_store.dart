import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/challenge_result_seen_store.dart';

/// Account-scoped implementation of the one-shot Result marker, held in
/// `users/{uid}/challengeState/challengeResultSeen`.
///
/// The marker was device-local before this: deleting and reinstalling the app,
/// or signing in on a second device, wiped it, and any result still inside the
/// presenter's recency window replayed its ceremony as if it had never been
/// shown. Keeping it on the account is what makes "presented exactly once"
/// survive a reinstall.
///
/// This adapter stores a single integer millis high-water mark and nothing
/// else. It is the one document the client may write under `users/{uid}`, and
/// `firestore.rules` constrains it to that shape and to moving forward only —
/// the outcome, badge ownership, and every metre stay backend-owned in
/// `challengeHistory` / `challengeBadges`.
class FirestoreChallengeResultSeenStore implements ChallengeResultSeenStore {
  FirestoreChallengeResultSeenStore({
    required this.uidProvider,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _field = 'lastSeenResultEndedAtMs';

  /// Resolves the signed-in uid; `null` when signed out (no marker read/write).
  final String? Function() uidProvider;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>>? _reference() {
    final uid = uidProvider();
    if (uid == null || uid.isEmpty) {
      return null;
    }
    // Path and document id are spelled out here because `firestore.rules` pins
    // both: the marker is writable only at this exact document.
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('challengeState')
        .doc('challengeResultSeen');
  }

  @override
  Future<int?> lastSeenResultEndedAtMs() async {
    final reference = _reference();
    if (reference == null) {
      return null;
    }
    final snapshot = await reference.get();
    final value = snapshot.data()?[_field];
    return value is int ? value : null;
  }

  @override
  Future<void> recordSeenResult(int endedAtMs) async {
    final reference = _reference();
    if (reference == null) {
      return;
    }
    // `merge` rather than a plain set so the write stays a single-field update
    // whether or not the document exists yet — which is exactly the shape the
    // rules allow.
    await reference.set(<String, Object?>{
      _field: endedAtMs,
    }, SetOptions(merge: true));
  }
}
