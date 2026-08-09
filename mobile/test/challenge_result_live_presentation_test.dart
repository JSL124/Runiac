import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/auth/data/non_production_auth_repository.dart';
import 'package:runiac_app/features/challenge/domain/challenge_result_seen_store.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_history.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_result_presentation_controller.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_result_screen.dart';
import 'package:runiac_app/features/home/presentation/home_tab.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_inbox_item.dart';
import 'package:runiac_app/features/notifications/domain/repositories/notification_inbox_repository.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';

import 'support/fake_challenge_repository.dart';

/// A challenge settles on a backend sweep that runs about a minute after the
/// run which completed it, so the result routinely lands while the app is in
/// the foreground and Home is already built. `initState` runs once and the tab
/// is kept alive forever, and `didChangeAppLifecycleState` only fires when the
/// OS backgrounds the app — so neither of the two original triggers coincided
/// with settlement. The celebration appeared only if the runner happened to
/// background and reopen the app, or tapped the inbox item by hand.
///
/// These tests pin the live path: the arrival of a challenge-result
/// notification, which the backend writes strictly after the history document
/// commits, re-checks for an unseen result.

ChallengeHistoryEntry _succeededEntry({
  String challengeId = 'c-1',
  required int endedAtMs,
}) {
  return ChallengeHistoryEntry(
    challengeId: challengeId,
    tierId: ChallengeTierId.k10,
    mode: ChallengeMode.group,
    role: ChallengeParticipantRole.member,
    outcome: ChallengeParticipantStatus.succeeded,
    terminalReason: ChallengeTerminalReason.targetReached,
    teamMeters: 10000,
    personalMeters: 6000,
    targetMeters: 10000,
    personalMinimumMeters: 3000,
    startedAtMs: endedAtMs - 3600000,
    endedAtMs: endedAtMs,
  );
}

NotificationInboxItem _resultReadyItem({String challengeId = 'c-1'}) {
  return NotificationInboxItem(
    id: 'challenge-result-$challengeId',
    title: 'Challenge complete',
    body: 'Your 10K challenge is settled.',
    createdAt: DateTime.utc(2026, 8, 3, 12),
    data: <String, Object?>{
      'kind': 'challenge_result_ready',
      'challengeId': challengeId,
      'tierId': '10K',
    },
  );
}

/// The result ceremony runs a confetti animation that never settles, so
/// `pumpAndSettle` times out once it is on screen (the same reason
/// challenge_result_ui_test.dart drives bounded frames). Pump enough frames for
/// the async peek, the marker write, and the route transition to complete.
Future<void> _pumpCeremonyFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Widget _homeUnderTest({
  required NotificationInboxRepository inbox,
  required ChallengeResultPresentationController presenter,
  // The inbox route reads history through HomeTab's own repository, not the
  // presenter's, so both must point at the same fake for that path to resolve.
  required FakeChallengeRepository challenges,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    home: HomeTab(
      authRepository: const NonProductionAuthRepository(),
      profileRepository: const StaticUserProfileRepository(),
      profilePersistenceRepository: const NoopUserProfilePersistenceRepository(),
      notificationInboxRepository: inbox,
      challengeRepository: challenges,
      challengeResultPresenter: presenter,
      enableForegroundGps: false,
    ),
  );
}

int _justSettledMs() => DateTime.now()
    .subtract(const Duration(minutes: 1))
    .millisecondsSinceEpoch;

