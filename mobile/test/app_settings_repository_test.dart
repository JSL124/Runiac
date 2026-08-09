import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/settings/data/shared_preferences_app_settings_repository.dart';
import 'package:runiac_app/features/settings/domain/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesAppSettingsRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('returns defaults when no settings have been saved', () async {
      // Given
      const repository = SharedPreferencesAppSettingsRepository(
        keyPrefix: 'test.emptyAppSettings',
      );

      // When
      final restored = await repository.loadSettings();

      // Then
      expect(restored, AppSettings.defaults);
    });

    test(
      'restores saved settings including a miles distance unit',
      () async {
        // Given
        const repository = SharedPreferencesAppSettingsRepository(
          keyPrefix: 'test.appSettings',
        );
        const savedSettings = AppSettings(
          distanceUnit: DistanceUnit.miles,
          hapticFeedbackEnabled: false,
          keepScreenOnDuringRun: true,
        );

        // When
        await repository.saveSettings(savedSettings);
        final restored = await repository.loadSettings();

        // Then
        expect(restored, savedSettings);
      },
    );

    test(
      'restores saved settings that keep the kilometers distance unit',
      () async {
        // Given
        const repository = SharedPreferencesAppSettingsRepository(
          keyPrefix: 'test.appSettingsKilometers',
        );
        const savedSettings = AppSettings(
          distanceUnit: DistanceUnit.kilometers,
          hapticFeedbackEnabled: true,
          keepScreenOnDuringRun: false,
        );

        // When
        await repository.saveSettings(savedSettings);
        final restored = await repository.loadSettings();

        // Then
        expect(restored, savedSettings);
      },
    );

    test(
      'falls back to the default unit for a garbage persisted distance unit',
      () async {
        // Given a persisted value that matches no DistanceUnit name (e.g.
        // written by a newer/older app build or corrupted storage).
        SharedPreferences.setMockInitialValues(<String, Object>{
          'test.appSettingsGarbage.distanceUnit': 'parsecs',
        });
        const repository = SharedPreferencesAppSettingsRepository(
          keyPrefix: 'test.appSettingsGarbage',
        );

        // When
        final restored = await repository.loadSettings();

        // Then: no throw, and the unknown unit resolves to the default.
        expect(restored.distanceUnit, AppSettings.defaults.distanceUnit);
        expect(restored, AppSettings.defaults);
      },
    );
  });
}
