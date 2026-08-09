enum RunVoiceAnnouncementType {
  startEncouragement,
  distanceMilestone,
  timeMilestone,
  targetHalfway,
  targetCompleted,
}

enum RunVoicePaceTrend { faster, steady, slower }

class RunVoiceAnnouncement {
  const RunVoiceAnnouncement({
    required this.id,
    required this.type,
    required this.priority,
    required this.distanceMeters,
    required this.elapsed,
    required this.averagePace,
    this.variant,
    this.paceTrend,
  });

  final String id;
  final RunVoiceAnnouncementType type;
  final int priority;
  final int? distanceMeters;
  final Duration elapsed;
  final Duration? averagePace;
  final int? variant;
  final RunVoicePaceTrend? paceTrend;

  @override
  bool operator ==(Object other) {
    return other is RunVoiceAnnouncement &&
        other.id == id &&
        other.type == type &&
        other.priority == priority &&
        other.distanceMeters == distanceMeters &&
        other.elapsed == elapsed &&
        other.averagePace == averagePace &&
        other.variant == variant &&
        other.paceTrend == paceTrend;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      type,
      priority,
      distanceMeters,
      elapsed,
      averagePace,
      variant,
      paceTrend,
    );
  }
}

class RunVoicePolicyResult {
  const RunVoicePolicyResult({
    required this.announcements,
    required this.consumedIds,
  });

  const RunVoicePolicyResult.empty()
    : announcements = const <RunVoiceAnnouncement>[],
      consumedIds = const <String>{};

  final List<RunVoiceAnnouncement> announcements;
  final Set<String> consumedIds;
}
