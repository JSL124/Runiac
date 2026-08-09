import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/domain/services/generated_plan_notification_schedule_builder.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/you/presentation/adapters/generated_plan_you_display_adapter.dart';

// Weekday resolution regression tests for mid-week plan starts.
//
// `startsOnDate` is whatever day onboarding finished — it is never snapped to
// a Monday — while workout `dayLabel`s denote real weekdays. The canonical
// mapping (shared with the Functions side) is
// `dayOffset = (weekdayOffset - startWeekdayOffset + 7) % 7`, so a label
// resolves to the matching weekday INSIDE that plan week's seven-day window.
// Reading offset 0 as Monday is the historical bug fixed in commit 9eab87cd.
//
// Calendar anchors used below: 2026-07-06 is a Monday and 2026-07-08 is a
// Wednesday.

void main() {
  group('activeGeneratedPlanWeekdayFor', () {
    test(
      'monday start plan resolves current dates to their real weekdays',
      () {
        final snapshot = _snapshot(startsOnDate: '2026-07-06');

        expect(
          activeGeneratedPlanWeekdayFor(
            snapshot,
            currentDate: DateTime(2026, 7, 6),
          ),
          DateTime.monday,
        );
        expect(
          activeGeneratedPlanWeekdayFor(
            snapshot,
            currentDate: DateTime(2026, 7, 8),
          ),
          DateTime.wednesday,
        );
        expect(
          activeGeneratedPlanWeekdayFor(
            snapshot,
            currentDate: DateTime(2026, 7, 10),
          ),
          DateTime.friday,
        );
      },
    );

    test(
      'wednesday start plan treats day offset zero as wednesday not monday',
      () {
        final snapshot = _snapshot(startsOnDate: '2026-07-08');
        final startDay = DateTime(2026, 7, 8);

        expect(
          activeGeneratedPlanDayIndexFor(snapshot, currentDate: startDay),
          0,
        );
        // The buggy interpretation was DateTime.monday + dayIndex, which
        // would report Monday here.
        expect(
          activeGeneratedPlanWeekdayFor(snapshot, currentDate: startDay),
          DateTime.wednesday,
        );
      },
    );

    test(
      'wednesday start plan resolves the following monday inside plan week one',
      () {
        final snapshot = _snapshot(startsOnDate: '2026-07-08', weekCount: 2);
        // 2026-07-13 is the Monday five days after the Wednesday start: the
        // Monday-role day of plan week 1, not a jump into week 2.
        final followingMonday = DateTime(2026, 7, 13);

        expect(
          activeGeneratedPlanWeekdayFor(
            snapshot,
            currentDate: followingMonday,
          ),
          DateTime.monday,
        );
        expect(
          activeGeneratedPlanDayIndexFor(
            snapshot,
            currentDate: followingMonday,
          ),
          5,
        );
        expect(
          activeGeneratedPlanWeekFor(
            snapshot,
            currentDate: followingMonday,
          )?.weekNumber,
          1,
        );
      },
    );

    test(
      'weekday before the start weekday wraps into the same plan week',
      () {
        final snapshot = _snapshot(startsOnDate: '2026-07-08', weekCount: 2);
        // Tuesday 2026-07-14 is the last (seventh) day of plan week 1 for a
        // Wednesday-start plan; the next day rolls over into week 2 at its
        // start weekday.
        final wrappedTuesday = DateTime(2026, 7, 14);
        final weekTwoWednesday = DateTime(2026, 7, 15);

        expect(
          activeGeneratedPlanWeekdayFor(snapshot, currentDate: wrappedTuesday),
          DateTime.tuesday,
        );
        expect(
          activeGeneratedPlanDayIndexFor(
            snapshot,
            currentDate: wrappedTuesday,
          ),
          6,
        );
        expect(
          activeGeneratedPlanWeekFor(
            snapshot,
            currentDate: wrappedTuesday,
          )?.weekNumber,
          1,
        );

        expect(
          activeGeneratedPlanWeekdayFor(
            snapshot,
            currentDate: weekTwoWednesday,
          ),
          DateTime.wednesday,
        );
        expect(
          activeGeneratedPlanWeekFor(
            snapshot,
            currentDate: weekTwoWednesday,
          )?.weekNumber,
          2,
        );
      },
    );

    test('returns null without a parseable plan start date', () {
      expect(
        activeGeneratedPlanWeekdayFor(
          _snapshot(startsOnDate: null),
          currentDate: DateTime(2026, 7, 8),
        ),
        isNull,
      );
      expect(
        activeGeneratedPlanWeekdayFor(
          _snapshot(startsOnDate: 'not-a-date'),
          currentDate: DateTime(2026, 7, 8),
        ),
        isNull,
      );
    });
  });

  group('workout day labels resolve to real calendar dates', () {
    // The canonical client mapper for label-to-date resolution. Single-label
    // scenarios are covered in
    // generated_plan_notification_schedule_builder_test.dart; these pin the
    // full Mon/Wed/Fri set against real calendar dates for both a Monday
    // start and a mid-week start.
    const builder = GeneratedPlanNotificationScheduleBuilder();

    Map<String, DateTime> datesByWorkoutId(
      BeginnerAdaptivePlanSnapshot snapshot,
      DateTime currentDate,
    ) {
      return {
        for (final workout in builder.workoutsForPlan(
          snapshot,
          currentDate: currentDate,
          completedScheduledWorkoutIds: const <String>{},
        ))
          workout.scheduledWorkoutId: workout.startsAt,
      };
    }

    test('monday start plan places Mon Wed Fri labels on that week\'s dates',
        () {
      final snapshot = _snapshot(
        startsOnDate: '2026-07-06',
        dayLabels: const ['Mon', 'Wed', 'Fri'],
      );

      final dates = datesByWorkoutId(snapshot, DateTime(2026, 7, 6, 9));

      expect(dates['week-1-mon-easy-run'], DateTime(2026, 7, 6, 7, 30));
      expect(dates['week-1-wed-easy-run'], DateTime(2026, 7, 8, 7, 30));
      expect(dates['week-1-fri-easy-run'], DateTime(2026, 7, 10, 7, 30));
    });

    test(
      'wednesday start plan wraps the Mon label into the following monday',
      () {
        final snapshot = _snapshot(
          startsOnDate: '2026-07-08',
          dayLabels: const ['Mon', 'Wed', 'Fri'],
          weekCount: 2,
        );

        final dates = datesByWorkoutId(snapshot, DateTime(2026, 7, 8, 9));

        // dayOffset = (weekdayOffset - startWeekdayOffset + 7) % 7 with the
        // Wednesday anchor: Wed -> 0, Fri -> 2, Mon -> 5 (wraps forward
        // inside the same plan week, never backwards before the start).
        expect(dates['week-1-wed-easy-run'], DateTime(2026, 7, 8, 7, 30));
        expect(dates['week-1-fri-easy-run'], DateTime(2026, 7, 10, 7, 30));
        expect(dates['week-1-mon-easy-run'], DateTime(2026, 7, 13, 7, 30));

        // Week 2 repeats the same weekday roles one seven-day window later.
        expect(dates['week-2-wed-easy-run'], DateTime(2026, 7, 15, 7, 30));
        expect(dates['week-2-fri-easy-run'], DateTime(2026, 7, 17, 7, 30));
        expect(dates['week-2-mon-easy-run'], DateTime(2026, 7, 20, 7, 30));
      },
    );
  });
}

