import 'package:flutter/material.dart';

import '../../../plan/domain/models/adaptive_plan_estimate_read_model.dart';
import '../../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import '../../../plan/domain/models/plan_family.dart';
import '../../../run/presentation/models/planned_run_context.dart';
import '../../../plan/presentation/current_session_generated_plan.dart';
import '../data/goal_plan_demo_snapshots.dart';
import '../data/weekly_workout_demo_snapshots.dart';
import '../data/you_overview_demo_snapshots.dart';

const _weeklyDisplayDayLabels = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const _generatedPlanFallbackTime = '7:30 AM';

class GeneratedYouPlanDisplay {
  const GeneratedYouPlanDisplay({
    required this.weeklyTitle,
    required this.subtitle,
    required this.progressLabel,
    required this.progressValue,
    required this.scheduleRows,
  });

  final String weeklyTitle;
  final String subtitle;
  final String progressLabel;
  final double progressValue;
  final List<YouPlanScheduleRow> scheduleRows;

  GeneratedYouPlanDisplay rescheduleWorkout(
    WeeklyWorkoutDetailSnapshot currentDetail,
    WorkoutScheduleEditSelection selection,
  ) {
    final updatedDetail = selection.updatedDetail(currentDetail);
    final sourceIndex = scheduleRows.indexWhere((row) {
      final rowDetail = row.detailSnapshot;
      return rowDetail != null &&
          (identical(rowDetail, currentDetail) ||
              (row.weekdayIndex == currentDetail.scheduleWeekdayIndex &&
                  rowDetail.title == currentDetail.title &&
                  rowDetail.planTitle == currentDetail.planTitle));
    });
    if (sourceIndex == -1) {
      return this;
    }

    final sourceRow = scheduleRows[sourceIndex];
    if (sourceRow.isPast || !sourceRow.canEditSchedule) {
      return this;
    }
    final targetIndex = scheduleRows.indexWhere(
      (row) => row.weekdayIndex == selection.weekdayIndex,
    );
    if (targetIndex == -1 || targetIndex == sourceIndex) {
      return this;
    }

    final targetRow = scheduleRows[targetIndex];
    if (!targetRow.isFuture) {
      return this;
    }

    final updatedRows = [...scheduleRows];
    final oldRow = scheduleRows[sourceIndex];
    updatedRows[sourceIndex] = _restRow(
      oldRow.day,
      weekdayIndex: oldRow.weekdayIndex,
      isToday: oldRow.isToday,
      isPast: oldRow.isPast,
      isFuture: oldRow.isFuture,
    );

    updatedRows[targetIndex] = YouPlanScheduleRow(
      targetRow.day,
      sourceRow.title,
      'Upcoming · ${selection.timeLabel}',
      sourceRow.icon,
      active: true,
      opensWorkoutDetail: true,
      detailSnapshot: updatedDetail,
      weekdayIndex: targetRow.weekdayIndex,
      isToday: targetRow.isToday,
      isPast: targetRow.isPast,
      isFuture: targetRow.isFuture,
      isRunningSession: true,
      canOpenDetail: true,
      canStart: targetRow.isToday,
      canEditSchedule: targetRow.isFuture,
    );

    return GeneratedYouPlanDisplay(
      weeklyTitle: weeklyTitle,
      subtitle: subtitle,
      progressLabel: progressLabel,
      progressValue: progressValue,
      scheduleRows: updatedRows,
    );
  }
}

class GeneratedPlanProgressDisplay {
  GeneratedPlanProgressDisplay({
    required Iterable<String> completedScheduledWorkoutIds,
  }) : completedScheduledWorkoutIds = Set.unmodifiable(
         completedScheduledWorkoutIds,
       );

  final Set<String> completedScheduledWorkoutIds;

  bool isCompleted(String scheduledWorkoutId) {
    return completedScheduledWorkoutIds.contains(scheduledWorkoutId);
  }
}

GoalPlanDisplaySnapshot? generatedGoalPlanDisplayFromPlan(
  GeneratedYouPlanDisplay? plan,
) {
  if (plan == null) {
    return null;
  }

  return GoalPlanDisplaySnapshot(
    title: plan.weeklyTitle,
    planName: plan.weeklyTitle,
    weekSummary: plan.subtitle,
    progressValue: plan.progressValue,
    progressPercentLabel: '',
    progressLabel: plan.progressLabel,
    currentPhaseLabel: 'Current schedule',
    currentPhase: plan.subtitle,
    showProgress: false,
    weeks: [
      GoalPlanWeekDisplaySnapshot(
        weekLabel: 'Week 1',
        title: plan.weeklyTitle,
        status: GoalPlanWeekStatus.current,
        dailyPlan: [
          for (final row in plan.scheduleRows)
            _goalPlanDailyRowFromScheduleRow(row),
        ],
      ),
    ],
  );
}

