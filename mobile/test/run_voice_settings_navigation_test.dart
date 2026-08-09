import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/presentation/run_launch_screen.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_coaching_settings.dart';
import 'package:runiac_app/features/run/voice/domain/repositories/run_voice_settings_repository.dart';

class _FakeRunVoiceSettingsRepository implements RunVoiceSettingsRepository {
  RunVoiceCoachingSettings _current = RunVoiceCoachingSettings.defaults;

  @override
  Future<RunVoiceCoachingSettings> load() async => _current;

  @override
  Future<void> save(RunVoiceCoachingSettings settings) async {
    _current = settings;
  }
}

void main() {
  testWidgets(
    'tapping the gear button on RunLaunchScreen navigates to Run Settings',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            enableForegroundGps: false,
            voiceSettingsRepository: _FakeRunVoiceSettingsRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Run settings'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings_button')));
      await tester.pumpAndSettle();

      expect(find.text('Run Settings'), findsOneWidget);
      expect(find.text('Voice progress updates'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Run Settings'), findsNothing);
      expect(find.byKey(const ValueKey('settings_button')), findsOneWidget);
    },
  );
}
