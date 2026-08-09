import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/features/paywall/domain/models/character_access_read_model.dart';
import 'package:runiac_app/features/paywall/domain/models/paywall_config_read_model.dart';
import 'package:runiac_app/features/paywall/domain/repositories/character_access_repository.dart';
import 'package:runiac_app/features/paywall/domain/repositories/paywall_config_repository.dart';
import 'package:runiac_app/features/paywall/presentation/current_session_character_access.dart';
import 'package:runiac_app/features/paywall/presentation/current_session_paywall_config.dart';
import 'package:runiac_app/features/paywall/presentation/premium_character_entitlement.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';

class _FixedUserAccountRepository implements UserAccountRepository {
  const _FixedUserAccountRepository(this.account);

  final UserAccountReadModel account;

  @override
  Future<UserAccountReadModel> loadUserAccount() async => account;
}

/// Never completes, so the account stays unresolved for the whole test — the
/// cold-start window a Premium runner must survive without losing their buddy.
class _PendingUserAccountRepository implements UserAccountRepository {
  @override
  Future<UserAccountReadModel> loadUserAccount() {
    return Completer<UserAccountReadModel>().future;
  }
}

/// Pushes tier changes the way the Firestore repository does, so a mid-session
/// expiry can be simulated.
class _LiveUserAccountRepository implements LiveUserAccountRepository {
  final _controller = StreamController<UserAccountReadModel>.broadcast();

  void emit(UserSubscriptionStatus status) {
    _controller.add(UserAccountReadModel(subscriptionStatus: status));
  }

  Future<void> close() => _controller.close();

  @override
  Stream<UserAccountReadModel> watchUserAccount() => _controller.stream;

  @override
  Future<UserAccountReadModel> loadUserAccount() {
    return Completer<UserAccountReadModel>().future;
  }
}

class _FixedCharacterAccessRepository implements CharacterAccessRepository {
  const _FixedCharacterAccessRepository(this.access);

  final CharacterAccessReadModel access;

  @override
  Future<CharacterAccessReadModel> loadCharacterAccess() async => access;
}

class _PendingCharacterAccessRepository implements CharacterAccessRepository {
  @override
  Future<CharacterAccessReadModel> loadCharacterAccess() {
    return Completer<CharacterAccessReadModel>().future;
  }
}

class _FixedPaywallConfigRepository implements PaywallConfigRepository {
  const _FixedPaywallConfigRepository(this.config);

  final PaywallConfigReadModel config;

  @override
  Future<PaywallConfigReadModel> loadPaywallConfig() async => config;
}

typedef _Harness = ({
  SelectedRunnerCharacterStore selected,
  List<RunnerCharacter> persisted,
});

/// Wires the enforcer to the four stores the app owns and lets every one-shot
/// read settle, mirroring `_RuniacAppState`.
Future<_Harness> _pump({
  required UserSubscriptionStatus subscriptionStatus,
  required RunnerCharacter initialCharacter,
  UserAccountRepository? accountRepository,
  CharacterAccessRepository? characterAccessRepository,
  bool paywallEnabled = true,
  void Function()? emitInitialTier,
}) async {
  final accountStore = CurrentSessionUserAccount(
    repository:
        accountRepository ??
        _FixedUserAccountRepository(
          UserAccountReadModel(subscriptionStatus: subscriptionStatus),
        ),
  );
  addTearDown(accountStore.dispose);

  final paywallStore = CurrentSessionPaywallConfig(
    repository: _FixedPaywallConfigRepository(
      PaywallConfigReadModel(enabled: paywallEnabled),
    ),
  );
  addTearDown(paywallStore.dispose);

  final accessStore = CurrentSessionCharacterAccess(
    repository:
        characterAccessRepository ??
        const _FixedCharacterAccessRepository(CharacterAccessReadModel.defaults),
  );
  addTearDown(accessStore.dispose);

  final selectedStore = SelectedRunnerCharacterStore()
    ..select(initialCharacter);
  addTearDown(selectedStore.dispose);

  final persisted = <RunnerCharacter>[];
  final entitlement = PremiumCharacterEntitlement(
    account: accountStore,
    paywallConfig: paywallStore,
    characterAccess: accessStore,
    selectedCharacter: selectedStore,
    onReverted: persisted.add,
  )..start();
  addTearDown(entitlement.dispose);

  // A live repository only has a tier once the first snapshot is pushed, which
  // must happen after the store has subscribed.
  emitInitialTier?.call();

  // Let the account read and both one-shot config reads resolve.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);

  return (selected: selectedStore, persisted: persisted);
}

