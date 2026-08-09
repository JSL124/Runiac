import '../models/feature_access_read_model.dart';

/// Read-only access to the backend-owned `config/featureAccess` document.
/// There is deliberately no write method: `firestore.rules` denies all
/// client writes to `config/*`, and feature tiers are owned by the admin
/// console.
abstract interface class FeatureAccessRepository {
  Future<FeatureAccessReadModel> loadFeatureAccess();
}

/// Preview/test default. Reports the built-in defaults instantly.
class StaticFeatureAccessRepository implements FeatureAccessRepository {
  const StaticFeatureAccessRepository();

  @override
  Future<FeatureAccessReadModel> loadFeatureAccess() async {
    return FeatureAccessReadModel.defaults;
  }
}
