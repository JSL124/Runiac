import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/run_voice_coaching_settings.dart';
import '../domain/models/run_voice_language.dart';
import '../domain/repositories/run_voice_settings_repository.dart';

class SharedPreferencesRunVoiceSettingsRepository
    implements RunVoiceSettingsRepository {
  const SharedPreferencesRunVoiceSettingsRepository({
    this.keyPrefix = 'runiac.voiceCoaching',
  });

  final String keyPrefix;

  @override
  Future<RunVoiceCoachingSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return RunVoiceCoachingSettings(
      enabled:
          preferences.getBool(_key('enabled')) ??
          RunVoiceCoachingSettings.defaults.enabled,
      distanceIntervalMeters: _readDistanceIntervalMeters(preferences),
      timeInterval: _readTimeInterval(preferences),
      includeElapsedTime:
          preferences.getBool(_key('includeElapsedTime')) ??
          RunVoiceCoachingSettings.defaults.includeElapsedTime,
      includeAveragePace:
          preferences.getBool(_key('includeAveragePace')) ??
          RunVoiceCoachingSettings.defaults.includeAveragePace,
      language: _readLanguage(preferences),
    );
  }

  @override
  Future<void> save(RunVoiceCoachingSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key('enabled'), settings.enabled);
    await preferences.setInt(
      _key('distanceIntervalMeters'),
      settings.distanceIntervalMeters,
    );
    final timeInterval = settings.timeInterval;
    if (timeInterval == null) {
      await preferences.remove(_key('timeIntervalSeconds'));
    } else {
      await preferences.setInt(
        _key('timeIntervalSeconds'),
        timeInterval.inSeconds,
      );
    }
    await preferences.setBool(
      _key('includeElapsedTime'),
      settings.includeElapsedTime,
    );
    await preferences.setBool(
      _key('includeAveragePace'),
      settings.includeAveragePace,
    );
    await preferences.setString(_key('language'), settings.language.name);
  }

  int _readDistanceIntervalMeters(SharedPreferences preferences) {
    final storedValue = preferences.getInt(_key('distanceIntervalMeters'));
    return switch (storedValue) {
      500 || 1000 || 2000 => storedValue!,
      _ => RunVoiceCoachingSettings.defaults.distanceIntervalMeters,
    };
  }

  Duration? _readTimeInterval(SharedPreferences preferences) {
    final storedSeconds = preferences.getInt(_key('timeIntervalSeconds'));
    if (storedSeconds == null) {
      return RunVoiceCoachingSettings.defaults.timeInterval;
    }
    return switch (storedSeconds) {
      300 || 600 || 900 => Duration(seconds: storedSeconds),
      _ => RunVoiceCoachingSettings.defaults.timeInterval,
    };
  }

  RunVoiceLanguage _readLanguage(SharedPreferences preferences) {
    final storedName = preferences.getString(_key('language'));
    for (final language in RunVoiceLanguage.values) {
      if (language.name == storedName) {
        return language;
      }
    }
    return RunVoiceCoachingSettings.defaults.language;
  }

  String _key(String name) {
    return '$keyPrefix.$name';
  }
}
