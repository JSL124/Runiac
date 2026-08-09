import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/you/presentation/adapters/generated_plan_you_display_adapter.dart';
import 'package:runiac_app/features/you/presentation/data/weekly_workout_demo_snapshots.dart';
import 'package:runiac_app/features/you/presentation/data/you_overview_demo_snapshots.dart';
import 'package:runiac_app/features/you/presentation/goal_plan_detail_screen.dart';
import 'package:runiac_app/features/you/presentation/weekly_workout_detail_screen.dart';
import 'package:runiac_app/features/you/presentation/widgets/weekly_plan_day_row.dart';
import 'package:runiac_app/features/you/presentation/widgets/you_plans_surface.dart';

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

BeginnerAdaptivePlanSnapshot _safetyReadinessPlanWithStaleWorkoutRows() {
  final basePlan = _tenKPerformancePlan();
  return BeginnerAdaptivePlanSnapshot(
    id: basePlan.id,
    title: 'Safety Readiness Plan',
    subtitle: basePlan.subtitle,
    planKind: basePlan.planKind,
    sourceLabel: basePlan.sourceLabel,
    durationWeeks: 0,
    safetyBand: basePlan.safetyBand,
    templateKind: basePlan.templateKind,
    family: basePlan.family,
    familyCategory: basePlan.familyCategory,
    familyReason: basePlan.familyReason,
    supportStyleLabel: basePlan.supportStyleLabel,
    weeklyFrequencyLabel: 'No running workouts',
    preferredScheduleLabel: 'No workout schedule',
    sessionDurationLabel: 'No duration target',
    safetyNote: basePlan.safetyNote,
    weeks: basePlan.weeks,
    clientDisplayStatus:
        BeginnerAdaptivePlanClientDisplayStatus.safetyReadiness,
  );
}

DateTime _weekdayDate(int weekday) {
  return DateTime(2026, 6, 21 + weekday);
}

Future<void> _pumpGeneratedPlans(
  WidgetTester tester, {
  required DateTime currentDate,
}) async {
  final generatedPlan = generatedYouPlanDisplayFromSnapshot(
    _tenKPerformancePlan(),
    currentDate: currentDate,
  );
  await tester.pumpWidget(
    MaterialApp(home: _GeneratedPlansHarness(generatedPlan: generatedPlan!)),
  );
}

Future<void> _openWorkoutDetail(WidgetTester tester, String rowText) async {
  await tester.ensureVisible(find.text(rowText));
  await tester.tap(find.text(rowText));
  await tester.pumpAndSettle();
}

Future<void> _selectOneMinuteLaterFromWheel(WidgetTester tester) async {
  expect(
    find.byKey(const ValueKey('edit_schedule_time_hour_picker')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('edit_schedule_time_minute_picker')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('edit_schedule_time_period_picker')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('edit_schedule_time_option_0645')),
    findsNothing,
  );

  await tester.timedDrag(
    find.byKey(const ValueKey('edit_schedule_time_minute_picker')),
    const Offset(0, -38),
    const Duration(milliseconds: 500),
  );
  await tester.pumpAndSettle();
  await tester.tapAt(const Offset(20, 20));
  await tester.pumpAndSettle();
}

bool _rowWithTextHasColor(
  WidgetTester tester,
  String rowText,
  Color expectedColor,
) {
  final rowFinder = find.ancestor(
    of: find.text(rowText),
    matching: find.byType(Container),
  );

  for (final container in tester.widgetList<Container>(rowFinder)) {
    final decoration = container.decoration;
    if (decoration is BoxDecoration && decoration.color == expectedColor) {
      return true;
    }
  }

  return false;
}

class _GeneratedPlansHarness extends StatefulWidget {
  const _GeneratedPlansHarness({
    required this.generatedPlan,
    this.safetyReadinessPlan,
  });

  final GeneratedYouPlanDisplay? generatedPlan;
  final SafetyReadinessYouPlanDisplay? safetyReadinessPlan;

  @override
  State<_GeneratedPlansHarness> createState() => _GeneratedPlansHarnessState();
}

