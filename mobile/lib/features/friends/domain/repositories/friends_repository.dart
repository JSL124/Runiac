import '../models/friends_read_model.dart';

abstract interface class FriendsRepository {
  Future<FriendsOverviewReadModel> loadFriendsOverview({
    required String ownerUid,
  });

  /// Snapshot-backed live read of the same owner-scoped lists as
  /// [loadFriendsOverview] (friends, incoming/outgoing requests, blocked
  /// users). Reads only — writes stay on the Cloud Functions callables.
  Stream<FriendsOverviewReadModel> watchFriendsOverview({
    required String ownerUid,
  });

  Future<List<FriendUserReadModel>> searchFriends({
    required String ownerUid,
    required String nickname,
  });

  Future<FriendsMutationResult> sendFriendRequest({
    required String ownerUid,
    required String targetUid,
  });

  Future<FriendsMutationResult> cancelFriendRequest({
    required String ownerUid,
    required String targetUid,
  });

  Future<FriendsMutationResult> respondToFriendRequest({
    required String ownerUid,
    required String senderUid,
    required FriendRequestResponseAction action,
  });

  Future<FriendsMutationResult> removeFriend({
    required String ownerUid,
    required String friendUid,
  });

  Future<FriendsMutationResult> blockUser({
    required String ownerUid,
    required String targetUid,
  });

  Future<FriendsMutationResult> unblockUser({
    required String ownerUid,
    required String targetUid,
  });
}
