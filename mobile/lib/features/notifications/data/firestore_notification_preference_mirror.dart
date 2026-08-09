import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/repositories/notification_preference_mirror.dart';

/// Writes the derived `socialActivityEnabled` boolean into
/// `notificationPreferences/{uid}`, so the server-side feed-engagement
/// notification emitter can read it without a client-trusted write path.
///
/// `merge: true` is mandatory: this document also carries
/// `runReminderEnabled` and `reminderTime`, which the scheduled push
/// dispatcher reads. A non-merge `set` would wipe those keys every time the
/// Social toggle changes.
class FirestoreNotificationPreferenceMirror
    implements NotificationPreferenceMirror {
  FirestoreNotificationPreferenceMirror({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<void> mirror({
    required String uid,
    required bool socialActivityEnabled,
  }) async {
    await _firestore.collection('notificationPreferences').doc(uid).set({
      'ownerUid': uid,
      'socialActivityEnabled': socialActivityEnabled,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }
}
