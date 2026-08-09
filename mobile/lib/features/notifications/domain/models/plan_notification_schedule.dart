enum PlanNotificationKind {
  planStartReminder,
  todaysPlanReminder,
  missedRunNudge,
  streakRiskNudge,
  planUpdate,
}

class PlanNotificationWorkoutInput {
  const PlanNotificationWorkoutInput({
    required this.planId,
    required this.scheduledWorkoutId,
    required this.title,
    required this.startsAt,
    required this.completed,
  });

  final String planId;
  final String scheduledWorkoutId;
  final String title;
  final DateTime startsAt;
  final bool completed;
}

class ScheduledPlanNotification {
  const ScheduledPlanNotification({
    required this.id,
    required this.kind,
    required this.scheduledAt,
    required this.title,
    required this.body,
    this.payload = const <String, String>{},
  });

  final String id;
  final PlanNotificationKind kind;
  final DateTime scheduledAt;
  final String title;
  final String body;
  final Map<String, String> payload;

  Map<String, Object?> toChannelMap() {
    return <String, Object?>{
      'id': id,
      'kind': kind.name,
      'scheduledAtMillis': scheduledAt.millisecondsSinceEpoch,
      'title': title,
      'body': body,
      'payload': payload,
    };
  }

  /// Serialization for the local ledger of notifications actually handed to the
  /// OS. Shares the channel map's shape so both sides stay in step.
  Map<String, Object?> toLedgerJson() => toChannelMap();

  static ScheduledPlanNotification? fromLedgerJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final title = json['title'];
    final body = json['body'];
    final scheduledAtMillis = json['scheduledAtMillis'];
    if (id is! String || title is! String || body is! String) {
      return null;
    }
    if (scheduledAtMillis is! int) {
      return null;
    }
    final rawPayload = json['payload'];
    return ScheduledPlanNotification(
      id: id,
      kind: PlanNotificationKind.values.firstWhere(
        (candidate) => candidate.name == json['kind'],
        orElse: () => PlanNotificationKind.planUpdate,
      ),
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(scheduledAtMillis),
      title: title,
      body: body,
      payload: rawPayload is Map
          ? <String, String>{
              for (final entry in rawPayload.entries)
                if (entry.value is String)
                  entry.key.toString(): entry.value as String,
            }
          : const <String, String>{},
    );
  }
}

class StreakRiskNotificationInput {
  const StreakRiskNotificationInput({
    required this.planId,
    required this.riskDate,
    required this.streakWouldBreakWithoutValidatedRun,
  });

  final String planId;
  final DateTime riskDate;
  final bool streakWouldBreakWithoutValidatedRun;
}
