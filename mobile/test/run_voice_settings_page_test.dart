import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_coaching_settings.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/repositories/run_voice_settings_repository.dart';
import 'package:runiac_app/features/run/voice/presentation/run_voice_settings_page.dart';

class _FakeRunVoiceSettingsRepository implements RunVoiceSettingsRepository {
  _FakeRunVoiceSettingsRepository({
    RunVoiceCoachingSettings initial = RunVoiceCoachingSettings.defaults,
  }) : _current = initial;

  RunVoiceCoachingSettings _current;
  RunVoiceCoachingSettings? lastSaved;

  @override
  Future<RunVoiceCoachingSettings> load() async => _current;

  @override
  Future<void> save(RunVoiceCoachingSettings settings) async {
    _current = settings;
    lastSaved = settings;
  }
}

void main() {
  testWidgets(
    'tapping the voice coaching switch persists enabled as true',
    (tester) async {
      final fake = _FakeRunVoiceSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(home: RunVoiceSettingsPage(settingsRepository: fake)),
      );
      await tester.pumpAndSettle();

      expect(fake.lastSaved, isNull);

      await tester.tap(
        find.byKey(const ValueKey('voice_coaching_enabled_switch')),
      );
      await tester.pumpAndSettle();

      expect(fake.lastSaved, isNotNull);
      expect(fake.lastSaved!.enabled, isTrue);
    },
  );

  testWidgets(
    'language and distance controls are ignored while coaching is disabled',
    (tester) async {
      final fake = _FakeRunVoiceSettingsRepository(
        initial: RunVoiceCoachingSettings.defaults,
      );

      await tester.pumpWidget(
        MaterialApp(home: RunVoiceSettingsPage(settingsRepository: fake)),
      );
      await tester.pumpAndSettle();

      final languageIgnorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('voice_language_control')),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      final distanceIgnorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byKey(
                const ValueKey('voice_distance_interval_control'),
              ),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );

      expect(languageIgnorePointer.ignoring, isTrue);
      expect(distanceIgnorePointer.ignoring, isTrue);
    },
  );

  testWidgets('selecting a language persists it', (tester) async {
    final fake = _FakeRunVoiceSettingsRepository(
      initial: RunVoiceCoachingSettings.defaults.copyWith(enabled: true),
    );

    await tester.pumpWidget(
      MaterialApp(home: RunVoiceSettingsPage(settingsRepository: fake)),
    );
    await tester.pumpAndSettle();

    final languageIgnorePointer = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('voice_language_control')),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(languageIgnorePointer.ignoring, isFalse);

    await tester.tap(find.byKey(const ValueKey('voice-language-korean')));
    await tester.pumpAndSettle();

    expect(fake.lastSaved, isNotNull);
    expect(fake.lastSaved!.language, RunVoiceLanguage.korean);
  });

  testWidgets('selecting a distance interval persists it', (tester) async {
    final fake = _FakeRunVoiceSettingsRepository(
      initial: RunVoiceCoachingSettings.defaults.copyWith(enabled: true),
    );

    await tester.pumpWidget(
      MaterialApp(home: RunVoiceSettingsPage(settingsRepository: fake)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('voice-distance-2km')));
    await tester.pumpAndSettle();

    expect(fake.lastSaved, isNotNull);
    expect(fake.lastSaved!.distanceIntervalMeters, 2000);
  });

  testWidgets(
    'selecting a time interval persists it, and selecting Off clears it',
    (tester) async {
      final fake = _FakeRunVoiceSettingsRepository(
        initial: RunVoiceCoachingSettings.defaults.copyWith(enabled: true),
      );

      await tester.pumpWidget(
        MaterialApp(home: RunVoiceSettingsPage(settingsRepository: fake)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('voice-time-10min')));
      await tester.pumpAndSettle();

      expect(fake.lastSaved, isNotNull);
      expect(fake.lastSaved!.timeInterval, const Duration(minutes: 10));

      await tester.tap(find.byKey(const ValueKey('voice-time-off')));
      await tester.pumpAndSettle();

      expect(fake.lastSaved, isNotNull);
      expect(fake.lastSaved!.timeInterval, isNull);
    },
  );

  testWidgets('toggling include-elapsed-time switch persists it', (
    tester,
  ) async {
    final fake = _FakeRunVoiceSettingsRepository(
      initial: RunVoiceCoachingSettings.defaults.copyWith(enabled: true),
    );

    await tester.pumpWidget(
      MaterialApp(home: RunVoiceSettingsPage(settingsRepository: fake)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('voice_include_elapsed_switch')),
    );
    await tester.tap(
      find.byKey(const ValueKey('voice_include_elapsed_switch')),
    );
    await tester.pumpAndSettle();

    expect(fake.lastSaved, isNotNull);
    expect(
      fake.lastSaved!.includeElapsedTime,
      isNot(RunVoiceCoachingSettings.defaults.includeElapsedTime),
    );
  });

  testWidgets('toggling include-average-pace switch persists it', (
    tester,
  ) async {
    final fake = _FakeRunVoiceSettingsRepository(
      initial: RunVoiceCoachingSettings.defaults.copyWith(enabled: true),
    );

    await tester.pumpWidget(
      MaterialApp(home: RunVoiceSettingsPage(settingsRepository: fake)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('voice_include_pace_switch')),
    );
    await tester.tap(find.byKey(const ValueKey('voice_include_pace_switch')));
    await tester.pumpAndSettle();

    expect(fake.lastSaved, isNotNull);
    expect(
      fake.lastSaved!.includeAveragePace,
      isNot(RunVoiceCoachingSettings.defaults.includeAveragePace),
    );
  });

  testWidgets(
    'time interval and announcement detail controls are ignored while '
    'coaching is disabled',
    (tester) async {
      final fake = _FakeRunVoiceSettingsRepository(
        initial: RunVoiceCoachingSettings.defaults,
      );

      await tester.pumpWidget(
        MaterialApp(home: RunVoiceSettingsPage(settingsRepository: fake)),
      );
      await tester.pumpAndSettle();

      final timeIgnorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('voice_time_interval_control')),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      final elapsedIgnorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byKey(
                const ValueKey('voice_include_elapsed_switch'),
              ),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      final paceIgnorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('voice_include_pace_switch')),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );

      expect(timeIgnorePointer.ignoring, isTrue);
      expect(elapsedIgnorePointer.ignoring, isTrue);
      expect(paceIgnorePointer.ignoring, isTrue);
    },
  );
}
