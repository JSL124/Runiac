import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/paywall_config_read_model.dart';
import '../domain/repositories/paywall_config_repository.dart';

/// Reads the signed-in-readable `config/paywall` document.
///
/// `firestore.rules` grants `allow read: if isSignedIn()` for this one config
/// doc and denies every client write, so this reader is read-only by
/// construction. A missing document, a malformed field, or a read failure all
/// resolve to [PaywallConfigReadModel.defaults] so the paywall sheet never
/// blocks on the network.
class FirestorePaywallConfigRepository implements PaywallConfigRepository {
  FirestorePaywallConfigRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<PaywallConfigReadModel> loadPaywallConfig() async {
    final snapshot = await _firestore.collection('config').doc('paywall').get();
    final data = snapshot.data();
    return PaywallConfigReadModel.fromMap(
      data == null ? null : Map<String, Object?>.from(data),
    );
  }
}
