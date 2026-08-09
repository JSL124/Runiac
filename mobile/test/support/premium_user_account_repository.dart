import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';

/// Test account seam reporting the Premium tier, for flows that exercise
/// premium-gated surfaces (advanced analysis, coaching, activity feedback)
/// without tripping the Basic paywall intercept.
class PremiumUserAccountRepository implements UserAccountRepository {
  const PremiumUserAccountRepository();

  @override
  Future<UserAccountReadModel> loadUserAccount() async {
    return const UserAccountReadModel(
      subscriptionStatus: UserSubscriptionStatus.premium,
    );
  }
}
