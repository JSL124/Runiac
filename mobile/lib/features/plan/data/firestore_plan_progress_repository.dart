import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/plan_progress_read_model.dart';
import '../domain/repositories/plan_progress_repository.dart';

abstract interface class PlanProgressDocumentStore {
  Future<Map<String, Object?>?> loadPlanProgress({required String uid});
}

class FirestorePlanProgressDocumentStore implements PlanProgressDocumentStore {
  FirestorePlanProgressDocumentStore({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<Map<String, Object?>?> loadPlanProgress({required String uid}) async {
    final snapshot = await _firestore.collection('planProgress').doc(uid).get();
    return snapshot.data();
  }
}

class FirestorePlanProgressRepository implements PlanProgressRepository {
  FirestorePlanProgressRepository({PlanProgressDocumentStore? documentStore})
    : _documentStore = documentStore ?? FirestorePlanProgressDocumentStore();

  final PlanProgressDocumentStore _documentStore;

  @override
  Future<PlanProgressReadModel> loadPlanProgress({
    required String uid,
    required String activeGeneratedPlanId,
  }) async {
    try {
      final data = await _documentStore.loadPlanProgress(uid: uid);
      return PlanProgressReadModel.fromBackend(
        activeGeneratedPlanId: activeGeneratedPlanId,
        data: data,
      );
    } catch (_) {
      return PlanProgressReadModel.empty();
    }
  }
}
