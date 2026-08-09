import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/data/shared_preferences_notification_center_settings_repository.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_center_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesNotificationCenterSettingsRepository', () {
    test(
      'restores notification center toggles after settings are saved',
      () async {
        // Given
        SharedPreferences.setMockInitialValues(<String, Object>{});
        const repository =
            SharedPreferencesNotificationCenterSettingsRepository(
              keyPrefix: 'test.notifications',
            );
        const savedSettings = NotificationCenterSettings(
          notificationsEnabled: true,
          planStartReminderEnabled: false,
          todaysPlanReminderEnabled: true,
          missedRunNudgeEnabled: false,
          planUpdatesEnabled: true,
          socialActivityEnabled: false,
        );

        // When
        await repository.saveSettings(savedSettings);
        final restored = await repository.loadSettings();

        // Then
        expect(restored, savedSettings);
      },
    );

    test(
      'returns all reminders enabled when no saved settings exist',
      () async {
        // Given
        SharedPreferences.setMockInitialValues(<String, Object>{});
        const repository =
            SharedPreferencesNotificationCenterSettingsRepository(
              keyPrefix: 'test.emptyNotifications',
            );

        // When
        final restored = await repository.loadSettings();

        // Then
        expect(restored, NotificationCenterSettings.defaults);
      },
    );

    test(
      'defaults socialActivityEnabled to true when the key is absent, even '
      'for a pre-existing install that only saved the other toggles',
      () async {
        // Given: an install that saved settings before the Social toggle
        // existed, so its key was never written.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'test.legacyNotifications.notificationsEnabled': true,
          'test.legacyNotifications.planStartReminderEnabled': false,
        });
        const repository =
            SharedPreferencesNotificationCenterSettingsRepository(
              keyPrefix: 'test.legacyNotifications',
            );

        // When
        final restored = await repository.loadSettings();

        // Then
        expect(restored.socialActivityEnabled, isTrue);
        expect(restored.notificationsEnabled, isTrue);
        expect(restored.planStartReminderEnabled, isFalse);
      },
    );
  });
}
