import 'package:flutter/material.dart';

import '../../../run/presentation/models/planned_run_context.dart';

// Display-only workout previews used by the static You prototype.
const weeklyWorkoutDetailSnapshot = WeeklyWorkoutDetailSnapshot(
  title: 'Workout detail',
  dayLabel: 'Thursday · Easy Run',
  planTitle: '20 min easy run',
  editScheduleCurrentLabel: 'Thu · 7:30 AM',
  editSchedulePreviewLabel: 'Fri · 7:30 AM',
  scheduleWeekdayIndex: DateTime.thursday,
  scheduleDayLabel: 'Thu',
  scheduleTimeLabel: '7:30 AM',
  occupiedScheduleWeekdays: {DateTime.thursday, DateTime.saturday},
  metrics: [
    WorkoutMetricDisplay('Distance', '3.0 km'),
    WorkoutMetricDisplay('Time', '20 min'),
    WorkoutMetricDisplay('Suggested pace', '7:30 /km'),
    WorkoutMetricDisplay('Effort', 'Low'),
  ],
  breakdown: [
    WorkoutStepDisplay(Icons.directions_walk, 'Warm-up', '5 min · easy walk'),
    WorkoutStepDisplay(
      Icons.directions_run,
      'Easy run',
      '12 min · conversational pace',
    ),
    WorkoutStepDisplay(
      Icons.self_improvement,
      'Cool-down',
      '3 min · slow walk',
    ),
  ],
  effortGuide:
      'Aim for 2 out of 5 — you can speak full sentences without gasping.',
  coachNotes: [
    'Start slower than you think.',
    'If breathing feels sharp, walk briefly and reset.',
    'Easy runs should feel almost too slow at first. That is normal.',
  ],
  startActionLabel: 'Start This Run',
);

const saturdayWeeklyWorkoutDetailSnapshot = WeeklyWorkoutDetailSnapshot(
  title: 'Workout detail',
  dayLabel: 'Saturday · Easy Run',
  planTitle: '20 min easy run',
  editScheduleCurrentLabel: 'Saturday',
  editSchedulePreviewLabel: 'Preview only',
  scheduleWeekdayIndex: DateTime.saturday,
  scheduleDayLabel: 'Sat',
  scheduleTimeLabel: '7:30 AM',
  occupiedScheduleWeekdays: {DateTime.thursday, DateTime.saturday},
  metrics: [
    WorkoutMetricDisplay('Distance', '3.0 km'),
    WorkoutMetricDisplay('Time', '20 min'),
    WorkoutMetricDisplay('Suggested pace', '7:30 /km'),
    WorkoutMetricDisplay('Effort', 'Low'),
  ],
  breakdown: [
    WorkoutStepDisplay(Icons.directions_walk, 'Warm-up', '5 min · easy walk'),
    WorkoutStepDisplay(
      Icons.directions_run,
      'Easy run',
      '12 min · conversational pace',
    ),
    WorkoutStepDisplay(
      Icons.self_improvement,
      'Cool-down',
      '3 min · slow walk',
    ),
  ],
  effortGuide:
      'Aim for 2 out of 5 — you can speak full sentences without gasping.',
  coachNotes: [
    'Start slower than you think.',
    'If breathing feels sharp, walk briefly and reset.',
    'Easy runs should feel almost too slow at first. That is normal.',
  ],
  startActionLabel: 'Start This Run',
);

class WeeklyWorkoutDetailSnapshot {
  const WeeklyWorkoutDetailSnapshot({
    required this.title,
    required this.dayLabel,
    String? planTitle,
    String? heroTitle,
    required this.editScheduleCurrentLabel,
    required this.editSchedulePreviewLabel,
    String? heroCopy,
    String? heroSupportCopy,
    required this.metrics,
    required this.breakdown,
    required this.effortGuide,
    required this.coachNotes,
    this.startActionLabel,
    this.canEditSchedule = true,
    this.plannedRunContext,
    this.scheduleWeekdayIndex,
    this.scheduleDayLabel,
    this.scheduleTimeLabel,
    this.occupiedScheduleWeekdays = const <int>{},
    this.briefingContext,
  }) : planTitle = planTitle ?? heroTitle ?? '';

