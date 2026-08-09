import '../models/user_account_read_model.dart';

/// Read-only access to the signed-in runner's trusted `users/{uid}` account
/// state. There is deliberately no write method: `firestore.rules` denies all
/// client writes to `users/{uid}`, and subscription state is owned by the
/// server.
abstract interface class UserAccountRepository {
  Future<UserAccountReadModel> loadUserAccount();
}

/// Adds a real-time seam so an admin-side subscription change is reflected in
/// the app without a restart or re-login.
abstract interface class LiveUserAccountRepository
    implements UserAccountRepository {
  Stream<UserAccountReadModel> watchUserAccount();
}

/// Preview/test default. Reports the safe non-privileged tier.
class StaticUserAccountRepository implements UserAccountRepository {
  const StaticUserAccountRepository();

  @override
  Future<UserAccountReadModel> loadUserAccount() async {
    return const UserAccountReadModel();
  }
}
