// Trusted, backend-owned account state for the signed-in runner, read from
// the top-level `users/{uid}` document.
//
// Every value here is written exclusively by trusted server paths (the admin
// console's Admin SDK writer and Cloud Functions). `firestore.rules` allows
// the owner to read `users/{uid}` and denies every client write, so the app
// may only relay these values for display. The client must never compute,
// grant, or persist subscription privilege state itself.

/// Backend-owned Basic/Premium subscription tier.
///
/// Feature access is gated server-side (Firestore Rules `isPremiumUser()` and
/// Cloud Functions). This enum exists so the client can *display* the trusted
/// tier, not to make access decisions locally.
enum UserSubscriptionStatus {
  basic,
  premium;

  /// Display label relayed next to the runner's nickname.
  String get label => switch (this) {
    UserSubscriptionStatus.basic => 'Basic',
    UserSubscriptionStatus.premium => 'Premium',
  };
}

class UserAccountReadModel {
  const UserAccountReadModel({
    this.subscriptionStatus = UserSubscriptionStatus.basic,
  });

  /// Trusted subscription tier. An absent `users/{uid}` document or an absent
  /// / unrecognised `subscriptionStatus` field resolves to
  /// [UserSubscriptionStatus.basic], matching the Firestore Rules check
  /// (`subscriptionStatus == 'premium'`), so an unknown value can never be
  /// displayed as premium.
  final UserSubscriptionStatus subscriptionStatus;

  bool get isPremium => subscriptionStatus == UserSubscriptionStatus.premium;

  /// Backend-provided tier label for the account badge.
  String get subscriptionStatusLabel => subscriptionStatus.label;

  @override
  bool operator ==(Object other) {
    return other is UserAccountReadModel &&
        other.subscriptionStatus == subscriptionStatus;
  }

  @override
  int get hashCode => subscriptionStatus.hashCode;
}
