import '../models/adaptive_plan_estimate_read_model.dart';

abstract interface class AdaptivePlanEstimateRepository {
  Future<AdaptivePlanEstimateReadModel> loadAdaptivePlanEstimate({
    required String uid,
  });
}

class NoopAdaptivePlanEstimateRepository
    implements AdaptivePlanEstimateRepository {
  const NoopAdaptivePlanEstimateRepository();

  @override
  Future<AdaptivePlanEstimateReadModel> loadAdaptivePlanEstimate({
    required String uid,
  }) async {
    return const AdaptivePlanEstimateReadModel.empty();
  }
}
