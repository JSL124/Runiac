import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';
import 'package:runiac_app/features/friends/domain/models/friends_read_model.dart';
import 'package:runiac_app/features/friends/domain/repositories/friends_repository.dart';
import 'package:runiac_app/features/friends/presentation/friends_screen.dart';
import 'package:runiac_app/features/friends/presentation/friends_screen_controller.dart';
import 'package:runiac_app/features/friends/presentation/widgets/friends_rows.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  late FakeRuniacAuthRepository auth;
  late _FakeFriendsRepository repository;

  setUp(() {
    auth = FakeRuniacAuthRepository()..emitSignedIn(uid: 'runner-a');
    repository = _FakeFriendsRepository();
  });

  tearDown(() {
    auth.dispose();
  });

  Widget harness() {
    return MaterialApp(
      home: FriendsScreen(
        authRepository: auth,
        repository: repository,
        onBack: () {},
      ),
    );
  }

  testWidgets('renders Friends, Search, Requests, and Blocked tabs', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Friends'), findsNWidgets(2));
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Suggested'), findsNothing);
  });

  testWidgets('friend tabs expose selected button semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final friendsTab = tester.getSemantics(
      find.bySemanticsLabel('Friends tab'),
    );
    final semanticsData = friendsTab.getSemanticsData();
    expect(semanticsData.flagsCollection.isButton, isTrue);
    expect(semanticsData.flagsCollection.isSelected, Tristate.isTrue);
    expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);
    expect(
      tester.getSize(find.bySemanticsLabel('Friends tab')).height,
      greaterThanOrEqualTo(44),
    );
    semantics.dispose();
  });

  testWidgets(
    'Friends tab, Requests tab, and Search results expose a profile link; '
    'Blocked tab does not',
    (tester) async {
      final semantics = tester.ensureSemantics();
      repository.overview = repository.overview.copyWith(
        incomingRequests: const <FriendUserReadModel>[_jasmine],
      );
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      final aishaLink = tester.getSemantics(
        find.bySemanticsLabel('View Aisha Rahman profile'),
      );
      expect(aishaLink.getSemanticsData().flagsCollection.isButton, isTrue);

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      final jasmineLink = tester.getSemantics(
        find.bySemanticsLabel('View Jasmine Koh profile'),
      );
      expect(jasmineLink.getSemanticsData().flagsCollection.isButton, isTrue);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Grace');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final graceLink = tester.getSemantics(
        find.bySemanticsLabel('View Grace Teo profile'),
      );
      expect(graceLink.getSemanticsData().flagsCollection.isButton, isTrue);

      await tester.tap(find.text('Blocked'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('View Blocked Runner profile'),
        findsNothing,
      );

      semantics.dispose();
    },
  );

  testWidgets('search only runs on exact submit and preserves the query', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    final search = find.byType(TextField);
    await tester.enterText(search, 'Grace');
    await tester.pump();
    expect(repository.searchCalls, 0);
    expect(find.text('Grace Teo'), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repository.searchCalls, 1);
    expect(repository.lastSearchNickname, 'Grace');
    expect(find.text('Grace Teo'), findsOneWidget);
    expect(find.text('Grace'), findsOneWidget);
  });

  testWidgets('editing a submitted search invalidates its stale completion', (
    tester,
  ) async {
    repository.holdSearch = true;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Grace');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Grace 2');
    await tester.pump();
    expect(find.text('Grace Teo'), findsNothing);
    expect(find.text('Grace 2'), findsOneWidget);

    repository.completeHeldSearch();
    await tester.pumpAndSettle();
    expect(find.text('Grace Teo'), findsNothing);
    expect(find.text('Grace 2'), findsOneWidget);
  });

  testWidgets('friend ellipsis requires confirmation before remove', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('friends-more-action-aisha')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Friend'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('friends-remove-action')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Aisha Rahman?'), findsOneWidget);
    expect(
      find.text(
        'This removes the friendship. You can send a new friend request after 24 hours.',
      ),
      findsOneWidget,
    );
    expect(repository.removeCalls, 0);

    await tester.tap(find.byKey(const ValueKey('friends-confirm-action')));
    await tester.pumpAndSettle();
    expect(repository.removeCalls, 1);
    expect(find.text('Aisha Rahman'), findsNothing);
  });

  testWidgets('friend ellipsis block confirms the full privacy reset', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('friends-more-action-aisha')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('friends-block-action')));
    await tester.pumpAndSettle();

    expect(find.text('Block Aisha Rahman?'), findsOneWidget);
    expect(
      find.text(
        'This removes the friendship and pending requests in both directions. '
        'You will no longer appear to each other in Friends, Search, or Feed.',
      ),
      findsOneWidget,
    );
    expect(repository.blockCalls, 0);

    await tester.tap(find.byKey(const ValueKey('friends-confirm-action')));
    await tester.pumpAndSettle();
    expect(repository.blockCalls, 1);
  });

  testWidgets('Blocked tab confirms unblock and restores nothing', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blocked'));
    await tester.pumpAndSettle();

    expect(find.text('Blocked Runner'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('friends-unblock-action-blocked')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unblock Blocked Runner?'), findsOneWidget);
    expect(repository.unblockCalls, 0);

    final confirmButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('friends-confirm-action')),
    );
    expect(
      confirmButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      RuniacColors.primaryBlue,
    );

    await tester.tap(find.byKey(const ValueKey('friends-confirm-action')));
    await tester.pumpAndSettle();
    expect(repository.unblockCalls, 1);
    expect(find.text('Blocked Runner'), findsNothing);
    expect(repository.overview.friends, isNot(contains(_blockedRunner)));
  });

  testWidgets('double tapping Add sends one request and shows pending', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Grace');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    final add = find.bySemanticsLabel('Add Grace Teo');
    await tester.tap(add);
    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(repository.sendCalls, 1);
    expect(find.bySemanticsLabel('Pending Grace Teo'), findsOneWidget);
  });

  testWidgets('Requests accept uses the backed callable action', (
    tester,
  ) async {
    repository.overview = repository.overview.copyWith(
      incomingRequests: const <FriendUserReadModel>[_jasmine],
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('friends-accept-action-jasmine')),
    );
    await tester.pumpAndSettle();
    expect(repository.responseActions, <FriendRequestResponseAction>[
      FriendRequestResponseAction.accept,
    ]);
    expect(find.text('Jasmine Koh'), findsNothing);
  });

  testWidgets('Requests decline uses the backed callable action', (
    tester,
  ) async {
    repository.overview = repository.overview.copyWith(
      incomingRequests: const <FriendUserReadModel>[_jasmine],
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('friends-decline-action-jasmine')),
    );
    await tester.pumpAndSettle();
    expect(
      repository.responseActions.last,
      FriendRequestResponseAction.decline,
    );
  });

  testWidgets('Requests cancel uses the backed callable action', (
    tester,
  ) async {
    repository.overview = repository.overview.copyWith(
      outgoingRequests: const <FriendUserReadModel>[_outgoing],
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('friends-cancel-action-outgoing')),
    );
    await tester.pumpAndSettle();
    expect(repository.cancelCalls, 1);
  });

  testWidgets('request and blocked rows match the Friends row height', (
    tester,
  ) async {
    repository.overview = repository.overview.copyWith(
      incomingRequests: const <FriendUserReadModel>[_jasmine],
      outgoingRequests: const <FriendUserReadModel>[_outgoing],
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final friendRowHeight = tester.getSize(find.byType(FriendUserRow)).height;

    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(FriendRequestRow).first).height,
      friendRowHeight,
    );
    for (final key in const <String>[
      'friends-accept-action-jasmine',
      'friends-decline-action-jasmine',
      'friends-cancel-action-outgoing',
    ]) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height, 44);
    }

    await tester.tap(find.text('Blocked'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BlockedUserRow)).height, friendRowHeight);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('friends-unblock-action-blocked')))
          .height,
      44,
    );
  });

  testWidgets('request mutation lock prevents fast alternate actions', (
    tester,
  ) async {
    repository.overview = repository.overview.copyWith(
      incomingRequests: const <FriendUserReadModel>[_jasmine],
    );
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('friends-accept-action-jasmine')),
    );
    await tester.tap(
      find.byKey(const ValueKey('friends-decline-action-jasmine')),
    );
    await tester.pumpAndSettle();

    expect(repository.responseActions, <FriendRequestResponseAction>[
      FriendRequestResponseAction.accept,
    ]);
  });

  testWidgets('stale load is discarded after sign out', (tester) async {
    repository.holdLoad = true;
    await tester.pumpWidget(harness());
    await tester.pump();
    auth.emitSignedOut();
    await tester.pumpAndSettle();

    expect(find.text('Sign in to view friends'), findsOneWidget);
    expect(find.text('Aisha Rahman'), findsNothing);
    repository.completeHeldLoad(ownerUid: 'runner-a');
    await tester.pumpAndSettle();
    expect(find.text('Aisha Rahman'), findsNothing);
  });

  testWidgets('stale load from account A is discarded after switching to B', (
    tester,
  ) async {
    repository.holdLoad = true;
    await tester.pumpWidget(harness());
    await tester.pump();
    auth.emitSignedIn(uid: 'runner-b');
    await tester.pump();

    repository.completeHeldLoad(ownerUid: 'runner-a');
    await tester.pump();
    expect(find.text('Aisha Rahman'), findsNothing);

    repository.completeHeldLoad(ownerUid: 'runner-b');
    await tester.pumpAndSettle();
    expect(find.text('Aisha Rahman'), findsOneWidget);
  });

  test('controller ignores an in-flight load after disposal', () async {
    repository.holdLoad = true;
    final controller = FriendsScreenController(
      authRepository: auth,
      repository: repository,
    );
    await Future<void>.delayed(Duration.zero);

    controller.dispose();
    repository.completeHeldLoad(ownerUid: 'runner-a');
    await Future<void>.delayed(Duration.zero);

    expect(controller.overview, isNull);
  });

  test(
    'prior owner completion cannot release the current mutation lock',
    () async {
      final controller = FriendsScreenController(
        authRepository: auth,
        repository: repository,
      );
      await Future<void>.delayed(Duration.zero);
      final firstMutation = Completer<FriendsMutationResult>();
      final secondMutation = Completer<FriendsMutationResult>();

      final firstRun = controller.runMutation(
        actionKey: 'request:same-runner',
        action: (ownerUid) {
          expect(ownerUid, 'runner-a');
          return firstMutation.future;
        },
      );
      await Future<void>.delayed(Duration.zero);

      auth.emitSignedIn(uid: 'runner-b');
      await Future<void>.delayed(Duration.zero);
      final secondRun = controller.runMutation(
        actionKey: 'request:same-runner',
        action: (ownerUid) {
          expect(ownerUid, 'runner-b');
          return secondMutation.future;
        },
      );
      await Future<void>.delayed(Duration.zero);

      firstMutation.complete(const FriendsMutationResult(changed: true));
      await firstRun;
      expect(controller.isActionInFlight('request:same-runner'), isTrue);

      secondMutation.complete(const FriendsMutationResult(changed: true));
      await secondRun;
      expect(controller.isActionInFlight('request:same-runner'), isFalse);
      controller.dispose();
    },
  );
}

