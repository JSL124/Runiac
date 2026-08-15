/// Resolves a generated plan onto real calendar dates.
///
/// A plan is a run of `durationWeeks * 7` consecutive days starting on
/// `startsOnDate`, which is whatever day onboarding finished — it is never
/// snapped to a Monday. Workout `dayLabel`s, by contrast, denote real weekdays,
/// because they come from the days the runner picked in onboarding. Plan week N
/// therefore runs for seven days from the start, and a label resolves to the one
/// date in that window whose actual weekday matches:
///
/// ```
/// dayOffset = (weekdayOffset(dayLabel) - weekdayOffset(startsOnDate) + 7) % 7
/// date      = startsOnDate + (weekNumber - 1) * 7 + dayOffset
/// ```
///
/// This is the same formula the backend uses in
/// `functions/src/plan/planProgressParsing.ts` (`scheduledDateFor`), which feeds
/// plan progress, plan-bounded streaks and scheduled push notifications. Both
/// sides must agree on which calendar date a workout belongs to, so this file is
/// the only place the client is allowed to derive it. For a Monday-start plan the
/// arithmetic is a no-op, which is why the historical "offset 0 means Monday"
/// reading went unnoticed until someone onboarded mid-week.
library;

import '../../presentation/current_session_generated_plan.dart'
    show isGeneratedPlanSession;
import '../models/beginner_adaptive_plan_snapshot.dart';

/// Canonical 3-letter English weekday labels, Monday-first, matching the labels
/// onboarding writes onto generated-plan workouts.
const List<String> kGeneratedPlanWeekdayLabels = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Number of day slots in one plan week.
const int kGeneratedPlanDaysPerWeek = 7;

/// One dated day of a generated plan.
///
/// [workout] is null for a day the plan covers but does not schedule a running
/// session on (a rest day). Days outside the plan's date range produce no entry
/// at all, so callers can tell "rest day" apart from "not in the plan".
class GeneratedPlanScheduledDay {
  const GeneratedPlanScheduledDay({
    required this.date,
    required this.weekNumber,
    required this.dayOffset,
    required this.dayLabel,
    this.workout,
    this.scheduledWorkoutId,
  });

  /// Midnight-normalized calendar date this plan day falls on.
  final DateTime date;

  /// Plan week (1-based) this day belongs to.
  final int weekNumber;

  /// Position of this day inside its plan week (0 = the plan's start weekday).
  final int dayOffset;

  /// Real weekday label of [date] (`'Mon'`..`'Sun'`).
  final String dayLabel;

  /// The running session scheduled on this date, or null on a rest day.
  final BeginnerAdaptiveWorkout? workout;

  /// Backend-matching id of [workout], or null on a rest day.
  final String? scheduledWorkoutId;

  bool get isRunningSession => workout != null;
}

/// Mon=0..Sun=6 index of [dayLabel], or null when it is not a weekday label
/// (e.g. the synthetic `'Day 1'` fallback the generator emits when onboarding
/// collected no preferred days).
int? generatedPlanWeekdayOffsetFor(String dayLabel) {
  final normalized = dayLabel.trim().toLowerCase();
  for (var index = 0; index < kGeneratedPlanWeekdayLabels.length; index++) {
    if (kGeneratedPlanWeekdayLabels[index].toLowerCase() == normalized) {
      return index;
    }
  }
  return null;
}

/// Mon=0..Sun=6 index of [date]'s weekday.
int generatedPlanWeekdayOffsetOf(DateTime date) {
  return date.weekday - DateTime.monday;
}

/// Weekday label (`'Mon'`..`'Sun'`) of [date].
String generatedPlanWeekdayLabelOf(DateTime date) {
  return kGeneratedPlanWeekdayLabels[generatedPlanWeekdayOffsetOf(date)];
}

/// Strips the time component so two dates can be compared as calendar days.
DateTime generatedPlanDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// Moves [date] by whole calendar days.
///
/// Deliberately not `add(Duration(days: n))`: a duration is absolute time, so
/// across a daylight-saving change it lands on 23:00 or 01:00 rather than
/// midnight. These dates are used as map keys and compared with `==`, so an
/// hour of drift would silently stop a day from matching its own schedule
/// entry for every runner in a DST timezone.
DateTime generatedPlanAddDays(DateTime date, int days) {
  return DateTime(date.year, date.month, date.day + days);
}

/// Whole calendar days from [from] to [to], for the same reason as
/// [generatedPlanAddDays]: `to.difference(from).inDays` counts elapsed absolute
/// time, so a 23-hour spring-forward day reports 0 for two adjacent dates.
int generatedPlanDaysBetween(DateTime from, DateTime to) {
  final fromDay = DateTime.utc(from.year, from.month, from.day);
  final toDay = DateTime.utc(to.year, to.month, to.day);
  return toDay.difference(fromDay).inDays;
}

/// Parses `startsOnDate` (a `yyyy-MM-dd` label) into a midnight local date.
DateTime? generatedPlanStartDate(BeginnerAdaptivePlanSnapshot snapshot) {
  return generatedPlanDateFromLabel(snapshot.startsOnDate);
}

