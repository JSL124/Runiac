import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/you/presentation/adapters/generated_plan_you_display_adapter.dart';
import 'package:runiac_app/features/you/presentation/data/goal_plan_demo_snapshots.dart';
import 'package:runiac_app/features/you/presentation/data/weekly_workout_demo_snapshots.dart';

import 'support/plan_family_test_drafts.dart';

Future<void> _openYouPlansTab(
  WidgetTester tester,
  CurrentSessionGeneratedPlanStore generatedPlanStore, {
  RuniacAuthRepository? authRepository,
  GeneratedPlanPersistenceRepository? generatedPlanPersistenceRepository,
  DateTime? currentDate,
}) async {
  await tester.pumpWidget(
    RuniacApp(
      showSplash: false,
      enableForegroundGps: false,
      authRepository: authRepository ?? const NonSignedInAuthRepository(),
      currentSessionGeneratedPlanStore: generatedPlanStore,
      generatedPlanPersistenceRepository:
          generatedPlanPersistenceRepository ??
          const NoopGeneratedPlanPersistenceRepository(),
      youProgressToday: currentDate,
    ),
  );
  await tester.tap(find.byTooltip('You'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Plans'));
  await tester.pumpAndSettle();
}

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

BeginnerAdaptivePlanSnapshot _sundayStartedTenKPerformancePlan() {
  return _tenKPerformancePlan().withStartsOnDate('2026-07-05');
}

BeginnerAdaptivePlanSnapshot _safetyReadinessPlan() {
  return const BeginnerAdaptivePlanGenerator().generate(
    planFamilyStarterDraft(health: OnboardingHealthComfort.heart),
  );
}

void main() {
  testWidgets('You shows safety readiness plan without workout detail', (
    WidgetTester tester,
  ) async {
    final safetyPlan = _safetyReadinessPlan();
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    expect(generatedPlanStore.setActivePlan(safetyPlan), isTrue);

    final generatedDisplay = generatedYouPlanDisplayFromSnapshot(safetyPlan);
    final safetyDisplay = safetyReadinessYouPlanDisplayFromSnapshot(safetyPlan);

    expect(generatedDisplay, isNull);
    expect(safetyDisplay, isNotNull);
    expect(safetyDisplay!.title, 'Safety Readiness Plan');
    expect(safetyDisplay.readinessRows, hasLength(4));
    expect(
      safetyDisplay.readinessRows.map((row) => row.title),
      containsAll(const [
        'Review answers',
        'Update answers',
        'Read non-prescriptive safety information',
        'Seek qualified professional guidance',
      ]),
    );

    await _openYouPlansTab(tester, generatedPlanStore);

    expect(find.text('Current Goal'), findsNothing);
    expect(find.text('Safety Readiness Plan'), findsOneWidget);
    expect(find.text('Read-only safety display'), findsOneWidget);
    expect(find.text('Review answers'), findsOneWidget);
    expect(find.text('Update answers'), findsOneWidget);
    expect(
      find.text('Read non-prescriptive safety information'),
      findsOneWidget,
    );
    expect(find.text('Seek qualified professional guidance'), findsOneWidget);
    expect(find.text('Start this run'), findsNothing);
    expect(find.text('Upcoming · 7:30 AM'), findsNothing);
    expect(find.text('Rest Day'), findsNothing);
    expect(find.textContaining(' done'), findsNothing);
    expect(
      find.byKey(const ValueKey('weekly_workout_detail_chevron')),
      findsNothing,
    );

    await tester.tap(find.text('Review answers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update answers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read non-prescriptive safety information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seek qualified professional guidance'));
    await tester.pumpAndSettle();

    expect(find.text('Workout detail'), findsNothing);
    expect(find.text('Safety Readiness Plan'), findsOneWidget);
  });

  testWidgets(
    'You Plans shows generated onboarding plan before static fallback',
    (WidgetTester tester) async {
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final plan = _tenKPerformancePlan();
      expect(generatedPlanStore.setActivePlan(plan), isTrue);

      await _openYouPlansTab(
        tester,
        generatedPlanStore,
        currentDate: DateTime(2026, 7, 6),
      );

      expect(find.text('Current Goal'), findsNothing);
      expect(find.text('View Goal Plan'), findsNothing);
      expect(find.text('10K Performance Build'), findsOneWidget);
      expect(
        find.text(
          '8-week structured plan with 4 morning sessions for your outdoor '
          'park routine, focused on base-building before longer goals.',
        ),
        findsOneWidget,
      );
      expect(find.text('Week 1 of ${plan.weeks.length}'), findsOneWidget);
      expect(find.textContaining(' done'), findsNothing);
      expect(find.text('2 of 3 done'), findsNothing);
      expect(find.text('Week 3 of 8'), findsNothing);
      expect(find.text('43% completed'), findsNothing);
      expect(find.text('15 min walk-run'), findsNothing);
      expect(find.text('Upcoming · 7:30 AM'), findsWidgets);

      for (final text in [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
        '25 min Comfortable Run',
        '25 min Controlled Steady Run',
        '30 min Longer Easy Run',
        '20 min Recovery Run',
      ]) {
        expect(find.text(text), findsWidgets);
      }
      expect(find.text('Rest Day'), findsNWidgets(3));
      expect(find.text('Rest'), findsNothing);
      expect(find.text('Recovery day'), findsNothing);
    },
  );

  testWidgets(
    'generated plan detail shows full onboarding-generated plan content',
    (WidgetTester tester) async {
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final plan = _tenKPerformancePlan();
      expect(generatedPlanStore.setActivePlan(plan), isTrue);

      final detailDisplay = generatedGoalPlanDisplayFromSnapshot(plan);
      expect(detailDisplay, isNotNull);
      expect(detailDisplay!.title, plan.title);
      expect(detailDisplay.planName, plan.title);
      expect(detailDisplay.showProgress, isFalse);
      expect(detailDisplay.weeks, hasLength(plan.weeks.length));
      expect(detailDisplay.weeks.first.dailyPlan, hasLength(7));
      expect(
        detailDisplay.weeks.first.dailyPlan.where(
          (row) => row.workoutDetail != null,
        ),
        hasLength(plan.weeks.first.workouts.length),
      );

      await _openYouPlansTab(tester, generatedPlanStore);

      await tester.tap(find.text(plan.title));
      await tester.pumpAndSettle();

      expect(find.text(plan.title), findsWidgets);
      expect(
        find.text('${plan.durationWeeks} weeks · ${plan.weeklyFrequencyLabel}'),
        findsOneWidget,
      );
      expect(find.text('Generated onboarding plan'), findsOneWidget);
      expect(find.text('Preferred days'), findsOneWidget);
      expect(find.text(plan.preferredScheduleLabel), findsOneWidget);
      expect(find.text('10K Goal Plan'), findsNothing);
      expect(find.text('10K Preparation'), findsNothing);
      expect(find.text('43% completed'), findsNothing);
      expect(find.text('43%'), findsNothing);
      expect(find.text('Base Endurance'), findsNothing);

      for (final week in plan.weeks) {
        expect(
          find.byKey(
            ValueKey('goal_plan_detail_week_toggle_Week ${week.weekNumber}'),
          ),
          findsOneWidget,
        );
        expect(find.text(week.title), findsWidgets);
      }

      await tester.tap(
        find.byKey(const ValueKey('goal_plan_detail_week_toggle_Week 1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('goal_plan_detail_daily_plan_Week 1')),
        findsOneWidget,
      );
      for (final weekday in const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ]) {
        expect(
          find.byKey(ValueKey('goal_plan_detail_day_Week 1_$weekday')),
          findsOneWidget,
        );
      }

      final firstWorkout = plan.weeks.first.workouts.first;
      expect(find.text(firstWorkout.title), findsOneWidget);
      expect(find.text('${firstWorkout.durationMinutes} min'), findsWidgets);
      expect(find.text('Rest Day'), findsWidgets);
      expect(find.text('Recovery'), findsWidgets);

      await tester.tap(find.text(firstWorkout.title));
      await tester.pumpAndSettle();

      expect(find.text('Workout detail'), findsOneWidget);
      expect(
        find.text('${firstWorkout.dayLabel} · ${firstWorkout.title}'),
        findsOneWidget,
      );
      expect(find.text(plan.title), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Effort'), findsOneWidget);
      expect(find.text('${firstWorkout.durationMinutes} min'), findsWidgets);
      expect(find.text('Source'), findsNothing);
      expect(find.text('Generated'), findsNothing);
      expect(find.text('Suggested pace'), findsNothing);
      expect(find.text('7:30 /km'), findsNothing);
    },
  );

  testWidgets('generated plan rolls to next week on start weekday midnight', (
    WidgetTester tester,
  ) async {
    final plan = _sundayStartedTenKPerformancePlan();
    final saturdayDisplay = generatedYouPlanDisplayFromSnapshot(
      plan,
      currentDate: DateTime(2026, 7, 11, 23, 59),
    );
    final sundayDisplay = generatedYouPlanDisplayFromSnapshot(
      plan,
      currentDate: DateTime(2026, 7, 12),
    );
    final saturdayGoal = generatedGoalPlanDisplayFromSnapshot(
      plan,
      currentDate: DateTime(2026, 7, 11, 23, 59),
    );
    final sundayGoal = generatedGoalPlanDisplayFromSnapshot(
      plan,
      currentDate: DateTime(2026, 7, 12),
      currentWeekDisplay: sundayDisplay,
    );

    expect(saturdayDisplay, isNotNull);
    expect(sundayDisplay, isNotNull);
    expect(
      saturdayDisplay!.scheduleRows
          .where((row) => row.detailSnapshot != null)
          .map((row) => row.detailSnapshot!.dayLabel),
      containsAll([
        for (final workout in plan.weeks.first.workouts)
          '${workout.dayLabel} · ${workout.title}',
      ]),
    );
    expect(
      sundayDisplay!.scheduleRows
          .where((row) => row.detailSnapshot != null)
          .map((row) => row.detailSnapshot!.dayLabel),
      containsAll([
        for (final workout in plan.weeks[1].workouts)
          '${workout.dayLabel} · ${workout.title}',
      ]),
    );
    expect(saturdayGoal!.weeks.first.status, GoalPlanWeekStatus.current);
    expect(sundayGoal!.weeks[1].status, GoalPlanWeekStatus.current);
  });

  // Regression coverage for the week-1-hardcode bug: a past week whose
  // weekday label happens to match today must not act like today, and the
  // plan's real active week must keep its "today" action even when the user
  // has never rescheduled (currentWeekDisplay omitted / null).
  test(
    'stale week matching today is not marked startable once the active week '
    'has advanced',
    () {
      final plan = _tenKPerformancePlan().withStartsOnDate('2026-07-06');
      // 2026-07-13 is the Monday that starts week 2; week 1's own Monday
      // workout shares that weekday label but must no longer act like today.
      final currentDate = DateTime(2026, 7, 13);
      expect(
        activeGeneratedPlanWeekFor(plan, currentDate: currentDate)?.weekNumber,
        2,
      );

      final goalDisplay = generatedGoalPlanDisplayFromSnapshot(
        plan,
        currentDate: currentDate,
      );

      expect(goalDisplay, isNotNull);
      final week1Monday = goalDisplay!.weeks[0].dailyPlan.firstWhere(
        (row) => row.weekday == 'Monday',
      );

      expect(week1Monday.workoutDetail, isNotNull);
      expect(week1Monday.workoutDetail!.startActionLabel, isNull);
      expect(week1Monday.workoutDetail!.plannedRunContext, isNull);
    },
  );

  test(
    'active week today row stays startable when no reschedule has happened',
    () {
      final plan = _tenKPerformancePlan().withStartsOnDate('2026-07-06');
      final currentDate = DateTime(2026, 7, 13);

      // currentWeekDisplay is intentionally omitted (null): this is the
      // never-rescheduled case, exactly what You Plans passes before the
      // user edits a schedule.
      final goalDisplay = generatedGoalPlanDisplayFromSnapshot(
        plan,
        currentDate: currentDate,
      );

      expect(goalDisplay, isNotNull);
      final week2Monday = goalDisplay!.weeks[1].dailyPlan.firstWhere(
        (row) => row.weekday == 'Monday',
      );

      expect(week2Monday.workoutDetail, isNotNull);
      expect(week2Monday.workoutDetail!.startActionLabel, 'Start this run');
      expect(week2Monday.workoutDetail!.plannedRunContext, isNotNull);
    },
  );

  test(
    'startable active-week row schedules progress against the active week, '
    'not week 1',
    () {
      final plan = _tenKPerformancePlan().withStartsOnDate('2026-07-06');
      final currentDate = DateTime(2026, 7, 13);

      final goalDisplay = generatedGoalPlanDisplayFromSnapshot(
        plan,
        currentDate: currentDate,
      );

      final week2Monday = goalDisplay!.weeks[1].dailyPlan.firstWhere(
        (row) => row.weekday == 'Monday',
      );
      final scheduledWorkoutId =
          week2Monday.workoutDetail!.plannedRunContext!.scheduledWorkoutId;

      expect(scheduledWorkoutId, isNotNull);
      expect(scheduledWorkoutId, startsWith('week-2-mon-'));
      expect(scheduledWorkoutId, isNot(startsWith('week-1-')));
    },
  );

  testWidgets('You Plans shows week 2 on the next Monday after plan start', (
    WidgetTester tester,
  ) async {
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    final plan = _tenKPerformancePlan().withStartsOnDate('2026-07-06');
    expect(generatedPlanStore.setActivePlan(plan), isTrue);

    await _openYouPlansTab(
      tester,
      generatedPlanStore,
      currentDate: DateTime(2026, 7, 13),
    );

    expect(find.text('Week 2 of ${plan.weeks.length}'), findsOneWidget);
    expect(find.text('Week 1 of ${plan.weeks.length}'), findsNothing);
    expect(find.text('Week 3 of ${plan.weeks.length}'), findsNothing);
  });

  test('generated plan week and day stay anchored to the creation weekday', () {
    final plan = _sundayStartedTenKPerformancePlan();

    expect(
      activeGeneratedPlanWeekFor(
        plan,
        currentDate: DateTime(2026, 7, 5),
      )?.weekNumber,
      1,
    );
    expect(
      activeGeneratedPlanDayIndexFor(plan, currentDate: DateTime(2026, 7, 5)),
      0,
    );
    expect(
      activeGeneratedPlanWeekFor(
        plan,
        currentDate: DateTime(2026, 7, 11),
      )?.weekNumber,
      1,
    );
    expect(
      activeGeneratedPlanDayIndexFor(plan, currentDate: DateTime(2026, 7, 11)),
      6,
    );
    expect(
      activeGeneratedPlanWeekFor(
        plan,
        currentDate: DateTime(2026, 7, 12),
      )?.weekNumber,
      2,
    );
    expect(
      activeGeneratedPlanDayIndexFor(plan, currentDate: DateTime(2026, 7, 12)),
      0,
    );
  });

  test(
    'Sunday-created generated plan advances every Sunday through week 8',
    () {
      final plan = _sundayStartedTenKPerformancePlan();
      final startSunday = DateTime(2026, 7, 5);

      for (var week = 1; week <= 8; week += 1) {
        final date = startSunday.add(Duration(days: 7 * (week - 1)));

        expect(
          activeGeneratedPlanWeekFor(plan, currentDate: date)?.weekNumber,
          week,
        );
        expect(activeGeneratedPlanDayIndexFor(plan, currentDate: date), 0);
      }
    },
  );

  testWidgets('You Plans advances every week through week 8', (
    WidgetTester tester,
  ) async {
    final startMonday = DateTime(2026, 7, 6);

    for (var week = 1; week <= 8; week += 1) {
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final plan = _tenKPerformancePlan().withStartsOnDate('2026-07-06');
      expect(generatedPlanStore.setActivePlan(plan), isTrue);
      addTearDown(generatedPlanStore.dispose);

      await _openYouPlansTab(
        tester,
        generatedPlanStore,
        currentDate: startMonday.add(Duration(days: 7 * (week - 1))),
      );

      expect(find.text('Week $week of ${plan.weeks.length}'), findsOneWidget);
      for (var otherWeek = 1; otherWeek <= 8; otherWeek += 1) {
        if (otherWeek == week) {
          continue;
        }
        expect(
          find.text('Week $otherWeek of ${plan.weeks.length}'),
          findsNothing,
          reason: 'visible week should be $week',
        );
      }
    }
  });

  testWidgets('generated weekly rest rows do not open workout detail', (
    WidgetTester tester,
  ) async {
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    final plan = _tenKPerformancePlan();
    expect(generatedPlanStore.setActivePlan(plan), isTrue);

    await _openYouPlansTab(tester, generatedPlanStore);

    expect(find.text('Rest Day'), findsNWidgets(3));
    expect(find.text('Rest'), findsNothing);
    expect(find.text('Recovery day'), findsNothing);
    await tester.ensureVisible(find.text('Rest Day').first);
    await tester.tap(find.text('Rest Day').first);
    await tester.pumpAndSettle();

    expect(find.text('Workout detail'), findsNothing);
    expect(find.text('10K Performance Build'), findsOneWidget);
    expect(find.text('Week 1 of ${plan.weeks.length}'), findsOneWidget);
  });

  testWidgets('You Plans keeps static fallback when no generated plan exists', (
    WidgetTester tester,
  ) async {
    await _openYouPlansTab(tester, CurrentSessionGeneratedPlanStore());

    expect(find.text('Current Goal'), findsOneWidget);
    expect(find.text('10K Preparation'), findsOneWidget);
    expect(find.text('2 of 3 done'), findsOneWidget);
    expect(find.text('10K Performance Build'), findsNothing);
    expect(find.text('Recovery day'), findsNothing);
  });

  testWidgets('You Plans shows starter movement plan before static fallback', (
    WidgetTester tester,
  ) async {
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    final starterPlan = const BeginnerAdaptivePlanGenerator().generate(
      planFamilyStarterDraft(availability: OnboardingAvailability.three),
    );
    expect(generatedPlanStore.setActivePlan(starterPlan), isTrue);

    await _openYouPlansTab(tester, generatedPlanStore);

    expect(find.text('Current Goal'), findsNothing);
    expect(find.text('Return to Movement'), findsOneWidget);
    expect(find.text('Week 1 of ${starterPlan.weeks.length}'), findsOneWidget);
    expect(find.textContaining('min Easy Walk'), findsNWidgets(3));
    expect(find.text('10K Base Builder'), findsNothing);
    expect(find.text('15 min walk-run'), findsNothing);
  });

  testWidgets(
    'You Plans shows restricted recovery plan before static fallback',
    (WidgetTester tester) async {
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final recoveryPlan = const BeginnerAdaptivePlanGenerator().generate(
        planFamilyPerformanceDraft(
          goal: OnboardingGoal.tenK,
          health: OnboardingHealthComfort.injury,
          style: OnboardingPlanStyle.performanceFocused,
        ),
      );
      expect(generatedPlanStore.setActivePlan(recoveryPlan), isTrue);

      await _openYouPlansTab(tester, generatedPlanStore);

      expect(find.text('Current Goal'), findsNothing);
      expect(find.text('Return to Movement'), findsOneWidget);
      expect(
        find.text('A gentle restart plan focused on comfort and consistency.'),
        findsOneWidget,
      );
      expect(
        find.text('Week 1 of ${recoveryPlan.weeks.length}'),
        findsOneWidget,
      );
      expect(find.text('20 min Easy Walk'), findsNWidgets(3));
      expect(find.text('10K Performance Build'), findsNothing);
    },
  );

  testWidgets('generated weekly row opens generated workout detail', (
    WidgetTester tester,
  ) async {
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    expect(generatedPlanStore.setActivePlan(_tenKPerformancePlan()), isTrue);

    await _openYouPlansTab(tester, generatedPlanStore);

    await tester.ensureVisible(find.text('25 min Controlled Steady Run'));
    await tester.tap(find.text('25 min Controlled Steady Run'));
    await tester.pumpAndSettle();

    expect(find.text('Workout detail'), findsOneWidget);
    expect(find.text('Tue · Controlled Steady Run'), findsOneWidget);
    expect(find.text('10K Performance Build'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Effort'), findsOneWidget);
    expect(find.text('25 min'), findsWidgets);
    expect(find.text('Source'), findsNothing);
    expect(find.text('Generated'), findsNothing);
    expect(find.text('Suggested pace'), findsNothing);
    expect(find.text('7:30 /km'), findsNothing);
  });

  testWidgets(
    'past incomplete generated workout is marked missed and cannot reschedule',
    (WidgetTester tester) async {
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final plan = _tenKPerformancePlan();
      final currentDate = DateTime(2026, 7, 8);
      expect(generatedPlanStore.setActivePlan(plan), isTrue);

      final display = generatedYouPlanDisplayFromSnapshot(
        plan,
        currentDate: currentDate,
      );
      final missedRows = display!.scheduleRows.where(
        (row) => row.isPast && row.isRunningSession,
      );

      expect(missedRows, isNotEmpty);
      expect(missedRows.every((row) => row.status == 'Missed'), isTrue);
      expect(missedRows.every((row) => !row.canEditSchedule), isTrue);
      expect(
        missedRows.every((row) => !row.detailSnapshot!.canEditSchedule),
        isTrue,
      );
      final missedDetail = missedRows.first.detailSnapshot!;
      const futureSelection = WorkoutScheduleEditSelection(
        weekdayIndex: DateTime.friday,
        dayLabel: 'Fri',
        timeLabel: '7:30 AM',
      );
      expect(
        display.rescheduleWorkout(missedDetail, futureSelection),
        same(display),
      );
      expect(
        rescheduleGeneratedPlanSnapshot(
          plan,
          missedDetail,
          futureSelection,
          currentDate: currentDate,
        ),
        isNull,
      );

      await _openYouPlansTab(
        tester,
        generatedPlanStore,
        currentDate: currentDate,
      );

      final missedRow = missedRows.first;
      expect(find.text('Missed'), findsWidgets);
      expect(
        find.byKey(ValueKey('weekly_plan_missed_${missedRow.weekdayIndex}')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text(missedRow.title));
      await tester.tap(find.text(missedRow.title));
      await tester.pumpAndSettle();

      expect(find.text('Workout detail'), findsOneWidget);
      expect(find.byTooltip('Edit schedule'), findsNothing);
      expect(find.text('Start this run'), findsNothing);
    },
  );

  test('future workout cannot be rescheduled onto a past weekday', () {
    final plan = _tenKPerformancePlan();
    final display = generatedYouPlanDisplayFromSnapshot(
      plan,
      currentDate: DateTime(2026, 7, 8),
    );
    final futureRow = display!.scheduleRows.firstWhere(
      (row) => row.isFuture && row.isRunningSession,
    );

    final updated = display.rescheduleWorkout(
      futureRow.detailSnapshot!,
      const WorkoutScheduleEditSelection(
        weekdayIndex: DateTime.tuesday,
        dayLabel: 'Tue',
        timeLabel: '7:30 AM',
      ),
    );

    expect(identical(updated, display), isTrue);
    expect(
      rescheduleGeneratedPlanSnapshot(
        plan,
        futureRow.detailSnapshot!,
        const WorkoutScheduleEditSelection(
          weekdayIndex: DateTime.tuesday,
          dayLabel: 'Tue',
          timeLabel: '7:30 AM',
        ),
        currentDate: DateTime(2026, 7, 8),
      ),
      isNull,
    );
  });

  testWidgets('generated workout edit schedule persists updated plan', (
    WidgetTester tester,
  ) async {
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    final plan = _tenKPerformancePlan();
    final generatedPlanRepository = _RecordingGeneratedPlanRepository();
    expect(generatedPlanStore.setActivePlan(plan), isTrue);

    await _openYouPlansTab(
      tester,
      generatedPlanStore,
      authRepository: const _SignedInAuthRepository('schedule-user'),
      generatedPlanPersistenceRepository: generatedPlanRepository,
      currentDate: DateTime(2026, 7, 6),
    );

    await tester.ensureVisible(find.text('25 min Controlled Steady Run'));
    await tester.tap(find.text('25 min Controlled Steady Run'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit_schedule_day_Fri')));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('Save New Schedule'));
    await tester.pumpAndSettle();

    expect(generatedPlanRepository.savedUid, 'schedule-user');
    expect(generatedPlanRepository.savedPlan, isNotNull);
    final savedWorkout = generatedPlanRepository.savedPlan!.weeks.first.workouts
        .singleWhere((workout) => workout.title == 'Controlled Steady Run');
    expect(savedWorkout.dayLabel, 'Fri');
    expect(savedWorkout.scheduleTimeLabel, '7:01 PM');
    expect(
      generatedPlanStore.activePlan,
      same(generatedPlanRepository.savedPlan),
    );
  });
}

class NonSignedInAuthRepository implements RuniacAuthRepository {
  const NonSignedInAuthRepository();

  @override
  RuniacAuthUser? get currentUser => null;

  @override
  Stream<RuniacAuthUser?> authStateChanges() => Stream.value(null);

  @override
  Future<RuniacAuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendEmailVerification() {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    throw UnimplementedError();
  }

  @override
  Future<RuniacAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<RuniacAuthUser> signInWithGoogle() {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() {
    throw UnimplementedError();
  }
}

class _SignedInAuthRepository extends NonSignedInAuthRepository {
  const _SignedInAuthRepository(this.uid);

  final String uid;

  @override
  RuniacAuthUser get currentUser =>
      RuniacAuthUser(uid: uid, email: '$uid@example.test', emailVerified: true);

  @override
  Stream<RuniacAuthUser?> authStateChanges() => Stream.value(currentUser);
}

class _RecordingGeneratedPlanRepository
    implements GeneratedPlanPersistenceRepository {
  String? savedUid;
  BeginnerAdaptivePlanSnapshot? savedPlan;

  @override
  Future<BeginnerAdaptivePlanSnapshot?> loadGeneratedPlan({
    required String uid,
  }) async {
    return null;
  }

  @override
  Future<void> saveGeneratedPlan({
    required String uid,
    required BeginnerAdaptivePlanSnapshot plan,
    bool resetCreatedAt = false,
  }) async {
    savedUid = uid;
    savedPlan = plan;
  }
}