const _aisha = FriendUserReadModel(
  userId: 'aisha',
  nickname: 'aisha-rahman',
  displayName: 'Aisha Rahman',
  avatarInitials: 'AR',
);

const _grace = FriendUserReadModel(
  userId: 'grace',
  nickname: 'grace-teo',
  displayName: 'Grace Teo',
  avatarInitials: 'GT',
);

const _blockedRunner = FriendUserReadModel(
  userId: 'blocked',
  nickname: 'blocked-runner',
  displayName: 'Blocked Runner',
  avatarInitials: 'BR',
);

const _jasmine = FriendUserReadModel(
  userId: 'jasmine',
  nickname: 'jasmine-koh',
  displayName: 'Jasmine Koh',
  avatarInitials: 'JK',
);

const _outgoing = FriendUserReadModel(
  userId: 'outgoing',
  nickname: 'outgoing-runner',
  displayName: 'Outgoing Runner',
  avatarInitials: 'OR',
);

class _FakeFriendsRepository implements FriendsRepository {
  _FakeFriendsRepository()
    : overview = FriendsOverviewReadModel(
        friends: const <FriendUserReadModel>[_aisha],
        incomingRequests: const <FriendUserReadModel>[],
        outgoingRequests: const <FriendUserReadModel>[],
        blockedUsers: const <FriendUserReadModel>[_blockedRunner],
      );

