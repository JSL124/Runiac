// QA scenario test: verifies the voice-coaching messages spoken by the
// REAL production pipeline (DefaultRunVoiceAnnouncementPolicy +
// PriorityRunVoiceAnnouncementSelector + LocalizedRunVoiceMessageFormatter,
// wired through RunVoiceCoachingCoordinator) come out exactly as specified,
// end-to-end, for every announcement scenario and every supported language.
//
// This test deliberately uses no fakes for policy/selector/formatter: only
// the speech output port is faked, so every asserted string is the exact
// wording a real user would hear.

import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/application/run_voice_coaching_coordinator.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_snapshot.dart';
import 'package:runiac_app/features/run/voice/domain/ports/run_speech_output.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_announcement_policy.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_announcement_selector.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_message_formatter.dart';

/// Records every spoken utterance with the language tag it was spoken in,
/// plus initialize/stop call counts, so assertions can check both wording
/// and speech-session bookkeeping.
class _QaSpeechOutput implements RunSpeechOutput {
  final List<({String message, String? languageTag})> messages = [];
  int initializeCount = 0;
  int stopCount = 0;

  @override
  Future<void> initialize() async {
    initializeCount += 1;
  }

  @override
  Future<void> speak(String message, {String? languageTag}) async {
    messages.add((message: message, languageTag: languageTag));
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

RunVoiceCoachingCoordinator _buildCoordinator(_QaSpeechOutput speech) {
  return RunVoiceCoachingCoordinator(
    policy: DefaultRunVoiceAnnouncementPolicy(),
    selector: const PriorityRunVoiceAnnouncementSelector(),
    formatter: const LocalizedRunVoiceMessageFormatter(),
    speechOutput: speech,
  );
}

RunVoiceSessionConfig _buildConfig({
  required RunVoiceLanguage language,
  int distanceIntervalMeters = 1000,
  Duration? timeInterval,
  double? targetDistanceMeters,
  bool includeElapsedTime = false,
  bool includeAveragePace = false,
  bool enabled = true,
}) {
  return RunVoiceSessionConfig(
    enabled: enabled,
    distanceIntervalMeters: distanceIntervalMeters,
    timeInterval: timeInterval,
    includeElapsedTime: includeElapsedTime,
    includeAveragePace: includeAveragePace,
    language: language,
    targetDistanceMeters: targetDistanceMeters,
  );
}

RunVoiceSnapshot _snap({
  required int distance,
  int elapsedSec = 0,
  int? paceSec,
  int? currentPaceSec,
  bool active = true,
  bool paused = false,
}) {
  return RunVoiceSnapshot(
    distanceMeters: distance,
    elapsed: Duration(seconds: elapsedSec),
    averagePace: paceSec == null ? null : Duration(seconds: paceSec),
    currentPace: currentPaceSec == null
        ? null
        : Duration(seconds: currentPaceSec),
    isActive: active,
    isPaused: paused,
  );
}

/// Feeds a snapshot through the coordinator and lets the detached speech
/// task settle, mirroring test/run_voice_coaching_coordinator_test.dart.
Future<void> _feed(
  RunVoiceCoachingCoordinator coordinator,
  RunVoiceSnapshot snapshot,
) async {
  await coordinator.onSnapshot(snapshot);
  await pumpEventQueue();
}

const _languageTags = {
  RunVoiceLanguage.english: 'en-US',
  RunVoiceLanguage.korean: 'ko-KR',
  RunVoiceLanguage.simplifiedChinese: 'zh-CN',
};

/// The four localized run-start encouragement lines
/// (LocalizedRunVoiceMessageFormatter._formatStartEncouragement), keyed by
/// language. The policy picks a random variant, so QA scenarios assert pool
/// membership rather than an exact line to stay deterministic.
const _startPool = {
  RunVoiceLanguage.english: [
    "Let's start your run. You've got this!",
    'Time to run. Enjoy every step!',
    'Starting now — steady and strong!',
    'Here we go. Have a great run!',
  ],
  RunVoiceLanguage.korean: [
    '러닝을 시작합니다. 오늘도 힘내세요!',
    '천천히, 꾸준히. 시작합니다!',
    '오늘의 러닝을 시작합니다. 즐겁게 달려요!',
    '좋은 페이스로 시작해볼까요? 화이팅!',
  ],
  RunVoiceLanguage.simplifiedChinese: [
    '开始跑步。今天也加油！',
    '慢慢来，坚持住。开始吧！',
    '开始今天的跑步。享受每一步！',
    '让我们出发吧，跑个痛快！',
  ],
};

void main() {
  group('QA: distance milestone speaks exactly once per language', () {
    const expectedMessages = {
      RunVoiceLanguage.english: 'You have completed 1 kilometer.',
      RunVoiceLanguage.korean: '1킬로미터를 완료했습니다.',
      RunVoiceLanguage.simplifiedChinese: '您已完成1公里。',
    };

    for (final language in RunVoiceLanguage.values) {
      test('$language', () async {
        final speech = _QaSpeechOutput();
        final coordinator = _buildCoordinator(speech);
        final config = _buildConfig(
          language: language,
          distanceIntervalMeters: 1000,
        );

        await coordinator.startSession(config);
        await _feed(coordinator, _snap(distance: 980, elapsedSec: 980));
        await _feed(coordinator, _snap(distance: 1020, elapsedSec: 1020));
        await _feed(coordinator, _snap(distance: 1050, elapsedSec: 1050));
        await _feed(coordinator, _snap(distance: 1100, elapsedSec: 1100));

        expect(speech.messages, hasLength(1));
        expect(speech.messages.single.message, expectedMessages[language]);
        expect(
          speech.messages.single.languageTag,
          _languageTags[language],
        );
      });
    }
  });

  group('QA: distance milestone with elapsed + pace (KO)', () {
    test(
      'crossing 1km with elapsed 6:12 and pace 6:12 states both clauses',
      () async {
        final speech = _QaSpeechOutput();
        final coordinator = _buildCoordinator(speech);
        final config = _buildConfig(
          language: RunVoiceLanguage.korean,
          includeElapsedTime: true,
          includeAveragePace: true,
        );

        await coordinator.startSession(config);
        await _feed(coordinator, _snap(distance: 980, elapsedSec: 360));
        await _feed(
          coordinator,
          _snap(distance: 1020, elapsedSec: 372, paceSec: 372),
        );

        expect(speech.messages, hasLength(1));
        expect(
          speech.messages.single.message,
          '1킬로미터를 완료했습니다. 운동 시간은 6분 12초입니다. 평균 페이스는 킬로미터당 6분 12초입니다.',
        );
      },
    );
  });

  group('QA: pace omitted when unavailable or disabled', () {
    test('includeAveragePace true but paceSec null omits the pace clause', () async {
      final speech = _QaSpeechOutput();
      final coordinator = _buildCoordinator(speech);
      final config = _buildConfig(
        language: RunVoiceLanguage.korean,
        includeAveragePace: true,
      );

      await coordinator.startSession(config);
      await _feed(coordinator, _snap(distance: 980, elapsedSec: 360));
      await _feed(
        coordinator,
        _snap(distance: 1020, elapsedSec: 372, paceSec: null),
      );

      expect(speech.messages, hasLength(1));
      final message = speech.messages.single.message;
      expect(message, contains('1킬로미터'));
      expect(message, isNot(contains('평균 페이스')));
    });

    test('includeAveragePace false omits the pace clause even with a pace', () async {
      final speech = _QaSpeechOutput();
      final coordinator = _buildCoordinator(speech);
      final config = _buildConfig(
        language: RunVoiceLanguage.korean,
        includeAveragePace: false,
      );

      await coordinator.startSession(config);
      await _feed(coordinator, _snap(distance: 980, elapsedSec: 360));
      await _feed(
        coordinator,
        _snap(distance: 1020, elapsedSec: 372, paceSec: 372),
      );

      expect(speech.messages, hasLength(1));
      expect(
        speech.messages.single.message,
        isNot(contains('평균 페이스')),
      );
    });
  });

  group('QA: no repeat', () {
    test('further crossings beyond the announced km add nothing', () async {
      final speech = _QaSpeechOutput();
      final coordinator = _buildCoordinator(speech);
      final config = _buildConfig(language: RunVoiceLanguage.english);

      await coordinator.startSession(config);
      await _feed(coordinator, _snap(distance: 980, elapsedSec: 980));
      await _feed(coordinator, _snap(distance: 1020, elapsedSec: 1020));
      expect(speech.messages, hasLength(1));

      await _feed(coordinator, _snap(distance: 1030, elapsedSec: 1030));
      await _feed(coordinator, _snap(distance: 1050, elapsedSec: 1050));
      await _feed(coordinator, _snap(distance: 1100, elapsedSec: 1100));

      expect(speech.messages, hasLength(1));
    });
  });

  group('QA: paused produces no speech', () {
    test('a paused snapshot crossing the milestone stays silent', () async {
      final speech = _QaSpeechOutput();
      final coordinator = _buildCoordinator(speech);
      final config = _buildConfig(
        language: RunVoiceLanguage.english,
        distanceIntervalMeters: 1000,
      );

      await coordinator.startSession(config);
      await _feed(coordinator, _snap(distance: 950, elapsedSec: 950));
      await _feed(
        coordinator,
        _snap(distance: 1020, elapsedSec: 1020, paused: true),
      );

      expect(speech.messages, isEmpty);
    });
  });

  group('QA: time milestone (KO)', () {
    test('crossing 10 minutes announces the elapsed minutes', () async {
      final speech = _QaSpeechOutput();
      final coordinator = _buildCoordinator(speech);
      final config = _buildConfig(
        language: RunVoiceLanguage.korean,
        timeInterval: const Duration(minutes: 10),
      );

      await coordinator.startSession(config);
      await _feed(coordinator, _snap(distance: 200, elapsedSec: 598));
      await _feed(coordinator, _snap(distance: 200, elapsedSec: 602));

      expect(speech.messages, hasLength(1));
      expect(speech.messages.single.message, '10분 경과했습니다.');
      expect(speech.messages.single.languageTag, 'ko-KR');
    });
  });

  group('QA: target halfway (KO)', () {
    test('crossing the midpoint of a 5000m target announces halfway', () async {
      final speech = _QaSpeechOutput();
      final coordinator = _buildCoordinator(speech);
      final config = _buildConfig(
        language: RunVoiceLanguage.korean,
        targetDistanceMeters: 5000,
      );

      await coordinator.startSession(config);
      await _feed(coordinator, _snap(distance: 2400, elapsedSec: 2400));
      await _feed(coordinator, _snap(distance: 2550, elapsedSec: 2550));

      expect(speech.messages, hasLength(1));
      expect(speech.messages.single.message, '목표 거리의 절반을 지났습니다.');
    });
  });

  group('QA: free run has no target announcement', () {
    test('a session without a target never announces halfway/completion', () async {
      final speech = _QaSpeechOutput();
      final coordinator = _buildCoordinator(speech);
      final config = _buildConfig(
        language: RunVoiceLanguage.korean,
        distanceIntervalMeters: 2000,
      );

      await coordinator.startSession(config);
      await _feed(coordinator, _snap(distance: 2400, elapsedSec: 2400));
      await _feed(coordinator, _snap(distance: 2550, elapsedSec: 2550));

      expect(speech.messages, isEmpty);
    });
  });

  group('QA: target completed outranks distance (KO)', () {
    test(
      'a jump crossing both the 5000m distance milestone and the 5000m '
      'target speaks only the target-completed message',
      () async {
        final speech = _QaSpeechOutput();
        final coordinator = _buildCoordinator(speech);
        final config = _buildConfig(
          language: RunVoiceLanguage.korean,
          distanceIntervalMeters: 1000,
          targetDistanceMeters: 5000,
        );

        await coordinator.startSession(config);
        await _feed(coordinator, _snap(distance: 4950, elapsedSec: 4950));
        await _feed(coordinator, _snap(distance: 5030, elapsedSec: 5030));

        expect(speech.messages, hasLength(1));
        expect(
          speech.messages.single.message,
          '목표 거리를 완료했습니다. 수고하셨습니다. 총 5.0킬로미터를 83분 50초에 완주했습니다.',
        );
      },
    );
  });

  group('QA: end stops and silences', () {
    test('stopSession stops speech output and silences later snapshots', () async {
      final speech = _QaSpeechOutput();
      final coordinator = _buildCoordinator(speech);
      final config = _buildConfig(language: RunVoiceLanguage.english);

      await coordinator.startSession(config);
      await _feed(coordinator, _snap(distance: 980, elapsedSec: 980));

      await coordinator.stopSession();
      expect(speech.stopCount, greaterThanOrEqualTo(1));

      final beforeStop = List<({String message, String? languageTag})>.of(
        speech.messages,
      );
      await _feed(coordinator, _snap(distance: 1020, elapsedSec: 1020));

      expect(speech.messages, beforeStop);
    });
  });

  group('QA: language applied to speech tag', () {
    for (final language in RunVoiceLanguage.values) {
      test('$language speaks with tag ${_languageTags[language]}', () async {
        final speech = _QaSpeechOutput();
        final coordinator = _buildCoordinator(speech);
        final config = _buildConfig(language: language);

        await coordinator.startSession(config);
        await _feed(coordinator, _snap(distance: 980, elapsedSec: 980));
        await _feed(coordinator, _snap(distance: 1020, elapsedSec: 1020));

        expect(speech.messages, hasLength(1));
        expect(
          speech.messages.single.languageTag,
          _languageTags[language],
        );
      });
    }
  });

  group('QA: start message speaks exactly once, from the start pool', () {
    for (final language in RunVoiceLanguage.values) {
      test('$language speaks one of the four start-pool lines', () async {
        final speech = _QaSpeechOutput();
        final coordinator = _buildCoordinator(speech);
        final config = _buildConfig(language: language);

        await coordinator.startSession(config);
        await _feed(coordinator, _snap(distance: 0, elapsedSec: 0));

        expect(speech.messages, hasLength(1));
        expect(speech.messages.single.message, isIn(_startPool[language]));
        expect(speech.messages.single.languageTag, _languageTags[language]);
      });
    }
  });

  group('QA: start message then distance milestone, FIFO order (EN)', () {
    test(
      'start speaks first, then the 1km milestone speaks with no overlap',
      () async {
        final speech = _QaSpeechOutput();
        final coordinator = _buildCoordinator(speech);
        final config = _buildConfig(
          language: RunVoiceLanguage.english,
          includeElapsedTime: true,
          includeAveragePace: true,
        );

        await coordinator.startSession(config);
        await _feed(coordinator, _snap(distance: 0, elapsedSec: 0));
        await _feed(coordinator, _snap(distance: 980, elapsedSec: 340));
        await _feed(
          coordinator,
          _snap(distance: 1020, elapsedSec: 372, paceSec: 372),
        );

        expect(speech.messages, hasLength(2));
        expect(
          speech.messages[0].message,
          isIn(_startPool[RunVoiceLanguage.english]),
        );
        expect(
          speech.messages[1].message,
          'You have completed 1 kilometer. Your time is 6 minutes 12 '
          'seconds. Your average pace is 6 minutes 12 seconds per '
          'kilometer.',
        );
      },
    );
  });

  group('QA: target halfway with pace evaluation (KO)', () {
    test(
      'a steady pace at the midpoint speaks the halfway evaluation clause',
      () async {
        final speech = _QaSpeechOutput();
        final coordinator = _buildCoordinator(speech);
        final config = _buildConfig(
          language: RunVoiceLanguage.korean,
          targetDistanceMeters: 5000,
          includeElapsedTime: true,
          includeAveragePace: true,
        );

        await coordinator.startSession(config);
        await _feed(coordinator, _snap(distance: 2400, elapsedSec: 850));
        await _feed(
          coordinator,
          _snap(
            distance: 2550,
            elapsedSec: 900,
            paceSec: 372,
            currentPaceSec: 372,
          ),
        );

        expect(speech.messages, hasLength(1));
        expect(
          speech.messages.single.message,
          '목표 거리의 절반을 지났습니다. 일정한 페이스를 잘 유지하고 있어요. '
          '운동 시간은 15분입니다. 평균 페이스는 킬로미터당 6분 12초입니다.',
        );
      },
    );
  });

  group('QA: target completed with pace analysis (KO)', () {
    test(
      'a slower finish speaks the completion analysis plus improvement '
      'clause',
      () async {
        final speech = _QaSpeechOutput();
        final coordinator = _buildCoordinator(speech);
        final config = _buildConfig(
          language: RunVoiceLanguage.korean,
          distanceIntervalMeters: 1000,
          targetDistanceMeters: 5000,
        );

        await coordinator.startSession(config);
        await _feed(coordinator, _snap(distance: 4950, elapsedSec: 4950));
        await _feed(
          coordinator,
          _snap(
            distance: 5030,
            elapsedSec: 5030,
            paceSec: 372,
            currentPaceSec: 400,
          ),
        );

        expect(speech.messages, hasLength(1));
        expect(
          speech.messages.single.message,
          '목표 거리를 완료했습니다. 수고하셨습니다. 총 5.0킬로미터를 83분 50초에 '
          '완주했고, 평균 페이스는 킬로미터당 6분 12초입니다. 후반에 페이스가 '
          '조금 떨어졌어요. 다음엔 끝까지 일정하게 달려보세요.',
        );
      },
    );
  });
}
