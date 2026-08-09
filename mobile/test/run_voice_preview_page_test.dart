import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/voice/domain/ports/run_speech_output.dart';
import 'package:runiac_app/features/run/voice/presentation/run_voice_preview_page.dart';

class _SpokenMessage {
  _SpokenMessage(this.message, this.languageTag);

  final String message;
  final String? languageTag;
}

class _FakeRunSpeechOutput implements RunSpeechOutput {
  final List<_SpokenMessage> spoken = <_SpokenMessage>[];
  int stopCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(String message, {String? languageTag}) async {
    spoken.add(_SpokenMessage(message, languageTag));
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

void main() {
  const englishStart = "Let's start your run. You've got this!";
  const englishDistance =
      'You have completed 1 kilometer. Your time is 6 minutes 12 '
      'seconds. Your average pace is 6 minutes 12 seconds per '
      'kilometer.';
  const koreanDistance =
      '1킬로미터를 완료했습니다. 운동 시간은 6분 12초입니다. '
      '평균 페이스는 킬로미터당 6분 12초입니다.';

  testWidgets(
    'default English: shows the distance sentence and speaks it with en-US',
    (tester) async {
      final fake = _FakeRunSpeechOutput();

      await tester.pumpWidget(
        MaterialApp(home: RunVoicePreviewPage(speechOutput: fake)),
      );
      await tester.pumpAndSettle();

      expect(find.text(englishDistance), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('preview_play_distance_full')),
      );
      await tester.pumpAndSettle();

      expect(fake.spoken, hasLength(1));
      expect(fake.spoken.single.message, englishDistance);
      expect(fake.spoken.single.languageTag, 'en-US');
    },
  );

  testWidgets(
    'switching to Korean recomputes displayed text and speaks with ko-KR',
    (tester) async {
      final fake = _FakeRunSpeechOutput();

      await tester.pumpWidget(
        MaterialApp(home: RunVoicePreviewPage(speechOutput: fake)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('preview-language-korean')));
      await tester.pumpAndSettle();

      expect(find.text(koreanDistance), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('preview_play_distance_full')),
      );
      await tester.pumpAndSettle();

      expect(fake.spoken, hasLength(1));
      expect(fake.spoken.single.message, koreanDistance);
      expect(fake.spoken.single.languageTag, 'ko-KR');
    },
  );

  testWidgets(
    'Start card speaks a start-pool line with the selected language tag',
    (tester) async {
      final fake = _FakeRunSpeechOutput();

      await tester.pumpWidget(
        MaterialApp(home: RunVoicePreviewPage(speechOutput: fake)),
      );
      await tester.pumpAndSettle();

      expect(find.text(englishStart), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('preview_play_start')));
      await tester.pumpAndSettle();

      expect(fake.spoken, hasLength(1));
      expect(fake.spoken.single.message, englishStart);
      expect(fake.spoken.single.languageTag, 'en-US');
    },
  );

  testWidgets('tapping Stop calls speechOutput.stop', (tester) async {
    final fake = _FakeRunSpeechOutput();

    await tester.pumpWidget(
      MaterialApp(home: RunVoicePreviewPage(speechOutput: fake)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('preview_stop_button')));
    await tester.pumpAndSettle();

    expect(fake.stopCount, greaterThanOrEqualTo(1));
  });
}
