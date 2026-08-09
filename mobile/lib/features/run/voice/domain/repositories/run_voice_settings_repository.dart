import '../models/run_voice_coaching_settings.dart';

abstract class RunVoiceSettingsRepository {
  Future<RunVoiceCoachingSettings> load();

  Future<void> save(RunVoiceCoachingSettings settings);
}