class _GeneratedPlansHarnessState extends State<_GeneratedPlansHarness> {
  WeeklyWorkoutDetailSnapshot? _detail;
  GeneratedYouPlanDisplay? _generatedPlan;
  var _goalPlanDetailVisible = false;

  @override
  void initState() {
    super.initState();
    _generatedPlan = widget.generatedPlan;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (detail != null) {
      return WeeklyWorkoutDetailScreen(
        snapshot: detail,
        onBack: () => setState(() => _detail = null),
        enableForegroundGps: false,
        showEditScheduleAction: detail.canEditSchedule,
        onScheduleChanged: (selection) {
          setState(() {
            _generatedPlan = _generatedPlan?.rescheduleWorkout(
              detail,
              selection,
            );
            _detail = selection.updatedDetail(detail);
          });
        },
      );
    }

    if (_goalPlanDetailVisible) {
      return GoalPlanDetailScreen(
        snapshot: generatedGoalPlanDisplayFromPlan(_generatedPlan)!,
        onWorkoutSelected: (snapshot) => setState(() => _detail = snapshot),
        onBack: () => setState(() => _goalPlanDetailVisible = false),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        child: YouPlansSurface(
          generatedPlan: _generatedPlan,
          safetyReadinessPlan: widget.safetyReadinessPlan,
          onViewGoalPlan: () => setState(() => _goalPlanDetailVisible = true),
          onViewWorkout: (snapshot) => setState(() => _detail = snapshot),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('safety readiness does not create planned run context', (
    tester,
  ) async {
    // Given: a Safety Readiness display state must win over any stale
    // generated workout rows carried in session-local display data.
    final safetySnapshot = _safetyReadinessPlanWithStaleWorkoutRows();

    // When: the normal generated weekly-plan adapter sees that display state.
    final generatedPlan = generatedYouPlanDisplayFromSnapshot(
      safetySnapshot,
      currentDate: _weekdayDate(DateTime.monday),
    );
    final safetyPlan = safetyReadinessYouPlanDisplayFromSnapshot(
      safetySnapshot,
    );

    // Then: it cannot create a workout detail, Start CTA, or planned context.
    expect(generatedPlan, isNull);
    expect(safetyPlan, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        home: _GeneratedPlansHarness(
          generatedPlan: generatedPlan,
          safetyReadinessPlan: safetyPlan,
        ),
      ),
    );

    expect(find.text('Safety Readiness Plan'), findsOneWidget);
    expect(find.text('25 min Comfortable Run'), findsNothing);
    expect(find.text('Workout detail'), findsNothing);
    expect(find.text('Start this run'), findsNothing);
    expect(find.text('CONTROLLED STEADY RUN'), findsNothing);
  });

  testWidgets('today generated running row is orange and shows Start only', (
    tester,
  ) async {
    // Given: Tuesday is the injected current day for the generated plan.
    await _pumpGeneratedPlans(
      tester,
      currentDate: _weekdayDate(DateTime.tuesday),
    );

    // Then: today's generated running row is visually highlighted.
    expect(
      _rowWithTextHasColor(
        tester,
        '25 min Controlled Steady Run',
        RuniacColors.accentOrange.withValues(alpha: 0.06),
      ),
      isTrue,
    );
    expect(find.text('Upcoming · 7:30 AM'), findsWidgets);

    // When: the matching generated running row is opened.
    await _openWorkoutDetail(tester, '25 min Controlled Steady Run');

    // Then: today's generated detail can start, but cannot edit schedule.
    expect(find.text('Workout detail'), findsOneWidget);
    expect(find.text('Tue · Controlled Steady Run'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Start this run'), findsOneWidget);
    expect(find.byTooltip('Edit schedule'), findsNothing);
  });

  testWidgets(
    'future generated running row opens with Edit but without Start',
    (tester) async {
      // Given: Tuesday is today and Thursday is a future generated workout.
      await _pumpGeneratedPlans(
        tester,
        currentDate: _weekdayDate(DateTime.tuesday),
      );

      // Then: the future running row keeps the original blue-row treatment
      // while still exposing the planned-time subtitle under the name.
      expect(
        _rowWithTextHasColor(
          tester,
          '20 min Recovery Run',
          RuniacColors.primaryBlue.withValues(alpha: 0.06),
        ),
        isTrue,
      );
      expect(find.text('Upcoming · 7:30 AM'), findsWidgets);

      // When: a future generated running row is opened.
      await _openWorkoutDetail(tester, '20 min Recovery Run');

      // Then: the future detail can be rescheduled, but cannot start today.
      expect(find.text('Workout detail'), findsOneWidget);
      expect(find.text('Thu · Recovery Run'), findsOneWidget);
      expect(find.byTooltip('Edit schedule'), findsOneWidget);
      expect(find.text('Edit schedule'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Start this run'), findsNothing);
    },
  );

  testWidgets('Workout detail edit schedule saves local schedule', (
    tester,
  ) async {
    // Given: Tuesday is today and Thursday is a future generated workout.
    await _pumpGeneratedPlans(
      tester,
      currentDate: _weekdayDate(DateTime.tuesday),
    );
    await _openWorkoutDetail(tester, '20 min Recovery Run');

    // When: the future workout is moved to an open Friday time.
    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();
    expect(find.text('New schedule'), findsOneWidget);
    expect(find.text('Select a day and time'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('edit_schedule_day_Fri')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit_schedule_time_selector')));
    await tester.pumpAndSettle();
    expect(find.text('Select time'), findsWidgets);
    expect(find.text('Use 06:45 AM'), findsNothing);
    await _selectOneMinuteLaterFromWheel(tester);
    expect(find.text('Fri · 7:01 PM'), findsOneWidget);

    final saveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save New Schedule'),
    );
    expect(saveButton.onPressed, isNotNull);
    await tester.tap(find.text('Save New Schedule'));
    await tester.pumpAndSettle();

    // Then: the sheet closes and the reopened weekly plan reflects the local move.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Thu · Recovery Run'), findsNothing);
    await tester.tap(find.byTooltip('Back to Plans'));
    await tester.pumpAndSettle();
    expect(find.text('20 min Recovery Run'), findsOneWidget);
    expect(find.text('Upcoming · 7:01 PM'), findsOneWidget);
    await _openWorkoutDetail(tester, '20 min Recovery Run');
    expect(find.text('Fri · Recovery Run'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Fri · 7:01 PM'), findsOneWidget);
  });

  testWidgets('Workout detail edit schedule updates goal plan surface', (
    tester,
  ) async {
    // Given: the workout detail is opened from the full generated plan view.
    await _pumpGeneratedPlans(
      tester,
      currentDate: _weekdayDate(DateTime.tuesday),
    );
    await tester.tap(find.text('10K Performance Build'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('goal_plan_detail_week_toggle_Week 1')),
    );
    await tester.pumpAndSettle();
    await _openWorkoutDetail(tester, '20 min Recovery Run');

    // When: the future workout is moved to an open Friday time.
    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit_schedule_day_Fri')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit_schedule_time_selector')));
    await tester.pumpAndSettle();
    await _selectOneMinuteLaterFromWheel(tester);
    await tester.tap(find.text('Save New Schedule'));
    await tester.pumpAndSettle();

    // Then: both the detail and the plan surface use the edited local plan.
    expect(find.text('Fri · Recovery Run'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10K Performance Build'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('goal_plan_detail_week_toggle_Week 1')),
    );
    await tester.pumpAndSettle();
    final thursdayRow = find.byKey(
      const ValueKey('goal_plan_detail_day_Week 1_Thursday'),
    );
    final fridayRow = find.byKey(
      const ValueKey('goal_plan_detail_day_Week 1_Friday'),
    );
    expect(
      find.descendant(
        of: thursdayRow,
        matching: find.text('20 min Recovery Run'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: fridayRow,
        matching: find.text('20 min Recovery Run'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fridayRow, matching: find.text('Upcoming · 7:01 PM')),
      findsOneWidget,
    );
  });

  testWidgets('Workout detail edit schedule blocks occupied days', (
    tester,
  ) async {
    // Given: Tuesday is today, with generated workouts already on Mon/Tue/Thu.
    await _pumpGeneratedPlans(
      tester,
      currentDate: _weekdayDate(DateTime.tuesday),
    );
    await _openWorkoutDetail(tester, '20 min Recovery Run');

    // When: the edit sheet opens.
    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();

    // Then: suggested times are gone and occupied days cannot become targets.
    for (final text in ['07:00 AM', '08:00 AM', '06:30 PM', '07:30 PM']) {
      expect(find.text(text), findsNothing);
    }
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('edit_schedule_day_Mon')),
          )
          .properties
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('edit_schedule_day_Mon')));
    await tester.pumpAndSettle();
    expect(find.text('Mon · 7:30 AM'), findsNothing);

    final blockedSaveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save New Schedule'),
    );
    expect(blockedSaveButton.onPressed, isNull);

    // And: choosing an open day plus custom time enables save.
    await tester.tap(find.byKey(const ValueKey('edit_schedule_day_Fri')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit_schedule_time_selector')));
    await tester.pumpAndSettle();
    expect(find.text('Use 06:45 AM'), findsNothing);
    await _selectOneMinuteLaterFromWheel(tester);
    final enabledSaveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save New Schedule'),
    );
    expect(enabledSaveButton.onPressed, isNotNull);
  });

  testWidgets('past generated running row opens without Edit or Start', (
    tester,
  ) async {
    // Given: Thursday is today and Monday is a past generated workout.
    await _pumpGeneratedPlans(
      tester,
      currentDate: _weekdayDate(DateTime.thursday),
    );

    expect(find.text('Missed'), findsWidgets);

    // When: a past generated running row is opened.
    await _openWorkoutDetail(tester, '25 min Comfortable Run');

    // Then: the past detail remains readable, but cannot be rescheduled or
    // started after its scheduled day.
    expect(find.text('Workout detail'), findsOneWidget);
    expect(find.text('Mon · Comfortable Run'), findsOneWidget);
    expect(find.byTooltip('Edit schedule'), findsNothing);
    expect(find.text('Edit schedule'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Start this run'), findsNothing);
  });

  testWidgets('rest generated row remains non-tappable', (tester) async {
    // Given: a generated weekly plan includes rest rows.
    await _pumpGeneratedPlans(
      tester,
      currentDate: _weekdayDate(DateTime.tuesday),
    );

    // When: a rest row is tapped.
    expect(find.text('Rest Day'), findsNWidgets(3));
    expect(find.text('Rest'), findsNothing);
    expect(find.text('Recovery day'), findsNothing);
    await tester.ensureVisible(find.text('Rest Day').first);
    await tester.tap(find.text('Rest Day').first);
    await tester.pumpAndSettle();

    // Then: no detail, Start CTA, or edit action appears.
    expect(find.text('Workout detail'), findsNothing);
    expect(find.text('Start this run'), findsNothing);
    expect(find.byTooltip('Edit schedule'), findsNothing);
  });

  testWidgets('today rest generated row uses orange row treatment', (
    tester,
  ) async {
    // Given: Sunday is the injected current day and the generated plan has a
    // rest day on Sunday.
    await _pumpGeneratedPlans(
      tester,
      currentDate: _weekdayDate(DateTime.sunday),
    );

    // Then: the rest row receives today's orange row treatment without
    // becoming tappable or opening workout detail.
    expect(find.text('Rest Day'), findsNWidgets(3));
    expect(
      _rowWithTextHasColor(
        tester,
        'Rest Day',
        RuniacColors.accentOrange.withValues(alpha: 0.06),
      ),
      isTrue,
    );

    await tester.ensureVisible(find.text('Rest Day').last);
    await tester.tap(find.text('Rest Day').last);
    await tester.pumpAndSettle();

    expect(find.text('Workout detail'), findsNothing);
    expect(find.text('Start this run'), findsNothing);
    expect(find.byTooltip('Edit schedule'), findsNothing);
  });

  testWidgets('today Start opens Run launch with planned workout context', (
    tester,
  ) async {
    // Given: the user is viewing today's generated workout detail.
    await _pumpGeneratedPlans(
      tester,
      currentDate: _weekdayDate(DateTime.tuesday),
    );
    await _openWorkoutDetail(tester, '25 min Controlled Steady Run');
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    // When: the planned Start CTA is pressed.
    await tester.tap(find.text('Start this run'));
    await tester.pumpAndSettle();

    // Then: Run launch opens with planned context and progress is unchanged.
    expect(find.text('CONTROLLED STEADY RUN'), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget);
    expect(find.text('controlled steady run'), findsOneWidget);
    expect(find.textContaining('no distance target'), findsOneWidget);
    expect(find.text('Start run'), findsOneWidget);
    expect(find.text('4.5'), findsNothing);
    expect(find.text('km easy run'), findsNothing);
    expect(find.text('0 of 4 done'), findsNothing);
    expect(find.textContaining('completed', findRichText: true), findsNothing);
  });

  testWidgets('generated plan card shows active week position', (tester) async {
    // Given: the generated plan starts two weeks before the injected date.
    final plan = _tenKPerformancePlan().withStartsOnDate(
      generatedPlanDateLabel(DateTime(2026, 6, 8)),
    );
    final display = generatedYouPlanDisplayFromSnapshot(
      plan,
      currentDate: DateTime(2026, 6, 23),
    );

    // When: the generated weekly card is rendered.
    await tester.pumpWidget(
      MaterialApp(home: _GeneratedPlansHarness(generatedPlan: display!)),
    );

    // Then: the header reports the active week position, not workout count.
    expect(find.text('Week 3 of ${plan.weeks.length}'), findsOneWidget);
    expect(find.textContaining(' done'), findsNothing);
  });

  testWidgets('generated planned context carries backend plan identifiers', (
    tester,
  ) async {
    // Given: Tuesday is today's generated workout in week 1.
    final plan = _tenKPerformancePlan();
    final detail = todayGeneratedWorkoutDetailFromSnapshot(
      plan,
      currentDate: _weekdayDate(DateTime.tuesday),
    );

    // Then: the planned run context can identify the backend plan row.
    final plannedRunContext = detail?.plannedRunContext;
    expect(plannedRunContext, isNotNull);
    expect(plannedRunContext!.planEnrollmentId, plan.id);
    expect(
      plannedRunContext.scheduledWorkoutId,
      'week-1-tue-controlled-steady-run',
    );
  });

  testWidgets('backend plan progress marks generated weekly row completed', (
    tester,
  ) async {
    // Given: the backend has accepted today's generated scheduled workout.
    final plan = _tenKPerformancePlan();
    final display = generatedYouPlanDisplayFromSnapshot(
      plan,
      currentDate: _weekdayDate(DateTime.tuesday),
      planProgress: GeneratedPlanProgressDisplay(
        completedScheduledWorkoutIds: const [
          'week-1-tue-controlled-steady-run',
        ],
      ),
    );

    // When: the generated weekly card is rendered.
    await tester.pumpWidget(
      MaterialApp(home: _GeneratedPlansHarness(generatedPlan: display!)),
    );

    // Then: only the matching planned workout row is marked complete.
    expect(find.text('25 min Controlled Steady Run'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    final checkIcon = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    expect(checkIcon.color, RuniacColors.white);
  });

  testWidgets(
    'generated plan progress uses completed non-rest workout denominator',
    (tester) async {
      // Given: one scheduled generated workout is complete and rest/unknown
      // backend ids are also present in the client-side read model.
      final plan = _tenKPerformancePlan();
      final display = generatedYouPlanDisplayFromSnapshot(
        plan,
        currentDate: _weekdayDate(DateTime.tuesday),
        planProgress: GeneratedPlanProgressDisplay(
          completedScheduledWorkoutIds: const [
            'week-1-tue-controlled-steady-run',
            'week-1-sun-rest-day',
            'unknown-scheduled-workout',
          ],
        ),
      );

      // Then: progress is based only on generated plan running sessions.
      expect(display, isNotNull);
      expect(display!.progressLabel, 'Week 1 of ${plan.weeks.length}');
      expect(display.progressValue, 0.25);
    },
  );

  testWidgets(
    'generated plan progress ignores duplicate ids and blocked plans',
    (tester) async {
      // Given: duplicate completed ids arrive from session history.
      final plan = _tenKPerformancePlan();
      final display = generatedYouPlanDisplayFromSnapshot(
        plan,
        currentDate: _weekdayDate(DateTime.tuesday),
        planProgress: GeneratedPlanProgressDisplay(
          completedScheduledWorkoutIds: const [
            'week-1-tue-controlled-steady-run',
            'week-1-tue-controlled-steady-run',
          ],
        ),
      );

      // Then: duplicate ids do not inflate the generated-plan progress.
      expect(display, isNotNull);
      expect(display!.progressLabel, 'Week 1 of ${plan.weeks.length}');
      expect(display.progressValue, 0.25);

      // And: safety-readiness plans still never expose generated progress.
      final blockedDisplay = generatedYouPlanDisplayFromSnapshot(
        _safetyReadinessPlanWithStaleWorkoutRows(),
        currentDate: _weekdayDate(DateTime.tuesday),
        planProgress: GeneratedPlanProgressDisplay(
          completedScheduledWorkoutIds: const [
            'week-1-mon-comfortable-run',
            'week-1-tue-controlled-steady-run',
            'week-1-thu-recovery-run',
            'week-1-sat-recovery-run',
          ],
        ),
      );
      expect(blockedDisplay, isNull);
    },
  );

  testWidgets('normal Run tab launch keeps static fallback context', (
    tester,
  ) async {
    // Given: the app opens without a planned workout launch context.
    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );

    // When: the normal Run tab is opened.
    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    // Then: the existing static Run launch fallback is unchanged.
    expect(find.text('TODAY\'S PLAN'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('km easy run'), findsOneWidget);
    expect(find.text('Start run'), findsOneWidget);
    expect(find.text('CONTROLLED STEADY RUN'), findsNothing);
  });

  testWidgets('Run tab uses today generated planned workout context', (
    tester,
  ) async {
    final generatedPlanStore = CurrentSessionGeneratedPlanStore()
      ..setActivePlan(_tenKPerformancePlan());
    addTearDown(generatedPlanStore.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        currentSessionGeneratedPlanStore: generatedPlanStore,
        youProgressToday: _weekdayDate(DateTime.tuesday),
      ),
    );

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    expect(find.text('CONTROLLED STEADY RUN'), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget);
    expect(find.text('controlled steady run'), findsOneWidget);
    expect(find.textContaining('no distance target'), findsOneWidget);
    expect(find.text('4.5'), findsNothing);
    expect(find.text('km easy run'), findsNothing);
  });

  testWidgets('Run tab shows rest day plan instead of fallback', (
    tester,
  ) async {
    final generatedPlanStore = CurrentSessionGeneratedPlanStore()
      ..setActivePlan(_tenKPerformancePlan());
    addTearDown(generatedPlanStore.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        currentSessionGeneratedPlanStore: generatedPlanStore,
        youProgressToday: _weekdayDate(DateTime.sunday),
      ),
    );

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    expect(find.text('TODAY\'S PLAN'), findsOneWidget);
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Recovery today · no run target'), findsOneWidget);
    expect(
      find.text('Optional easy run only if you feel fresh'),
      findsOneWidget,
    );
    expect(find.text('4.5'), findsNothing);
    expect(find.text('km easy run'), findsNothing);
  });

  testWidgets('completed today row uses blue circle with white check', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyPlanDayRow(
            const YouPlanScheduleRow(
              'Tue',
              '25 min Controlled Steady Run',
              'Completed',
              Icons.check_circle,
              active: true,
              weekdayIndex: DateTime.tuesday,
              isToday: true,
              isRunningSession: true,
            ),
            showDivider: false,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(
      _rowWithTextHasColor(
        tester,
        '25 min Controlled Steady Run',
        RuniacColors.accentOrange.withValues(alpha: 0.06),
      ),
      isTrue,
    );
    final checkIconFinder = find.byIcon(Icons.check_rounded);
    final checkIcon = tester.widget<Icon>(checkIconFinder);
    expect(checkIcon.color, RuniacColors.white);
    final checkNode = tester
        .widgetList<Container>(
          find.ancestor(of: checkIconFinder, matching: find.byType(Container)),
        )
        .firstWhere((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.color == RuniacColors.primaryBlue;
        });
    expect(
      (checkNode.decoration! as BoxDecoration).color,
      RuniacColors.primaryBlue,
    );
  });
}
