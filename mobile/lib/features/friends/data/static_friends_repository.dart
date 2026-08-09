import '../domain/models/friends_read_model.dart';
import '../domain/repositories/friends_repository.dart';
import '../presentation/data/friends_demo_snapshots.dart';

/// Deterministic local fallback for previews and widget tests. Production
/// wiring supplies [FirebaseFriendsRepository] from the composition root.
class StaticFriendsRepository implements FriendsRepository {
  const StaticFriendsRepository();

  @override
  Future<FriendsOverviewReadModel> loadFriendsOverview({
    required String ownerUid,
  }) async {
    return friendsOverviewDemoSnapshot;
  }

  @override
  Stream<FriendsOverviewReadModel> watchFriendsOverview({
    required String ownerUid,
  }) => Stream.fromFuture(loadFriendsOverview(ownerUid: ownerUid));

  @override
  Future<List<FriendUserReadModel>> searchFriends({
    required String ownerUid,
    required String nickname,
  }) async {
    final query = nickname.trim().toLowerCase();
    return friendsOverviewDemoSnapshot.searchableUsers
        .where((user) => user.nickname.toLowerCase() == query)
        .take(1)
        .toList(growable: false);
  }

  @override
  Future<FriendsMutationResult> sendFriendRequest({
    required String ownerUid,
    required String targetUid,
  }) async => const FriendsMutationResult(changed: true, status: 'PENDING');

  @override
  Future<FriendsMutationResult> cancelFriendRequest({
    required String ownerUid,
    required String targetUid,
  }) async => const FriendsMutationResult(changed: true);

  @override
  Future<FriendsMutationResult> respondToFriendRequest({
    required String ownerUid,
    required String senderUid,
    required FriendRequestResponseAction action,
  }) async => const FriendsMutationResult(changed: true);

  @override
  Future<FriendsMutationResult> removeFriend({
    required String ownerUid,
    required String friendUid,
  }) async => const FriendsMutationResult(changed: true);

  @override
  Future<FriendsMutationResult> blockUser({
    required String ownerUid,
    required String targetUid,
  }) async => const FriendsMutationResult(changed: true);

  @override
  Future<FriendsMutationResult> unblockUser({
    required String ownerUid,
    required String targetUid,
  }) async => const FriendsMutationResult(changed: true);
}