/// Date every other calculation here anchors on.
///
/// Onboarding always stamps `startsOnDate`, so in production this is simply the
/// day the plan was generated. Fixtures and demo snapshots can omit it; those
/// fall back to the Monday of [today]'s calendar week, which makes plan week 1
/// coincide with the current calendar week. That is the same fallback
/// `GeneratedPlanNotificationScheduleBuilder` has always used, and it keeps
/// undated plans rendering exactly as they did before dates were introduced.
DateTime generatedPlanAnchorDate(
  BeginnerAdaptivePlanSnapshot snapshot, {
  required DateTime today,
}) {
  final start = generatedPlanStartDate(snapshot);
  if (start != null) {
    return start;
  }
  final day = generatedPlanDateOnly(today);
  return generatedPlanAddDays(day, -generatedPlanWeekdayOffsetOf(day));
}

/// Parses a `yyyy-MM-dd` plan date label, returning null for anything else.
DateTime? generatedPlanDateFromLabel(String? value) {
  if (value == null || value.length != 10) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Last calendar date the plan covers, inclusive.
///
/// A four-week plan started on a Saturday ends 27 days later, on a Friday.
DateTime? generatedPlanLastDate(
  BeginnerAdaptivePlanSnapshot snapshot, {
  required DateTime start,
}) {
  if (snapshot.weeks.isEmpty) {
    return null;
  }
  final days = snapshot.weeks.length * kGeneratedPlanDaysPerWeek;
  return generatedPlanAddDays(start, days - 1);
}

/// Position of [dayLabel] inside a plan week that starts on [start], or null
/// when [dayLabel] is not a real weekday.
int? generatedPlanDayOffsetFor({
  required DateTime start,
  required String dayLabel,
}) {
  final weekdayOffset = generatedPlanWeekdayOffsetFor(dayLabel);
  if (weekdayOffset == null) {
    return null;
  }
  return (weekdayOffset - generatedPlanWeekdayOffsetOf(start) + 7) % 7;
}

/// Calendar date that week [weekNumber]'s [dayLabel] falls on.
///
/// Mirrors `scheduledDateFor` in `functions/src/plan/planProgressParsing.ts`.
DateTime? generatedPlanScheduledDate({
  required DateTime start,
  required int weekNumber,
  required String dayLabel,
}) {
  final dayOffset = generatedPlanDayOffsetFor(start: start, dayLabel: dayLabel);
  if (dayOffset == null) {
    return null;
  }
  return generatedPlanAddDays(
    start,
    (weekNumber - 1) * kGeneratedPlanDaysPerWeek + dayOffset,
  );
}

/// Every date the plan covers, keyed by calendar date.
///
/// Covers the plan's whole range, so rest days appear as entries with a null
/// workout and only dates outside the plan are absent. Two workouts can never
/// collide on a date: each plan week's seven-day window contains each weekday
/// exactly once, so distinct labels inside a week map to distinct dates. A plan
/// that does repeat a label within one week keeps the first workout, matching
/// the order the generator emitted them.
Map<DateTime, GeneratedPlanScheduledDay> generatedPlanScheduleByDate(
  BeginnerAdaptivePlanSnapshot snapshot, {
  required DateTime start,
}) {
  if (snapshot.weeks.isEmpty) {
    return const <DateTime, GeneratedPlanScheduledDay>{};
  }

  final schedule = <DateTime, GeneratedPlanScheduledDay>{};
  for (final week in snapshot.weeks) {
    for (var dayOffset = 0; dayOffset < kGeneratedPlanDaysPerWeek; dayOffset++) {
      final date = generatedPlanAddDays(
        start,
        (week.weekNumber - 1) * kGeneratedPlanDaysPerWeek + dayOffset,
      );
      schedule[date] = GeneratedPlanScheduledDay(
        date: date,
        weekNumber: week.weekNumber,
        dayOffset: dayOffset,
        dayLabel: generatedPlanWeekdayLabelOf(date),
      );
    }

    for (final workout in week.workouts) {
      if (!isGeneratedPlanSession(workout)) {
        continue;
      }
      final date = generatedPlanScheduledDate(
        start: start,
        weekNumber: week.weekNumber,
        dayLabel: workout.dayLabel,
      );
      final slot = date == null ? null : schedule[date];
      if (date == null || slot == null || slot.isRunningSession) {
        continue;
      }
      schedule[date] = GeneratedPlanScheduledDay(
        date: date,
        weekNumber: slot.weekNumber,
        dayOffset: slot.dayOffset,
        dayLabel: slot.dayLabel,
        workout: workout,
        scheduledWorkoutId: generatedPlanScheduledWorkoutId(
          weekNumber: week.weekNumber,
          dayLabel: workout.dayLabel,
          title: workout.title,
        ),
      );
    }
  }
  return schedule;
}

/// The seven dates of the calendar week (Monday..Sunday) containing [date].
List<DateTime> calendarWeekDatesFor(DateTime date) {
  final today = generatedPlanDateOnly(date);
  final monday = generatedPlanAddDays(
    today,
    -generatedPlanWeekdayOffsetOf(today),
  );
  return [
    for (var index = 0; index < kGeneratedPlanDaysPerWeek; index++)
      generatedPlanAddDays(monday, index),
  ];
}

/// Id used to match a planned workout against the backend-owned completed set.
///
/// The scheme (`week-{n}-{daylabel}-{title-slug}`) is a contract with
/// `fallbackWorkoutId` in `functions/src/plan/planProgressParsing.ts`; changing
/// it would silently orphan every already-recorded completion.
String generatedPlanScheduledWorkoutId({
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
