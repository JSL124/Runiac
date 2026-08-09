import '../models/app_settings.dart';

abstract class AppSettingsRepository {
  Future<AppSettings> loadSettings();

  Future<void> saveSettings(AppSettings settings);
}
