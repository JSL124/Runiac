import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/domain/models/run_voice_coaching_settings.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';

void main() {
  group('RunVoiceCoachingSettings', () {
    test('defaults are correct', () {
      const defaults = RunVoiceCoachingSettings.defaults;

      expect(defaults.enabled, isFalse);
      expect(defaults.distanceIntervalMeters, 1000);
      expect(defaults.timeInterval, isNull);
      expect(defaults.includeElapsedTime, isTrue);
      expect(defaults.includeAveragePace, isTrue);
      expect(defaults.language, RunVoiceLanguage.english);
    });

    test('copyWith clearTimeInterval nulls the time interval', () {
      const settings = RunVoiceCoachingSettings.defaults;
      final withInterval = settings.copyWith(
        timeInterval: const Duration(minutes: 10),
      );
      expect(withInterval.timeInterval, const Duration(minutes: 10));

      final cleared = withInterval.copyWith(clearTimeInterval: true);
      expect(cleared.timeInterval, isNull);
    });

    test('copyWith preserves other fields when not overridden', () {
      const settings = RunVoiceCoachingSettings.defaults;
      final updated = settings.copyWith(enabled: true);

      expect(updated.enabled, isTrue);
      expect(updated.distanceIntervalMeters, settings.distanceIntervalMeters);
      expect(updated.includeElapsedTime, settings.includeElapsedTime);
      expect(updated.includeAveragePace, settings.includeAveragePace);
      expect(updated.language, settings.language);
    });

    test('== and hashCode use value equality', () {
      const a = RunVoiceCoachingSettings(
        enabled: true,
        distanceIntervalMeters: 500,
        timeInterval: Duration(minutes: 5),
        includeElapsedTime: false,
        includeAveragePace: true,
        language: RunVoiceLanguage.korean,
      );
      const b = RunVoiceCoachingSettings(
        enabled: true,
        distanceIntervalMeters: 500,
        timeInterval: Duration(minutes: 5),
        includeElapsedTime: false,
        includeAveragePace: true,
        language: RunVoiceLanguage.korean,
      );
      const c = RunVoiceCoachingSettings(
        enabled: false,
        distanceIntervalMeters: 500,
        timeInterval: Duration(minutes: 5),
        includeElapsedTime: false,
        includeAveragePace: true,
        language: RunVoiceLanguage.korean,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('validateDistanceInterval', () {
    test('throws for values outside the allowed set', () {
      expect(() => validateDistanceInterval(0), throwsArgumentError);
      expect(() => validateDistanceInterval(750), throwsArgumentError);
    });

    test('returns the value for allowed intervals', () {
      expect(validateDistanceInterval(500), 500);
      expect(validateDistanceInterval(1000), 1000);
      expect(validateDistanceInterval(2000), 2000);
    });
  });

  group('validateTimeInterval', () {
    test('throws for an interval shorter than 5 minutes', () {
      expect(
        () => validateTimeInterval(const Duration(minutes: 1)),
        throwsArgumentError,
      );
    });

    test('accepts null and allowed minute values', () {
      expect(validateTimeInterval(null), isNull);
      expect(
        validateTimeInterval(const Duration(minutes: 5)),
        const Duration(minutes: 5),
      );
      expect(
        validateTimeInterval(const Duration(minutes: 10)),
        const Duration(minutes: 10),
      );
      expect(
        validateTimeInterval(const Duration(minutes: 15)),
        const Duration(minutes: 15),
      );
    });
  });
}
