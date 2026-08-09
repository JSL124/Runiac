import '../models/notification_center_settings.dart';
import '../models/plan_notification_schedule.dart';

class FixedTimePlanNotificationPolicy {
  const FixedTimePlanNotificationPolicy();

  List<ScheduledPlanNotification> notificationsForWorkout(
    PlanNotificationWorkoutInput workout, {
    required NotificationCenterSettings settings,
    required DateTime now,
  }) {
    if (!settings.notificationsEnabled) {
      return const <ScheduledPlanNotification>[];
    }

    final notifications = <ScheduledPlanNotification>[];
    if (settings.todaysPlanReminderEnabled) {
      notifications.add(
        _notification(
          workout,
          kind: PlanNotificationKind.todaysPlanReminder,
          suffix: 'today',
          scheduledAt: DateTime(
            workout.startsAt.year,
            workout.startsAt.month,
            workout.startsAt.day,
          ),
          title: 'Today has a planned run',
          body: '${workout.title} is scheduled for today.',
        ),
      );
    }

    if (settings.planStartReminderEnabled) {
      notifications.addAll([
        _beforeStart(workout, minutesBeforeStart: 120),
        _beforeStart(workout, minutesBeforeStart: 60),
        _beforeStart(workout, minutesBeforeStart: 10),
      ]);
    }

    if (!workout.completed && settings.missedRunNudgeEnabled) {
      notifications.addAll([
        _afterStart(workout, minutesAfterStart: 60),
        _afterStart(workout, minutesAfterStart: 120),
      ]);
    }

    return [
      for (final notification in notifications)
        if (notification.scheduledAt.isAfter(now)) notification,
    ]..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
  }

  ScheduledPlanNotification? planUpdateNotification({
    required String planId,
    required String title,
    required NotificationCenterSettings settings,
    required DateTime now,
  }) {
    if (!settings.notificationsEnabled || !settings.planUpdatesEnabled) {
      return null;
    }
    return ScheduledPlanNotification(
      id: '$planId-plan-update-${now.millisecondsSinceEpoch}',
      kind: PlanNotificationKind.planUpdate,
      scheduledAt: now,
      title: 'New plan update',
      body: title,
      payload: <String, String>{'planId': planId},
    );
  }

  List<ScheduledPlanNotification> streakRiskNotifications({
    required String planId,
    required DateTime riskDate,
    required bool streakWouldBreakWithoutValidatedRun,
    required NotificationCenterSettings settings,
    required DateTime now,
  }) {
    if (!settings.notificationsEnabled ||
        !settings.missedRunNudgeEnabled ||
        !streakWouldBreakWithoutValidatedRun) {
      return const <ScheduledPlanNotification>[];
    }

    final riskDay = DateTime(riskDate.year, riskDate.month, riskDate.day);
    final notifications = [
      _streakRiskNotification(
        planId: planId,
        riskDay: riskDay,
        hour: 22,
        suffix: '2200',
      ),
      _streakRiskNotification(
        planId: planId,
        riskDay: riskDay,
        hour: 23,
        suffix: '2300',
      ),
    ];

    return [
      for (final notification in notifications)
        if (notification.scheduledAt.isAfter(now)) notification,
    ]..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
  }

  ScheduledPlanNotification _beforeStart(
    PlanNotificationWorkoutInput workout, {
    required int minutesBeforeStart,
  }) {
    final hours = minutesBeforeStart ~/ 60;
    final label = hours > 0 ? '$hours hour${hours == 1 ? '' : 's'}' : '10 min';
    return _notification(
      workout,
      kind: PlanNotificationKind.planStartReminder,
      suffix: 'start-$minutesBeforeStart',
      scheduledAt: workout.startsAt.subtract(
        Duration(minutes: minutesBeforeStart),
      ),
      title: '${workout.title} starts in $label',
      body: 'Open Runiac when you are ready to start.',
    );
  }

  ScheduledPlanNotification _afterStart(
    PlanNotificationWorkoutInput workout, {
    required int minutesAfterStart,
  }) {
    final hours = minutesAfterStart ~/ 60;
    return _notification(
      workout,
      kind: PlanNotificationKind.missedRunNudge,
      suffix: 'missed-$minutesAfterStart',
      scheduledAt: workout.startsAt.add(Duration(minutes: minutesAfterStart)),
      title: 'Still planning to run?',
      body:
          '${workout.title} was scheduled $hours hour${hours == 1 ? '' : 's'} ago.',
    );
  }

  ScheduledPlanNotification _notification(
    PlanNotificationWorkoutInput workout, {
    required PlanNotificationKind kind,
    required String suffix,
    required DateTime scheduledAt,
    required String title,
    required String body,
  }) {
    return ScheduledPlanNotification(
      id: '${workout.planId}-${workout.scheduledWorkoutId}-$suffix',
      kind: kind,
      scheduledAt: scheduledAt,
      title: title,
      body: body,
      payload: <String, String>{
        'planId': workout.planId,
        'scheduledWorkoutId': workout.scheduledWorkoutId,
        'kind': kind.name,
      },
    );
  }

  ScheduledPlanNotification _streakRiskNotification({
    required String planId,
    required DateTime riskDay,
    required int hour,
    required String suffix,
  }) {
    const kind = PlanNotificationKind.streakRiskNudge;
    return ScheduledPlanNotification(
      id: '$planId-streak-risk-${riskDay.year}-${riskDay.month}-${riskDay.day}-$suffix',
      kind: kind,
      scheduledAt: DateTime(riskDay.year, riskDay.month, riskDay.day, hour),
      title: 'Your streak may need a validated run',
      body: 'Log a completed run before midnight if you want to keep it going.',
      payload: <String, String>{'planId': planId, 'kind': kind.name},
    );
  }
}
