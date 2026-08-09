enum PlannedRunObjectiveKind { distance, duration, restDay }

enum PlannedRunEstimateConfidence { none, low, medium, high }

class PlannedRunContext {
  const PlannedRunContext({
    required this.title,
    required this.durationMinutes,
    required this.planTitle,
    required this.planFamilyLabel,
    required this.workoutKindLabel,
    required this.intensityLabel,
    required this.steps,
    required this.supportiveNote,
    required this.sourceLabel,
    this.objectiveKind = PlannedRunObjectiveKind.duration,
    String? primaryValueLabel,
    String? primaryUnitLabel,
    String? supportLabel,
    this.secondarySupportLabel,
    String? estimatedDistanceLabel,
    this.estimateConfidence = PlannedRunEstimateConfidence.none,
    this.targetDistanceMeters,
    this.planEnrollmentId,
    this.scheduledWorkoutId,
    this.alreadyCompletedToday = false,
  }) : primaryValueLabel = primaryValueLabel ?? '$durationMinutes min',
       primaryUnitLabel = primaryUnitLabel ?? workoutKindLabel,
       estimatedDistanceLabel = estimatedDistanceLabel,
       supportLabel =
           supportLabel ??
           (alreadyCompletedToday
               ? "Today's planned run is already complete. Start an extra run? It will be saved to your activity history, but it will not count as another planned session."
               : objectiveKind == PlannedRunObjectiveKind.duration
               ? '$intensityLabel effort · ${estimateConfidence == PlannedRunEstimateConfidence.none || estimatedDistanceLabel == null ? 'no distance target' : 'About $estimatedDistanceLabel estimate'}'
               : objectiveKind == PlannedRunObjectiveKind.distance
               ? planTitle
               : 'Recovery today · no run target');

  final String title;
  final int durationMinutes;
  final String planTitle;
  final String planFamilyLabel;
  final String workoutKindLabel;
  final String intensityLabel;
  final List<String> steps;
  final String supportiveNote;
  final String sourceLabel;
  final PlannedRunObjectiveKind objectiveKind;
  final String primaryValueLabel;
  final String primaryUnitLabel;
  final String supportLabel;
  final String? secondarySupportLabel;
  final String? estimatedDistanceLabel;
  final PlannedRunEstimateConfidence estimateConfidence;
  final int? targetDistanceMeters;
  final String? planEnrollmentId;
  final String? scheduledWorkoutId;
  final bool alreadyCompletedToday;

  String get durationLabel => '$durationMinutes min';

  int get targetDurationSeconds => durationMinutes * 60;
}
