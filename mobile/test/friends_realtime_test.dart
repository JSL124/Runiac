import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/friends/data/friends_repository_errors.dart';
import 'package:runiac_app/features/friends/domain/models/friends_read_model.dart';
import 'package:runiac_app/features/friends/domain/repositories/friends_repository.dart';
import 'package:runiac_app/features/friends/presentation/friends_screen.dart';
import 'package:runiac_app/features/friends/presentation/friends_screen_controller.dart';

import 'support/fake_runiac_auth_repository.dart';

const _aisha = FriendUserReadModel(
  userId: 'aisha',
  displayName: 'Aisha Rahman',
  avatarInitials: 'AR',
);

const _jasmine = FriendUserReadModel(
  userId: 'jasmine',
  displayName: 'Jasmine Koh',
  avatarInitials: 'JK',
);

const _grace = FriendUserReadModel(
  userId: 'grace',
  displayName: 'Grace Teo',
  avatarInitials: 'GT',
);

const _blockedRunner = FriendUserReadModel(
  userId: 'blocked',
  displayName: 'Blocked Runner',
  avatarInitials: 'BR',
);

const _baseOverview = FriendsOverviewReadModel(
  friends: <FriendUserReadModel>[_aisha],
  incomingRequests: <FriendUserReadModel>[],
  outgoingRequests: <FriendUserReadModel>[],
  blockedUsers: <FriendUserReadModel>[],
);

/// Fake repository whose [watchFriendsOverview] is fully controlled by the
/// test via a live [StreamController], so cross-device pushes can be
/// simulated without any [loadFriendsOverview] one-shot call.
class _StreamingFakeFriendsRepository implements FriendsRepository {
  var loadCalls = 0;
  var watchCalls = 0;
  StreamController<FriendsOverviewReadModel>? lastController;

  @override
  Future<FriendsOverviewReadModel> loadFriendsOverview({
    required String ownerUid,
  }) async {
    loadCalls += 1;
    return _baseOverview;
  }

  @override
  Stream<FriendsOverviewReadModel> watchFriendsOverview({
    required String ownerUid,
  }) {
    watchCalls += 1;
    final controller = StreamController<FriendsOverviewReadModel>();
    lastController = controller;
    return controller.stream;
  }

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
  late FakeRuniacAuthRepository auth;
  late _StreamingFakeFriendsRepository repository;

  setUp(() {
    auth = FakeRuniacAuthRepository()..emitSignedIn(uid: 'runner-a');
    repository = _StreamingFakeFriendsRepository();
  });

  tearDown(() {
    auth.dispose();
  });

  test('first emission populates overview without loading state', () async {
    final controller = FriendsScreenController(
      authRepository: auth,
      repository: repository,
    );
    var notifyCount = 0;
    controller.addListener(() => notifyCount += 1);
    await Future<void>.delayed(Duration.zero);

    expect(controller.isLoading, isTrue);
    expect(controller.overview, isNull);

    repository.lastController!.add(_baseOverview);
    await Future<void>.delayed(Duration.zero);

    expect(controller.overview, _baseOverview);
    expect(controller.isLoading, isFalse);
    expect(notifyCount, greaterThan(0));

    controller.dispose();
  });

  test(
    'remote pushes update overview live without any loadOverview call',
    () async {
      final controller = FriendsScreenController(
        authRepository: auth,
        repository: repository,
      );
      await Future<void>.delayed(Duration.zero);
      repository.lastController!.add(_baseOverview);
      await Future<void>.delayed(Duration.zero);
      final loadCallsAfterFirst = repository.loadCalls;

      final withIncoming = _baseOverview.copyWithForTest(
        incomingRequests: const <FriendUserReadModel>[_jasmine],
      );
      repository.lastController!.add(withIncoming);
      await Future<void>.delayed(Duration.zero);
      expect(controller.overview!.incomingRequests, <FriendUserReadModel>[
        _jasmine,
      ]);

      final withNewFriend = withIncoming.copyWithForTest(
        friends: const <FriendUserReadModel>[_aisha, _grace],
      );
      repository.lastController!.add(withNewFriend);
      await Future<void>.delayed(Duration.zero);
      expect(controller.overview!.friends, <FriendUserReadModel>[
        _aisha,
        _grace,
      ]);

      final withBlocked = withNewFriend.copyWithForTest(
        blockedUsers: const <FriendUserReadModel>[_blockedRunner],
      );
      repository.lastController!.add(withBlocked);
      await Future<void>.delayed(Duration.zero);
      expect(controller.overview!.blockedUsers, <FriendUserReadModel>[
        _blockedRunner,
      ]);

      expect(repository.loadCalls, loadCallsAfterFirst);

      controller.dispose();
    },
  );

  testWidgets(
    'widget reflects a pushed incoming request without navigation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FriendsScreen(
            authRepository: auth,
            repository: repository,
            onBack: () {},
          ),
        ),
      );
      await tester.pump();
      repository.lastController!.add(_baseOverview);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(find.text('Jasmine Koh'), findsNothing);

      repository.lastController!.add(
        _baseOverview.copyWithForTest(
          incomingRequests: const <FriendUserReadModel>[_jasmine],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jasmine Koh'), findsOneWidget);
    },
  );

  test('dispose cancels the overview subscription', () async {
    final controller = FriendsScreenController(
      authRepository: auth,
      repository: repository,
    );
    await Future<void>.delayed(Duration.zero);
    final controllerStream = repository.lastController!;
    expect(controllerStream.hasListener, isTrue);

    controller.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(controllerStream.hasListener, isFalse);
  });

  test('a stream error surfaces and a later good emission clears it', () async {
    final controller = FriendsScreenController(
      authRepository: auth,
      repository: repository,
    );
    await Future<void>.delayed(Duration.zero);

    repository.lastController!.addError(
      const FriendsRepositoryException(FriendsRepositoryErrorCode.unavailable),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.errorMessage, isNotNull);

    repository.lastController!.add(_baseOverview);
    await Future<void>.delayed(Duration.zero);
    expect(controller.errorMessage, isNull);
    expect(controller.overview, _baseOverview);

    controller.dispose();
  });
}

extension _FriendsOverviewTestCopy on FriendsOverviewReadModel {
  FriendsOverviewReadModel copyWithForTest({
    List<FriendUserReadModel>? friends,
    List<FriendUserReadModel>? incomingRequests,
    List<FriendUserReadModel>? outgoingRequests,
    List<FriendUserReadModel>? blockedUsers,
  }) {
    return FriendsOverviewReadModel(
      friends: friends ?? this.friends,
      incomingRequests: incomingRequests ?? this.incomingRequests,
      outgoingRequests: outgoingRequests ?? this.outgoingRequests,
      blockedUsers: blockedUsers ?? this.blockedUsers,
    );
  }
}
