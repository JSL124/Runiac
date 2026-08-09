import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_center_settings.dart';
import 'package:runiac_app/features/notifications/domain/services/generated_plan_notification_schedule_builder.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';

void main() {
  group('GeneratedPlanNotificationScheduleBuilder', () {
    test('uses saved schedule time labels and generated plan start dates', () {
      // Given
      const builder = GeneratedPlanNotificationScheduleBuilder();
      final snapshot = _snapshot(
        startsOnDate: '2026-07-06',
        workout: _workout(dayLabel: 'Wed', scheduleTimeLabel: '6:15 PM'),
      );

      // When
      final workouts = builder.workoutsForPlan(
        snapshot,
        currentDate: DateTime(2026, 7, 7, 9),
        completedScheduledWorkoutIds: const <String>{},
      );

      // Then
      expect(workouts, hasLength(1));
      expect(workouts.single.startsAt, DateTime(2026, 7, 8, 18, 15));
      expect(workouts.single.scheduledWorkoutId, 'week-1-wed-easy-run');
    });

    test('schedules a mid-week plan start on the label\'s real weekday', () {
      // Given 2026-07-08 is a Wednesday, so a "Wed" workout is the start day
      // itself — not two days later as a Monday anchor would place it.
      const builder = GeneratedPlanNotificationScheduleBuilder();
      final snapshot = _snapshot(
        startsOnDate: '2026-07-08',
        workout: _workout(dayLabel: 'Wed', scheduleTimeLabel: '6:15 PM'),
      );

      // When
      final workouts = builder.workoutsForPlan(
        snapshot,
        currentDate: DateTime(2026, 7, 8, 9),
        completedScheduledWorkoutIds: const <String>{},
      );

      // Then
      expect(workouts.single.startsAt, DateTime(2026, 7, 8, 18, 15));
    });

    test('wraps an earlier weekday label into the same plan week', () {
      // Given
      const builder = GeneratedPlanNotificationScheduleBuilder();
      final snapshot = _snapshot(
        startsOnDate: '2026-07-08',
        workout: _workout(dayLabel: 'Mon', scheduleTimeLabel: '6:15 PM'),
      );

      // When
      final workouts = builder.workoutsForPlan(
        snapshot,
        currentDate: DateTime(2026, 7, 8, 9),
        completedScheduledWorkoutIds: const <String>{},
      );

      // Then
      expect(workouts.single.startsAt, DateTime(2026, 7, 13, 18, 15));
    });

    test(
      'uses the app fallback start time when a workout has no saved time',
      () {
        // Given
        const builder = GeneratedPlanNotificationScheduleBuilder();
        final snapshot = _snapshot(
          startsOnDate: '2026-07-06',
          workout: _workout(dayLabel: 'Thu'),
        );

        // When
        final workouts = builder.workoutsForPlan(
          snapshot,
          currentDate: DateTime(2026, 7, 7, 9),
          completedScheduledWorkoutIds: const <String>{},
        );

        // Then
        expect(workouts.single.startsAt, DateTime(2026, 7, 9, 7, 30));
      },
    );

    test('does not infer streak-risk reminders from completed workout ids', () {
      // Given
      const builder = GeneratedPlanNotificationScheduleBuilder();
      final snapshot = _snapshot(
        startsOnDate: '2026-07-06',
        workout: _workout(dayLabel: 'Wed', scheduleTimeLabel: '6:15 PM'),
      );

      // When
      final notifications = builder.notificationsForPlan(
        snapshot,
        settings: NotificationCenterSettings.defaults,
        now: DateTime(2026, 7, 8, 21),
        completedScheduledWorkoutIds: const <String>{},
      );

      // Then
      expect(
        notifications.map((notification) => notification.kind.name),
        isNot(contains('streakRiskNudge')),
      );
    });
  });
}

BeginnerAdaptivePlanSnapshot _snapshot({
  required String startsOnDate,
  required BeginnerAdaptiveWorkout workout,
}) {
  return BeginnerAdaptivePlanSnapshot(
    id: 'generated-plan',
    title: 'Generated plan',
    subtitle: 'Beginner schedule',
    planKind: BeginnerAdaptivePlanKind.onboardingBased,
    sourceLabel: 'Generated onboarding plan',
    startsOnDate: startsOnDate,
    durationWeeks: 1,
    safetyBand: BeginnerPlanSafetyBand.clear,
    templateKind: BeginnerPlanTemplateKind.standardBeginnerStart,
    family: null,
    familyCategory: null,
    familyReason: 'Test fixture',
    supportStyleLabel: 'Gentle',
    weeklyFrequencyLabel: '3 days',
    preferredScheduleLabel: workout.dayLabel,
    sessionDurationLabel: '20 min',
    safetyNote: 'Stop if anything feels wrong.',
    weeks: [
      BeginnerAdaptivePlanWeek(
        weekNumber: 1,
        title: 'Week 1',
        focus: 'Start easy',
        workouts: [workout],
      ),
    ],
  );
}

BeginnerAdaptiveWorkout _workout({
  required String dayLabel,
  String? scheduleTimeLabel,
}) {
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
    scheduleTimeLabel: scheduleTimeLabel,
  );
}
