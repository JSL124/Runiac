/// QA scenario cover for the real end-of-run journey on a plan day:
///
///   Home -> (run) -> Run Summary -> View XP Update -> Home
///
/// The plan's final scheduled workout is finished with the app already open,
/// so `completeRun` records `planCompletions[planId]` and the app's
/// `onRemoteRunSynced` wiring re-reads plan progress *while the runner is
/// still standing on the Run Summary screen* — i.e. while Home is buried under
/// pushed routes.
///
/// `showPlanCompletionCeremony` pushes a dialog route onto the same root
/// navigator, so without a gate the ceremony would land on whichever run-flow
/// screen happens to be on top when the refresh resolves — blocking that
/// screen's CTAs behind its non-dismissible barrier and spending the one-shot
/// seen marker somewhere the runner was never meant to be celebrated, leaving
/// Home silent afterwards.
///
/// `HomeTab` therefore holds the celebration until Home is frontmost. These
/// tests pin that down for every arrival timing: the ceremony must reach the
/// runner on the Home dashboard, and nowhere else.
///
/// Existing cover in `plan_completion_trigger_test.dart` drives the same sync
/// with Home already on top of the navigator stack, so it cannot see this.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/home/presentation/home_tab.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/models/plan_progress_read_model.dart';
import 'package:runiac_app/features/plan/domain/plan_completion_seen_store.dart';
import 'package:runiac_app/features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/plan/domain/repositories/plan_progress_repository.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/run/domain/models/complete_run_result.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/repositories/run_repository.dart';
import 'package:runiac_app/features/run/presentation/cool_down_screen.dart';
import 'package:runiac_app/features/run/presentation/data/run_completion_demo_snapshots.dart';
import 'package:runiac_app/features/run/presentation/view_summary_screen.dart';
import 'package:runiac_app/features/run/presentation/xp_update_screen.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';
import 'package:runiac_app/features/you/presentation/you_tab.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/plan_family_test_drafts.dart';

final _completedAt = DateTime.utc(2026, 7, 5, 9, 30);

const _ceremonyText = 'Plan Completed!';

