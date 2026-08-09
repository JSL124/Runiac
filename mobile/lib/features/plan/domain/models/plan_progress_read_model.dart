class PlanProgressReadModel {
  PlanProgressReadModel({
    required Iterable<String> completedScheduledWorkoutIds,
    this.planCompletedAt,
  }) : completedScheduledWorkoutIds = Set.unmodifiable(
         completedScheduledWorkoutIds,
       );

  factory PlanProgressReadModel.empty() {
    return PlanProgressReadModel(completedScheduledWorkoutIds: const []);
  }

  factory PlanProgressReadModel.fromBackend({
    required String activeGeneratedPlanId,
    required Map<String, Object?>? data,
  }) {
    if (data == null || activeGeneratedPlanId.isEmpty) {
      return PlanProgressReadModel.empty();
    }

    final planCompletedAt = _planCompletedAt(
      data['planCompletions'],
      activeGeneratedPlanId: activeGeneratedPlanId,
    );

    final workouts = data['workouts'];
    if (workouts is! Map) {
      return PlanProgressReadModel(
        completedScheduledWorkoutIds: const [],
        planCompletedAt: planCompletedAt,
      );
    }

    final completedIds = <String>{};
    for (final entry in workouts.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! Map || value['completedAt'] == null) {
        continue;
      }
      if (key != key.trim()) {
        continue;
      }
      final scheduledWorkoutId = _activeScheduledWorkoutId(
        key,
        activeGeneratedPlanId: activeGeneratedPlanId,
      );
      if (scheduledWorkoutId != null) {
        completedIds.add(scheduledWorkoutId);
      }
    }

    return PlanProgressReadModel(
      completedScheduledWorkoutIds: completedIds,
      planCompletedAt: planCompletedAt,
    );
  }

  final Set<String> completedScheduledWorkoutIds;

  /// When the backend recorded the active plan as finished, or `null` while it
  /// is still in progress. Written only by the `completeRun` Cloud Function
  /// into the backend-owned `planProgress/{uid}` document; the client never
  /// derives or writes it.
  final DateTime? planCompletedAt;
}

DateTime? _planCompletedAt(
  Object? planCompletions, {
  required String activeGeneratedPlanId,
}) {
  if (planCompletions is! Map) {
    return null;
  }

  final completion = planCompletions[activeGeneratedPlanId];
  if (completion is! Map) {
    return null;
  }

  final completedAt = completion['completedAt'];
  if (completedAt is! String) {
    return null;
  }
  return DateTime.tryParse(completedAt)?.toLocal();
}

String? _activeScheduledWorkoutId(
  String key, {
  required String activeGeneratedPlanId,
}) {
  final separatorIndex = key.indexOf('__');
  if (separatorIndex <= 0 || separatorIndex != key.lastIndexOf('__')) {
    return null;
  }

  final generatedPlanId = key.substring(0, separatorIndex);
  final scheduledWorkoutId = key.substring(separatorIndex + 2);
  if (generatedPlanId != activeGeneratedPlanId ||
      scheduledWorkoutId.isEmpty ||
      scheduledWorkoutId != scheduledWorkoutId.trim()) {
    return null;
  }
  return scheduledWorkoutId;
}
