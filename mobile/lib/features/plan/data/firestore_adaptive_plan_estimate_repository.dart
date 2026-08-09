import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/adaptive_plan_estimate_read_model.dart';
import '../domain/repositories/adaptive_plan_estimate_repository.dart';

abstract interface class AdaptivePlanEstimateDocumentStore {
  Future<Map<String, Object?>?> loadAdaptivePlanEstimate({required String uid});
}

class FirestoreAdaptivePlanEstimateDocumentStore
    implements AdaptivePlanEstimateDocumentStore {
  FirestoreAdaptivePlanEstimateDocumentStore({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<Map<String, Object?>?> loadAdaptivePlanEstimate({
    required String uid,
  }) async {
    final snapshot = await _firestore
        .collection('adaptivePlanEstimates')
        .doc(uid)
        .get();
    return snapshot.data();
  }
}

class FirestoreAdaptivePlanEstimateRepository
    implements AdaptivePlanEstimateRepository {
  FirestoreAdaptivePlanEstimateRepository({
    AdaptivePlanEstimateDocumentStore? documentStore,
  }) : _documentStore =
           documentStore ?? FirestoreAdaptivePlanEstimateDocumentStore();

  final AdaptivePlanEstimateDocumentStore _documentStore;

  @override
  Future<AdaptivePlanEstimateReadModel> loadAdaptivePlanEstimate({
    required String uid,
  }) async {
    try {
      final data = await _documentStore.loadAdaptivePlanEstimate(uid: uid);
      return AdaptivePlanEstimateReadModel.fromBackend(data);
    } catch (_) {
      return const AdaptivePlanEstimateReadModel.empty();
    }
  }
}