void main() {
  group('QA — plan completed on a run taken with the app open', () {
    testWidgets(
      'A. sync lands on the Run Summary: the ceremony is held, the summary '
      'stays usable, and Home celebrates after the XP update',
      (tester) async {
        final harness = await _pumpPlanDayApp(tester);
        expect(find.byType(HomeTab), findsOneWidget);
        expect(find.text(_ceremonyText), findsNothing);

        await _pushRunSummary(tester);
        expect(find.byType(ViewSummaryScreen), findsOneWidget);

        await harness.syncFinalWorkout(tester, onScreen: ViewSummaryScreen);

        // Nothing opens over the summary, and the one-shot marker is intact.
        expect(find.text(_ceremonyText), findsNothing);
        expect(find.byType(ViewSummaryScreen), findsOneWidget);
        expect(
          await harness.seenStore.lastSeenPlanCompletedAtMs(),
          isNull,
          reason: 'a held celebration must not spend the seen marker',
        );

        // The summary's own CTA still works — no barrier is in the way.
        await tester.tap(find.text('View XP Update'));
        await tester.pumpAndSettle();
        expect(find.byType(XpUpdateScreen), findsOneWidget);
        expect(find.text(_ceremonyText), findsNothing);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(HomeTab), findsOneWidget);
        expect(
          find.text(_ceremonyText),
          findsOneWidget,
          reason: 'the runner is on the Home dashboard, so it celebrates here',
        );
        expect(
          await harness.seenStore.lastSeenPlanCompletedAtMs(),
          _completedAt.millisecondsSinceEpoch,
        );

        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
        expect(find.text(_ceremonyText), findsNothing);
      },
    );

    testWidgets(
      'B. sync lands on the XP Update screen: the reveal is left alone and the '
      '"Home" CTA carries the runner to the celebration',
      (tester) async {
        final harness = await _pumpPlanDayApp(tester);

        await _pushRunSummary(tester);
        await tester.tap(find.text('View XP Update'));
        await tester.pumpAndSettle();
        expect(find.byType(XpUpdateScreen), findsOneWidget);

        await harness.syncFinalWorkout(tester, onScreen: XpUpdateScreen);

        // The XP reveal is not covered.
        expect(find.text(_ceremonyText), findsNothing);
        expect(find.byType(XpUpdateScreen), findsOneWidget);

        // The XP screen's own "Home" CTA is reachable and pops to the root.
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(HomeTab), findsOneWidget);
        expect(
          find.text(_ceremonyText),
          findsOneWidget,
          reason: 'Home dashboard first, then the ceremony',
        );
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'D. sync lands on the Cool-Down screen (the real production timing): '
      'the ceremony is held and the cool-down CTAs stay reachable',
      (tester) async {
        final harness = await _pumpPlanDayApp(tester);

        // `RunCompletionCoordinator.complete()` kicks the plan-progress read
        // off *before* the run flow pushes the cool-down, so this is the
        // earliest — and most likely — route for the signal to arrive on.
        await _pushRoute(
          tester,
          CoolDownScreen(
            completionResult: _syncedCompletion('final-workout'),
            completionPayload: _syncPayload('final-workout-session'),
            repository: const _RemoteAcceptingRunRepository(),
          ),
        );
        expect(find.byType(CoolDownScreen), findsOneWidget);

        await harness.syncFinalWorkout(tester, onScreen: CoolDownScreen);

        expect(find.text(_ceremonyText), findsNothing);
        expect(find.byType(CoolDownScreen), findsOneWidget);

        // "Start Cool-down" — the only path to the server-owned cool-down
        // stretch XP bonus — is not blocked by an overlay barrier.
        await tester.tap(find.text('Start Cool-down'));
        await tester.pumpAndSettle();
        expect(
          find.byType(CoolDownScreen),
          findsNothing,
          reason: 'the tap reached the button and advanced the cool-down',
        );
        expect(find.text(_ceremonyText), findsNothing);
      },
    );

    testWidgets(
      'C. sync lands after the runner is back on Home: the ceremony works as '
      'designed',
      (tester) async {
        final harness = await _pumpPlanDayApp(tester);

        await _pushRunSummary(tester);
        await tester.tap(find.text('View XP Update'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeTab), findsOneWidget);
        expect(find.byType(ViewSummaryScreen), findsNothing);

        await harness.syncFinalWorkout(tester, onScreen: HomeTab);

        expect(
          find.text(_ceremonyText),
          findsOneWidget,
          reason: 'the ceremony reaches the runner when Home is on top',
        );
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'E. the celebration stays one-shot: once shown on Home and closed, '
      'leaving and returning does not replay it',
      (tester) async {
        final harness = await _pumpPlanDayApp(tester);

        await _pushRunSummary(tester);
        await harness.syncFinalWorkout(tester, onScreen: ViewSummaryScreen);
        await tester.tap(find.text('View XP Update'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text(_ceremonyText), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
        expect(find.text(_ceremonyText), findsNothing);

        // Home goes to the back of the stack and returns to the front again.
        await _pushRunSummary(tester);
        await tester.tap(find.text('View XP Update'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.text(_ceremonyText),
          findsNothing,
          reason: 'the seen marker was spent when it was actually shown',
        );
      },
    );

    testWidgets(
      'F. the run was started from another tab: the XP update\'s "Home" CTA '
      'selects the Home dashboard so the held ceremony is released',
      (tester) async {
        // The realistic case this was missing. A run started from You (or Feed,
        // or Leaderboard) pops back to *that* tab, so Home never becomes
        // frontmost and the celebration stays held indefinitely — the runner
        // would only ever see it by happening to tap Home later.
        final harness = await _pumpPlanDayApp(tester);
        await _selectTab(tester, Icons.person);
        expect(find.byType(YouTab), findsOneWidget);
        expect(find.byType(HomeTab), findsNothing, reason: 'You is selected');

        await _pushRunSummary(tester);
        await harness.syncFinalWorkout(tester, onScreen: ViewSummaryScreen);
        await tester.tap(find.text('View XP Update'));
        await tester.pumpAndSettle();
        expect(find.byType(XpUpdateScreen), findsOneWidget);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byType(HomeTab),
          findsOneWidget,
          reason: 'the CTA carries the runner to the Home dashboard itself',
        );
        expect(find.byType(YouTab), findsNothing);
        expect(
          find.text(_ceremonyText),
          findsOneWidget,
          reason: 'Home is frontmost, so the held celebration is released',
        );
        expect(
          await harness.seenStore.lastSeenPlanCompletedAtMs(),
          _completedAt.millisecondsSinceEpoch,
        );

        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'G. no plan completion: the "Home" CTA leaves the runner on the tab the '
      'run was started from',
      (tester) async {
        // The redirect is conditional on purpose. Hijacking the tab after every
        // single run would be a behaviour change for every runner, every day.
        await _pumpPlanDayApp(tester);
        await _selectTab(tester, Icons.person);

        await _pushRunSummary(tester);
        await tester.tap(find.text('View XP Update'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(YouTab), findsOneWidget);
        expect(find.byType(HomeTab), findsNothing);
        expect(find.text(_ceremonyText), findsNothing);
      },
    );

    testWidgets(
      'H. the redirect is as one-shot as the ceremony: the next run from '
      'another tab returns there',
      (tester) async {
        final harness = await _pumpPlanDayApp(tester);
        await _selectTab(tester, Icons.person);

        // First run finishes the plan and celebrates on Home.
        await _pushRunSummary(tester);
        await harness.syncFinalWorkout(tester, onScreen: ViewSummaryScreen);
        await tester.tap(find.text('View XP Update'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(_ceremonyText), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();

        // A later run, started from You while the same completion is still
        // recorded on the backend. The marker is spent, so nothing is pending.
        await _selectTab(tester, Icons.person);
        await _pushRunSummary(tester);
        await tester.tap(find.text('View XP Update'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byType(YouTab),
          findsOneWidget,
          reason: 'a spent celebration must not keep redirecting the runner',
        );
        expect(find.text(_ceremonyText), findsNothing);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _Harness {
  _Harness({required this.planProgressRepository, required this.seenStore});

  final _CompletingPlanProgressRepository planProgressRepository;
  final InMemoryPlanCompletionSeenStore seenStore;

  /// Mirrors `completeRun` recording `planCompletions[planId]` and the app's
  /// own `onRemoteRunSynced` wiring re-reading plan progress afterwards.
  /// [onScreen] is the route that is on top when the refresh resolves.
  Future<void> syncFinalWorkout(
    WidgetTester tester, {
    required Type onScreen,
  }) async {
    planProgressRepository.completePlan();

    final store = CurrentSessionActivityHistoryScope.maybeRead(
      tester.element(find.byType(onScreen)),
    );
    expect(store, isNotNull, reason: 'the app must compose its own store');
    await store!.saveCompletedRun(
      _syncedCompletion('final-workout'),
      payload: _syncPayload('final-workout-session'),
    );
    await store.syncPendingRuns(const _RemoteAcceptingRunRepository());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<_Harness> _pumpPlanDayApp(WidgetTester tester) async {
  // A phone-sized surface, so the run-flow CTAs are on screen the way they are
  // on a real device rather than clipped by the 800x600 test default.
  tester.view.physicalSize = const Size(1290, 2796);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final planProgressRepository = _CompletingPlanProgressRepository();
  final seenStore = InMemoryPlanCompletionSeenStore();
  final authRepository = FakeRuniacAuthRepository()
    ..emitSignedIn(uid: 'runner-1');
  addTearDown(authRepository.dispose);

  await tester.pumpWidget(
    RuniacApp(
      showSplash: false,
      showAuth: true,
      enableForegroundGps: false,
      authRepository: authRepository,
      profileRepository: const StaticUserProfileRepository(),
      generatedPlanPersistenceRepository: _LoadedGeneratedPlanRepository(
        const BeginnerAdaptivePlanGenerator().generate(
          planFamilyPerformanceDraft(
            goal: OnboardingGoal.tenK,
            style: OnboardingPlanStyle.performanceFocused,
            days: const [
              OnboardingPreferredDay.mon,
              OnboardingPreferredDay.tue,
            ],
          ),
        ),
      ),
      planProgressRepository: planProgressRepository,
      planCompletionSeenStore: seenStore,
    ),
  );
  await tester.pumpAndSettle();

  return _Harness(
    planProgressRepository: planProgressRepository,
    seenStore: seenStore,
  );
}

/// Pushes the Run Summary screen the way the cool-down flow does: onto the
/// same root navigator Home lives under.
Future<void> _pushRunSummary(WidgetTester tester) {
  return _pushRoute(
    tester,
    ViewSummaryScreen(
      completionResult: _syncedCompletion('final-workout'),
      completionPayload: _syncPayload('final-workout-session'),
    ),
  );
}

/// Pushes a run-flow screen onto the same root navigator Home lives under,
/// which is exactly what the real flow does.
///
/// Anchored on the shell's navigation bar rather than on `HomeTab`, because a
/// run can be started from any tab and `HomeTab` is offstage — and so unfindable
/// — whenever it is not the selected one.
Future<void> _pushRoute(WidgetTester tester, Widget screen) async {
  final shellContext = tester.element(find.byType(BottomNavigationBar));
  unawaited(
    Navigator.of(
      shellContext,
    ).push(MaterialPageRoute<void>(builder: (context) => screen)),
  );
  await tester.pumpAndSettle();
}

/// Selects a tab the way the runner does, through the shell's navigation bar.
Future<void> _selectTab(WidgetTester tester, IconData icon) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.byIcon(icon),
    ),
  );
  await tester.pumpAndSettle();
}

class _LoadedGeneratedPlanRepository
    implements GeneratedPlanPersistenceRepository {
  const _LoadedGeneratedPlanRepository(this.plan);

  final BeginnerAdaptivePlanSnapshot plan;

  @override
  Future<BeginnerAdaptivePlanSnapshot?> loadGeneratedPlan({
    required String uid,
  }) async {
    return plan;
  }

  @override
  Future<void> saveGeneratedPlan({
    required String uid,
    required BeginnerAdaptivePlanSnapshot plan,
    bool resetCreatedAt = false,
  }) async {}
}

class _CompletingPlanProgressRepository implements PlanProgressRepository {
  var loadCount = 0;
  var _completed = false;

  void completePlan() {
    _completed = true;
  }

  @override
  Future<PlanProgressReadModel> loadPlanProgress({
    required String uid,
    required String activeGeneratedPlanId,
  }) async {
    loadCount += 1;
    return PlanProgressReadModel(
      completedScheduledWorkoutIds: const ['week-1-mon-easy-run'],
      planCompletedAt: _completed ? _completedAt : null,
    );
  }
}

class _RemoteAcceptingRunRepository implements RunRepository {
  const _RemoteAcceptingRunRepository();

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    return _syncedCompletion(payload.clientRunSessionId);
  }

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CompleteRunResult> loadLatestCompletionResult() {
    throw UnimplementedError();
  }

  @override
  Future<RunActivityReadModel> loadLatestRunActivity() {
    throw UnimplementedError();
  }

  @override
  Future<RunSummaryReadModel> loadLatestRunSummary() {
    throw UnimplementedError();
  }
}

CompleteRunResult _syncedCompletion(String id) {
  return CompleteRunResult(
    activityId: 'activity_$id',
    summaryId: 'summary_$id',
    progressionEventId: 'progression_$id',
    summary: RunSummarySnapshot(
      title: 'Synced Run',
      dateLabel: 'Today',
      timeLabel: '8:10 AM',
      distanceKm: '3.00',
      avgPace: '6’15”',
      duration: '18:30',
      avgHeartRate: '--',
      calories: '--',
      routeName: 'Current Session Route',
      hasSufficientData: true,
      route: RunRouteSnapshot.empty,
    ),
    xpUpdate: defaultXpUpdateDisplayModel,
  );
}

LocalRunCompletionPayload _syncPayload(String clientRunSessionId) {
  return LocalRunCompletionPayload(
    clientRunSessionId: clientRunSessionId,
    startedAt: DateTime.utc(2026, 6, 30, 8),
    completedAt: DateTime.utc(2026, 6, 30, 8, 30),
    durationSeconds: 1800,
    distanceMeters: 3000,
    avgPaceSecondsPerKm: 360,
    source: 'mobile',
    routePrivacy: 'private',
  );
}
