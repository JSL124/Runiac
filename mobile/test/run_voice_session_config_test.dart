// Unit tests for RunVoiceSessionConfig.fromSettings (the settings -> session
// projection that injects the run's target distance) plus its value
// equality, and the RunVoiceLanguage.ttsLocale mapping consumed by the
// speech output. None of these had a dedicated unit test before.

import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/domain/models/run_voice_coaching_settings.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';

const _customSettings = RunVoiceCoachingSettings(
  enabled: true,
  distanceIntervalMeters: 500,
  timeInterval: Duration(minutes: 15),
  includeElapsedTime: false,
  includeAveragePace: true,
  language: RunVoiceLanguage.simplifiedChinese,
);

void main() {
  group('RunVoiceSessionConfig.fromSettings', () {
    test('carries every settings field through verbatim', () {
      final config = RunVoiceSessionConfig.fromSettings(
        settings: _customSettings,
        targetDistanceMeters: 5000,
      );

      expect(config.enabled, isTrue);
      expect(config.distanceIntervalMeters, 500);
      expect(config.timeInterval, const Duration(minutes: 15));
      expect(config.includeElapsedTime, isFalse);
      expect(config.includeAveragePace, isTrue);
      expect(config.language, RunVoiceLanguage.simplifiedChinese);
    });

    test('injects the supplied target distance (free run when null)', () {
      final targeted = RunVoiceSessionConfig.fromSettings(
        settings: RunVoiceCoachingSettings.defaults,
        targetDistanceMeters: 3000,
      );
      final free = RunVoiceSessionConfig.fromSettings(
        settings: RunVoiceCoachingSettings.defaults,
        targetDistanceMeters: null,
      );

      expect(targeted.targetDistanceMeters, 3000);
      expect(free.targetDistanceMeters, isNull);
    });

    test('a disabled settings object projects a disabled config', () {
      final config = RunVoiceSessionConfig.fromSettings(
        settings: RunVoiceCoachingSettings.defaults,
        targetDistanceMeters: null,
      );

      expect(config.enabled, isFalse);
    });
  });

  group('RunVoiceSessionConfig value equality', () {
    test('two configs with identical fields are equal and share a hashCode', () {
      final a = RunVoiceSessionConfig.fromSettings(
        settings: _customSettings,
        targetDistanceMeters: 5000,
      );
      final b = RunVoiceSessionConfig.fromSettings(
        settings: _customSettings,
        targetDistanceMeters: 5000,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a differing target distance breaks equality', () {
      final a = RunVoiceSessionConfig.fromSettings(
        settings: _customSettings,
        targetDistanceMeters: 5000,
      );
      final b = RunVoiceSessionConfig.fromSettings(
        settings: _customSettings,
        targetDistanceMeters: 10000,
      );

      expect(a == b, isFalse);
    });
  });

  group('RunVoiceLanguage.ttsLocale', () {
    test('maps each language to its BCP-47 speech tag', () {
      expect(RunVoiceLanguage.english.ttsLocale, 'en-US');
      expect(RunVoiceLanguage.korean.ttsLocale, 'ko-KR');
      expect(RunVoiceLanguage.simplifiedChinese.ttsLocale, 'zh-CN');
    });

    test('every language value resolves to a non-empty locale', () {
      for (final language in RunVoiceLanguage.values) {
        expect(language.ttsLocale, isNotEmpty);
      }
    });
  });
}