class SafetyReadinessYouPlanDisplay {
  const SafetyReadinessYouPlanDisplay({
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.readinessRows,
  });

  final String title;
  final String subtitle;
  final String statusLabel;
  final List<SafetyReadinessYouPlanRow> readinessRows;
}

class SafetyReadinessYouPlanRow {
  const SafetyReadinessYouPlanRow({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

GeneratedYouPlanDisplay? generatedYouPlanDisplayFromSnapshot(
  BeginnerAdaptivePlanSnapshot? snapshot, {
  DateTime? currentDate,
  GeneratedPlanProgressDisplay? planProgress,
  AdaptivePlanEstimateReadModel? adaptiveEstimate,
}) {
  if (snapshot == null || !isEligibleCurrentSessionGeneratedPlan(snapshot)) {
    return null;
  }

  final currentWeek = activeGeneratedPlanWeekFor(
    snapshot,
    currentDate: currentDate,
  );
  if (currentWeek == null) {
    return null;
  }
  final currentWeekdayIndex = (currentDate ?? DateTime.now()).weekday;
  final progress = _generatedPlanProgressFor(currentWeek, planProgress);
  return GeneratedYouPlanDisplay(
    weeklyTitle: snapshot.title,
    subtitle: snapshot.subtitle,
    progressLabel: 'Week ${currentWeek.weekNumber} of ${snapshot.weeks.length}',
    progressValue: progress?.value ?? 0,
    scheduleRows: _weeklyScheduleRowsFor(
      currentWeek,
      snapshot,
      currentWeekdayIndex,
      planProgress: planProgress,
      adaptiveEstimate: adaptiveEstimate,
    ),
  );
}

_GeneratedPlanProgressSummary? _generatedPlanProgressFor(
  BeginnerAdaptivePlanWeek currentWeek,
  GeneratedPlanProgressDisplay? planProgress,
) {
  if (planProgress == null) {
    return null;
  }

  final plannedWorkoutIds = {
    for (final workout in currentWeek.workouts)
      if (isGeneratedPlanSession(workout))
        _scheduledWorkoutIdFor(
          weekNumber: currentWeek.weekNumber,
          dayLabel: workout.dayLabel,
          title: workout.title,
        ),
  };
  if (plannedWorkoutIds.isEmpty) {
    return const _GeneratedPlanProgressSummary(value: 0);
  }

  final completedCount = plannedWorkoutIds
      .where(planProgress.isCompleted)
      .length;
  return _GeneratedPlanProgressSummary(
    value: completedCount / plannedWorkoutIds.length,
  );
}

class _GeneratedPlanProgressSummary {
  const _GeneratedPlanProgressSummary({required this.value});

  final double value;
}

WeeklyWorkoutDetailSnapshot? todayGeneratedWorkoutDetailFromSnapshot(
  BeginnerAdaptivePlanSnapshot? snapshot, {
  DateTime? currentDate,
  GeneratedPlanProgressDisplay? planProgress,
  AdaptivePlanEstimateReadModel? adaptiveEstimate,
}) {
  final display = generatedYouPlanDisplayFromSnapshot(
    snapshot,
    currentDate: currentDate,
    planProgress: planProgress,
    adaptiveEstimate: adaptiveEstimate,
  );
  if (display == null) {
    return null;
  }

  for (final row in display.scheduleRows) {
    if (row.isToday && row.detailSnapshot != null) {
      return row.detailSnapshot;
    }
  }
  return null;
}

PlannedRunContext? todayPlannedRunContextFromSnapshot(
  BeginnerAdaptivePlanSnapshot? snapshot, {
  DateTime? currentDate,
  GeneratedPlanProgressDisplay? planProgress,
  AdaptivePlanEstimateReadModel? adaptiveEstimate,
}) {
  final detail = todayGeneratedWorkoutDetailFromSnapshot(
    snapshot,
    currentDate: currentDate,
    planProgress: planProgress,
    adaptiveEstimate: adaptiveEstimate,
  );
  if (detail != null) {
    return detail.plannedRunContext;
  }

  final display = generatedYouPlanDisplayFromSnapshot(
    snapshot,
    currentDate: currentDate,
    planProgress: planProgress,
    adaptiveEstimate: adaptiveEstimate,
  );
  if (display == null || snapshot == null) {
    return null;
  }

  for (final row in display.scheduleRows) {
    if (row.isToday && row.title == 'Rest Day') {
      return _restDayPlannedRunContext(snapshot);
    }
  }
  return null;
}

BeginnerAdaptivePlanSnapshot? rescheduleGeneratedPlanSnapshot(
  BeginnerAdaptivePlanSnapshot snapshot,
  WeeklyWorkoutDetailSnapshot currentDetail,
  WorkoutScheduleEditSelection selection, {
  DateTime? currentDate,
}) {
  if (!isEligibleCurrentSessionGeneratedPlan(snapshot) ||
      snapshot.weeks.isEmpty) {
    return null;
  }

  final currentWeek = activeGeneratedPlanWeekFor(
    snapshot,
    currentDate: currentDate,
  );
  if (currentWeek == null) {
    return null;
  }
  final sourceIndex = currentWeek.workouts.indexWhere((workout) {
    return workout.dayLabel == currentDetail.scheduleDayLabel &&
        currentDetail.dayLabel.endsWith(workout.title);
  });
  if (sourceIndex == -1) {
    return null;
  }
  final sourceWeekdayIndex = _weekdayIndexFor(
    currentWeek.workouts[sourceIndex].dayLabel,
  );
  final currentWeekdayIndex = (currentDate ?? DateTime.now()).weekday;
  if (sourceWeekdayIndex <= currentWeekdayIndex ||
      selection.weekdayIndex <= currentWeekdayIndex) {
    return null;
  }

  final updatedWorkouts = [...currentWeek.workouts];
  final sourceWorkout = currentWeek.workouts[sourceIndex];
  updatedWorkouts[sourceIndex] = BeginnerAdaptiveWorkout(
    dayLabel: selection.dayLabel,
    title: sourceWorkout.title,
    durationMinutes: sourceWorkout.durationMinutes,
    kind: sourceWorkout.kind,
    intensity: sourceWorkout.intensity,
    description: sourceWorkout.description,
    steps: sourceWorkout.steps,
    supportiveNote: sourceWorkout.supportiveNote,
    detail: sourceWorkout.detail,
    scheduleTimeLabel: selection.timeLabel,
  );

  final updatedWeeks = [...snapshot.weeks];
  final activeWeekIndex = snapshot.weeks.indexWhere(
    (week) => week.weekNumber == currentWeek.weekNumber,
  );
  if (activeWeekIndex == -1) {
    return null;
  }
  updatedWeeks[activeWeekIndex] = BeginnerAdaptivePlanWeek(
    weekNumber: currentWeek.weekNumber,
    title: currentWeek.title,
    focus: currentWeek.focus,
    workouts: updatedWorkouts,
  );

  return BeginnerAdaptivePlanSnapshot(
    id: snapshot.id,
    title: snapshot.title,
    subtitle: snapshot.subtitle,
    planKind: snapshot.planKind,
    sourceLabel: snapshot.sourceLabel,
    startsOnDate: snapshot.startsOnDate,
    durationWeeks: snapshot.durationWeeks,
    safetyBand: snapshot.safetyBand,
    templateKind: snapshot.templateKind,
    family: snapshot.family,
    familyCategory: snapshot.familyCategory,
    familyReason: snapshot.familyReason,
    supportStyleLabel: snapshot.supportStyleLabel,
    weeklyFrequencyLabel: snapshot.weeklyFrequencyLabel,
    preferredScheduleLabel: _preferredScheduleLabelFor(updatedWorkouts),
    sessionDurationLabel: snapshot.sessionDurationLabel,
    safetyNote: snapshot.safetyNote,
    weeks: updatedWeeks,
    clientDisplayStatus: snapshot.clientDisplayStatus,
  );
}

BeginnerAdaptivePlanWeek? activeGeneratedPlanWeekFor(
  BeginnerAdaptivePlanSnapshot snapshot, {
  DateTime? currentDate,
}) {
  if (snapshot.weeks.isEmpty) {
    return null;
  }
  final startsOnDate = _dateFromPlanLabel(snapshot.startsOnDate);
  if (startsOnDate == null) {
    return snapshot.weeks.first;
  }

  final today = currentDate ?? DateTime.now();
  final elapsedDays = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(startsOnDate).inDays;
  if (elapsedDays <= 0) {
    return snapshot.weeks.first;
  }

  final activeIndex = (elapsedDays ~/ 7).clamp(0, snapshot.weeks.length - 1);
  return snapshot.weeks[activeIndex];
}

int? activeGeneratedPlanDayIndexFor(
  BeginnerAdaptivePlanSnapshot snapshot, {
  DateTime? currentDate,
}) {
  final startsOnDate = _dateFromPlanLabel(snapshot.startsOnDate);
  if (startsOnDate == null) {
    return null;
  }

  final today = currentDate ?? DateTime.now();
  final elapsedDays = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(startsOnDate).inDays;
  if (elapsedDays <= 0) {
    return 0;
  }

  return elapsedDays % 7;
}

/// Real weekday (`DateTime.monday`..`DateTime.sunday`) of the plan day that is
/// currently active.
///
/// The stage map slots stones by the workout's actual weekday label, so it needs
/// a real weekday here. Reading the raw day index as `DateTime.monday + index`
/// only lines up when the plan happens to start on a Monday.
int? activeGeneratedPlanWeekdayFor(
  BeginnerAdaptivePlanSnapshot snapshot, {
  DateTime? currentDate,
}) {
  final startsOnDate = _dateFromPlanLabel(snapshot.startsOnDate);
  final dayIndex = activeGeneratedPlanDayIndexFor(
    snapshot,
    currentDate: currentDate,
  );
  if (startsOnDate == null || dayIndex == null) {
    return null;
  }

  return startsOnDate.add(Duration(days: dayIndex)).weekday;
}

DateTime? _dateFromPlanLabel(String? value) {
  if (value == null || value.length != 10) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

SafetyReadinessYouPlanDisplay? safetyReadinessYouPlanDisplayFromSnapshot(
  BeginnerAdaptivePlanSnapshot? snapshot,
) {
  if (snapshot == null || !snapshot.isSafetyReadinessDisplay) {
    return null;
  }

  return SafetyReadinessYouPlanDisplay(
    title: snapshot.title,
    subtitle: snapshot.subtitle,
    statusLabel: 'Read-only safety display',
    readinessRows: const [
      SafetyReadinessYouPlanRow(
        title: 'Review answers',
        subtitle:
            'Check the onboarding health and symptom answers stored for this session.',
        icon: Icons.fact_check_outlined,
      ),
      SafetyReadinessYouPlanRow(
        title: 'Update answers',
        subtitle: 'Change any answer that is incomplete or no longer accurate.',
        icon: Icons.edit_note_outlined,
      ),
      SafetyReadinessYouPlanRow(
        title: 'Read non-prescriptive safety information',
        subtitle:
            'Use general safety information that avoids workout instructions.',
        icon: Icons.menu_book_outlined,
      ),
      SafetyReadinessYouPlanRow(
        title: 'Seek qualified professional guidance',
        subtitle:
            'Ask a qualified professional before choosing a running plan.',
        icon: Icons.health_and_safety_outlined,
      ),
    ],
  );
}

GoalPlanDisplaySnapshot? generatedGoalPlanDisplayFromSnapshot(
  BeginnerAdaptivePlanSnapshot? snapshot, {
  DateTime? currentDate,
  GeneratedYouPlanDisplay? currentWeekDisplay,
}) {
  if (snapshot == null || !isEligibleCurrentSessionGeneratedPlan(snapshot)) {
    return null;
  }

  final activeWeek = activeGeneratedPlanWeekFor(
    snapshot,
    currentDate: currentDate,
  );
  final currentWeekdayIndex = (currentDate ?? DateTime.now()).weekday;
  return GoalPlanDisplaySnapshot(
    title: snapshot.title,
    planName: snapshot.title,
    weekSummary:
        '${snapshot.durationWeeks} weeks · ${snapshot.weeklyFrequencyLabel}',
    progressValue: 0,
    progressPercentLabel: '',
    progressLabel: 'Generated onboarding plan',
    currentPhaseLabel: 'Preferred days',
    currentPhase: snapshot.preferredScheduleLabel,
    showProgress: false,
    weeks: [
      for (final week in snapshot.weeks)
        GoalPlanWeekDisplaySnapshot(
          weekLabel: 'Week ${week.weekNumber}',
          title: week.title,
          status: _goalPlanWeekStatusFor(
            week,
            snapshot.weeks.length,
            activeWeekNumber: activeWeek?.weekNumber,
          ),
          dailyPlan:
              activeWeek != null &&
                  week.weekNumber == activeWeek.weekNumber &&
                  currentWeekDisplay != null
              ? [
                  for (final row in currentWeekDisplay.scheduleRows)
                    _goalPlanDailyRowFromScheduleRow(row),
                ]
              : _goalPlanDailyRowsFor(
                  week,
                  snapshot,
                  currentWeekdayIndex: currentWeekdayIndex,
                  activeWeekNumber: activeWeek?.weekNumber ?? 1,
                ),
        ),
    ],
  );
}

GoalPlanDayDisplaySnapshot _goalPlanDailyRowFromScheduleRow(
  YouPlanScheduleRow row,
) {
  return GoalPlanDayDisplaySnapshot(
    weekday: _fullWeekdayLabelFor(row.day),
    workoutType: row.title,
    distanceOrTime: row.status,
    workoutDetail: row.detailSnapshot,
  );
}

GoalPlanWeekStatus _goalPlanWeekStatusFor(
  BeginnerAdaptivePlanWeek week,
  int totalWeeks, {
  int? activeWeekNumber,
}) {
  final currentWeekNumber = activeWeekNumber ?? 1;
  if (week.weekNumber == currentWeekNumber) {
    return GoalPlanWeekStatus.current;
  }
  if (week.weekNumber == totalWeeks) {
    return GoalPlanWeekStatus.goalWeek;
  }
  return GoalPlanWeekStatus.upcoming;
}

List<GoalPlanDayDisplaySnapshot> _goalPlanDailyRowsFor(
  BeginnerAdaptivePlanWeek week,
  BeginnerAdaptivePlanSnapshot snapshot, {
  required int currentWeekdayIndex,
  required int activeWeekNumber,
}) {
  final workoutsByDay = {
    for (final workout in week.workouts) workout.dayLabel: workout,
  };
  final occupiedWeekdayIndexes = {
    for (final workout in week.workouts)
      if (isGeneratedPlanSession(workout)) _weekdayIndexFor(workout.dayLabel),
  };

  return [
    for (final dayLabel in _weeklyDisplayDayLabels)
      _goalPlanDailyRowFor(
        dayLabel,
        workoutsByDay[dayLabel],
        week,
        snapshot,
        occupiedWeekdayIndexes: occupiedWeekdayIndexes,
        currentWeekdayIndex: currentWeekdayIndex,
        activeWeekNumber: activeWeekNumber,
      ),
  ];
}

GoalPlanDayDisplaySnapshot _goalPlanDailyRowFor(
  String dayLabel,
  BeginnerAdaptiveWorkout? workout,
  BeginnerAdaptivePlanWeek week,
  BeginnerAdaptivePlanSnapshot snapshot, {
  required Set<int> occupiedWeekdayIndexes,
  required int currentWeekdayIndex,
  required int activeWeekNumber,
}) {
  if (workout == null || !isGeneratedPlanSession(workout)) {
    return GoalPlanDayDisplaySnapshot(
      weekday: _fullWeekdayLabelFor(dayLabel),
      workoutType: 'Rest Day',
      distanceOrTime: 'Recovery',
    );
  }

  final weekdayIndex = _weekdayIndexFor(dayLabel);
  // Only the plan's actual active week can produce a startable "today" row.
  // Every other week's matching weekday is either already elapsed or still
  // ahead, even when its weekday label happens to match today's.
  final isCurrentWeekToday =
      week.weekNumber == activeWeekNumber &&
      weekdayIndex == currentWeekdayIndex;
  return GoalPlanDayDisplaySnapshot(
    weekday: _fullWeekdayLabelFor(dayLabel),
    workoutType: workout.title,
    distanceOrTime: '${workout.durationMinutes} min',
    workoutDetail: _workoutDetailFor(
      workout,
      snapshot,
      weekNumber: week.weekNumber,
      canStart: isCurrentWeekToday,
      canEditSchedule: !isCurrentWeekToday,
      occupiedWeekdayIndexes: occupiedWeekdayIndexes,
    ),
  );
}

List<YouPlanScheduleRow> _weeklyScheduleRowsFor(
  BeginnerAdaptivePlanWeek currentWeek,
  BeginnerAdaptivePlanSnapshot snapshot,
  int currentWeekdayIndex, {
  GeneratedPlanProgressDisplay? planProgress,
  AdaptivePlanEstimateReadModel? adaptiveEstimate,
}) {
  final workoutsByDay = {
    for (final workout in currentWeek.workouts) workout.dayLabel: workout,
  };
  final occupiedWeekdayIndexes = {
    for (final workout in currentWeek.workouts)
      if (isGeneratedPlanSession(workout)) _weekdayIndexFor(workout.dayLabel),
  };

  return [
    for (final dayLabel in _weeklyDisplayDayLabels)
      _scheduleRowForDay(
        dayLabel,
        workoutsByDay[dayLabel],
        snapshot,
        occupiedWeekdayIndexes,
        currentWeekdayIndex,
        weekNumber: currentWeek.weekNumber,
        planProgress: planProgress,
        adaptiveEstimate: adaptiveEstimate,
      ),
  ];
}

YouPlanScheduleRow _scheduleRowForDay(
  String dayLabel,
  BeginnerAdaptiveWorkout? workout,
  BeginnerAdaptivePlanSnapshot snapshot,
  Set<int> occupiedWeekdayIndexes,
  int currentWeekdayIndex, {
  required int weekNumber,
  GeneratedPlanProgressDisplay? planProgress,
  AdaptivePlanEstimateReadModel? adaptiveEstimate,
}) {
  final weekdayIndex = _weekdayIndexFor(dayLabel);
  final isToday = weekdayIndex == currentWeekdayIndex;
  final isPast = weekdayIndex < currentWeekdayIndex;
  final isFuture = weekdayIndex > currentWeekdayIndex;

  if (workout == null || !isGeneratedPlanSession(workout)) {
    return _restRow(
      dayLabel,
      weekdayIndex: weekdayIndex,
      isToday: isToday,
      isPast: isPast,
      isFuture: isFuture,
    );
  }

  final canStart = isToday;
  final canEditSchedule = isFuture;
  final scheduleTimeLabel =
      workout.scheduleTimeLabel ?? _generatedPlanFallbackTime;
  final scheduledWorkoutId = _scheduledWorkoutIdFor(
    weekNumber: weekNumber,
    dayLabel: workout.dayLabel,
    title: workout.title,
  );
  final completed = planProgress?.isCompleted(scheduledWorkoutId) ?? false;
  return YouPlanScheduleRow(
    dayLabel,
    '${workout.durationMinutes} min ${workout.title}',
    completed
        ? 'Completed'
        : isPast
        ? 'Missed'
        : 'Upcoming · $scheduleTimeLabel',
    _iconForWorkout(workout.kind),
    active: true,
    opensWorkoutDetail: true,
    detailSnapshot: _workoutDetailFor(
      workout,
      snapshot,
      weekNumber: weekNumber,
      canStart: canStart,
      canEditSchedule: canEditSchedule,
      alreadyCompletedToday: completed && isToday,
      keepPlannedRunContext: completed && isToday,
      adaptiveEstimate: adaptiveEstimate,
      occupiedWeekdayIndexes: {
        ...occupiedWeekdayIndexes,
        for (var day = DateTime.monday; day <= currentWeekdayIndex; day++) day,
      },
    ),
    weekdayIndex: weekdayIndex,
    isToday: isToday,
    isPast: isPast,
    isFuture: isFuture,
    isRunningSession: true,
    canOpenDetail: true,
    canStart: canStart && !completed,
    canEditSchedule: canEditSchedule && !completed,
  );
}

YouPlanScheduleRow _restRow(
  String dayLabel, {
  required int weekdayIndex,
  required bool isToday,
  required bool isPast,
  required bool isFuture,
}) {
  return YouPlanScheduleRow(
    dayLabel,
    'Rest Day',
    '',
    Icons.hotel_outlined,
    weekdayIndex: weekdayIndex,
    isToday: isToday,
    isPast: isPast,
    isFuture: isFuture,
  );
}

WeeklyWorkoutDetailSnapshot _workoutDetailFor(
  BeginnerAdaptiveWorkout workout,
  BeginnerAdaptivePlanSnapshot snapshot, {
  required int weekNumber,
  required bool canStart,
  required bool canEditSchedule,
  bool alreadyCompletedToday = false,
  bool keepPlannedRunContext = false,
  AdaptivePlanEstimateReadModel? adaptiveEstimate,
  Set<int> occupiedWeekdayIndexes = const <int>{},
}) {
  final canStartPlannedRun =
      (canStart || keepPlannedRunContext) && snapshot.canStartPlannedRun;
  final canEditGeneratedSchedule =
      canEditSchedule && snapshot.canStartPlannedRun;

  return WeeklyWorkoutDetailSnapshot(
    title: 'Workout detail',
    dayLabel: '${workout.dayLabel} · ${workout.title}',
    planTitle: snapshot.title,
    editScheduleCurrentLabel:
        '${workout.dayLabel} · ${workout.scheduleTimeLabel ?? _generatedPlanFallbackTime}',
    editSchedulePreviewLabel: 'Preview only',
    scheduleWeekdayIndex: _weekdayIndexFor(workout.dayLabel),
    scheduleDayLabel: workout.dayLabel,
    scheduleTimeLabel: workout.scheduleTimeLabel ?? _generatedPlanFallbackTime,
    occupiedScheduleWeekdays: occupiedWeekdayIndexes,
    metrics: [
      for (final metric in workout.detail.metrics)
        WorkoutMetricDisplay(metric.label, metric.value),
    ],
    breakdown: [
      for (final step in workout.detail.breakdown) _stepDisplayFor(step),
    ],
    effortGuide: workout.detail.effortGuide,
    coachNotes: [...workout.detail.coachNotes, snapshot.safetyNote],
    briefingContext: WorkoutBriefingContext(
      planId: snapshot.id,
      weekNumber: weekNumber,
      weekFocus: _weekFocusFor(snapshot, weekNumber),
    ),
    startActionLabel: canStartPlannedRun && !alreadyCompletedToday
        ? 'Start this run'
        : null,
    canEditSchedule: canEditGeneratedSchedule,
    plannedRunContext: canStartPlannedRun
        ? _plannedRunContextFor(
            workout,
            snapshot,
            weekNumber: weekNumber,
            alreadyCompletedToday: alreadyCompletedToday,
            adaptiveEstimate: adaptiveEstimate,
          )
        : null,
  );
}

/// The week's focus line, which the detail screen never renders but the AI
/// briefing uses to say what this week is building toward.
String? _weekFocusFor(BeginnerAdaptivePlanSnapshot snapshot, int weekNumber) {
  for (final week in snapshot.weeks) {
    if (week.weekNumber == weekNumber) {
      return week.focus.trim().isEmpty ? null : week.focus;
    }
  }
  return null;
}

String _preferredScheduleLabelFor(List<BeginnerAdaptiveWorkout> workouts) {
  return [
    for (final workout in workouts)
      if (isGeneratedPlanSession(workout)) workout.dayLabel,
  ].join(' · ');
}

PlannedRunContext _plannedRunContextFor(
  BeginnerAdaptiveWorkout workout,
  BeginnerAdaptivePlanSnapshot snapshot, {
  required int weekNumber,
  bool alreadyCompletedToday = false,
  AdaptivePlanEstimateReadModel? adaptiveEstimate,
}) {
  final workoutKindLabel = _kindLabel(workout.kind);
  final intensityLabel = _intensityLabel(workout.intensity);
  final distanceLabel = adaptiveEstimate?.distanceLabelForDurationMinutes(
    workout.durationMinutes,
  );
  final targetDistanceMeters = adaptiveEstimate
      ?.targetDistanceMetersForDurationMinutes(workout.durationMinutes);

  return PlannedRunContext(
    title: workout.title,
    durationMinutes: workout.durationMinutes,
    planTitle: snapshot.title,
    planFamilyLabel: snapshot.family?.title ?? snapshot.sourceLabel,
    workoutKindLabel: workoutKindLabel,
    intensityLabel: intensityLabel,
    steps: workout.steps,
    supportiveNote: workout.supportiveNote,
    sourceLabel: 'Generated onboarding plan',
    objectiveKind: PlannedRunObjectiveKind.duration,
    primaryValueLabel: '${workout.durationMinutes} min',
    primaryUnitLabel: workoutKindLabel.toLowerCase(),
    estimatedDistanceLabel: distanceLabel,
    estimateConfidence: _plannedRunConfidenceFor(adaptiveEstimate),
    targetDistanceMeters: targetDistanceMeters,
    planEnrollmentId: snapshot.id,
    scheduledWorkoutId: _scheduledWorkoutIdFor(
      weekNumber: weekNumber,
      dayLabel: workout.dayLabel,
      title: workout.title,
    ),
    alreadyCompletedToday: alreadyCompletedToday,
  );
}

PlannedRunEstimateConfidence _plannedRunConfidenceFor(
  AdaptivePlanEstimateReadModel? adaptiveEstimate,
) {
  return switch (adaptiveEstimate?.estimateConfidence) {
    AdaptivePlanEstimateConfidence.low => PlannedRunEstimateConfidence.low,
    AdaptivePlanEstimateConfidence.medium =>
      PlannedRunEstimateConfidence.medium,
    AdaptivePlanEstimateConfidence.none ||
    null => PlannedRunEstimateConfidence.none,
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

PlannedRunContext _restDayPlannedRunContext(
  BeginnerAdaptivePlanSnapshot snapshot,
) {
  return PlannedRunContext(
    title: 'Today\'s plan',
    durationMinutes: 0,
    planTitle: snapshot.title,
    planFamilyLabel: snapshot.family?.title ?? snapshot.sourceLabel,
    workoutKindLabel: 'Rest day',
    intensityLabel: 'Recovery',
    steps: const ['Rest or light mobility.'],
    supportiveNote: 'Let the body absorb the week.',
    sourceLabel: 'Generated onboarding plan',
    objectiveKind: PlannedRunObjectiveKind.restDay,
    primaryValueLabel: 'Rest day',
    primaryUnitLabel: '',
    supportLabel: 'Recovery today · no run target',
    secondarySupportLabel: 'Optional easy run only if you feel fresh',
  );
}

int _weekdayIndexFor(String dayLabel) {
  final index = _weeklyDisplayDayLabels.indexOf(dayLabel);
  if (index == -1) {
    return 0;
  }
  return index + DateTime.monday;
}

String _fullWeekdayLabelFor(String dayLabel) {
  return switch (dayLabel) {
    'Mon' => 'Monday',
    'Tue' => 'Tuesday',
    'Wed' => 'Wednesday',
    'Thu' => 'Thursday',
    'Fri' => 'Friday',
    'Sat' => 'Saturday',
    'Sun' => 'Sunday',
    _ => dayLabel,
  };
}

WorkoutStepDisplay _stepDisplayFor(BeginnerAdaptiveWorkoutBreakdownStep step) {
  return WorkoutStepDisplay(_iconForStep(step.kind), step.title, step.detail);
}

IconData _iconForStep(BeginnerAdaptiveWorkoutBreakdownStepKind kind) {
  return switch (kind) {
    BeginnerAdaptiveWorkoutBreakdownStepKind.walk => Icons.directions_walk,
    BeginnerAdaptiveWorkoutBreakdownStepKind.run => Icons.directions_run,
    BeginnerAdaptiveWorkoutBreakdownStepKind.mobility => Icons.self_improvement,
  };
}

IconData _iconForWorkout(BeginnerWorkoutKind kind) {
  return switch (kind) {
    BeginnerWorkoutKind.recoveryWalk => Icons.directions_walk,
    BeginnerWorkoutKind.restOrMobility => Icons.self_improvement,
    _ => Icons.directions_run,
  };
}

String _kindLabel(BeginnerWorkoutKind kind) {
  return switch (kind) {
    BeginnerWorkoutKind.easyRun => 'Easy run',
    BeginnerWorkoutKind.runWalk => 'Run-walk',
    BeginnerWorkoutKind.walkRun => 'Walk-run',
    BeginnerWorkoutKind.recoveryWalk => 'Recovery walk',
    BeginnerWorkoutKind.steadyRun => 'Steady run',
    BeginnerWorkoutKind.controlledSteadyRun => 'Controlled steady run',
    BeginnerWorkoutKind.longerEasyRun => 'Longer easy run',
    BeginnerWorkoutKind.recoveryRun => 'Recovery run',
    BeginnerWorkoutKind.restOrMobility => 'Rest or mobility',
  };
}

String _intensityLabel(BeginnerPlanIntensity intensity) {
  return switch (intensity) {
    BeginnerPlanIntensity.veryGentle => 'Very gentle',
    BeginnerPlanIntensity.gentle => 'Gentle',
    BeginnerPlanIntensity.balanced => 'Balanced',
  };
}
