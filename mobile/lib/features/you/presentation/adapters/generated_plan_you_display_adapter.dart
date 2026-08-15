import 'package:flutter/material.dart';

import '../../../plan/domain/models/adaptive_plan_estimate_read_model.dart';
import '../../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import '../../../plan/domain/models/plan_family.dart';
import '../../../plan/domain/services/generated_plan_schedule.dart';
import '../../../run/presentation/models/planned_run_context.dart';
import '../../../plan/presentation/current_session_generated_plan.dart';
import '../data/goal_plan_demo_snapshots.dart';
import '../data/weekly_workout_demo_snapshots.dart';
import '../data/you_overview_demo_snapshots.dart';

/// Weekly schedule rows are laid out on the **calendar** week (Mon..Sun) the
/// runner is currently in, and each row is filled from the plan by date.
///
/// A plan runs for seven days from whatever day onboarding finished, so a plan
/// week and a calendar week only coincide for Monday-start plans. Comparing raw
/// weekday numbers to decide past/today/future — what this file used to do —
/// therefore called a Saturday-start plan's Monday session "Missed" on the day
/// it was created, every week, while the notification builder was already
/// scheduling that same session correctly for the following Monday. Dates are
/// the only thing both sides agree on, so dates are what these rows use.
const _generatedPlanFallbackTime = '7:30 AM';

class GeneratedYouPlanDisplay {
  const GeneratedYouPlanDisplay({
    required this.weeklyTitle,
    required this.subtitle,
    required this.progressLabel,
    required this.progressValue,
    required this.scheduleRows,
    this.planWeekRangeLabel = '',
    this.calendarWeekRangeLabel = '',
  });

  final String weeklyTitle;
  final String subtitle;

  /// Plan-week progress, e.g. `Week 1 of 4`. Deliberately scoped to the plan
  /// week, not the calendar week the rows below show.
  final String progressLabel;
  final double progressValue;
  final List<YouPlanScheduleRow> scheduleRows;

  /// Dates the plan week behind [progressLabel]/[progressValue] covers.
  ///
  /// Shown next to the progress label because on a mid-week-start plan the
  /// counted sessions can all sit outside the seven rows on screen — a
  /// Saturday signup reads `Week 1 of 4 · 15–21 Aug` while the rows below it
  /// cover 10–16 Aug.
  final String planWeekRangeLabel;

  /// Dates the seven [scheduleRows] cover.
  final String calendarWeekRangeLabel;

  /// Session-local echo of a schedule edit, so the week view updates before the
  /// persisted plan round-trips.
  ///
  /// The move is authorized on **dates**, not weekday order: the target is the
  /// date the workout's own plan week assigns to [selection]'s weekday. That
  /// date is not always on screen — a Saturday-start plan editing a Sunday
  /// session can move it to a Monday that belongs to the same plan week but the
  /// next calendar week — in which case the source row simply clears and the
  /// workout reappears when the rows roll over.
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
    if (!targetRow.isFuture || targetRow.isOutsidePlan) {
      return this;
    }

    final updatedRows = [...scheduleRows];
    updatedRows[sourceIndex] = _restRow(
      sourceRow.day,
      date: sourceRow.date,
      weekdayIndex: sourceRow.weekdayIndex,
      planWeekNumber: sourceRow.planWeekNumber,
      isToday: sourceRow.isToday,
      isPast: sourceRow.isPast,
      isFuture: sourceRow.isFuture,
    );

