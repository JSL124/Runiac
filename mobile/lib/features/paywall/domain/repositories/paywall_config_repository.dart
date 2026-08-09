import '../models/paywall_config_read_model.dart';

/// Read-only access to the backend-owned `config/paywall` document. There is
/// deliberately no write method: `firestore.rules` denies all client writes to
/// `config/*`, and paywall copy is owned by the admin console.
abstract interface class PaywallConfigRepository {
  Future<PaywallConfigReadModel> loadPaywallConfig();
}

/// Preview/test default. Reports the built-in defaults instantly.
class StaticPaywallConfigRepository implements PaywallConfigRepository {
  const StaticPaywallConfigRepository();

  @override
  Future<PaywallConfigReadModel> loadPaywallConfig() async {
    return PaywallConfigReadModel.defaults;
  }
}
