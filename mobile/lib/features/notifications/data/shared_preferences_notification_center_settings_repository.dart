import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/notification_center_settings.dart';
import '../domain/repositories/notification_center_settings_repository.dart';

class SharedPreferencesNotificationCenterSettingsRepository
    implements NotificationCenterSettingsRepository {
  const SharedPreferencesNotificationCenterSettingsRepository({
    this.keyPrefix = 'runiac.notificationCenter',
  });

  final String keyPrefix;

  @override
  Future<NotificationCenterSettings> loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    return NotificationCenterSettings(
      notificationsEnabled:
          preferences.getBool(_key('notificationsEnabled')) ??
          NotificationCenterSettings.defaults.notificationsEnabled,
      planStartReminderEnabled:
          preferences.getBool(_key('planStartReminderEnabled')) ??
          NotificationCenterSettings.defaults.planStartReminderEnabled,
      todaysPlanReminderEnabled:
          preferences.getBool(_key('todaysPlanReminderEnabled')) ??
          NotificationCenterSettings.defaults.todaysPlanReminderEnabled,
      missedRunNudgeEnabled:
          preferences.getBool(_key('missedRunNudgeEnabled')) ??
          NotificationCenterSettings.defaults.missedRunNudgeEnabled,
      planUpdatesEnabled:
          preferences.getBool(_key('planUpdatesEnabled')) ??
          NotificationCenterSettings.defaults.planUpdatesEnabled,
      socialActivityEnabled:
          preferences.getBool(_key('socialActivityEnabled')) ??
          NotificationCenterSettings.defaults.socialActivityEnabled,
    );
  }

  @override
  Future<void> saveSettings(NotificationCenterSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      _key('notificationsEnabled'),
      settings.notificationsEnabled,
    );
    await preferences.setBool(
      _key('planStartReminderEnabled'),
      settings.planStartReminderEnabled,
    );
    await preferences.setBool(
      _key('todaysPlanReminderEnabled'),
      settings.todaysPlanReminderEnabled,
    );
    await preferences.setBool(
      _key('missedRunNudgeEnabled'),
      settings.missedRunNudgeEnabled,
    );
    await preferences.setBool(
      _key('planUpdatesEnabled'),
      settings.planUpdatesEnabled,
    );
    await preferences.setBool(
      _key('socialActivityEnabled'),
      settings.socialActivityEnabled,
    );
  }

  String _key(String name) {
    return '$keyPrefix.$name';
  }
}
