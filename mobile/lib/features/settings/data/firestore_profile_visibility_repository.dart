import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/repositories/profile_visibility_repository.dart';

typedef CurrentUidReader = String? Function();

/// Reads and writes `userProfiles/{uid}.publicStatsHidden` for the signed-in
/// runner.
///
/// `userProfiles/{uid}` is owner-read/owner-write in `firestore.rules`, so this
/// touches only the runner's own document. What another viewer receives is
/// decided by `getRunnerPublicProfile`, never here.
class FirestoreProfileVisibilityRepository
    implements ProfileVisibilityRepository {
  const FirestoreProfileVisibilityRepository({this.firestore, this.currentUid});

  /// Injected by tests. Null resolves to [FirebaseFirestore.instance], and only
  /// after the uid check has passed.
  final FirebaseFirestore? firestore;

  /// Injected by tests. Null reads the signed-in runner from FirebaseAuth.
  final CurrentUidReader? currentUid;

  @override
  Future<bool> loadStatsHidden() async {
    final document = await _profileRef().get();
    // Anything other than an explicit `true` reads as visible, matching the
    // server-side gate in `getRunnerPublicProfile` exactly. A malformed or
    // absent field must never be shown to the runner as "you are hidden".
    return document.data()?['publicStatsHidden'] == true;
  }

  @override
  Future<void> saveStatsHidden({required bool hidden}) async {
    // Merged, not set: this document also holds the runner's onboarding and
    // personal profile, and the switch owns exactly one field of it.
    await _profileRef().set(<String, Object>{
      'publicStatsHidden': hidden,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _profileRef() {
    final uid = _resolveUid();
    if (uid == null || uid.isEmpty) {
      throw const ProfileVisibilityUnavailable();
    }
    return _resolveFirestore().collection('userProfiles').doc(uid);
  }

  /// Guarded the same way `runner_achievement_profile_screen.dart` guards its
  /// own `FirebaseAuth.instance` read: widget tests that reach this repository
  /// never call `Firebase.initializeApp()`, so `FirebaseAuth.instance` itself
  /// throws rather than just returning a null user.
  String? _resolveUid() {
    final reader = currentUid;
    if (reader != null) {
      return reader();
    }
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } on Object {
      return null;
    }
  }

  /// Resolved only after the uid check passes, so an unauthenticated build
  /// surfaces [ProfileVisibilityUnavailable] instead of a Firebase
  /// initialization error.
  FirebaseFirestore _resolveFirestore() {
    return firestore ?? FirebaseFirestore.instance;
  }
}
