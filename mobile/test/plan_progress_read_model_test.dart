import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map_model.dart';
import 'package:runiac_app/features/plan/data/firestore_plan_progress_repository.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/models/plan_progress_read_model.dart';
import 'package:runiac_app/features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/plan/domain/repositories/plan_progress_repository.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/you/presentation/adapters/generated_plan_you_display_adapter.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/plan_family_test_drafts.dart';

BeginnerAdaptivePlanSnapshot _tenKPerformancePlan() {
  return const BeginnerAdaptivePlanGenerator().generate(
    planFamilyPerformanceDraft(
      goal: OnboardingGoal.tenK,
      style: OnboardingPlanStyle.performanceFocused,
      days: const [
        OnboardingPreferredDay.mon,
        OnboardingPreferredDay.tue,
        OnboardingPreferredDay.wed,
        OnboardingPreferredDay.thu,
      ],
    ),
  );
}

DateTime _weekdayDate(int weekday) {
  return DateTime(2026, 6, 21 + weekday);
}

void main() {
  group('PlanProgressReadModel.fromBackend', () {
    test(
      'hydrates active generated plan workout keys as raw scheduled ids',
      () {
        // Given: backend progress keys combine generated plan and workout ids.
        final progress = PlanProgressReadModel.fromBackend(
          activeGeneratedPlanId: 'generated-plan-1',
          data: const {
            'workouts': {
              'generated-plan-1__week-1-tue-controlled-steady-run': {
                'completedAt': '2026-06-23T10:00:00.000Z',
              },
              'generated-plan-2__week-1-thu-recovery-run': {
                'completedAt': '2026-06-25T10:00:00.000Z',
              },
            },
          },
        );

        // Then: only the active generated plan prefix is normalized away.
        expect(progress.completedScheduledWorkoutIds, {
          'week-1-tue-controlled-steady-run',
        });
      },
    );

    test(
      'filters missing malformed stale duplicate and planSnapshots progress',
      () {
        // Given: backend progress includes every ignored shape G003 calls out.
        final progress = PlanProgressReadModel.fromBackend(
          activeGeneratedPlanId: 'generated-plan-1',
          data: const {
            'workouts': {
              'generated-plan-1__week-1-tue-controlled-steady-run': {
                'completedAt': '2026-06-23T10:00:00.000Z',
              },
              'generated-plan-1__week-1-tue-controlled-steady-run ': {
                'completedAt': '2026-06-23T10:00:00.000Z',
              },
              'generated-plan-2__week-1-thu-recovery-run': {
                'completedAt': '2026-06-25T10:00:00.000Z',
              },
              'generated-plan-1__': {'completedAt': '2026-06-23T10:00:00.000Z'},
              '__week-1-sat-recovery-run': {
                'completedAt': '2026-06-27T10:00:00.000Z',
              },
              'week-1-mon-comfortable-run': {
                'completedAt': '2026-06-22T10:00:00.000Z',
              },
              'generated-plan-1__week-1-sun-rest-day': 'completed',
              'generated-plan-1__week-1-mon-comfortable-run': {},
            },
            'planSnapshots': {
              'generated-plan-1': {
                'completedScheduledWorkoutIds': [
                  'week-1-thu-recovery-run',
                  'week-1-sat-recovery-run',
                ],
              },
            },
          },
        );

        // Then: only well-formed completed active-plan workouts remain.
        expect(progress.completedScheduledWorkoutIds, {
          'week-1-tue-controlled-steady-run',
        });
      },
    );

    test('missing document falls back to empty progress', () {
      // Given/When: the owner document is absent.
      final progress = PlanProgressReadModel.fromBackend(
        activeGeneratedPlanId: 'generated-plan-1',
        data: null,
      );

      // Then: no completions are inferred.
      expect(progress.completedScheduledWorkoutIds, isEmpty);
    });
  });

  group('PlanProgressRepository', () {
    test('read exceptions fall back to empty progress', () async {
      // Given: the document store throws as it would for permission/offline.
      final repository = FirestorePlanProgressRepository(
        documentStore: _ThrowingPlanProgressDocumentStore(),
      );

      // When: backend progress is loaded.
      final progress = await repository.loadPlanProgress(
        uid: 'runner-1',
        activeGeneratedPlanId: 'generated-plan-1',
      );

      // Then: the app receives safe empty progress instead of a thrown error.
      expect(progress.completedScheduledWorkoutIds, isEmpty);
    });
  });

  testWidgets(
    'RuniacApp hydrates generated snapshot with backend plan progress',
    (tester) async {
      // Given: generatedPlans owns the snapshot and planProgress owns progress.
      final plan = _tenKPerformancePlan();
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
            plan,
          ),
          planProgressRepository: _LoadedPlanProgressRepository(
            completedIds: const ['week-1-tue-controlled-steady-run'],
          ),
          youProgressToday: _weekdayDate(DateTime.tuesday),
        ),
      );
      await tester.pumpAndSettle();

      // When: the You plan surface is opened.
      await tester.tap(find.byTooltip('You'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();

      // Then: the generated snapshot renders with backend-owned completion.
      expect(find.text('10K Performance Build'), findsOneWidget);
      expect(find.text('Week 1 of ${plan.weeks.length}'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    },
  );

  testWidgets('RuniacApp preserves generated plan progress after reschedule', (
    tester,
  ) async {
    // Given: generatedPlans owns the snapshot and planProgress owns a
    // completed workout in this week's schedule.
    final plan = _tenKPerformancePlan();
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
          plan,
        ),
        planProgressRepository: _LoadedPlanProgressRepository(
          completedIds: const ['week-1-tue-controlled-steady-run'],
        ),
        youProgressToday: _weekdayDate(DateTime.tuesday),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('You'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);

    // When: a different future workout is rescheduled.
    await tester.ensureVisible(find.text('20 min Recovery Run'));
    await tester.tap(find.text('20 min Recovery Run'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit_schedule_day_Fri')));
    await tester.pumpAndSettle();
    await _selectOneMinuteLaterFromWheel(tester);
    final saveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save New Schedule'),
    );
    expect(saveButton.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save New Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to Plans'));
    await tester.pumpAndSettle();

    // Then: the backend-owned completed state is still visible and the
    // progress bar remains hydrated instead of resetting to zero.
    expect(find.text('Completed'), findsOneWidget);
    final progressIndicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progressIndicator.value, 0.25);

    await tester.tap(find.byTooltip('Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final homeStageMap = tester.widget<HomeStageMap>(find.byType(HomeStageMap));
    final firstWeekStones = homeStageMap.model!.sections.first.stones;
    expect(
      firstWeekStones[DateTime.thursday - 1].kind,
      HomeStageStoneKind.rest,
    );
    expect(firstWeekStones[DateTime.friday - 1].workoutTitle, 'Recovery Run');
  });

  testWidgets(
    'RuniacApp Run launch combines generated snapshot with backend progress',
    (tester) async {
      // Given: backend progress says today's generated workout is complete.
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
            _tenKPerformancePlan(),
          ),
          planProgressRepository: _LoadedPlanProgressRepository(
            completedIds: const ['week-1-tue-controlled-steady-run'],
          ),
          youProgressToday: _weekdayDate(DateTime.tuesday),
        ),
      );
      await tester.pumpAndSettle();

      // When: the Run tab opens from the hydrated app shell.
      await tester.tap(find.byTooltip('Run'));
      await tester.pumpAndSettle();

      // Then: Run uses the generated planned context and backend completion
      // state instead of the static fallback run.
      expect(find.text('CONTROLLED STEADY RUN COMPLETE'), findsOneWidget);
      expect(find.text('25 min'), findsOneWidget);
      expect(
        find.textContaining("Today's planned run is already complete"),
        findsOneWidget,
      );
      expect(find.text('4.5'), findsNothing);
      expect(find.text('km easy run'), findsNothing);
    },
  );

  testWidgets('RuniacApp no-progress hydration renders generated plan safely', (
    tester,
  ) async {
    // Given: generatedPlans has a snapshot but planProgress is missing/null.
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
          _tenKPerformancePlan(),
        ),
        planProgressRepository: _LoadedPlanProgressRepository(),
        youProgressToday: _weekdayDate(DateTime.tuesday),
      ),
    );
    await tester.pumpAndSettle();

    // When: the You plan surface is opened.
    await tester.tap(find.byTooltip('You'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();

    // Then: existing generatedPlans fallback remains safe and not completed.
    expect(find.text('10K Performance Build'), findsOneWidget);
    expect(find.text('Upcoming · 7:30 AM'), findsWidgets);
    expect(find.text('Completed'), findsNothing);
  });

  test('session activity completion still merges with backend progress', () {
    // Given: backend progress and current-session activity each complete one
    // distinct generated workout.
    final progress = GeneratedPlanProgressDisplay(
      completedScheduledWorkoutIds: const [
        'week-1-tue-controlled-steady-run',
        'week-1-thu-recovery-run',
      ],
    );

    // When: the existing generated-plan adapter receives the merged display.
    final plan = _tenKPerformancePlan();
    final display = generatedYouPlanDisplayFromSnapshot(
      plan,
      currentDate: _weekdayDate(DateTime.tuesday),
      planProgress: progress,
    );

    // Then: both completions count once against the generated snapshot.
    expect(display, isNotNull);
    expect(display!.progressLabel, 'Week 1 of ${plan.weeks.length}');
    expect(display.progressValue, 0.5);
  });
}

Future<void> _selectOneMinuteLaterFromWheel(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('edit_schedule_time_selector')));
  await tester.pumpAndSettle();
  await tester.timedDrag(
    find.byKey(const ValueKey('edit_schedule_time_minute_picker')),
    const Offset(0, -38),
    const Duration(milliseconds: 500),
  );
  await tester.pumpAndSettle();
  await tester.tapAt(const Offset(20, 20));
  await tester.pumpAndSettle();
}

class _ThrowingPlanProgressDocumentStore implements PlanProgressDocumentStore {
  @override
  Future<Map<String, Object?>?> loadPlanProgress({required String uid}) {
    throw StateError('offline');
  }
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

class _LoadedPlanProgressRepository implements PlanProgressRepository {
  const _LoadedPlanProgressRepository({this.completedIds = const <String>[]});

  final Iterable<String> completedIds;

  @override
  Future<PlanProgressReadModel> loadPlanProgress({
    required String uid,
    required String activeGeneratedPlanId,
  }) async {
    return PlanProgressReadModel(completedScheduledWorkoutIds: completedIds);
  }
}