  FriendsOverviewReadModel overview;
  var searchCalls = 0;
  var sendCalls = 0;
  var removeCalls = 0;
  var blockCalls = 0;
  var unblockCalls = 0;
  var holdLoad = false;
  var holdSearch = false;
  var cancelCalls = 0;
  final responseActions = <FriendRequestResponseAction>[];
  String? lastSearchNickname;
  final _heldLoads = <String, Completer<FriendsOverviewReadModel>>{};
  Completer<List<FriendUserReadModel>>? _heldSearch;

  @override
  Future<FriendsOverviewReadModel> loadFriendsOverview({
    required String ownerUid,
  }) async {
    if (!holdLoad) return overview;
    final held = Completer<FriendsOverviewReadModel>();
    _heldLoads[ownerUid] = held;
    return held.future;
  }

  void completeHeldLoad({required String ownerUid}) {
    _heldLoads.remove(ownerUid)?.complete(overview);
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
    searchCalls += 1;
    lastSearchNickname = nickname;
    if (holdSearch) {
      _heldSearch = Completer<List<FriendUserReadModel>>();
      return _heldSearch!.future;
    }
    return nickname == 'Grace' ? const <FriendUserReadModel>[_grace] : const [];
  }

  void completeHeldSearch() {
    _heldSearch?.complete(const <FriendUserReadModel>[_grace]);
    _heldSearch = null;
  }

