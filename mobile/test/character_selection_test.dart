import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/local_selected_runner_character_storage.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/features/onboarding/presentation/character_selection_screen.dart';
import 'package:runiac_app/features/onboarding/presentation/runiac_character_selection_gate.dart';
import 'package:runiac_app/features/paywall/presentation/current_session_character_access.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _paywallTitleKey = Key('paywall-title');

class _FixedUserAccountRepository implements UserAccountRepository {
  const _FixedUserAccountRepository(this.account);

  final UserAccountReadModel account;

  @override
  Future<UserAccountReadModel> loadUserAccount() async => account;
}

// Never resolves, so the account store stays `null` — simulates the first
// `users/{uid}` read still in flight while the picker is on screen.
class _PendingUserAccountRepository implements UserAccountRepository {
  _PendingUserAccountRepository();

  final Completer<UserAccountReadModel> _never =
      Completer<UserAccountReadModel>();

  @override
  Future<UserAccountReadModel> loadUserAccount() => _never.future;
}

// Wraps [CharacterSelectionScreen] with the trusted account + character-access
// scopes so the picker's Premium lock is exercised end to end. Defaults gate
// Cap and Ivy behind Premium (StaticCharacterAccessRepository). Pass
// [accountRepository] to control the account load (e.g. an unresolved read);
// otherwise a fixed [subscriptionStatus] account is used.
Future<void> _pumpGatedSelection(
  WidgetTester tester, {
  UserSubscriptionStatus? subscriptionStatus,
  UserAccountRepository? accountRepository,
  ValueChanged<RunnerCharacter>? onConfirm,
}) async {
  assert(
    subscriptionStatus != null || accountRepository != null,
    'provide a subscriptionStatus or an accountRepository',
  );
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final accountStore = CurrentSessionUserAccount(
    repository:
        accountRepository ??
        _FixedUserAccountRepository(
          UserAccountReadModel(subscriptionStatus: subscriptionStatus!),
        ),
  );
  addTearDown(accountStore.dispose);
  final characterAccessStore = CurrentSessionCharacterAccess();
  addTearDown(characterAccessStore.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: CurrentSessionUserAccountScope(
        store: accountStore,
        child: CharacterAccessScope(
          store: characterAccessStore,
          child: CharacterSelectionScreen(onConfirm: onConfirm ?? (_) {}),
        ),
      ),
    ),
  );
  // Let the one-shot account + character-access loads resolve so the lock
  // state settles.
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharacterSelectionScreen', () {
    testWidgets('shows all four guide characters and requires a choice', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      RunnerCharacter? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: CharacterSelectionScreen(
            onConfirm: (character) => confirmed = character,
          ),
        ),
      );

      for (final name in ['Bolt', 'Cap', 'Mila', 'Ivy']) {
        expect(find.text(name), findsOneWidget);
      }

      // The confirm CTA is disabled until a character is picked.
      FilledButton confirmButton() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirmButton().onPressed, isNull);
      expect(find.text('Pick a buddy to continue'), findsOneWidget);
      expect(confirmed, isNull);

      await tester.tap(find.text('Mila'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(confirmButton().onPressed, isNotNull);
      expect(find.text("Let's go with Mila"), findsOneWidget);

      await tester.tap(find.text("Let's go with Mila"));
      await tester.pump();

      expect(confirmed, RunnerCharacter.pink);
    });
  });

  group('CharacterSelectionScreen premium gating', () {
    testWidgets('locks Cap and Ivy for a Basic runner, leaves Bolt/Mila open', (
      tester,
    ) async {
      await _pumpGatedSelection(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
      );

      // Cap and Ivy are the two premium-gated buddies by default.
      expect(find.text('Premium'), findsNWidgets(2));
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
    });

    testWidgets('a Basic runner tapping Cap opens the paywall, no selection', (
      tester,
    ) async {
      RunnerCharacter? confirmed;
      await _pumpGatedSelection(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
        onConfirm: (character) => confirmed = character,
      );

      await tester.tap(find.text('Cap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The paywall intercepted the tap; nothing was selected.
      expect(find.byKey(_paywallTitleKey), findsOneWidget);
      expect(find.text("Let's go with Cap"), findsNothing);
      expect(confirmed, isNull);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a Basic runner can still select Mila', (tester) async {
      RunnerCharacter? confirmed;
      await _pumpGatedSelection(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
        onConfirm: (character) => confirmed = character,
      );

      await tester.tap(find.text('Mila'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(_paywallTitleKey), findsNothing);
      expect(find.text("Let's go with Mila"), findsOneWidget);

      await tester.tap(find.text("Let's go with Mila"));
      await tester.pump();
      expect(confirmed, RunnerCharacter.pink);
    });

    testWidgets(
      'fails closed while the account is unresolved: Cap stays locked and its '
      'tap opens the paywall',
      (tester) async {
        RunnerCharacter? confirmed;
        await _pumpGatedSelection(
          tester,
          // The first users/{uid} read never resolves, so account == null.
          accountRepository: _PendingUserAccountRepository(),
          onConfirm: (character) => confirmed = character,
        );

        // Premium-only buddies (Cap + Ivy) are locked even though the
        // subscription is not yet known — the client gate has no server
        // backstop, so it must not let a premium buddy through the load window.
        expect(find.text('Premium'), findsNWidgets(2));
        expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));

        await tester.tap(find.text('Cap'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byKey(_paywallTitleKey), findsOneWidget);
        expect(confirmed, isNull);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a Premium runner sees no locks and can select Cap', (
      tester,
    ) async {
      RunnerCharacter? confirmed;
      await _pumpGatedSelection(
        tester,
        subscriptionStatus: UserSubscriptionStatus.premium,
        onConfirm: (character) => confirmed = character,
      );

      expect(find.text('Premium'), findsNothing);
      expect(find.byIcon(Icons.lock_rounded), findsNothing);

      await tester.tap(find.text('Cap'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(_paywallTitleKey), findsNothing);
      expect(find.text("Let's go with Cap"), findsOneWidget);

      await tester.tap(find.text("Let's go with Cap"));
      await tester.pump();
      expect(confirmed, RunnerCharacter.cap);
    });
  });

  group('RuniacCharacterSelectionGate', () {
    testWidgets('shows selection screen then reveals child after confirm', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = SelectedRunnerCharacterStore();
      addTearDown(store.dispose);
      RunnerCharacter? persisted;

      await tester.pumpWidget(
        MaterialApp(
          home: SelectedRunnerCharacterScope(
            store: store,
            child: RuniacCharacterSelectionGate(
              active: true,
              store: store,
              onCharacterConfirmed: (character) => persisted = character,
              child: const Text('ONBOARDING'),
            ),
          ),
        ),
      );

      expect(find.text('Choose your running buddy'), findsOneWidget);
      expect(find.text('ONBOARDING'), findsNothing);

      await tester.tap(find.text('Bolt'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text("Let's go with Bolt"));
      await tester.pump();

      expect(persisted, RunnerCharacter.blue);
      expect(store.selected, RunnerCharacter.blue);
      expect(find.text('Choose your running buddy'), findsNothing);
      expect(find.text('ONBOARDING'), findsOneWidget);
    });

    testWidgets('skips selection when a choice is already restored', (
      tester,
    ) async {
      final store = SelectedRunnerCharacterStore()
        ..select(RunnerCharacter.purple);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SelectedRunnerCharacterScope(
            store: store,
            child: RuniacCharacterSelectionGate(
              active: true,
              store: store,
              onCharacterConfirmed: (_) {},
              child: const Text('ONBOARDING'),
            ),
          ),
        ),
      );

      expect(find.text('Choose your running buddy'), findsNothing);
      expect(find.text('ONBOARDING'), findsOneWidget);
    });

    testWidgets('passes through to child when inactive', (tester) async {
      final store = SelectedRunnerCharacterStore();
      addTearDown(store.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: RuniacCharacterSelectionGate(
            active: false,
            store: store,
            onCharacterConfirmed: (_) {},
            child: const Text('ONBOARDING'),
          ),
        ),
      );

      expect(find.text('Choose your running buddy'), findsNothing);
      expect(find.text('ONBOARDING'), findsOneWidget);
    });
  });

  group('SharedPreferencesSelectedRunnerCharacterStorage', () {
    test('persists per uid and restores on next launch', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const storage = SharedPreferencesSelectedRunnerCharacterStorage();

      expect(await storage.readSelectedCharacter(uid: 'user-1'), isNull);

      await storage.writeSelectedCharacter(
        uid: 'user-1',
        character: RunnerCharacter.pink,
      );

      // Simulates a fresh launch reading the same stored value back.
      expect(
        await storage.readSelectedCharacter(uid: 'user-1'),
        RunnerCharacter.pink,
      );
      // A different uid does not inherit another user's choice.
      expect(await storage.readSelectedCharacter(uid: 'user-2'), isNull);
    });

    test('uses an anonymous fallback key when uid is null', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const storage = SharedPreferencesSelectedRunnerCharacterStorage();

      await storage.writeSelectedCharacter(
        uid: null,
        character: RunnerCharacter.cap,
      );

      expect(
        await storage.readSelectedCharacter(uid: null),
        RunnerCharacter.cap,
      );
      expect(
        selectedRunnerCharacterPreferenceKey(null),
        'selected_runner_character_anonymous',
      );
    });

    test('restored selection lands in SelectedRunnerCharacterStore', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'selected_runner_character_user-1': 'purple',
      });
      const storage = SharedPreferencesSelectedRunnerCharacterStorage();
      final store = SelectedRunnerCharacterStore();
      addTearDown(store.dispose);

      final restored = await storage.readSelectedCharacter(uid: 'user-1');
      expect(restored, RunnerCharacter.purple);

      store.select(restored!);
      expect(store.hasSelection, isTrue);
      expect(store.selected, RunnerCharacter.purple);
    });
  });
}
