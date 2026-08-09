import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/app_settings.dart';
import '../domain/repositories/app_settings_repository.dart';

class SharedPreferencesAppSettingsRepository
    implements AppSettingsRepository {
  const SharedPreferencesAppSettingsRepository({
    this.keyPrefix = 'runiac.appSettings',
  });

  final String keyPrefix;

  @override
  Future<AppSettings> loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings(
      distanceUnit: _readDistanceUnit(preferences),
      hapticFeedbackEnabled:
          preferences.getBool(_key('hapticFeedbackEnabled')) ??
          AppSettings.defaults.hapticFeedbackEnabled,
      keepScreenOnDuringRun:
          preferences.getBool(_key('keepScreenOnDuringRun')) ??
          AppSettings.defaults.keepScreenOnDuringRun,
    );
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key('distanceUnit'),
      settings.distanceUnit.name,
    );
    await preferences.setBool(
      _key('hapticFeedbackEnabled'),
      settings.hapticFeedbackEnabled,
    );
    await preferences.setBool(
      _key('keepScreenOnDuringRun'),
      settings.keepScreenOnDuringRun,
    );
  }

  DistanceUnit _readDistanceUnit(SharedPreferences preferences) {
    final storedName = preferences.getString(_key('distanceUnit'));
    for (final unit in DistanceUnit.values) {
      if (unit.name == storedName) {
        return unit;
      }
    }
    return AppSettings.defaults.distanceUnit;
  }

  String _key(String name) {
    return '$keyPrefix.$name';
  }
}
