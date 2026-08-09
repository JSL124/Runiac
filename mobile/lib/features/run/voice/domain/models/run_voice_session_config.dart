import 'run_voice_coaching_settings.dart';
import 'run_voice_language.dart';

class RunVoiceSessionConfig {
  const RunVoiceSessionConfig({
    required this.enabled,
    required this.distanceIntervalMeters,
    required this.timeInterval,
    required this.includeElapsedTime,
    required this.includeAveragePace,
    required this.language,
    required this.targetDistanceMeters,
  });

  factory RunVoiceSessionConfig.fromSettings({
    required RunVoiceCoachingSettings settings,
    required double? targetDistanceMeters,
  }) {
    return RunVoiceSessionConfig(
      enabled: settings.enabled,
      distanceIntervalMeters: settings.distanceIntervalMeters,
      timeInterval: settings.timeInterval,
      includeElapsedTime: settings.includeElapsedTime,
      includeAveragePace: settings.includeAveragePace,
      language: settings.language,
      targetDistanceMeters: targetDistanceMeters,
    );
  }

  final bool enabled;
  final int distanceIntervalMeters;
  final Duration? timeInterval;
  final bool includeElapsedTime;
  final bool includeAveragePace;
  final RunVoiceLanguage language;
  final double? targetDistanceMeters;

  @override
  bool operator ==(Object other) {
    return other is RunVoiceSessionConfig &&
        other.enabled == enabled &&
        other.distanceIntervalMeters == distanceIntervalMeters &&
        other.timeInterval == timeInterval &&
        other.includeElapsedTime == includeElapsedTime &&
        other.includeAveragePace == includeAveragePace &&
        other.language == language &&
        other.targetDistanceMeters == targetDistanceMeters;
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
      targetDistanceMeters,
    );
  }
}
