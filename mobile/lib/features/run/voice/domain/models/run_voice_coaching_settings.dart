import 'run_voice_language.dart';

const List<int> _allowedDistanceIntervalsMeters = [500, 1000, 2000];
const List<int> _allowedTimeIntervalMinutes = [5, 10, 15];

int validateDistanceInterval(int meters) {
  if (!_allowedDistanceIntervalsMeters.contains(meters)) {
    throw ArgumentError.value(
      meters,
      'meters',
      'Distance interval must be one of $_allowedDistanceIntervalsMeters',
    );
  }
  return meters;
}

Duration? validateTimeInterval(Duration? interval) {
  if (interval == null) {
    return null;
  }
  final isAllowed = _allowedTimeIntervalMinutes.any(
    (minutes) => interval == Duration(minutes: minutes),
  );
  if (!isAllowed) {
    throw ArgumentError.value(
      interval,
      'interval',
      'Time interval must be null or one of $_allowedTimeIntervalMinutes minutes',
    );
  }
  return interval;
}

class RunVoiceCoachingSettings {
  const RunVoiceCoachingSettings({
    required this.enabled,
    required this.distanceIntervalMeters,
    required this.timeInterval,
    required this.includeElapsedTime,
    required this.includeAveragePace,
    required this.language,
  });

  static const defaults = RunVoiceCoachingSettings(
    enabled: false,
    distanceIntervalMeters: 1000,
    timeInterval: null,
    includeElapsedTime: true,
    includeAveragePace: true,
    language: RunVoiceLanguage.english,
  );

  final bool enabled;
  final int distanceIntervalMeters;
  final Duration? timeInterval;
  final bool includeElapsedTime;
  final bool includeAveragePace;
  final RunVoiceLanguage language;

  RunVoiceCoachingSettings copyWith({
    bool? enabled,
    int? distanceIntervalMeters,
    Duration? timeInterval,
    bool clearTimeInterval = false,
    bool? includeElapsedTime,
    bool? includeAveragePace,
    RunVoiceLanguage? language,
  }) {
    return RunVoiceCoachingSettings(
      enabled: enabled ?? this.enabled,
      distanceIntervalMeters:
          distanceIntervalMeters ?? this.distanceIntervalMeters,
      timeInterval: clearTimeInterval
          ? null
          : (timeInterval ?? this.timeInterval),
      includeElapsedTime: includeElapsedTime ?? this.includeElapsedTime,
      includeAveragePace: includeAveragePace ?? this.includeAveragePace,
      language: language ?? this.language,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RunVoiceCoachingSettings &&
        other.enabled == enabled &&
        other.distanceIntervalMeters == distanceIntervalMeters &&
        other.timeInterval == timeInterval &&
        other.includeElapsedTime == includeElapsedTime &&
        other.includeAveragePace == includeAveragePace &&
        other.language == language;
  }

  @override
  int get hashCode {
    return Object.hash(
      enabled,
      distanceIntervalMeters,
      timeInterval,
      includeElapsedTime,
      includeAveragePace,
      language,
    );
  }
}
