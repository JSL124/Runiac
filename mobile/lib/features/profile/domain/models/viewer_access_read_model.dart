/// Backend-produced viewer access display contract.
///
/// Access labels may be shown by Flutter, but privilege and role authority stay
/// owned by backend/Auth and server-side checks.
class ViewerAccessReadModel {
  const ViewerAccessReadModel({
    required this.subscriptionStatusLabel,
    required this.userRoleLabel,
  });

  final String subscriptionStatusLabel;
  final String userRoleLabel;
}
