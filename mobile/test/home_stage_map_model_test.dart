import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_background_sequence.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map_model.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/you/presentation/adapters/generated_plan_you_display_adapter.dart';

import 'support/plan_family_test_drafts.dart';

BeginnerAdaptivePlanSnapshot _plan() {
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

String _idFor(BeginnerAdaptivePlanWeek week, BeginnerAdaptiveWorkout workout) {
  return homeStageScheduledWorkoutId(
    weekNumber: week.weekNumber,
    dayLabel: workout.dayLabel,
    title: workout.title,
  );
}

BeginnerAdaptiveWorkoutDetail _detail() {
  return BeginnerAdaptiveWorkoutDetail(
    metrics: const <BeginnerAdaptiveWorkoutMetric>[],
    breakdown: const <BeginnerAdaptiveWorkoutBreakdownStep>[],
    effortGuide: 'Easy effort',
    coachNotes: const <String>[],
  );
}

BeginnerAdaptiveWorkout _workout({
  required String dayLabel,
  required String title,
  BeginnerWorkoutKind kind = BeginnerWorkoutKind.easyRun,
}) {
  return BeginnerAdaptiveWorkout(
    dayLabel: dayLabel,
    title: title,
    durationMinutes: 30,
    kind: kind,
    intensity: BeginnerPlanIntensity.gentle,
    description: 'Description',
    steps: const <String>[],
    supportiveNote: 'You can do this.',
    detail: _detail(),
  );
}

BeginnerAdaptivePlanWeek _manualWeek(
  int weekNumber,
  List<BeginnerAdaptiveWorkout> workouts,
) {
  return BeginnerAdaptivePlanWeek(
    weekNumber: weekNumber,
    title: 'Week $weekNumber',
    focus: 'Focus',
    workouts: workouts,
  );
}

BeginnerAdaptivePlanSnapshot _manualPlan(
  List<BeginnerAdaptivePlanWeek> weeks, {
  String? startsOnDate,
}) {
  return BeginnerAdaptivePlanSnapshot(
    id: 'manual-plan',
    title: 'Manual Plan',
    subtitle: 'Subtitle',
    planKind: BeginnerAdaptivePlanKind.onboardingBased,
    sourceLabel: 'Onboarding based',
    startsOnDate: startsOnDate,
    durationWeeks: weeks.length,
    safetyBand: BeginnerPlanSafetyBand.clear,
    templateKind: BeginnerPlanTemplateKind.standardBeginnerStart,
    family: null,
    familyCategory: null,
    familyReason: 'reason',
    supportStyleLabel: 'Clear weekly plan',
    weeklyFrequencyLabel: '3 sessions / week',
    preferredScheduleLabel: 'Mon · Tue',
    sessionDurationLabel: '30 minutes',
    safetyNote: 'Note',
    weeks: weeks,
  );
}

void main() {
  test('each section has seven evenly spaced connected chevron anchors', () {
    for (var sectionIndex = 0; sectionIndex < 4; sectionIndex++) {
      final anchors = homeStageAnchorsForSection(sectionIndex);
      expect(anchors, hasLength(kHomeStageDaysPerWeek));
      expect(anchors.first.dx, closeTo(0.5, 0.0001));
      expect(anchors.last.dx, closeTo(0.5, 0.0001));
      expect(anchors.last.dy, closeTo(0.19, 0.0001));
      if (sectionIndex == 0) {
        expect(anchors.first.dy, closeTo(0.86, 0.0001));
      } else {
        expect(anchors.first.dy, closeTo(0.97, 0.0001));
      }

      final verticalInterval =
          (anchors.first.dy - anchors.last.dy) / (kHomeStageDaysPerWeek - 1);
      for (var index = 1; index < anchors.length; index++) {
        expect(
          anchors[index - 1].dy - anchors[index].dy,
          closeTo(verticalInterval, 0.0001),
          reason: 'section $sectionIndex vertical interval $index',
        );
      }
      expect(
        anchors[3].dx,
        sectionIndex.isEven ? lessThan(0.5) : greaterThan(0.5),
      );
    }
  });

  test('every section has exactly 7 stones padded with rest', () {
    final plan = _plan();
    final model = buildHomeStageMapModel(
      plan: plan,
      completedScheduledWorkoutIds: const <String>{},
      activeWeekNumber: plan.weeks.first.weekNumber,
      backgroundSequence: homeStageBackgroundSequence(
        planId: plan.id,
        weekCount: plan.weeks.length,
      ),
    );

    expect(model.sections, hasLength(plan.weeks.length));
    for (final section in model.sections) {
      expect(section.stones, hasLength(kHomeStageDaysPerWeek));
    }
  });

  test('run vs rest stones follow the workout kind and padding', () {
    final plan = _plan();
    final model = buildHomeStageMapModel(
      plan: plan,
      completedScheduledWorkoutIds: const <String>{},
      activeWeekNumber: plan.weeks.first.weekNumber,
      backgroundSequence: homeStageBackgroundSequence(
        planId: plan.id,
        weekCount: plan.weeks.length,
      ),
    );

    final week = plan.weeks.first;
    final section = model.sections.first;
    for (var d = 0; d < kHomeStageDaysPerWeek; d++) {
      final stone = section.stones[d];
      if (d < week.workouts.length) {
        final expectedRun = isGeneratedPlanSession(week.workouts[d]);
        expect(
          stone.kind,
          expectedRun ? HomeStageStoneKind.run : HomeStageStoneKind.rest,
        );
      } else {
        expect(stone.kind, HomeStageStoneKind.rest);
      }
    }
  });

  test('completed run stones come only from backend completed ids', () {
    final plan = _plan();
    final week = plan.weeks.first;
    final firstRun = week.workouts.firstWhere(isGeneratedPlanSession);
    final completedId = _idFor(week, firstRun);

    final model = buildHomeStageMapModel(
      plan: plan,
      completedScheduledWorkoutIds: {completedId},
      activeWeekNumber: week.weekNumber,
      backgroundSequence: homeStageBackgroundSequence(
        planId: plan.id,
        weekCount: plan.weeks.length,
      ),
    );

    final completedStone = model.sections.first.stones.firstWhere(
      (stone) => stone.scheduledWorkoutId == completedId,
    );
    expect(completedStone.state, HomeStageStoneState.completed);

    // Today is now the next uncompleted run after the completed one.
    final today = model.todayDayIndex;
    expect(today, isNotNull);
    final todayStone = model.sections.first.stones[today!];
    expect(todayStone.kind, HomeStageStoneKind.run);
    expect(todayStone.state, HomeStageStoneState.current);
    expect(todayStone.dayIndex, greaterThan(completedStone.dayIndex));
  });

  test('current stage is the first uncompleted run of the active week', () {
    final plan = _plan();
    final model = buildHomeStageMapModel(
      plan: plan,
      completedScheduledWorkoutIds: const <String>{},
      activeWeekNumber: plan.weeks.first.weekNumber,
      backgroundSequence: homeStageBackgroundSequence(
        planId: plan.id,
        weekCount: plan.weeks.length,
      ),
    );

    expect(model.currentWeekIndex, 0);
    final firstRunIndex = model.sections.first.stones.indexWhere(
      (stone) => stone.isRun,
    );
    expect(model.todayDayIndex, firstRunIndex);
    expect(model.characterDayIndex, firstRunIndex);
    expect(model.currentStageId, HomeStageMapModel.stageId(0, firstRunIndex));
  });

  test('calendar day marks earlier incomplete run stones as missed', () {
    final plan = _plan();
    final model = buildHomeStageMapModel(
      plan: plan,
      completedScheduledWorkoutIds: const <String>{},
      activeWeekNumber: plan.weeks.first.weekNumber,
      currentWeekdayIndex: DateTime.thursday,
      backgroundSequence: homeStageBackgroundSequence(
        planId: plan.id,
        weekCount: plan.weeks.length,
      ),
    );

    final stones = model.sections.first.stones;
    expect(stones[0].state, HomeStageStoneState.missed);
    expect(stones[1].state, HomeStageStoneState.missed);
    expect(stones[2].state, HomeStageStoneState.missed);
    expect(stones[3].state, HomeStageStoneState.current);
    expect(model.todayDayIndex, DateTime.thursday - 1);
    expect(model.characterDayIndex, DateTime.thursday - 1);
  });

  test('empty-week plan produces no sections', () {
    final plan = _plan();
    final emptyPlan = BeginnerAdaptivePlanSnapshot(
      id: plan.id,
      title: plan.title,
      subtitle: plan.subtitle,
      planKind: plan.planKind,
      sourceLabel: plan.sourceLabel,
      durationWeeks: 0,
      safetyBand: plan.safetyBand,
      templateKind: plan.templateKind,
      family: plan.family,
      familyCategory: plan.familyCategory,
      familyReason: plan.familyReason,
      supportStyleLabel: plan.supportStyleLabel,
      weeklyFrequencyLabel: plan.weeklyFrequencyLabel,
      preferredScheduleLabel: plan.preferredScheduleLabel,
      sessionDurationLabel: plan.sessionDurationLabel,
      safetyNote: plan.safetyNote,
      weeks: const <BeginnerAdaptivePlanWeek>[],
    );

    final model = buildHomeStageMapModel(
      plan: emptyPlan,
      completedScheduledWorkoutIds: const <String>{},
      activeWeekNumber: 1,
      backgroundSequence: const <String>[],
    );
    expect(model.hasStages, isFalse);
    expect(model.currentStageId, isNull);
  });

  test(
    'runs on Tue/Thu/Sat land at weekday slots 1/3/5 with rest elsewhere',
    () {
      final week = _manualWeek(1, [
        _workout(dayLabel: 'Tue', title: 'Tuesday Run'),
        _workout(dayLabel: 'Thu', title: 'Thursday Run'),
        _workout(dayLabel: 'Sat', title: 'Saturday Run'),
      ]);
      final plan = _manualPlan([week]);

      final model = buildHomeStageMapModel(
        plan: plan,
        completedScheduledWorkoutIds: const <String>{},
        activeWeekNumber: 1,
        backgroundSequence: const <String>['bg.webp'],
      );

      final stones = model.sections.single.stones;
      expect(stones, hasLength(kHomeStageDaysPerWeek));
      for (var d = 0; d < kHomeStageDaysPerWeek; d++) {
        final expectRun = d == 1 || d == 3 || d == 5;
        expect(
          stones[d].kind,
          expectRun ? HomeStageStoneKind.run : HomeStageStoneKind.rest,
          reason: 'slot $d',
        );
        expect(
          stones[d].dayLabel,
          kHomeStageWeekdayLabels[d],
          reason: 'slot $d label',
        );
      }
      expect(stones[1].workoutTitle, 'Tuesday Run');
      expect(stones[3].workoutTitle, 'Thursday Run');
      expect(stones[5].workoutTitle, 'Saturday Run');
    },
  );

  test(
    'duplicate weekday labels shift the later workout to the next free slot',
    () {
      final week = _manualWeek(1, [
        _workout(dayLabel: 'Mon', title: 'First Monday Run'),
        _workout(dayLabel: 'Mon', title: 'Second Monday Run'),
      ]);
      final plan = _manualPlan([week]);

      final model = buildHomeStageMapModel(
        plan: plan,
        completedScheduledWorkoutIds: const <String>{},
        activeWeekNumber: 1,
        backgroundSequence: const <String>['bg.webp'],
      );

      final stones = model.sections.single.stones;
      expect(stones[0].kind, HomeStageStoneKind.run);
      expect(stones[0].workoutTitle, 'First Monday Run');
      expect(stones[0].dayLabel, 'Mon');
      // Tuesday's slot was free, so the second Monday workout shifts there.
      expect(stones[1].kind, HomeStageStoneKind.run);
      expect(stones[1].workoutTitle, 'Second Monday Run');
      expect(stones[1].dayLabel, 'Tue');
      for (var d = 2; d < kHomeStageDaysPerWeek; d++) {
        expect(stones[d].kind, HomeStageStoneKind.rest, reason: 'slot $d');
      }
    },
  );

  test('synthetic Day N labels keep positional layout for the whole plan', () {
    final week = _manualWeek(1, [
      _workout(dayLabel: 'Day 1', title: 'Session A'),
      _workout(
        dayLabel: 'Day 2',
        title: 'Session B',
        kind: BeginnerWorkoutKind.restOrMobility,
      ),
      _workout(dayLabel: 'Day 3', title: 'Session C'),
    ]);
    final plan = _manualPlan([week]);

    final model = buildHomeStageMapModel(
      plan: plan,
      completedScheduledWorkoutIds: const <String>{},
      activeWeekNumber: 1,
      backgroundSequence: const <String>['bg.webp'],
    );

    final stones = model.sections.single.stones;
    // Positional: workout index d -> slot d, unaffected by dayLabel value.
    expect(stones[0].kind, HomeStageStoneKind.run);
    expect(stones[0].workoutTitle, 'Session A');
    expect(stones[0].dayLabel, 'Day 1');
    expect(stones[1].kind, HomeStageStoneKind.rest);
    expect(stones[1].dayLabel, isNull);
    expect(stones[2].kind, HomeStageStoneKind.run);
    expect(stones[2].workoutTitle, 'Session C');
    expect(stones[2].dayLabel, 'Day 3');
    for (var d = 3; d < kHomeStageDaysPerWeek; d++) {
      expect(stones[d].kind, HomeStageStoneKind.rest, reason: 'slot $d');
      expect(stones[d].dayLabel, isNull, reason: 'slot $d');
    }
  });

  test('a single non-weekday label anywhere in the plan forces positional '
      'layout for every week', () {
    final weekdayWeek = _manualWeek(1, [
      _workout(dayLabel: 'Mon', title: 'Week 1 Run'),
    ]);
    final syntheticWeek = _manualWeek(2, [
      _workout(dayLabel: 'Day 1', title: 'Week 2 Run'),
    ]);
    final plan = _manualPlan([weekdayWeek, syntheticWeek]);

    final model = buildHomeStageMapModel(
      plan: plan,
      completedScheduledWorkoutIds: const <String>{},
      activeWeekNumber: 1,
      backgroundSequence: const <String>['bg.webp', 'bg2.webp'],
    );

    // Positional fallback: the single Monday-labeled run still lands at
    // slot 0 (its workout index), but its dayLabel is the literal 'Mon'
    // string rather than a slot-derived weekday.
    final firstWeekStones = model.sections.first.stones;
    expect(firstWeekStones[0].kind, HomeStageStoneKind.run);
    expect(firstWeekStones[0].dayLabel, 'Mon');
  });

  test(
    'todayDayIndex still picks the first uncompleted run slot after weekday mapping',
    () {
      final week = _manualWeek(1, [
        _workout(dayLabel: 'Tue', title: 'Tuesday Run'),
        _workout(dayLabel: 'Thu', title: 'Thursday Run'),
        _workout(dayLabel: 'Sat', title: 'Saturday Run'),
      ]);
      final plan = _manualPlan([week]);
      final tuesdayId = homeStageScheduledWorkoutId(
        weekNumber: 1,
        dayLabel: 'Tue',
        title: 'Tuesday Run',
      );

      final model = buildHomeStageMapModel(
        plan: plan,
        completedScheduledWorkoutIds: {tuesdayId},
        activeWeekNumber: 1,
        backgroundSequence: const <String>['bg.webp'],
      );

      // Tuesday (slot 1) is completed, so today should be Thursday (slot 3).
      expect(model.todayDayIndex, 3);
      expect(
        model.sections.single.stones[1].state,
        HomeStageStoneState.completed,
      );
      expect(
        model.sections.single.stones[3].state,
        HomeStageStoneState.current,
      );
    },
  );

  test(
    'mid-week startsOnDate slots the today stone on the real calendar weekday',
    () {
      // Mirrors the home_tab wiring: currentWeekdayIndex comes from
      // activeGeneratedPlanWeekdayFor, so day offset 0 of a Wednesday-start
      // plan is Wednesday's slot — not Monday's, as the pre-9eab87cd
      // `DateTime.monday + dayIndex` wiring would have reported.
      final week = _manualWeek(1, [
        _workout(dayLabel: 'Mon', title: 'Monday Run'),
        _workout(dayLabel: 'Wed', title: 'Wednesday Run'),
        _workout(dayLabel: 'Fri', title: 'Friday Run'),
      ]);
      // 2026-07-08 is a Wednesday.
      final plan = _manualPlan([week], startsOnDate: '2026-07-08');

      final activeWeekdayIndex = activeGeneratedPlanWeekdayFor(
        plan,
        currentDate: DateTime(2026, 7, 8),
      );
      expect(activeWeekdayIndex, DateTime.wednesday);

      final model = buildHomeStageMapModel(
        plan: plan,
        completedScheduledWorkoutIds: const <String>{},
        activeWeekNumber: 1,
        currentWeekdayIndex: activeWeekdayIndex,
        backgroundSequence: const <String>['bg.webp'],
      );

      final stones = model.sections.single.stones;
      expect(model.todayDayIndex, 2);
      expect(stones[2].kind, HomeStageStoneKind.run);
      expect(stones[2].workoutTitle, 'Wednesday Run');
      expect(stones[2].state, HomeStageStoneState.current);
      // The Monday-role run of this plan week lies AFTER the Wednesday start,
      // so it must not pulse as today and (being before today's slot in the
      // calendar column) renders as missed-style rather than current.
      expect(stones[0].workoutTitle, 'Monday Run');
      expect(stones[0].state, isNot(HomeStageStoneState.current));
      expect(stones[4].workoutTitle, 'Friday Run');
      expect(stones[4].state, HomeStageStoneState.future);
    },
  );

  test(
    'mid-week plan reaches its Monday-role stone on the following monday',
    () {
      final week = _manualWeek(1, [
        _workout(dayLabel: 'Mon', title: 'Monday Run'),
        _workout(dayLabel: 'Wed', title: 'Wednesday Run'),
        _workout(dayLabel: 'Fri', title: 'Friday Run'),
      ]);
      final plan = _manualPlan([week], startsOnDate: '2026-07-08');

      // 2026-07-13 is the Monday inside plan week 1 of a Wednesday start.
      final activeWeekdayIndex = activeGeneratedPlanWeekdayFor(
        plan,
        currentDate: DateTime(2026, 7, 13),
      );
      expect(activeWeekdayIndex, DateTime.monday);

      final model = buildHomeStageMapModel(
        plan: plan,
        completedScheduledWorkoutIds: const <String>{},
        activeWeekNumber: 1,
        currentWeekdayIndex: activeWeekdayIndex,
        backgroundSequence: const <String>['bg.webp'],
      );

      final stones = model.sections.single.stones;
      expect(model.todayDayIndex, 0);
      expect(stones[0].workoutTitle, 'Monday Run');
      expect(stones[0].state, HomeStageStoneState.current);
      expect(stones[2].state, HomeStageStoneState.future);
      expect(stones[4].state, HomeStageStoneState.future);
    },
  );
}