void main() {
  testWidgets(
    'a challenge that settles while the app is open celebrates without '
    'needing a background/foreground cycle',
    (WidgetTester tester) async {
      // Empty history: the run is done but the settlement sweep has not run.
      final history = <ChallengeHistoryEntry>[];
      final challenges = FakeChallengeRepository(historyOverride: history);
      final inbox = InMemoryNotificationInboxRepository(items: const []);
      final presenter = ChallengeResultPresentationController(
        repository: challenges,
        seenStore: InMemoryChallengeResultSeenStore(),
      );

      await tester.pumpWidget(
        _homeUnderTest(
          inbox: inbox,
          presenter: presenter,
          challenges: challenges,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(ChallengeResultScreen),
        findsNothing,
        reason: 'nothing has settled yet',
      );

      // The sweep lands: the history document is written first, then the inbox
      // document. Reproduce that order.
      history.add(
        _succeededEntry(
          endedAtMs: _justSettledMs(),
        ),
      );
      await inbox.saveInboxItem(_resultReadyItem());
      await _pumpCeremonyFrames(tester);

      expect(find.byType(ChallengeResultScreen), findsOneWidget);
    },
  );

  testWidgets(
    'an unrelated inbox item does not present anything',
    (WidgetTester tester) async {
      final history = <ChallengeHistoryEntry>[
        _succeededEntry(
          endedAtMs: _justSettledMs(),
        ),
      ];
      final challenges = FakeChallengeRepository(historyOverride: history);
      final inbox = InMemoryNotificationInboxRepository(items: const []);
      // A marker already covering the entry: it has been celebrated before.
      final presenter = ChallengeResultPresentationController(
        repository: challenges,
        seenStore: InMemoryChallengeResultSeenStore(
          initialEndedAtMs: history.first.endedAtMs,
        ),
      );

      await tester.pumpWidget(
        _homeUnderTest(
          inbox: inbox,
          presenter: presenter,
          challenges: challenges,
        ),
      );
      await tester.pumpAndSettle();

      await inbox.saveInboxItem(
        NotificationInboxItem(
          id: 'plan-1',
          title: 'Run reminder',
          body: 'Your easy run is ready.',
          createdAt: DateTime.utc(2026, 8, 3, 12),
          data: const <String, Object?>{'kind': 'plan_reminder'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChallengeResultScreen), findsNothing);
    },
  );

  testWidgets(
    'the celebration is presented once and does not replay on a later '
    'inbox emission',
    (WidgetTester tester) async {
      final history = <ChallengeHistoryEntry>[
        _succeededEntry(
          endedAtMs: _justSettledMs(),
        ),
      ];
      final challenges = FakeChallengeRepository(historyOverride: history);
      final inbox = InMemoryNotificationInboxRepository(items: const []);
      final seenStore = InMemoryChallengeResultSeenStore();
      final presenter = ChallengeResultPresentationController(
        repository: challenges,
        seenStore: seenStore,
      );

      await tester.pumpWidget(
        _homeUnderTest(
          inbox: inbox,
          presenter: presenter,
          challenges: challenges,
        ),
      );
      await _pumpCeremonyFrames(tester);

      // The mount-time check already presents it, since history is populated.
      expect(find.byType(ChallengeResultScreen), findsOneWidget);
      expect(
        await seenStore.lastSeenResultEndedAtMs(),
        history.first.endedAtMs,
        reason: 'the marker advances only once the ceremony is on screen',
      );

      // Close the ceremony, then let the notification for it arrive late.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ChallengeResultScreen), findsNothing);

      await inbox.saveInboxItem(_resultReadyItem());
      await _pumpCeremonyFrames(tester);

      expect(
        find.byType(ChallengeResultScreen),
        findsNothing,
        reason: 'the marker already covers this result',
      );
    },
  );

  testWidgets(
    'a result that settles while Home is covered is held, then celebrated '
    'once Home is frontmost again',
    (WidgetTester tester) async {
      // Settlement lands while the runner is still inside the run flow. The
      // ceremony is a full-screen route: pushing it there would cover the
      // cool-down / summary / XP screens and block their CTAs, and would spend
      // the celebration on a screen it was never meant for. It must wait.
      final history = <ChallengeHistoryEntry>[];
      final challenges = FakeChallengeRepository(historyOverride: history);
      final inbox = InMemoryNotificationInboxRepository(items: const []);
      final navigatorKey = GlobalKey<NavigatorState>();
      final presenter = ChallengeResultPresentationController(
        repository: challenges,
        seenStore: InMemoryChallengeResultSeenStore(),
      );

      await tester.pumpWidget(
        _homeUnderTest(
          inbox: inbox,
          presenter: presenter,
          challenges: challenges,
          navigatorKey: navigatorKey,
        ),
      );
      await tester.pumpAndSettle();

      // Stand in for the run-summary / XP flow sitting on top of Home.
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Run summary')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Run summary'), findsOneWidget);

      history.add(_succeededEntry(endedAtMs: _justSettledMs()));
      await inbox.saveInboxItem(_resultReadyItem());
      await _pumpCeremonyFrames(tester);

      expect(
        find.byType(ChallengeResultScreen),
        findsNothing,
        reason: 'Home is covered — the ceremony must be held, not pushed',
      );

      navigatorKey.currentState!.pop();
      await _pumpCeremonyFrames(tester);

      expect(
        find.byType(ChallengeResultScreen),
        findsOneWidget,
        reason: 'returning to Home must retry the held celebration',
      );
    },
  );

  testWidgets(
    'the app-resume path still celebrates a result that settled while the '
    'app was backgrounded',
    (WidgetTester tester) async {
      // The original (only) working trigger. It must keep working alongside
      // the new live one.
      final history = <ChallengeHistoryEntry>[];
      final challenges = FakeChallengeRepository(historyOverride: history);
      final inbox = InMemoryNotificationInboxRepository(items: const []);
      final presenter = ChallengeResultPresentationController(
        repository: challenges,
        seenStore: InMemoryChallengeResultSeenStore(),
      );

      await tester.pumpWidget(
        _homeUnderTest(
          inbox: inbox,
          presenter: presenter,
          challenges: challenges,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChallengeResultScreen), findsNothing);

      // Settled while backgrounded: no inbox emission is observed, because the
      // stream was not delivering while the app was suspended.
      history.add(_succeededEntry(endedAtMs: _justSettledMs()));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpCeremonyFrames(tester);

      expect(find.byType(ChallengeResultScreen), findsOneWidget);
    },
  );

  testWidgets(
    'opening the result from the notification inbox marks it seen, so it '
    'does not auto-present again afterwards',
    (WidgetTester tester) async {
      // The inbox path used to present the ceremony without touching the
      // marker, so viewing a result by hand and then backgrounding the app
      // replayed the very same celebration.
      final entry = _succeededEntry(endedAtMs: _justSettledMs());
      final challenges = FakeChallengeRepository(
        historyOverride: <ChallengeHistoryEntry>[entry],
      );
      final inbox = InMemoryNotificationInboxRepository(
        items: [_resultReadyItem()],
      );
      final seenStore = InMemoryChallengeResultSeenStore(
        // Already marked, so the auto path stays quiet and this test isolates
        // the inbox route.
        initialEndedAtMs: entry.endedAtMs,
      );
      final presenter = ChallengeResultPresentationController(
        repository: challenges,
        seenStore: seenStore,
      );

      await tester.pumpWidget(
        _homeUnderTest(
          inbox: inbox,
          presenter: presenter,
          challenges: challenges,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChallengeResultScreen), findsNothing);

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Challenge complete'));
      await _pumpCeremonyFrames(tester);

      expect(find.byType(ChallengeResultScreen), findsOneWidget);
      expect(
        await seenStore.lastSeenResultEndedAtMs(),
        entry.endedAtMs,
        reason: 'the inbox route must advance the marker too',
      );
    },
  );

  testWidgets(
    'two celebrations are never stacked when triggers overlap',
    (WidgetTester tester) async {
      final history = <ChallengeHistoryEntry>[
        _succeededEntry(endedAtMs: _justSettledMs()),
      ];
      final challenges = FakeChallengeRepository(historyOverride: history);
      final inbox = InMemoryNotificationInboxRepository(items: const []);
      final presenter = ChallengeResultPresentationController(
        repository: challenges,
        seenStore: InMemoryChallengeResultSeenStore(),
      );

      await tester.pumpWidget(
        _homeUnderTest(
          inbox: inbox,
          presenter: presenter,
          challenges: challenges,
        ),
      );
      // Fire the inbox trigger and a resume while the mount-time check is
      // still in flight.
      await inbox.saveInboxItem(_resultReadyItem());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpCeremonyFrames(tester);

      expect(find.byType(ChallengeResultScreen), findsOneWidget);
    },
  );
}
