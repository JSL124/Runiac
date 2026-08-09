import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/home/domain/guide/home_guide_consent.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/shell/runiac_shell.dart';
import 'package:runiac_app/features/tutorial/domain/app_tour_seen_store.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

import 'support/fake_runiac_auth_repository.dart';

const _ownerUid = 'test-auth-user-1';

/// Fixed-status consent repository — mirrors `_FakeConsentRepository` in
/// `privacy_safety_screen_test.dart`, trimmed to a single constant status
/// since this test never toggles consent, only dismisses the sheet.
class _FixedHomeGuideConsentRepository implements HomeGuideConsentRepository {
  const _FixedHomeGuideConsentRepository(this.status);

  final HomeGuideConsentStatus status;

  @override
  Future<HomeGuideConsentStatus> read() async => status;

  @override
  Future<HomeGuideConsentStatus> update({required bool granted}) async =>
      granted
      ? HomeGuideConsentStatus.granted
      : HomeGuideConsentStatus.notGranted;
}

/// Advances the fake clock in explicit ticks rather than `pumpAndSettle`,
/// mirroring `_pumpTourSettle` in `app_tour_flow_test.dart`.
///
/// Both the tour controller's anchor poll and `AppTourHost`'s settle-delay
/// wait via plain timers that do not necessarily schedule a new frame while
/// pending, so `pumpAndSettle` (which stops as soon as no frame is scheduled)
/// can return before those waits actually conclude.
Future<void> _pumpTourSettle(WidgetTester tester, {int ticks = 50}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _buildHarness({
  required FakeRuniacAuthRepository authRepository,
  required AppTourSeenStore seenStore,
}) {
  return MaterialApp(
    home: CurrentSessionActivityHistoryScope(
      store: CurrentSessionActivityHistoryStore(ownerUid: _ownerUid),
      child: CurrentSessionGeneratedPlanScope(
        store: CurrentSessionGeneratedPlanStore(),
        child: RuniacShell(
          authRepository: authRepository,
          feedRepository: const StaticFeedRepository(),
          profileRepository: const StaticUserProfileRepository(),
          profilePersistenceRepository:
              const NoopUserProfilePersistenceRepository(),
          enableForegroundGps: false,
          appTourSeenStore: seenStore,
          appTourAutoStartArmed: true,
          homeGuideConsentRepository: const _FixedHomeGuideConsentRepository(
            HomeGuideConsentStatus.notGranted,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'defers the app tour behind the home-guide consent sheet, then '
    'auto-starts once the sheet is dismissed',
    (tester) async {
      // Empty (not missing) SharedPreferences, so
      // `SharedPreferencesHomeGuideConsentPromptStore.hasPrompted` resolves
      // deterministically to false instead of relying on the
      // MissingPluginException fallback branch.
      SharedPreferences.setMockInitialValues(const <String, Object>{});

      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      addTearDown(authRepository.dispose);
      final seenStore = InMemoryAppTourSeenStore();
      await seenStore.setArmed(uid: _ownerUid, armed: true);

      await tester.pumpWidget(
        _buildHarness(authRepository: authRepository, seenStore: seenStore),
      );
      await _pumpTourSettle(tester);

      // The consent sheet takes priority over the tour: it is showing, and
      // the tour overlay has not started (whether because the sheet won the
      // race or because AppTourHost paused it the moment the sheet's route
      // became frontmost — either way the observable state is the same).
      expect(
        find.byKey(const ValueKey<String>('homeGuideConsentSheet')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('appTourNextButton')), findsNothing);

      // Answer the sheet (which way does not matter to the tour, only that
      // it is gone) and let the host's settle delay run out.
      await tester.tap(
        find.byKey(const ValueKey<String>('homeGuideConsentDisagree')),
      );
      await tester.pump(); // let the bottom-sheet route finish popping
      await _pumpTourSettle(tester);

      expect(
        find.byKey(const ValueKey<String>('homeGuideConsentSheet')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('appTourNextButton')), findsOneWidget);
    },
  );
}