  final String title;
  final String dayLabel;
  final String planTitle;
  final String editScheduleCurrentLabel;
  final String editSchedulePreviewLabel;
  final List<WorkoutMetricDisplay> metrics;
  final List<WorkoutStepDisplay> breakdown;
  final String effortGuide;
  final List<String> coachNotes;
  final String? startActionLabel;
  final bool canEditSchedule;
  final PlannedRunContext? plannedRunContext;
  final int? scheduleWeekdayIndex;
  final String? scheduleDayLabel;
  final String? scheduleTimeLabel;
  final Set<int> occupiedScheduleWeekdays;

  /// Plan address for the AI briefing's local cache key, and the week context
  /// the screen itself does not display. Null on the static demo snapshots,
  /// which simply means the briefing is never cached for them.
  final WorkoutBriefingContext? briefingContext;

  WeeklyWorkoutDetailSnapshot copyWith({
    String? dayLabel,
    String? editScheduleCurrentLabel,
    int? scheduleWeekdayIndex,
    String? scheduleDayLabel,
    String? scheduleTimeLabel,
    Set<int>? occupiedScheduleWeekdays,
  }) {
    return WeeklyWorkoutDetailSnapshot(
      title: title,
      dayLabel: dayLabel ?? this.dayLabel,
      planTitle: planTitle,
      editScheduleCurrentLabel:
          editScheduleCurrentLabel ?? this.editScheduleCurrentLabel,
      editSchedulePreviewLabel: editSchedulePreviewLabel,
      metrics: metrics,
      breakdown: breakdown,
      effortGuide: effortGuide,
      coachNotes: coachNotes,
      startActionLabel: startActionLabel,
      canEditSchedule: canEditSchedule,
      plannedRunContext: plannedRunContext,
      scheduleWeekdayIndex: scheduleWeekdayIndex ?? this.scheduleWeekdayIndex,
      scheduleDayLabel: scheduleDayLabel ?? this.scheduleDayLabel,
      scheduleTimeLabel: scheduleTimeLabel ?? this.scheduleTimeLabel,
      occupiedScheduleWeekdays:
          occupiedScheduleWeekdays ?? this.occupiedScheduleWeekdays,
      briefingContext: briefingContext,
    );
  }
}

/// Plan-side context carried alongside a workout detail snapshot for the AI
/// briefing. `planId` is cache-key material only and is never sent to the
/// callable — only `weekNumber` and `weekFocus` reach the prompt.
@immutable
class WorkoutBriefingContext {
  const WorkoutBriefingContext({
    required this.planId,
    required this.weekNumber,
    this.weekFocus,
  });

  final String planId;
  final int weekNumber;
  final String? weekFocus;
}

class WorkoutScheduleEditSelection {
  const WorkoutScheduleEditSelection({
    required this.weekdayIndex,
    required this.dayLabel,
    required this.timeLabel,
  });

  final int weekdayIndex;
  final String dayLabel;
  final String timeLabel;

  WeeklyWorkoutDetailSnapshot updatedDetail(
    WeeklyWorkoutDetailSnapshot snapshot,
  ) {
    final updatedOccupiedWeekdays = {
      ...snapshot.occupiedScheduleWeekdays,
      weekdayIndex,
    };
    final previousWeekday = snapshot.scheduleWeekdayIndex;
    if (previousWeekday != null && previousWeekday != weekdayIndex) {
      updatedOccupiedWeekdays.remove(previousWeekday);
    }

    return snapshot.copyWith(
      dayLabel: '$dayLabel · ${_workoutTitleFrom(snapshot.dayLabel)}',
      editScheduleCurrentLabel: '$dayLabel · $timeLabel',
      scheduleWeekdayIndex: weekdayIndex,
      scheduleDayLabel: dayLabel,
      scheduleTimeLabel: timeLabel,
      occupiedScheduleWeekdays: updatedOccupiedWeekdays,
    );
  }
}

String _workoutTitleFrom(String dayLabel) {
  final separatorIndex = dayLabel.indexOf(' · ');
  if (separatorIndex == -1) {
    return dayLabel;
  }
  return dayLabel.substring(separatorIndex + 3);
}

class WorkoutMetricDisplay {
  const WorkoutMetricDisplay(this.label, this.value);

  final String label;
  final String value;
}

class WorkoutStepDisplay {
  const WorkoutStepDisplay(this.icon, this.title, this.copy);

  final IconData icon;
  final String title;
  final String copy;
}
