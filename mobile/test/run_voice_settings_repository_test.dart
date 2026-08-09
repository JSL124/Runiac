import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/voice/data/shared_preferences_run_voice_settings_repository.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_coaching_settings.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesRunVoiceSettingsRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('returns defaults when no settings have been saved', () async {
      // Given
      const repository = SharedPreferencesRunVoiceSettingsRepository(
        keyPrefix: 'test.emptyVoiceCoaching',
      );

      // When
      final restored = await repository.load();

      // Then
      expect(restored, RunVoiceCoachingSettings.defaults);
    });

    test('round-trips a fully-populated settings object', () async {
      // Given
      const repository = SharedPreferencesRunVoiceSettingsRepository(
        keyPrefix: 'test.voiceCoachingFull',
      );
      const savedSettings = RunVoiceCoachingSettings(
        enabled: true,
        distanceIntervalMeters: 500,
        timeInterval: Duration(minutes: 10),
        includeElapsedTime: true,
        includeAveragePace: false,
        language: RunVoiceLanguage.korean,
      );

      // When
      await repository.save(savedSettings);
      final restored = await repository.load();

      // Then
      expect(restored, savedSettings);
    });

    test(
      'per-field fallback preserves a valid field while an unsupported '
      'sibling field falls back to its default',
      () async {
        // Given a persisted store where `enabled` is valid but
        // `distanceIntervalMeters` holds an unsupported value (999).
        SharedPreferences.setMockInitialValues(<String, Object>{
          'test.voiceCoachingPartial.enabled': true,
          'test.voiceCoachingPartial.distanceIntervalMeters': 999,
        });
        const repository = SharedPreferencesRunVoiceSettingsRepository(
          keyPrefix: 'test.voiceCoachingPartial',
        );

        // When
        final restored = await repository.load();

        // Then: the valid `enabled` value survives, and the malformed
        // distance interval falls back to the default without discarding it.
        expect(restored.enabled, isTrue);
        expect(
          restored.distanceIntervalMeters,
          RunVoiceCoachingSettings.defaults.distanceIntervalMeters,
        );
      },
    );

    test(
      'falls back to the default language for an unknown persisted value',
      () async {
        // Given a persisted value that matches no RunVoiceLanguage name.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'test.voiceCoachingGarbageLanguage.language': 'klingon',
        });
        const repository = SharedPreferencesRunVoiceSettingsRepository(
          keyPrefix: 'test.voiceCoachingGarbageLanguage',
        );

        // When
        final restored = await repository.load();

        // Then: no throw, and the unknown language resolves to the default.
        expect(restored.language, RunVoiceCoachingSettings.defaults.language);
      },
    );

    test(
      'falls back to no time interval for an unsupported persisted value',
      () async {
        // Given a persisted seconds value outside the allowed set.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'test.voiceCoachingGarbageTime.timeIntervalSeconds': 42,
        });
        const repository = SharedPreferencesRunVoiceSettingsRepository(
          keyPrefix: 'test.voiceCoachingGarbageTime',
        );

        // When
        final restored = await repository.load();

        // Then
        expect(
          restored.timeInterval,
          RunVoiceCoachingSettings.defaults.timeInterval,
        );
      },
    );

    test('save with a null time interval removes the persisted key', () async {
      // Given
      const repository = SharedPreferencesRunVoiceSettingsRepository(
        keyPrefix: 'test.voiceCoachingClearTime',
      );
      const withTime = RunVoiceCoachingSettings(
        enabled: true,
        distanceIntervalMeters: 1000,
        timeInterval: Duration(minutes: 5),
        includeElapsedTime: true,
        includeAveragePace: true,
        language: RunVoiceLanguage.english,
      );
      await repository.save(withTime);

      // When
      await repository.save(withTime.copyWith(clearTimeInterval: true));
      final restored = await repository.load();

      // Then
      expect(restored.timeInterval, isNull);
    });
  });
}
