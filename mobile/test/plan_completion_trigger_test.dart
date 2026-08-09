import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/home/presentation/home_tab.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/plan/domain/repositories/plan_progress_repository.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_read_model.dart';
import 'package:runiac_app/features/run/domain/models/complete_run_result.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_read_model.dart';
import 'package:runiac_app/features/run/domain/repositories/run_repository.dart';
import 'package:runiac_app/features/run/presentation/data/run_completion_demo_snapshots.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';
import 'package:runiac_app/features/plan/domain/models/plan_progress_read_model.dart';
import 'package:runiac_app/features/plan/domain/plan_completion_seen_store.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/plan_family_test_drafts.dart';

const _activePlanId = 'plan-alpha';
final _completedAt = DateTime.utc(2026, 7, 5, 9, 30);

Map<String, Object?> _backendData({
  required String completionPlanId,
  String completedAt = '2026-07-05T09:30:00.000Z',
}) {
  return <String, Object?>{
    'workouts': <String, Object?>{
      '${_activePlanId}__w1': <String, Object?>{
        'completedAt': '2026-07-02T00:00:00.000Z',
      },
    },
    'planCompletions': <String, Object?>{
      completionPlanId: <String, Object?>{
        'planId': completionPlanId,
        'completedAt': completedAt,
        'completedWorkoutCount': 3,
        'plannedWorkoutTotal': 3,
      },
    },
  };
}

