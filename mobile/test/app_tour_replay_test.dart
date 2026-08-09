import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/shell/runiac_shell.dart';
import 'package:runiac_app/features/tutorial/domain/app_tour_seen_store.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

import 'support/fake_runiac_auth_repository.dart';

const _ownerUid = 'test-auth-user-1';

/// Matches `app_tour_flow_test.dart`'s ticking helper: the controller's
/// anchor poll waits via plain `Timer`/`Future.delayed`, which
/// `pumpAndSettle` can outrun since it stops as soon as no frame is
/// scheduled. A fixed number of 100ms ticks advances those timers
/// deterministically instead.
Future<void> _pumpTourSettle(WidgetTester tester, {int ticks = 20}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _buildHarness({
  required FakeRuniacAuthRepository authRepository,
  required AppTourSeenStore? seenStore,
  bool autoStartArmed = false,
}) {
  final activityHistoryStore = CurrentSessionActivityHistoryStore(
    ownerUid: _ownerUid,
  );
  addTearDown(activityHistoryStore.dispose);
  return MaterialApp(
    home: CurrentSessionActivityHistoryScope(
      store: activityHistoryStore,
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
          appTourAutoStartArmed: autoStartArmed,
        ),
      ),
    ),
  );
}

final Finder _menuTrigger = find.byKey(const ValueKey('homeMenuTrigger'));
final Finder _appTourRow = find.byKey(const Key('home_menu_app_tour'));
final Finder _nextButton = find.byKey(const ValueKey('appTourNextButton'));

const _welcomeMessage =
    "Hi, I'm Bolt — your running buddy. Give me 30 seconds and I'll "
    'show you around.';

void main() {
  testWidgets(
    'a completed, unarmed store never auto-shows the overlay, but the Home '
    'menu can replay the tour without re-arming auto-start',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      addTearDown(authRepository.dispose);
      final seenStore = InMemoryAppTourSeenStore();
      await seenStore.markCompleted(uid: _ownerUid);

      await tester.pumpWidget(
        _buildHarness(
          authRepository: authRepository,
          seenStore: seenStore,
          autoStartArmed: true,
        ),
      );
      await _pumpTourSettle(tester);

      // Returning user: already completed, never (re-)armed. No overlay on
      // load even though the host's own autoStartArmed flag is true.
      expect(_nextButton, findsNothing);
      expect(await seenStore.isCompleted(uid: _ownerUid), isTrue);
      expect(await seenStore.isArmed(uid: _ownerUid), isFalse);

      // Open the Home menu and tap the manual replay row.
      await tester.tap(_menuTrigger);
      await tester.pumpAndSettle();
      expect(_appTourRow, findsOneWidget);

      await tester.tap(_appTourRow);
      await _pumpTourSettle(tester);

      // The tour is running again, at step 1, showing the welcome copy.
      expect(_nextButton, findsOneWidget);
      expect(find.text(_welcomeMessage), findsOneWidget);

      // Replay must never re-arm auto-start or disturb completion.
      expect(await seenStore.isCompleted(uid: _ownerUid), isTrue);
      expect(await seenStore.isArmed(uid: _ownerUid), isFalse);
    },
  );

  testWidgets(
    'the App tour row is absent when the shell has no appTourSeenStore',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      addTearDown(authRepository.dispose);

      await tester.pumpWidget(
        _buildHarness(authRepository: authRepository, seenStore: null),
      );
      await _pumpTourSettle(tester);

      await tester.tap(_menuTrigger);
      await tester.pumpAndSettle();

      expect(_appTourRow, findsNothing);
      // Sanity: the menu itself still opened normally.
      expect(find.text('Settings'), findsOneWidget);
    },
  );
}