BeginnerAdaptivePlanSnapshot _snapshot({
  required String? startsOnDate,
  List<String> dayLabels = const ['Wed'],
  int weekCount = 1,
}) {
  return BeginnerAdaptivePlanSnapshot(
    id: 'weekday-regression-plan',
    title: 'Weekday regression plan',
    subtitle: 'Beginner schedule',
    planKind: BeginnerAdaptivePlanKind.onboardingBased,
    sourceLabel: 'Generated onboarding plan',
    startsOnDate: startsOnDate,
    durationWeeks: weekCount,
    safetyBand: BeginnerPlanSafetyBand.clear,
    templateKind: BeginnerPlanTemplateKind.standardBeginnerStart,
    family: null,
    familyCategory: null,
    familyReason: 'Test fixture',
    supportStyleLabel: 'Gentle',
    weeklyFrequencyLabel: '${dayLabels.length} days',
    preferredScheduleLabel: dayLabels.join(' · '),
    sessionDurationLabel: '20 min',
    safetyNote: 'Stop if anything feels wrong.',
    weeks: [
      for (var weekNumber = 1; weekNumber <= weekCount; weekNumber++)
        BeginnerAdaptivePlanWeek(
          weekNumber: weekNumber,
          title: 'Week $weekNumber',
          focus: 'Start easy',
          workouts: [for (final dayLabel in dayLabels) _workout(dayLabel)],
        ),
    ],
  );
}

BeginnerAdaptiveWorkout _workout(String dayLabel) {
  return BeginnerAdaptiveWorkout(
    dayLabel: dayLabel,
    title: 'Easy Run',
    durationMinutes: 20,
    kind: BeginnerWorkoutKind.easyRun,
    intensity: BeginnerPlanIntensity.gentle,
    description: 'Easy effort',
    steps: const ['Warm up', 'Run easy'],
    supportiveNote: 'Keep it relaxed.',
    detail: BeginnerAdaptiveWorkoutDetail(
      metrics: const [
        BeginnerAdaptiveWorkoutMetric(label: 'Time', value: '20 min'),
      ],
      breakdown: const [
        BeginnerAdaptiveWorkoutBreakdownStep(
          kind: BeginnerAdaptiveWorkoutBreakdownStepKind.run,
          title: 'Easy run',
          detail: 'Run relaxed.',
        ),
      ],
      effortGuide: 'Easy',
      coachNotes: const ['Stay conversational.'],
    ),
  );
}
