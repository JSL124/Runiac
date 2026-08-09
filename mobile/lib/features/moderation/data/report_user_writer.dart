import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/report_user_reason.dart';

/// Writes a report-a-user document directly to Firestore. No Cloud Function
/// is involved: `firestore.rules` already permits an authenticated,
/// unsuspended client to create a `reports/{reporterUid}_{targetId}`
/// document for `targetType: "user"` — see the `match /reports/{reportId}`
/// block. This is a display-only client write of fixed, backend-approved
/// fields; no XP, streak, level, rank, leaderboard score, or subscription
/// value is read, calculated, or written here.
///
/// Dedup and self-report rejection are enforced entirely by the security
/// rules (a deterministic `<reporterUid>_<targetId>` document id, and
/// `targetId != request.auth.uid`) — this function does not duplicate that
/// logic and must not be given a way to bypass it (the id is always derived
/// the same way here).
///
/// A duplicate report attempt comes back from Firestore as a
/// `permission-denied` FirebaseException: Firestore classifies the second
/// `set()` on an id that already exists as an `update`, and the rule denies
/// all `update`s to this collection. That specific denial is swallowed here
/// so the caller — and therefore the UI — cannot distinguish "reported for
/// the first time" from "already reported this target", which is
/// intentional: the report sheet must not reveal whether a prior report
/// exists. Any other failure (network, unavailable, a genuinely malformed
/// call) is rethrown.
Future<void> reportUser({
  required String reporterUid,
  required String targetId,
  required ReportUserReason reason,
  String description = '',
  FirebaseFirestore? firestore,
}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final reportId = '${reporterUid}_$targetId';
  try {
    await db.collection('reports').doc(reportId).set(<String, Object?>{
      'reporterUid': reporterUid,
      'targetType': 'user',
      'targetId': targetId,
      'reason': reason.value,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } on FirebaseException catch (error) {
    if (error.code == 'permission-denied') {
      return;
    }
    rethrow;
  }
}
