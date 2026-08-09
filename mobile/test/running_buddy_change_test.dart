import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/characters/local_selected_runner_character_storage.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/features/paywall/presentation/current_session_character_access.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';
import 'package:runiac_app/features/profile/presentation/data/account_profile_demo_snapshots.dart';
import 'package:runiac_app/features/profile/presentation/running_buddy_screen.dart';
import 'package:runiac_app/features/profile/presentation/widgets/account_profile_sections.dart';

import 'support/fake_runiac_auth_repository.dart';

const _paywallTitleKey = Key('paywall-title');

class _FixedUserAccountRepository implements UserAccountRepository {
  const _FixedUserAccountRepository(this.account);

  final UserAccountReadModel account;

  @override
  Future<UserAccountReadModel> loadUserAccount() async => account;
}

// Pumps the Account → Running buddy screen with the trusted account and
// character-access scopes, plus the session store holding [initialCharacter],
// so the premium lock and the "current buddy" preselection are both exercised.
// Returns the store and storage so a test can assert what a confirm wrote.
typedef _PumpedRunningBuddy = ({
  SelectedRunnerCharacterStore store,
  MemorySelectedRunnerCharacterStorage storage,
});

Future<_PumpedRunningBuddy> _pumpRunningBuddyScreen(
  WidgetTester tester, {
  required UserSubscriptionStatus subscriptionStatus,
  RunnerCharacter? initialCharacter,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final accountStore = CurrentSessionUserAccount(
    repository: _FixedUserAccountRepository(
      UserAccountReadModel(subscriptionStatus: subscriptionStatus),
    ),
  );
  addTearDown(accountStore.dispose);
  final characterAccessStore = CurrentSessionCharacterAccess();
  addTearDown(characterAccessStore.dispose);
  final selectedStore = SelectedRunnerCharacterStore();
  addTearDown(selectedStore.dispose);
  if (initialCharacter != null) {
    selectedStore.select(initialCharacter);
  }
  final storage = MemorySelectedRunnerCharacterStorage();

  await tester.pumpWidget(
    MaterialApp(
      home: CurrentSessionUserAccountScope(
        store: accountStore,
        child: CharacterAccessScope(
          store: characterAccessStore,
          child: SelectedRunnerCharacterScope(
            store: selectedStore,
            child: RunningBuddyScreen(
              authRepository: FakeRuniacAuthRepository(),
              characterStorage: storage,
            ),
          ),
        ),
      ),
    ),
  );
  // Let the one-shot account + character-access loads resolve so the lock
  // state settles.
  await tester.pump();
  await tester.pump();
  return (store: selectedStore, storage: storage);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Account → Running buddy entry point', () {
    testWidgets('tapping the row pushes RunningBuddyScreen, no snackbar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountManageSection(
              rows: accountProfileDemoSnapshot.manageRows,
              authRepository: FakeRuniacAuthRepository(),
            ),
          ),
        ),
      );

      expect(find.byType(RunningBuddyScreen), findsNothing);

      await tester.tap(find.text('Running buddy'));
      await tester.pumpAndSettle();

      expect(find.byType(RunningBuddyScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the Running buddy row carries a real (non-snackBar) action', (
      tester,
    ) async {
      final row = accountProfileDemoSnapshot.manageRows.firstWhere(
        (row) => row.title == 'Running buddy',
      );

      expect(row.action, UserProfileManageAction.runningBuddy);
      expect(row.snackBarMessage, isEmpty);
    });
  });

  group('RunningBuddyScreen', () {
    testWidgets('preselects the current buddy and offers the swap CTA', (
      tester,
    ) async {
      await _pumpRunningBuddyScreen(
        tester,
        subscriptionStatus: UserSubscriptionStatus.premium,
        initialCharacter: RunnerCharacter.blue,
      );

      expect(find.text('Switch your running buddy'), findsOneWidget);
      // Preselected, so the CTA is live immediately — no "pick one first".
      expect(find.text('Run with Bolt from now on'), findsOneWidget);
      expect(find.text('Pick a buddy to continue'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'a Basic runner sees Cap and Ivy locked and cannot switch to them',
      (tester) async {
        final pumped = await _pumpRunningBuddyScreen(
          tester,
          subscriptionStatus: UserSubscriptionStatus.basic,
          initialCharacter: RunnerCharacter.blue,
        );

        // Cap and Ivy are the two premium-gated buddies by default.
        expect(find.text('Premium'), findsNWidgets(2));
        expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));

        await tester.tap(find.text('Cap'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // The paywall intercepted the tap; the stored buddy is untouched.
        expect(find.byKey(_paywallTitleKey), findsOneWidget);
        expect(pumped.store.selected, RunnerCharacter.blue);
        expect(
          await pumped.storage.readSelectedCharacter(uid: null),
          isNull,
        );

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a Basic runner can switch between the free buddies', (
      tester,
    ) async {
      final pumped = await _pumpRunningBuddyScreen(
        tester,
        subscriptionStatus: UserSubscriptionStatus.basic,
        initialCharacter: RunnerCharacter.blue,
      );

      await tester.tap(find.text('Mila'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(_paywallTitleKey), findsNothing);
      await tester.tap(find.text('Run with Mila from now on'));
      await tester.pumpAndSettle();

      // Session store updated for every surface showing the buddy, and the
      // device-local preference written for the next launch.
      expect(pumped.store.selected, RunnerCharacter.pink);
      expect(
        await pumped.storage.readSelectedCharacter(uid: null),
        RunnerCharacter.pink,
      );
    });

    testWidgets('a Premium runner can switch to a premium-only buddy', (
      tester,
    ) async {
      final pumped = await _pumpRunningBuddyScreen(
        tester,
        subscriptionStatus: UserSubscriptionStatus.premium,
        initialCharacter: RunnerCharacter.blue,
      );

      expect(find.byIcon(Icons.lock_rounded), findsNothing);

      await tester.tap(find.text('Cap'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(_paywallTitleKey), findsNothing);
      await tester.tap(find.text('Run with Cap from now on'));
      await tester.pumpAndSettle();

      expect(pumped.store.selected, RunnerCharacter.cap);
      expect(
        await pumped.storage.readSelectedCharacter(uid: null),
        RunnerCharacter.cap,
      );
    });
  });
}
