import '../models/plan_progress_read_model.dart';

abstract interface class PlanProgressRepository {
  Future<PlanProgressReadModel> loadPlanProgress({
    required String uid,
    required String activeGeneratedPlanId,
  });
}

class NoopPlanProgressRepository implements PlanProgressRepository {
  const NoopPlanProgressRepository();

  @override
  Future<PlanProgressReadModel> loadPlanProgress({
    required String uid,
    required String activeGeneratedPlanId,
  }) async {
    return PlanProgressReadModel.empty();
  }
}