void main() {
  test('an expiry mid-session reverts Cap without a restart', () async {
    // The real downgrade path: `users/{uid}` is watched live, so the tier flips
    // under a running app rather than at the next launch.
    final repository = _LiveUserAccountRepository();
    addTearDown(repository.close);

    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.premium,
      initialCharacter: RunnerCharacter.cap,
      accountRepository: repository,
      emitInitialTier: () =>
          repository.emit(UserSubscriptionStatus.premium),
    );

    // Still subscribed: Cap stays.
    expect(harness.selected.selected, RunnerCharacter.cap);

    repository.emit(UserSubscriptionStatus.basic);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(harness.selected.selected, RunnerCharacter.blue);
    expect(harness.persisted, [RunnerCharacter.blue]);
  });

  test('a lapsed subscription reverts a premium-only buddy to Bolt', () async {
    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.basic,
      initialCharacter: RunnerCharacter.cap,
    );

    expect(harness.selected.selected, RunnerCharacter.blue);
    // Written through, so the next cold start does not restore Cap.
    expect(harness.persisted, [RunnerCharacter.blue]);
  });

  test('Ivy reverts the same way as Cap', () async {
    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.basic,
      initialCharacter: RunnerCharacter.purple,
    );

    expect(harness.selected.selected, RunnerCharacter.blue);
    expect(harness.persisted, [RunnerCharacter.blue]);
  });

  test('a Premium runner keeps a premium-only buddy', () async {
    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.premium,
      initialCharacter: RunnerCharacter.cap,
    );

    expect(harness.selected.selected, RunnerCharacter.cap);
    expect(harness.persisted, isEmpty);
  });

  test('a Basic runner on a free buddy is left alone', () async {
    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.basic,
      initialCharacter: RunnerCharacter.pink,
    );

    expect(harness.selected.selected, RunnerCharacter.pink);
    expect(harness.persisted, isEmpty);
  });

  test('an unresolved account never strips the buddy', () async {
    // The cold-start window: failing closed here would take Cap away from a
    // Premium runner every launch, before their tier had even arrived.
    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.basic,
      initialCharacter: RunnerCharacter.cap,
      accountRepository: _PendingUserAccountRepository(),
    );

    expect(harness.selected.selected, RunnerCharacter.cap);
    expect(harness.persisted, isEmpty);
  });

  test('an unloaded character-access document never strips the buddy', () async {
    // Acting on the pre-load defaults would strip a buddy the administrator
    // had actually opened to everyone.
    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.basic,
      initialCharacter: RunnerCharacter.cap,
      characterAccessRepository: _PendingCharacterAccessRepository(),
    );

    expect(harness.selected.selected, RunnerCharacter.cap);
    expect(harness.persisted, isEmpty);
  });

  test('the paywall kill switch suspends the revert', () async {
    // With the paywall off every character is open, so there is nothing to
    // revert to a free tier.
    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.basic,
      initialCharacter: RunnerCharacter.cap,
      paywallEnabled: false,
    );

    expect(harness.selected.selected, RunnerCharacter.cap);
    expect(harness.persisted, isEmpty);
  });

  test('a character the administrator opened is not reverted', () async {
    // config/characterAccess is the authority, not the shipped default set.
    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.basic,
      initialCharacter: RunnerCharacter.cap,
      characterAccessRepository: const _FixedCharacterAccessRepository(
        CharacterAccessReadModel(
          premiumOnlyCharacters: {RunnerCharacter.purple},
        ),
      ),
    );

    expect(harness.selected.selected, RunnerCharacter.cap);
    expect(harness.persisted, isEmpty);
  });

  test('falls through to another free buddy when Bolt is gated too', () async {
    final harness = await _pump(
      subscriptionStatus: UserSubscriptionStatus.basic,
      initialCharacter: RunnerCharacter.cap,
      characterAccessRepository: const _FixedCharacterAccessRepository(
        CharacterAccessReadModel(
          premiumOnlyCharacters: {
            RunnerCharacter.blue,
            RunnerCharacter.cap,
            RunnerCharacter.purple,
          },
        ),
      ),
    );

    expect(harness.selected.selected, RunnerCharacter.pink);
    expect(harness.persisted, [RunnerCharacter.pink]);
  });
}
