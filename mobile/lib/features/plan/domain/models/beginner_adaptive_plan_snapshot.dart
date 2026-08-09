export 'beginner_plan_profile.dart';

import 'beginner_plan_profile.dart';
import 'plan_family.dart';

enum BeginnerAdaptivePlanKind { onboardingBased }

enum BeginnerAdaptivePlanClientDisplayStatus { generatedPlan, safetyReadiness }

enum BeginnerWorkoutKind {
  easyRun,
  runWalk,
  walkRun,
  recoveryWalk,
  steadyRun,
  controlledSteadyRun,
  longerEasyRun,
  recoveryRun,
  restOrMobility,
}

enum BeginnerPlanIntensity { veryGentle, gentle, balanced }

class BeginnerAdaptivePlanSnapshot {
  BeginnerAdaptivePlanSnapshot({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.planKind,
    required this.sourceLabel,
    this.startsOnDate,
    required this.durationWeeks,
    required this.safetyBand,
    required this.templateKind,
    required this.family,
    required this.familyCategory,
    required this.familyReason,
    required this.supportStyleLabel,
    required this.weeklyFrequencyLabel,
    required this.preferredScheduleLabel,
    required this.sessionDurationLabel,
    required this.safetyNote,
    required List<BeginnerAdaptivePlanWeek> weeks,
    this.clientDisplayStatus =
        BeginnerAdaptivePlanClientDisplayStatus.generatedPlan,
  }) : weeks = List.unmodifiable(weeks);

  final String id;
  final String title;
  final String subtitle;
  final BeginnerAdaptivePlanKind planKind;
  final String sourceLabel;
  final String? startsOnDate;
  final int durationWeeks;
  final BeginnerPlanSafetyBand safetyBand;
  final BeginnerPlanTemplateKind templateKind;
  final PlanFamily? family;
  final PlanFamilyCategory? familyCategory;
  final String familyReason;
  final String supportStyleLabel;
  final String weeklyFrequencyLabel;
  final String preferredScheduleLabel;
  final String sessionDurationLabel;
  final String safetyNote;
  final List<BeginnerAdaptivePlanWeek> weeks;
  // Frontend/session-local display state only. This is not a PlanFamily,
  // Firestore plan status, or backend-owned plan lifecycle value.
  final BeginnerAdaptivePlanClientDisplayStatus clientDisplayStatus;

  bool get isBlocked => family == null;

  bool get isSafetyReadinessDisplay =>
      clientDisplayStatus ==
      BeginnerAdaptivePlanClientDisplayStatus.safetyReadiness;

  bool get canStartPlannedRun =>
      clientDisplayStatus ==
          BeginnerAdaptivePlanClientDisplayStatus.generatedPlan &&
      !isBlocked &&
      weeks.any((week) => week.workouts.isNotEmpty);

  BeginnerAdaptivePlanSnapshot withStartsOnDate(String startsOnDate) {
    return BeginnerAdaptivePlanSnapshot(
      id: id,
      title: title,
      subtitle: subtitle,
      planKind: planKind,
      sourceLabel: sourceLabel,
      startsOnDate: startsOnDate,
      durationWeeks: durationWeeks,
      safetyBand: safetyBand,
      templateKind: templateKind,
      family: family,
      familyCategory: familyCategory,
      familyReason: familyReason,
      supportStyleLabel: supportStyleLabel,
      weeklyFrequencyLabel: weeklyFrequencyLabel,
      preferredScheduleLabel: preferredScheduleLabel,
      sessionDurationLabel: sessionDurationLabel,
      safetyNote: safetyNote,
      weeks: weeks,
      clientDisplayStatus: clientDisplayStatus,
    );
  }
}

String generatedPlanDateLabel(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

class BeginnerAdaptivePlanWeek {
  BeginnerAdaptivePlanWeek({
    required this.weekNumber,
    required this.title,
    required this.focus,
    required List<BeginnerAdaptiveWorkout> workouts,
  }) : workouts = List.unmodifiable(workouts);

  final int weekNumber;
  final String title;
  final String focus;
  final List<BeginnerAdaptiveWorkout> workouts;
}

class BeginnerAdaptiveWorkout {
  BeginnerAdaptiveWorkout({
    required this.dayLabel,
    required this.title,
    required this.durationMinutes,
    required this.kind,
    required this.intensity,
    required this.description,
    required List<String> steps,
    required this.supportiveNote,
    required this.detail,
    this.scheduleTimeLabel,
  }) : steps = List.unmodifiable(steps);

  final String dayLabel;
  final String title;
  final int durationMinutes;
  final BeginnerWorkoutKind kind;
  final BeginnerPlanIntensity intensity;
  final String description;
  final List<String> steps;
  final String supportiveNote;
  final BeginnerAdaptiveWorkoutDetail detail;
  final String? scheduleTimeLabel;
}

class BeginnerAdaptiveWorkoutDetail {
  BeginnerAdaptiveWorkoutDetail({
    required List<BeginnerAdaptiveWorkoutMetric> metrics,
    required List<BeginnerAdaptiveWorkoutBreakdownStep> breakdown,
    required this.effortGuide,
    required List<String> coachNotes,
  }) : metrics = List.unmodifiable(metrics),
       breakdown = List.unmodifiable(breakdown),
       coachNotes = List.unmodifiable(coachNotes);

  final List<BeginnerAdaptiveWorkoutMetric> metrics;
  final List<BeginnerAdaptiveWorkoutBreakdownStep> breakdown;
  final String effortGuide;
  final List<String> coachNotes;
}

class BeginnerAdaptiveWorkoutMetric {
  const BeginnerAdaptiveWorkoutMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class BeginnerAdaptiveWorkoutBreakdownStep {
  const BeginnerAdaptiveWorkoutBreakdownStep({
    required this.kind,
    required this.title,
    required this.detail,
  });

  final BeginnerAdaptiveWorkoutBreakdownStepKind kind;
  final String title;
  final String detail;
}

enum BeginnerAdaptiveWorkoutBreakdownStepKind { walk, run, mobility }
