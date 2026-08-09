import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_explore_screen.dart';
import 'package:runiac_app/features/friends/domain/models/friends_read_model.dart';
import 'package:runiac_app/features/friends/domain/repositories/friends_repository.dart';
import 'package:runiac_app/features/home/presentation/home_tab.dart';

import 'support/fake_runiac_auth_repository.dart';

const _aisha = FriendUserReadModel(
  userId: 'friend-aisha',
  displayName: 'Aisha Runner',
  avatarInitials: 'AR',
  levelLabel: 'Lv.12',
);

const _ben = FriendUserReadModel(
  userId: 'friend-ben',
  displayName: 'Ben Pacer',
  avatarInitials: 'BP',
  levelLabel: 'Lv.7',
);

class _FakeFriendsRepository implements FriendsRepository {
  var loadCalls = 0;
  String? lastOwnerUid;

  @override
  Future<FriendsOverviewReadModel> loadFriendsOverview({
    required String ownerUid,
  }) async {
    loadCalls += 1;
    lastOwnerUid = ownerUid;
    return const FriendsOverviewReadModel(
      friends: <FriendUserReadModel>[_aisha, _ben],
      incomingRequests: <FriendUserReadModel>[],
    );
  }

  @override
  Stream<FriendsOverviewReadModel> watchFriendsOverview({
    required String ownerUid,
  }) => Stream.fromFuture(loadFriendsOverview(ownerUid: ownerUid));

  @override
  Future<List<FriendUserReadModel>> searchFriends({
    required String ownerUid,
    required String nickname,
  }) async => const <FriendUserReadModel>[];

  @override
  Future<FriendsMutationResult> sendFriendRequest({
    required String ownerUid,
    required String targetUid,
  }) async => const FriendsMutationResult(changed: false);

  @override
  Future<FriendsMutationResult> cancelFriendRequest({
    required String ownerUid,
    required String targetUid,
  }) async => const FriendsMutationResult(changed: false);

  @override
  Future<FriendsMutationResult> respondToFriendRequest({
    required String ownerUid,
    required String senderUid,
    required FriendRequestResponseAction action,
  }) async => const FriendsMutationResult(changed: false);

  @override
  Future<FriendsMutationResult> removeFriend({
    required String ownerUid,
    required String friendUid,
  }) async => const FriendsMutationResult(changed: false);

  @override
  Future<FriendsMutationResult> blockUser({
    required String ownerUid,
    required String targetUid,
  }) async => const FriendsMutationResult(changed: false);

  @override
  Future<FriendsMutationResult> unblockUser({
    required String ownerUid,
    required String targetUid,
  }) async => const FriendsMutationResult(changed: false);
}

void main() {
  testWidgets(
    'opening Challenge from Home wires the real reciprocal friends list into the invite picker',
    (tester) async {
      final auth = FakeRuniacAuthRepository()..emitSignedIn(uid: 'owner-uid');
      final friendsRepository = _FakeFriendsRepository();
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeTab(
            authRepository: auth,
            profileRepository: const StaticUserProfileRepository(),
            profilePersistenceRepository:
                const NoopUserProfilePersistenceRepository(),
            friendsRepository: friendsRepository,
            enableForegroundGps: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Challenge'));
      await tester.pumpAndSettle();

      final exploreScreen = tester.widget<ChallengeExploreScreen>(
        find.byType(ChallengeExploreScreen),
      );
      final invitable = await exploreScreen.invitableFriendsLoader();

      expect(friendsRepository.loadCalls, 1);
      expect(friendsRepository.lastOwnerUid, 'owner-uid');
      expect(
        invitable.map(
          (f) => (f.uid, f.displayName, f.initials, f.levelLabel),
        ),
        [
          ('friend-aisha', 'Aisha Runner', 'AR', 'Lv.12'),
          ('friend-ben', 'Ben Pacer', 'BP', 'Lv.7'),
        ],
      );
    },
  );

  testWidgets(
    'invite loader returns empty list without throwing when signed out',
    (tester) async {
      final auth = FakeRuniacAuthRepository();
      final friendsRepository = _FakeFriendsRepository();
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeTab(
            authRepository: auth,
            profileRepository: const StaticUserProfileRepository(),
            profilePersistenceRepository:
                const NoopUserProfilePersistenceRepository(),
            friendsRepository: friendsRepository,
            enableForegroundGps: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Challenge'));
      await tester.pumpAndSettle();

      final exploreScreen = tester.widget<ChallengeExploreScreen>(
        find.byType(ChallengeExploreScreen),
      );
      final invitable = await exploreScreen.invitableFriendsLoader();

      expect(friendsRepository.loadCalls, 0);
      expect(invitable, isEmpty);
    },
  );
}