  @override
  Future<FriendsMutationResult> sendFriendRequest({
    required String ownerUid,
    required String targetUid,
  }) async {
    sendCalls += 1;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    overview = overview.copyWith(
      outgoingRequests: <FriendUserReadModel>[_grace],
    );
    return const FriendsMutationResult(changed: true, status: 'PENDING');
  }

  @override
  Future<FriendsMutationResult> cancelFriendRequest({
    required String ownerUid,
    required String targetUid,
  }) async {
    cancelCalls += 1;
    overview = overview.copyWith(
      outgoingRequests: const <FriendUserReadModel>[],
    );
    return const FriendsMutationResult(changed: true);
  }

  @override
  Future<FriendsMutationResult> respondToFriendRequest({
    required String ownerUid,
    required String senderUid,
    required FriendRequestResponseAction action,
  }) async {
    responseActions.add(action);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    overview = overview.copyWith(
      incomingRequests: overview.incomingRequests
          .where((request) => request.userId != senderUid)
          .toList(growable: false),
    );
    return const FriendsMutationResult(changed: true);
  }

  @override
  Future<FriendsMutationResult> removeFriend({
    required String ownerUid,
    required String friendUid,
  }) async {
    removeCalls += 1;
    overview = overview.copyWith(friends: const <FriendUserReadModel>[]);
    return const FriendsMutationResult(changed: true);
  }

  @override
  Future<FriendsMutationResult> blockUser({
    required String ownerUid,
    required String targetUid,
  }) async {
    blockCalls += 1;
    overview = overview.copyWith(
      friends: const <FriendUserReadModel>[],
      blockedUsers: const <FriendUserReadModel>[_aisha],
    );
    return const FriendsMutationResult(changed: true);
  }

  @override
  Future<FriendsMutationResult> unblockUser({
    required String ownerUid,
    required String targetUid,
  }) async {
    unblockCalls += 1;
    overview = overview.copyWith(blockedUsers: const <FriendUserReadModel>[]);
    return const FriendsMutationResult(changed: true);
  }
}

extension on FriendsOverviewReadModel {
  FriendsOverviewReadModel copyWith({
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
