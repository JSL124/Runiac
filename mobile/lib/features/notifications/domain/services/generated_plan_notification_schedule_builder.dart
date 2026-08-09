import '../../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'fixed_time_plan_notification_policy.dart';
import '../models/notification_center_settings.dart';
import '../models/plan_notification_schedule.dart';

class GeneratedPlanNotificationScheduleBuilder {
  const GeneratedPlanNotificationScheduleBuilder({
    this.policy = const FixedTimePlanNotificationPolicy(),
  });

  static const fallbackScheduleTimeLabel = '7:30 AM';

  final FixedTimePlanNotificationPolicy policy;

  List<PlanNotificationWorkoutInput> workoutsForPlan(
    BeginnerAdaptivePlanSnapshot snapshot, {
    required DateTime currentDate,
    required Set<String> completedScheduledWorkoutIds,
  }) {
    final anchorDate = _planStartDate(snapshot.startsOnDate, currentDate);
    return [
      for (final week in snapshot.weeks)
        for (final workout in week.workouts)
          if (_isRunnableWorkout(workout))
            _workoutInput(
              snapshot,
              week,
              workout,
              anchorDate: anchorDate,
              completedScheduledWorkoutIds: completedScheduledWorkoutIds,
            ),
    ];
  }

  List<ScheduledPlanNotification> notificationsForPlan(
    BeginnerAdaptivePlanSnapshot snapshot, {
    required NotificationCenterSettings settings,
    required DateTime now,
    required Set<String> completedScheduledWorkoutIds,
    StreakRiskNotificationInput? streakRisk,
  }) {
    return [
      for (final workout in workoutsForPlan(
        snapshot,
        currentDate: now,
        completedScheduledWorkoutIds: completedScheduledWorkoutIds,
      ))
        ...policy.notificationsForWorkout(
          workout,
          settings: settings,
          now: now,
        ),
      if (streakRisk != null)
        ...policy.streakRiskNotifications(
          planId: streakRisk.planId,
          riskDate: streakRisk.riskDate,
          streakWouldBreakWithoutValidatedRun:
              streakRisk.streakWouldBreakWithoutValidatedRun,
          settings: settings,
          now: now,
        ),
    ];
  }

  PlanNotificationWorkoutInput _workoutInput(
    BeginnerAdaptivePlanSnapshot snapshot,
    BeginnerAdaptivePlanWeek week,
    BeginnerAdaptiveWorkout workout, {
    required DateTime anchorDate,
    required Set<String> completedScheduledWorkoutIds,
  }) {
    final scheduledWorkoutId = _scheduledWorkoutIdFor(
      weekNumber: week.weekNumber,
      dayLabel: workout.dayLabel,
      title: workout.title,
    );
    return PlanNotificationWorkoutInput(
      planId: snapshot.id,
      scheduledWorkoutId: scheduledWorkoutId,
      title: workout.title,
      startsAt: _workoutStartAt(
        anchorDate,
        weekNumber: week.weekNumber,
        dayLabel: workout.dayLabel,
        timeLabel: workout.scheduleTimeLabel ?? fallbackScheduleTimeLabel,
      ),
      completed: completedScheduledWorkoutIds.contains(scheduledWorkoutId),
    );
  }

  DateTime _workoutStartAt(
    DateTime anchorDate, {
    required int weekNumber,
    required String dayLabel,
    required String timeLabel,
  }) {
    final time = _timeFromLabel(timeLabel);
    // `dayLabel` is a real weekday, but the plan can start on any day, so a
    // label resolves to the matching weekday inside that week's seven-day
    // window. Monday-start plans keep the dates they already had.
    final anchorOffset = (anchorDate.weekday - DateTime.monday) % 7;
    final dayOffset = (_weekdayOffset(dayLabel) - anchorOffset + 7) % 7;
    final daysFromAnchor = ((weekNumber - 1) * DateTime.daysPerWeek) + dayOffset;
    final workoutDate = anchorDate.add(Duration(days: daysFromAnchor));
    return DateTime(
      workoutDate.year,
      workoutDate.month,
      workoutDate.day,
      time.hour,
      time.minute,
    );
  }

  DateTime _planStartDate(String? startsOnDate, DateTime currentDate) {
    final parsed = startsOnDate == null
        ? null
        : DateTime.tryParse(startsOnDate);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    final today = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );
    return today.subtract(
      Duration(days: currentDate.weekday - DateTime.monday),
    );
  }

  bool _isRunnableWorkout(BeginnerAdaptiveWorkout workout) {
    return workout.kind != BeginnerWorkoutKind.restOrMobility;
  }

  _ClockTime _timeFromLabel(String label) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(label.trim());
    if (match == null) {
      return const _ClockTime(7, 30);
    }
    final rawHour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final marker = match.group(3)!.toUpperCase();
    final normalizedHour = rawHour % 12;
    final hour = marker == 'PM' ? normalizedHour + 12 : normalizedHour;
    return _ClockTime(hour, minute.clamp(0, 59));
  }

  int _weekdayOffset(String dayLabel) {
    return switch (dayLabel) {
      'Mon' => 0,
      'Tue' => 1,
      'Wed' => 2,
      'Thu' => 3,
      'Fri' => 4,
      'Sat' => 5,
      'Sun' => 6,
      _ => 0,
    };
  }

  String _scheduledWorkoutIdFor({
    required int weekNumber,
    required String dayLabel,
    required String title,
  }) {
    final titleSlug = title
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-+$'), '');
    final suffix = titleSlug.isEmpty ? 'workout' : titleSlug;
    return 'week-$weekNumber-${dayLabel.toLowerCase()}-$suffix';
  }
}

class _ClockTime {
  const _ClockTime(this.hour, this.minute);

  final int hour;
  final int minute;
}
