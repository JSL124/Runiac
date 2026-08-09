import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/feature_access_read_model.dart';
import '../domain/repositories/feature_access_repository.dart';

/// Reads the signed-in-readable `config/featureAccess` document.
///
/// `firestore.rules` grants `allow read: if isSignedIn()` for this doc and
/// denies every client write, so this reader is read-only by construction.
/// A missing document, a malformed field, or a read failure all resolve to
/// [FeatureAccessReadModel.defaults] so the upsell never blocks on the
/// network.
class FirestoreFeatureAccessRepository implements FeatureAccessRepository {
  FirestoreFeatureAccessRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<FeatureAccessReadModel> loadFeatureAccess() async {
    final snapshot = await _firestore
        .collection('config')
        .doc('featureAccess')
        .get();
    final data = snapshot.data();
    return FeatureAccessReadModel.fromMap(
      data == null ? null : Map<String, Object?>.from(data),
    );
  }
}
