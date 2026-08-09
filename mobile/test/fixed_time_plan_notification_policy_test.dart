import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_center_settings.dart';
import 'package:runiac_app/features/notifications/domain/models/plan_notification_schedule.dart';
import 'package:runiac_app/features/notifications/domain/services/fixed_time_plan_notification_policy.dart';

void main() {
  group('FixedTimePlanNotificationPolicy', () {
    const policy = FixedTimePlanNotificationPolicy();

    test('builds fixed reminders around a future planned run', () {
      // Given
      final now = DateTime(2026, 7, 7, 6);
      final workout = PlanNotificationWorkoutInput(
        planId: 'plan-1',
        scheduledWorkoutId: 'week-1-tue-easy-run',
        title: 'Easy Run',
        startsAt: DateTime(2026, 7, 8, 7, 30),
        completed: false,
      );

      // When
      final notifications = policy.notificationsForWorkout(
        workout,
        settings: NotificationCenterSettings.defaults,
        now: now,
      );

      // Then
      expect(notifications.map((notification) => notification.scheduledAt), [
        DateTime(2026, 7, 8),
        DateTime(2026, 7, 8, 5, 30),
        DateTime(2026, 7, 8, 6, 30),
        DateTime(2026, 7, 8, 7, 20),
        DateTime(2026, 7, 8, 8, 30),
        DateTime(2026, 7, 8, 9, 30),
      ]);
      expect(notifications.map((notification) => notification.kind), [
        PlanNotificationKind.todaysPlanReminder,
        PlanNotificationKind.planStartReminder,
        PlanNotificationKind.planStartReminder,
        PlanNotificationKind.planStartReminder,
        PlanNotificationKind.missedRunNudge,
        PlanNotificationKind.missedRunNudge,
      ]);
    });

    test('does not build reminders when master notifications are disabled', () {
      // Given
      final workout = PlanNotificationWorkoutInput(
        planId: 'plan-1',
        scheduledWorkoutId: 'week-1-tue-easy-run',
        title: 'Easy Run',
        startsAt: DateTime(2026, 7, 8, 7, 30),
        completed: false,
      );

      // When
      final notifications = policy.notificationsForWorkout(
        workout,
        settings: NotificationCenterSettings.defaults.copyWith(
          notificationsEnabled: false,
        ),
        now: DateTime(2026, 7, 7, 6),
      );

      // Then
      expect(notifications, isEmpty);
    });

    test('skips missed-run nudges when the planned workout is complete', () {
      // Given
      final workout = PlanNotificationWorkoutInput(
        planId: 'plan-1',
        scheduledWorkoutId: 'week-1-tue-easy-run',
        title: 'Easy Run',
        startsAt: DateTime(2026, 7, 8, 7, 30),
        completed: true,
      );

      // When
      final notifications = policy.notificationsForWorkout(
        workout,
        settings: NotificationCenterSettings.defaults,
        now: DateTime(2026, 7, 7, 6),
      );

      // Then
      expect(
        notifications.map((notification) => notification.kind),
        isNot(contains(PlanNotificationKind.missedRunNudge)),
      );
    });

    test(
      'builds 22:00 and 23:00 streak-risk reminders only from explicit risk input',
      () {
        // Given
        final dynamic streakRiskPolicy = policy;

        // When
        final notifications =
            streakRiskPolicy.streakRiskNotifications(
                  planId: 'generated-plan',
                  riskDate: DateTime(2026, 7, 8),
                  streakWouldBreakWithoutValidatedRun: true,
                  settings: NotificationCenterSettings.defaults,
                  now: DateTime(2026, 7, 8, 21),
                )
                as List<ScheduledPlanNotification>;

        // Then
        expect(notifications.map((notification) => notification.scheduledAt), [
          DateTime(2026, 7, 8, 22),
          DateTime(2026, 7, 8, 23),
        ]);
        expect(
          notifications.every(
            (notification) =>
                notification.payload['kind'] == 'streakRiskNudge' &&
                !notification.payload.containsKey('xp') &&
                !notification.payload.containsKey('streak') &&
                !notification.payload.containsKey('leaderboardScore'),
          ),
          isTrue,
        );
      },
    );
  });
}