    updatedRows[targetIndex] = YouPlanScheduleRow(
      targetRow.day,
      sourceRow.title,
      'Upcoming · ${selection.timeLabel}',
      sourceRow.icon,
      active: true,
      opensWorkoutDetail: true,
      detailSnapshot: updatedDetail,
      date: targetRow.date,
      planWeekNumber: targetRow.planWeekNumber,
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
      planWeekRangeLabel: planWeekRangeLabel,
      calendarWeekRangeLabel: calendarWeekRangeLabel,
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
  final today = generatedPlanDateOnly(currentDate ?? DateTime.now());
  final anchor = generatedPlanAnchorDate(snapshot, today: today);
  final schedule = generatedPlanScheduleByDate(snapshot, start: anchor);
  final calendarWeekDates = calendarWeekDatesFor(today);
  final planWeekStart = generatedPlanAddDays(
    anchor,
    (currentWeek.weekNumber - 1) * kGeneratedPlanDaysPerWeek,
  );
  final progress = _generatedPlanProgressFor(currentWeek, planProgress);
  return GeneratedYouPlanDisplay(
    weeklyTitle: snapshot.title,
    subtitle: snapshot.subtitle,
    progressLabel: 'Week ${currentWeek.weekNumber} of ${snapshot.weeks.length}',
    progressValue: progress?.value ?? 0,
    planWeekRangeLabel: _dateRangeLabel(
      planWeekStart,
      generatedPlanAddDays(planWeekStart, kGeneratedPlanDaysPerWeek - 1),
    ),
    calendarWeekRangeLabel: _dateRangeLabel(
      calendarWeekDates.first,
      calendarWeekDates.last,
    ),
    scheduleRows: [
      for (final date in calendarWeekDates)
        _scheduleRowForDate(
          date: date,
          planDay: schedule[date],
          snapshot: snapshot,
          today: today,
          anchor: anchor,
          planProgress: planProgress,
          adaptiveEstimate: adaptiveEstimate,
        ),
    ],
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
        generatedPlanScheduledWorkoutId(
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
  // Both ends are judged as dates inside this plan week's own seven-day window.
  // Weekday order would say a Saturday-start plan cannot move anything to the
  // coming Monday, because Monday sorts before Saturday.
  final today = generatedPlanDateOnly(currentDate ?? DateTime.now());
  final anchor = generatedPlanAnchorDate(snapshot, today: today);
  final sourceDate = generatedPlanScheduledDate(
    start: anchor,
    weekNumber: currentWeek.weekNumber,
    dayLabel: currentWeek.workouts[sourceIndex].dayLabel,
  );
  final targetDate = generatedPlanScheduledDate(
    start: anchor,
    weekNumber: currentWeek.weekNumber,
    dayLabel: selection.dayLabel,
  );
  if (sourceDate == null ||
      targetDate == null ||
      !sourceDate.isAfter(today) ||
      !targetDate.isAfter(today)) {
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
  final elapsedDays = generatedPlanDaysBetween(startsOnDate, today);
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
  final elapsedDays = generatedPlanDaysBetween(startsOnDate, today);
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

  return generatedPlanAddDays(startsOnDate, dayIndex).weekday;
}

DateTime? _dateFromPlanLabel(String? value) =>
    generatedPlanDateFromLabel(value);

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

/// The whole plan, week by week.
///
/// Unlike the weekly card this stays on **plan** weeks: each row is the plan's
/// own seven-day window, ordered from the day the plan starts on, so a
/// four-week plan is four rows of seven days with no blanks at either end.
GoalPlanDisplaySnapshot? generatedGoalPlanDisplayFromSnapshot(
  BeginnerAdaptivePlanSnapshot? snapshot, {
  DateTime? currentDate,
}) {
  if (snapshot == null || !isEligibleCurrentSessionGeneratedPlan(snapshot)) {
    return null;
  }

  final activeWeek = activeGeneratedPlanWeekFor(
    snapshot,
    currentDate: currentDate,
  );
  final today = generatedPlanDateOnly(currentDate ?? DateTime.now());
  final anchor = generatedPlanAnchorDate(snapshot, today: today);
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
          dateRangeLabel: _planWeekRangeLabelFor(
            anchor: anchor,
            weekNumber: week.weekNumber,
          ),
          dailyPlan: _goalPlanDailyRowsFor(
            week,
            snapshot,
            anchor: anchor,
            today: today,
          ),
        ),
    ],
  );
}

String _planWeekRangeLabelFor({
  required DateTime anchor,
  required int weekNumber,
}) {
  final start = generatedPlanAddDays(
    anchor,
    (weekNumber - 1) * kGeneratedPlanDaysPerWeek,
  );
  return _dateRangeLabel(
    start,
    generatedPlanAddDays(start, kGeneratedPlanDaysPerWeek - 1),
  );
}

GoalPlanDayDisplaySnapshot _goalPlanDailyRowFromScheduleRow(
  YouPlanScheduleRow row,
) {
  final date = row.date;
  return GoalPlanDayDisplaySnapshot(
    weekday: _fullWeekdayLabelFor(row.day),
    workoutType: row.isOutsidePlan ? '' : row.title,
    distanceOrTime: row.status,
    dateLabel: date == null ? '' : _dayLabelFor(date),
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
  if (week.weekNumber < currentWeekNumber) {
    return GoalPlanWeekStatus.completed;
  }
  if (week.weekNumber == totalWeeks) {
    return GoalPlanWeekStatus.goalWeek;
  }
  return GoalPlanWeekStatus.upcoming;
}

List<GoalPlanDayDisplaySnapshot> _goalPlanDailyRowsFor(
  BeginnerAdaptivePlanWeek week,
  BeginnerAdaptivePlanSnapshot snapshot, {
  required DateTime anchor,
  required DateTime today,
}) {
  final workoutsByDay = {
    for (final workout in week.workouts) workout.dayLabel: workout,
  };
  final occupiedWeekdayIndexes = _occupiedScheduleWeekdaysFor(
    snapshot,
    weekNumber: week.weekNumber,
    anchor: anchor,
    today: today,
  );

  // Ordered from the day the plan starts on, so the seven rows read in the
  // order they will actually be run.
  return [
    for (var offset = 0; offset < kGeneratedPlanDaysPerWeek; offset++)
      () {
        final date = generatedPlanAddDays(
          anchor,
          (week.weekNumber - 1) * kGeneratedPlanDaysPerWeek + offset,
        );
        final dayLabel = generatedPlanWeekdayLabelOf(date);
        return _goalPlanDailyRowFor(
          dayLabel,
          workoutsByDay[dayLabel],
          week,
          snapshot,
          date: date,
          today: today,
          occupiedWeekdayIndexes: occupiedWeekdayIndexes,
        );
      }(),
  ];
}

GoalPlanDayDisplaySnapshot _goalPlanDailyRowFor(
  String dayLabel,
  BeginnerAdaptiveWorkout? workout,
  BeginnerAdaptivePlanWeek week,
  BeginnerAdaptivePlanSnapshot snapshot, {
  required DateTime date,
  required DateTime today,
  required Set<int> occupiedWeekdayIndexes,
}) {
  if (workout == null || !isGeneratedPlanSession(workout)) {
    return GoalPlanDayDisplaySnapshot(
      weekday: _fullWeekdayLabelFor(dayLabel),
      workoutType: 'Rest Day',
      distanceOrTime: 'Recovery',
      dateLabel: _dayLabelFor(date),
    );
  }

  // A row is startable only on the exact calendar date it falls on. The same
  // weekday in another plan week is a different date, so it never qualifies.
  final isToday = date == today;
  return GoalPlanDayDisplaySnapshot(
    weekday: _fullWeekdayLabelFor(dayLabel),
    workoutType: workout.title,
    distanceOrTime: '${workout.durationMinutes} min',
    dateLabel: _dayLabelFor(date),
    workoutDetail: _workoutDetailFor(
      workout,
      snapshot,
      weekNumber: week.weekNumber,
      canStart: isToday,
      canEditSchedule: date.isAfter(today),
      occupiedWeekdayIndexes: occupiedWeekdayIndexes,
    ),
  );
}

String _dayLabelFor(DateTime date) {
  return '${date.day} ${_shortMonthLabels[date.month - 1]}';
}

YouPlanScheduleRow _scheduleRowForDate({
  required DateTime date,
  required GeneratedPlanScheduledDay? planDay,
  required BeginnerAdaptivePlanSnapshot snapshot,
  required DateTime today,
  required DateTime anchor,
  GeneratedPlanProgressDisplay? planProgress,
  AdaptivePlanEstimateReadModel? adaptiveEstimate,
}) {
  final dayLabel = generatedPlanWeekdayLabelOf(date);
  final weekdayIndex = date.weekday;
  final isToday = date == today;
  final isPast = date.isBefore(today);
  final isFuture = date.isAfter(today);

  // No plan day at all: this calendar date falls before the plan started or
  // after it ends. It is neither a session nor a rest day, so it stays blank.
  if (planDay == null) {
    return _outsidePlanRow(
      dayLabel,
      date: date,
      weekdayIndex: weekdayIndex,
      isToday: isToday,
      isPast: isPast,
      isFuture: isFuture,
    );
  }

  final workout = planDay.workout;
  final scheduledWorkoutId = planDay.scheduledWorkoutId;
  if (workout == null || scheduledWorkoutId == null) {
    return _restRow(
      dayLabel,
      date: date,
      weekdayIndex: weekdayIndex,
      planWeekNumber: planDay.weekNumber,
      isToday: isToday,
      isPast: isPast,
      isFuture: isFuture,
    );
  }

  final canStart = isToday;
  final canEditSchedule = isFuture;
  final scheduleTimeLabel =
      workout.scheduleTimeLabel ?? _generatedPlanFallbackTime;
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
      weekNumber: planDay.weekNumber,
      canStart: canStart,
      canEditSchedule: canEditSchedule,
      alreadyCompletedToday: completed && isToday,
      keepPlannedRunContext: completed && isToday,
      adaptiveEstimate: adaptiveEstimate,
      occupiedWeekdayIndexes: _occupiedScheduleWeekdaysFor(
        snapshot,
        weekNumber: planDay.weekNumber,
        anchor: anchor,
        today: today,
      ),
    ),
    date: date,
    planWeekNumber: planDay.weekNumber,
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

/// Weekdays the schedule editor must refuse for a workout in [weekNumber].
///
/// Two reasons a weekday is unavailable, and both have to be judged inside that
/// plan week's own seven-day window: another session already owns it, or the
/// date it maps to has already been reached. The second used to be "every
/// weekday up to today's weekday number", which on a Saturday marked the coming
/// Monday — two days away — as past.
Set<int> _occupiedScheduleWeekdaysFor(
  BeginnerAdaptivePlanSnapshot snapshot, {
  required int weekNumber,
  required DateTime anchor,
  required DateTime today,
}) {
  final occupied = <int>{};
  for (final week in snapshot.weeks) {
    if (week.weekNumber != weekNumber) {
      continue;
    }
    for (final workout in week.workouts) {
      if (!isGeneratedPlanSession(workout)) {
        continue;
      }
      final offset = generatedPlanWeekdayOffsetFor(workout.dayLabel);
      if (offset != null) {
        occupied.add(offset + DateTime.monday);
      }
    }
  }
  for (var offset = 0; offset < kGeneratedPlanDaysPerWeek; offset++) {
    final date = generatedPlanScheduledDate(
      start: anchor,
      weekNumber: weekNumber,
      dayLabel: kGeneratedPlanWeekdayLabels[offset],
    );
    if (date != null && !date.isAfter(today)) {
      occupied.add(offset + DateTime.monday);
    }
  }
  return occupied;
}

YouPlanScheduleRow _restRow(
  String dayLabel, {
  required DateTime? date,
  required int weekdayIndex,
  required int? planWeekNumber,
  required bool isToday,
  required bool isPast,
  required bool isFuture,
}) {
  return YouPlanScheduleRow(
    dayLabel,
    'Rest Day',
    '',
    Icons.hotel_outlined,
    date: date,
    planWeekNumber: planWeekNumber,
    weekdayIndex: weekdayIndex,
    isToday: isToday,
    isPast: isPast,
    isFuture: isFuture,
  );
}

/// A calendar day the plan does not cover.
///
/// Kept visually distinct from a rest day on purpose: a rest day is the plan
/// working, an uncovered day is the plan not having started (or having ended).
YouPlanScheduleRow _outsidePlanRow(
  String dayLabel, {
  required DateTime date,
  required int weekdayIndex,
  required bool isToday,
  required bool isPast,
  required bool isFuture,
}) {
  return YouPlanScheduleRow(
    dayLabel,
    '',
    '',
    Icons.remove,
    date: date,
    weekdayIndex: weekdayIndex,
    isToday: isToday,
    isPast: isPast,
    isFuture: isFuture,
    isOutsidePlan: true,
  );
}

String _dateRangeLabel(DateTime start, DateTime end) {
  if (start.month == end.month) {
    return '${start.day}–${end.day} ${_shortMonthLabels[end.month - 1]}';
  }
  return '${start.day} ${_shortMonthLabels[start.month - 1]} – '
      '${end.day} ${_shortMonthLabels[end.month - 1]}';
}

const _shortMonthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

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
    scheduledWorkoutId: generatedPlanScheduledWorkoutId(
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
  final offset = generatedPlanWeekdayOffsetFor(dayLabel);
  if (offset == null) {
    return 0;
  }
  return offset + DateTime.monday;
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
