// Integration/regression tests driving the REAL voice pipeline
// (DefaultRunVoiceAnnouncementPolicy + PriorityRunVoiceAnnouncementSelector +
// LocalizedRunVoiceMessageFormatter through RunVoiceCoachingCoordinator) with
// only the speech output faked. These cover behaviours the existing
// coordinator/QA suites do not: the first-snapshot baseline (a run that
// starts already past a milestone must stay silent), onSnapshot arriving
// before startSession, the halfway+completed collapse to a single spoken
// completion, and fractional-kilometre wording end-to-end.

import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/application/run_voice_coaching_coordinator.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_snapshot.dart';
import 'package:runiac_app/features/run/voice/domain/ports/run_speech_output.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_announcement_policy.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_announcement_selector.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_message_formatter.dart';

class _RecordingSpeechOutput implements RunSpeechOutput {
  final List<String> messages = [];
  final List<String?> languageTags = [];
  int initializeCount = 0;
  int stopCount = 0;

  @override
  Future<void> initialize() async {
    initializeCount += 1;
  }

  @override
  Future<void> speak(String message, {String? languageTag}) async {
    messages.add(message);
    languageTags.add(languageTag);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

RunVoiceCoachingCoordinator _coordinator(_RecordingSpeechOutput speech) {
  return RunVoiceCoachingCoordinator(
    policy: DefaultRunVoiceAnnouncementPolicy(),
    selector: const PriorityRunVoiceAnnouncementSelector(),
    formatter: const LocalizedRunVoiceMessageFormatter(),
    speechOutput: speech,
  );
}

RunVoiceSessionConfig _config({
  RunVoiceLanguage language = RunVoiceLanguage.english,
  int distanceIntervalMeters = 1000,
  double? targetDistanceMeters,
}) {
  return RunVoiceSessionConfig(
    enabled: true,
    distanceIntervalMeters: distanceIntervalMeters,
    timeInterval: null,
    includeElapsedTime: false,
    includeAveragePace: false,
    language: language,
    targetDistanceMeters: targetDistanceMeters,
  );
}

RunVoiceSnapshot _snap(int distance) {
  return RunVoiceSnapshot(
    distanceMeters: distance,
    elapsed: Duration(seconds: distance),
    averagePace: null,
    isActive: true,
    isPaused: false,
  );
}

Future<void> _feed(
  RunVoiceCoachingCoordinator coordinator,
  RunVoiceSnapshot snapshot,
) async {
  await coordinator.onSnapshot(snapshot);
  await pumpEventQueue();
}

void main() {
  group('first-snapshot baseline', () {
    test(
      'a run that starts already past 1km never announces the 1km milestone',
      () async {
        final speech = _RecordingSpeechOutput();
        final coordinator = _coordinator(speech);

        await coordinator.startSession(_config());
        // First snapshot establishes the baseline against itself; a later
        // advance within the same kilometre must not trigger 1km.
        await _feed(coordinator, _snap(1020));
        await _feed(coordinator, _snap(1080));

        expect(speech.messages, isEmpty);
        expect(speech.initializeCount, 0);
      },
    );

    test(
      'after starting past 1km, the next whole kilometre is still announced',
      () async {
        final speech = _RecordingSpeechOutput();
        final coordinator = _coordinator(speech);

        await coordinator.startSession(_config());
        await _feed(coordinator, _snap(1020)); // baseline
        await _feed(coordinator, _snap(2010)); // crosses 2km

        expect(speech.messages, ['You have completed 2 kilometers.']);
      },
    );
  });

  group('snapshot before startSession', () {
    test('is a silent no-op with no initialization', () async {
      final speech = _RecordingSpeechOutput();
      final coordinator = _coordinator(speech);

      await _feed(coordinator, _snap(1020));

      expect(speech.messages, isEmpty);
      expect(speech.initializeCount, 0);
      expect(coordinator.activeSessionCount, 0);
    });
  });

  group('target halfway + completed collapse', () {
    test(
      'a single jump past a small target speaks only the completion message '
      'and consumes halfway so it never fires afterwards',
      () async {
        final speech = _RecordingSpeechOutput();
        final coordinator = _coordinator(speech);
        final config = _config(
          distanceIntervalMeters: 2000, // no distance milestone before 2km
          targetDistanceMeters: 1000,
        );

        await coordinator.startSession(config);
        // Seeds `previous` state only; distance 1 / elapsed 1s can't trip the
        // start-encouragement gate (which requires distance 0 AND elapsed 0),
        // so this does not represent a real run-start snapshot.
        await _feed(coordinator, _snap(1)); // baseline
        await _feed(coordinator, _snap(1200)); // crosses half (500) and target

        expect(
          speech.messages,
          [
            'You have reached your goal distance. Well done. You finished '
            '1.2 kilometers in 20 minutes.',
          ],
        );

        // A later snapshot re-touching the half point must add nothing.
        await _feed(coordinator, _snap(1300));
        expect(speech.messages, hasLength(1));
      },
    );
  });

  group('fractional kilometre wording end-to-end', () {
    test('a 500m interval speaks "0.5 kilometers" on the first half km', () async {
      final speech = _RecordingSpeechOutput();
      final coordinator = _coordinator(speech);

      await coordinator.startSession(_config(distanceIntervalMeters: 500));
      // Seeds `previous` state only; distance 1 / elapsed 1s can't trip the
      // start-encouragement gate (which requires distance 0 AND elapsed 0),
      // so this does not represent a real run-start snapshot.
      await _feed(coordinator, _snap(1)); // baseline
      await _feed(coordinator, _snap(600)); // crosses 500m

      expect(speech.messages, ['You have completed 0.5 kilometers.']);
      expect(speech.languageTags, ['en-US']);
    });
  });
}