Future<void> _pumpHomeTab(
  WidgetTester tester, {
  required DateTime? planCompletedAt,
  required PlanCompletionSeenStore? seenStore,
}) async {
  final authRepository = FakeRuniacAuthRepository()
    ..emitSignedIn(uid: 'runner-1');
  await tester.pumpWidget(
    MaterialApp(
      home: HomeTab(
        authRepository: authRepository,
        profileRepository: const StaticUserProfileRepository(),
        profilePersistenceRepository:
            const NoopUserProfilePersistenceRepository(),
        planCompletedAt: planCompletedAt,
        planCompletionSeenStore: seenStore,
        enableForegroundGps: false,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('PlanProgressReadModel.planCompletedAt', () {
    test('reads the backend completion for the active plan', () {
      final model = PlanProgressReadModel.fromBackend(
        activeGeneratedPlanId: _activePlanId,
        data: _backendData(completionPlanId: _activePlanId),
      );

      expect(model.planCompletedAt, _completedAt.toLocal());
      expect(model.completedScheduledWorkoutIds, {'w1'});
    });

    test('ignores a completion recorded for a different plan', () {
      final model = PlanProgressReadModel.fromBackend(
        activeGeneratedPlanId: _activePlanId,
        data: _backendData(completionPlanId: 'plan-previous'),
      );

      expect(model.planCompletedAt, isNull);
    });

    test('is null when the backend recorded no completion', () {
      final model = PlanProgressReadModel.fromBackend(
        activeGeneratedPlanId: _activePlanId,
        data: const <String, Object?>{
          'workouts': <String, Object?>{},
        },
      );

      expect(model.planCompletedAt, isNull);
    });

    test('survives a malformed completion entry', () {
      final model = PlanProgressReadModel.fromBackend(
        activeGeneratedPlanId: _activePlanId,
        data: const <String, Object?>{
          'workouts': <String, Object?>{},
          'planCompletions': <String, Object?>{
            _activePlanId: <String, Object?>{'completedAt': 42},
          },
        },
      );

      expect(model.planCompletedAt, isNull);
    });

    test('is preserved when the plan has no per-workout entries', () {
      final model = PlanProgressReadModel.fromBackend(
        activeGeneratedPlanId: _activePlanId,
        data: <String, Object?>{
          'planCompletions': _backendData(
            completionPlanId: _activePlanId,
          )['planCompletions'],
        },
      );

      expect(model.planCompletedAt, _completedAt.toLocal());
    });
  });

  group('HomeTab plan-completion ceremony', () {
    testWidgets('celebrates a newly recorded completion once', (tester) async {
      final seenStore = InMemoryPlanCompletionSeenStore();

      await _pumpHomeTab(
        tester,
        planCompletedAt: _completedAt,
        seenStore: seenStore,
      );

      expect(find.text('Plan Completed!'), findsOneWidget);
      expect(
        await seenStore.lastSeenPlanCompletedAtMs(),
        _completedAt.millisecondsSinceEpoch,
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Plan Completed!'), findsNothing);
    });

    testWidgets('does not re-celebrate an already-seen completion', (
      tester,
    ) async {
      final seenStore = InMemoryPlanCompletionSeenStore(
        initialCompletedAtMs: _completedAt.millisecondsSinceEpoch,
      );

      await _pumpHomeTab(
        tester,
        planCompletedAt: _completedAt,
        seenStore: seenStore,
      );

      expect(find.text('Plan Completed!'), findsNothing);
    });

    testWidgets('stays silent while the plan is still in progress', (
      tester,
    ) async {
      await _pumpHomeTab(
        tester,
        planCompletedAt: null,
        seenStore: InMemoryPlanCompletionSeenStore(),
      );

      expect(find.text('Plan Completed!'), findsNothing);
    });

    testWidgets('stays silent when no seen store is composed', (tester) async {
      await _pumpHomeTab(
        tester,
        planCompletedAt: _completedAt,
        seenStore: null,
      );

      expect(find.text('Plan Completed!'), findsNothing);
    });

    testWidgets('celebrates a completion that arrives after the first frame', (
      tester,
    ) async {
      final seenStore = InMemoryPlanCompletionSeenStore();
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'runner-1');

      Widget buildHome({required DateTime? planCompletedAt}) {
        return MaterialApp(
          home: HomeTab(
            authRepository: authRepository,
            profileRepository: const StaticUserProfileRepository(),
            profilePersistenceRepository:
                const NoopUserProfilePersistenceRepository(),
            planCompletedAt: planCompletedAt,
            planCompletionSeenStore: seenStore,
            enableForegroundGps: false,
          ),
        );
      }

      await tester.pumpWidget(buildHome(planCompletedAt: null));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Plan Completed!'), findsNothing);

      // The async plan-progress load resolves and pushes the signal down.
      await tester.pumpWidget(buildHome(planCompletedAt: _completedAt));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Plan Completed!'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });
  });

  group('HomeTab plan-completion after run sync', _runSyncRefreshTests);
}


/// Regression cover for the foreground run-completion path: when the final
/// scheduled workout is finished with the app already open, `completeRun`
/// records the completion on `planProgress/{uid}`, so the app must re-read
/// plan progress after the run syncs. Without that refresh the ceremony would
/// only surface on the next app launch.
void _runSyncRefreshTests() {
  testWidgets('re-reads plan progress after a run syncs remotely', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final planProgressRepository = _CompletingPlanProgressRepository();
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'runner-1');
    addTearDown(authRepository.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        enableForegroundGps: false,
        authRepository: authRepository,
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
        planCompletionSeenStore: InMemoryPlanCompletionSeenStore(),
      ),
    );
    await tester.pumpAndSettle();

    // The first load happened before the run, with the plan still unfinished.
    expect(planProgressRepository.loadCount, greaterThanOrEqualTo(1));
    expect(find.text('Plan Completed!'), findsNothing);

    // The backend now records the completion, as `completeRun` would.
    planProgressRepository.completePlan();

    // Drive the app's *own* activity-history store, so the production
    // `onRemoteRunSynced` wiring is exercised rather than a test-injected one.
    final store = CurrentSessionActivityHistoryScope.maybeRead(
      tester.element(find.byType(HomeTab)),
    );
    expect(store, isNotNull);
    await store!.saveCompletedRun(
      _syncedCompletion('final-workout'),
      payload: _syncPayload('final-workout-session'),
    );
    await store.syncPendingRuns(const _RemoteAcceptingRunRepository());
    await tester.pumpAndSettle();

    expect(find.text('Plan Completed!'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
  });
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

/// Returns no completion until [completePlan] is called, mimicking the backend
/// recording `planCompletions` during the run that finishes the plan.
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
      avgPace: '6\u201915\u201d',
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
