import '../models/beginner_adaptive_plan_snapshot.dart';

abstract interface class GeneratedPlanPersistenceRepository {
  Future<BeginnerAdaptivePlanSnapshot?> loadGeneratedPlan({
    required String uid,
  });

  Future<void> saveGeneratedPlan({
    required String uid,
    required BeginnerAdaptivePlanSnapshot plan,
    bool resetCreatedAt = false,
  });
}

class NoopGeneratedPlanPersistenceRepository
    implements GeneratedPlanPersistenceRepository {
  const NoopGeneratedPlanPersistenceRepository();

  @override
  Future<BeginnerAdaptivePlanSnapshot?> loadGeneratedPlan({
    required String uid,
  }) async {
    return null;
  }

  @override
  Future<void> saveGeneratedPlan({
    required String uid,
    required BeginnerAdaptivePlanSnapshot plan,
    bool resetCreatedAt = false,
  }) async {}
}
