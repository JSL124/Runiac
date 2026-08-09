/// Display-only friends read contracts.
///
/// Friend relationships, request state, and level labels are backend-owned.
/// The client renders pre-formatted display strings only; it never derives
/// levels, XP, rank, or streak values and never writes friend relationship
/// state. The static repository remains a deterministic local fallback; the
/// production composition root supplies the trusted backend read model.
class FriendUserReadModel {
  const FriendUserReadModel({
    required this.userId,
    required this.displayName,
    required this.avatarInitials,
    this.nickname = '',
    this.levelLabel = '',
    this.levelProgressFraction,
    this.subtitleLabel = '',
    this.avatarUrl = '',
  });

  final String userId;
  final String nickname;
  final String displayName;
  final String avatarInitials;

  /// Raw, not-yet-sanitised avatar photo URL, resolved live via
  /// `getFriendLevels`. Empty when the friend has no photo set.
  final String avatarUrl;

  /// Pre-formatted backend-owned display string, e.g. `'Lv.12'`.
  /// Never computed on the client.
  final String levelLabel;

  /// Backend-owned progress toward the next level, already converted from a
  /// 0..100 percent into 0.0..1.0 and clamped. `null` means unresolved (no
  /// live level data available yet), which is distinct from a genuine
  /// resolved `0.0`. Never computed on the client.
  final double? levelProgressFraction;

  /// Short supporting display copy, e.g. a favourite running area.
  final String subtitleLabel;
}

/// One display snapshot covering all Friends screen tabs.
class FriendsOverviewReadModel {
  const FriendsOverviewReadModel({
    required this.friends,
    required this.incomingRequests,
    this.outgoingRequests = const <FriendUserReadModel>[],
    this.blockedUsers = const <FriendUserReadModel>[],
    this.recommended = const <FriendUserReadModel>[],
    this.searchableUsers = const <FriendUserReadModel>[],
  });

  /// Accepted friends, display order supplied by the source.
  final List<FriendUserReadModel> friends;

  /// Incoming friend requests awaiting a local accept/decline gesture.
  final List<FriendUserReadModel> incomingRequests;

  /// Outgoing friend requests awaiting a recipient response.
  final List<FriendUserReadModel> outgoingRequests;

  /// Users blocked directionally by the current authenticated user.
  final List<FriendUserReadModel> blockedUsers;

  /// Legacy static-shell compatibility only. Backed Friends does not render
  /// a Suggested tab or client-side discovery list.
  @Deprecated('Backed Friends uses exact-submit searchFriends results.')
  final List<FriendUserReadModel> recommended;

  /// Legacy static-shell compatibility only. Backed Friends never filters a
  /// local list; it submits the exact nickname to the backend.
  @Deprecated('Backed Friends uses exact-submit searchFriends results.')
  final List<FriendUserReadModel> searchableUsers;
}

enum FriendRequestResponseAction { accept, decline }

class FriendsMutationResult {
  const FriendsMutationResult({required this.changed, this.status});

  final bool changed;
  final String? status;
}
