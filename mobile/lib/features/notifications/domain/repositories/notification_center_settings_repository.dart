import '../models/notification_center_settings.dart';

abstract interface class NotificationCenterSettingsRepository {
  Future<NotificationCenterSettings> loadSettings();

  Future<void> saveSettings(NotificationCenterSettings settings);
}

class InMemoryNotificationCenterSettingsRepository
    implements NotificationCenterSettingsRepository {
  InMemoryNotificationCenterSettingsRepository({
    NotificationCenterSettings initialSettings =
        NotificationCenterSettings.defaults,
  }) : _settings = initialSettings;

  NotificationCenterSettings _settings;

  @override
  Future<NotificationCenterSettings> loadSettings() async {
    return _settings;
  }

  @override
  Future<void> saveSettings(NotificationCenterSettings settings) async {
    _settings = settings;
  }
}
