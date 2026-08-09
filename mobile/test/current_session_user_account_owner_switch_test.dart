import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';

const _premiumAccount = UserAccountReadModel(
  subscriptionStatus: UserSubscriptionStatus.premium,
);
const _basicAccount = UserAccountReadModel();

/// One-shot repository whose reads only resolve when the test completes them,
/// so a switch of the signed-in user can race an in-flight account read.
class _CompleterUserAccountRepository implements UserAccountRepository {
  final pendingLoads = <Completer<UserAccountReadModel>>[];

  int get loadCount => pendingLoads.length;

  @override
  Future<UserAccountReadModel> loadUserAccount() {
    final completer = Completer<UserAccountReadModel>();
    pendingLoads.add(completer);
    return completer.future;
  }
}

/// Live repository that hands out a fresh stream per `watchUserAccount()`
/// call, mirroring how a Firestore-backed repository would open a new
/// snapshot listener each time the store rebinds after an owner switch.
class _RebindingLiveUserAccountRepository implements LiveUserAccountRepository {
  final watchControllers = <StreamController<UserAccountReadModel>>[];

  @override
  Future<UserAccountReadModel> loadUserAccount() async => _basicAccount;

  @override
  Stream<UserAccountReadModel> watchUserAccount() {
    final controller = StreamController<UserAccountReadModel>.broadcast();
    watchControllers.add(controller);
    return controller.stream;
  }

  Future<void> dispose() async {
    for (final controller in watchControllers) {
      await controller.close();
    }
  }
}

Future<void> _drainMicrotasks() => Future<void>.delayed(Duration.zero);

void main() {
  group('CurrentSessionUserAccount owner switch', () {
    test(
      'switching owner clears the prior owner\'s premium account state',
      () async {
        final repository = _CompleterUserAccountRepository();
        final store = CurrentSessionUserAccount(
          ownerUid: 'user-a',
          repository: repository,
        );
        addTearDown(store.dispose);

        repository.pendingLoads.single.complete(_premiumAccount);
        await _drainMicrotasks();
        expect(store.account?.isPremium, isTrue);
        expect(store.subscriptionStatusLabel, 'Premium');

        store.updateOwnerUid('user-b');

        // Synchronously after the switch — before user B's own trusted read
        // resolves — user A's premium tier must already be gone so user B can
        // never see it, not even for one frame.
        expect(store.ownerUid, 'user-b');
        expect(store.account, isNull);
        expect(store.subscriptionStatusLabel, '');
      },
    );

    test(
      'late arriving account for previous owner is discarded after switch',
      () async {
        final repository = _CompleterUserAccountRepository();
        final store = CurrentSessionUserAccount(
          ownerUid: 'user-a',
          repository: repository,
        );
        addTearDown(store.dispose);

        // User A's read is still in flight when the account switches to B.
        store.updateOwnerUid('user-b');
        expect(repository.loadCount, 2);

        // User A's premium result now completes late; the serial guard must
        // drop it instead of publishing it into user B's session.
        repository.pendingLoads.first.complete(_premiumAccount);
        await _drainMicrotasks();
        expect(store.account, isNull);
        expect(store.subscriptionStatusLabel, '');

        // User B's own read still lands normally afterwards.
        repository.pendingLoads[1].complete(_basicAccount);
        await _drainMicrotasks();
        expect(store.account, _basicAccount);
        expect(store.account?.isPremium, isFalse);
        expect(store.subscriptionStatusLabel, 'Basic');
      },
    );

    test(
      'live stream events from the previous owner stop after switch',
      () async {
        final repository = _RebindingLiveUserAccountRepository();
        addTearDown(repository.dispose);
        final store = CurrentSessionUserAccount(
          ownerUid: 'user-a',
          repository: repository,
        );
        addTearDown(store.dispose);

        final ownerAWatch = repository.watchControllers.single;
        ownerAWatch.add(_premiumAccount);
        await _drainMicrotasks();
        expect(store.account?.isPremium, isTrue);

        store.updateOwnerUid('user-b');
        expect(store.account, isNull);

        // A snapshot still arriving on user A's cancelled listener must not
        // be published into user B's session.
        ownerAWatch.add(_premiumAccount);
        await _drainMicrotasks();
        expect(store.account, isNull);

        // The store rebinds to a fresh watch for the new owner, which relays
        // the trusted tier normally.
        expect(repository.watchControllers, hasLength(2));
        repository.watchControllers[1].add(_basicAccount);
        await _drainMicrotasks();
        expect(store.account, _basicAccount);
        expect(store.subscriptionStatusLabel, 'Basic');
      },
    );

    test(
      'same owner uid update keeps resolved account state without reloading',
      () async {
        // Pins the current behavior read from updateOwnerUid: an identical
        // uid returns early, so the resolved account is neither cleared nor
        // re-fetched and listeners are not re-notified.
        final repository = _CompleterUserAccountRepository();
        final store = CurrentSessionUserAccount(
          ownerUid: 'user-a',
          repository: repository,
        );
        addTearDown(store.dispose);

        repository.pendingLoads.single.complete(_premiumAccount);
        await _drainMicrotasks();
        expect(store.account?.isPremium, isTrue);

        var notifications = 0;
        store.addListener(() => notifications += 1);

        store.updateOwnerUid('user-a');
        await _drainMicrotasks();

        expect(store.account?.isPremium, isTrue);
        expect(store.subscriptionStatusLabel, 'Premium');
        expect(repository.loadCount, 1);
        expect(notifications, 0);
      },
    );

    test('signing out clears the premium account state immediately', () async {
      final repository = _CompleterUserAccountRepository();
      final store = CurrentSessionUserAccount(
        ownerUid: 'user-a',
        repository: repository,
      );
      addTearDown(store.dispose);

      repository.pendingLoads.single.complete(_premiumAccount);
      await _drainMicrotasks();
      expect(store.account?.isPremium, isTrue);

      store.updateOwnerUid(null);

      expect(store.ownerUid, isNull);
      expect(store.account, isNull);
      expect(store.subscriptionStatusLabel, '');
    });
  });
}
