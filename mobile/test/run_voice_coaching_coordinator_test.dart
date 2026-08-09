import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/application/run_voice_coaching_coordinator.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_announcement.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_snapshot.dart';
import 'package:runiac_app/features/run/voice/domain/ports/run_speech_output.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_announcement_policy.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_announcement_selector.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_message_formatter.dart';

class _FakeRunSpeechOutput implements RunSpeechOutput {
  int initializeCallCount = 0;
  int stopCallCount = 0;
  final List<String> spokenMessages = [];
  final List<String?> languageTags = [];
  bool throwOnSpeak = false;
  Completer<void>? gate;

  @override
  Future<void> initialize() async {
    initializeCallCount += 1;
  }

  @override
  Future<void> speak(String message, {String? languageTag}) async {
    if (throwOnSpeak) {
      throw StateError('speak failed');
    }
    spokenMessages.add(message);
    languageTags.add(languageTag);
    final currentGate = gate;
    if (currentGate != null) {
      await currentGate.future;
    }
  }

  @override
  Future<void> stop() async {
    stopCallCount += 1;
  }
}

class _EchoIdMessageFormatter implements RunVoiceMessageFormatter {
  const _EchoIdMessageFormatter();

  @override
  String format(
    RunVoiceAnnouncement announcement,
    RunVoiceSessionConfig config,
  ) {
    return announcement.id;
  }
}

class _ScriptedPolicy implements RunVoiceAnnouncementPolicy {
  _ScriptedPolicy(this._results);

  final List<RunVoicePolicyResult> _results;
  int _callIndex = 0;

  @override
  RunVoicePolicyResult evaluate({
    required RunVoiceSnapshot previous,
    required RunVoiceSnapshot current,
    required RunVoiceSessionConfig config,
    required Set<String> announcedIds,
  }) {
    if (_callIndex >= _results.length) {
      return const RunVoicePolicyResult.empty();
    }
    final result = _results[_callIndex];
    _callIndex += 1;
    return result;
  }
}

RunVoiceSnapshot _snapshot(
  int distanceMeters, {
  bool isActive = true,
  bool isPaused = false,
}) {
  return RunVoiceSnapshot(
    distanceMeters: distanceMeters,
    elapsed: Duration(seconds: distanceMeters),
    averagePace: null,
    isActive: isActive,
    isPaused: isPaused,
  );
}

RunVoiceSessionConfig _config({bool enabled = true}) {
  return RunVoiceSessionConfig(
    enabled: enabled,
    distanceIntervalMeters: 1000,
    timeInterval: null,
    // Elapsed-time/pace clauses are covered exhaustively by
    // run_voice_message_formatter_test.dart; keep this coordinator config
    // on the bare-line path so integration assertions below stay focused
    // on speak sequencing rather than message wording.
    includeElapsedTime: false,
    includeAveragePace: false,
    language: RunVoiceLanguage.english,
    targetDistanceMeters: null,
  );
}

RunVoiceAnnouncement _scriptedAnnouncement(String id, int priority) {
  return RunVoiceAnnouncement(
    id: id,
    type: RunVoiceAnnouncementType.distanceMilestone,
    priority: priority,
    distanceMeters: null,
    elapsed: Duration.zero,
    averagePace: null,
  );
}

RunVoiceCoachingCoordinator _realCoordinator(
  _FakeRunSpeechOutput speech, {
  Duration speakTimeout = RunVoiceCoachingCoordinator.defaultSpeakTimeout,
}) {
  return RunVoiceCoachingCoordinator(
    policy: DefaultRunVoiceAnnouncementPolicy(),
    selector: const PriorityRunVoiceAnnouncementSelector(),
    formatter: const LocalizedRunVoiceMessageFormatter(),
    speechOutput: speech,
    speakTimeout: speakTimeout,
  );
}

void main() {
  group('RunVoiceCoachingCoordinator', () {
    test('crossing 980, 1020, 1050 speaks the 1km milestone exactly once', () async {
      final speech = _FakeRunSpeechOutput();
      final coordinator = _realCoordinator(speech);

      await coordinator.startSession(_config());
      await coordinator.onSnapshot(_snapshot(980));
      await pumpEventQueue();
      await coordinator.onSnapshot(_snapshot(1020));
      await pumpEventQueue();
      await coordinator.onSnapshot(_snapshot(1050));
      await pumpEventQueue();

      expect(speech.spokenMessages, ['You have completed 1 kilometer.']);
      expect(speech.initializeCallCount, 1);
    });

    test('a disabled config never initializes or speaks', () async {
      final speech = _FakeRunSpeechOutput();
      final coordinator = _realCoordinator(speech);

      await coordinator.startSession(_config(enabled: false));
      await coordinator.onSnapshot(_snapshot(980));
      await pumpEventQueue();
      await coordinator.onSnapshot(_snapshot(1020));
      await pumpEventQueue();

      expect(speech.initializeCallCount, 0);
      expect(speech.spokenMessages, isEmpty);
    });

    test(
      'an utterance that never reports completion does not deadlock the '
      'drain loop for the rest of the run',
      () async {
        // initialize() sets awaitSpeakCompletion(true), so speak() only
        // resolves when the platform reports the utterance finished. When
        // audio is unavailable that callback can simply never arrive. Before
        // the timeout, the drain loop awaited it forever: `_speaking` stayed
        // true and every later announcement queued behind a loop that could no
        // longer advance, so one bad utterance silenced the whole run.
        final speech = _FakeRunSpeechOutput()..gate = Completer<void>();
        final coordinator = _realCoordinator(
          speech,
          speakTimeout: const Duration(milliseconds: 50),
        );

        await coordinator.startSession(_config());
        await coordinator.onSnapshot(_snapshot(980));
        await pumpEventQueue();
        await coordinator.onSnapshot(_snapshot(1020));
        await pumpEventQueue();

        expect(
          speech.spokenMessages,
          ['You have completed 1 kilometer.'],
          reason: 'the first utterance is in flight and never completes',
        );

        // The gate is deliberately still open: the 1 km utterance is
        // permanently stuck. A later milestone must still be announced.
        await coordinator.onSnapshot(_snapshot(2020));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await pumpEventQueue();

        expect(speech.spokenMessages, [
          'You have completed 1 kilometer.',
          'You have completed 2 kilometers.',
        ]);
      },
    );

    test('a throwing speech output does not surface an exception', () async {
      final speech = _FakeRunSpeechOutput()..throwOnSpeak = true;
      final coordinator = _realCoordinator(speech);

      await coordinator.startSession(_config());
      await expectLater(coordinator.onSnapshot(_snapshot(980)), completes);
      await pumpEventQueue();
      await expectLater(coordinator.onSnapshot(_snapshot(1020)), completes);
      await pumpEventQueue();

      expect(speech.spokenMessages, isEmpty);
    });

    test(
      'a paused snapshot between active ones does not repeat the 1km milestone',
      () async {
        final speech = _FakeRunSpeechOutput();
        final coordinator = _realCoordinator(speech);

        await coordinator.startSession(_config());
        await coordinator.onSnapshot(_snapshot(980));
        await pumpEventQueue();
        await coordinator.onSnapshot(_snapshot(1020));
        await pumpEventQueue();
        expect(speech.spokenMessages, hasLength(1));

        await coordinator.onSnapshot(_snapshot(1025, isPaused: true));
        await pumpEventQueue();
        await coordinator.onSnapshot(_snapshot(1040));
        await pumpEventQueue();

        expect(speech.spokenMessages, hasLength(1));
      },
    );

    test(
      'stopSession stops speech output and later snapshots produce no speech',
      () async {
        final speech = _FakeRunSpeechOutput();
        final coordinator = _realCoordinator(speech);

        await coordinator.startSession(_config());
        await coordinator.onSnapshot(_snapshot(980));
        await pumpEventQueue();
        await coordinator.onSnapshot(_snapshot(1020));
        await pumpEventQueue();
        expect(speech.spokenMessages, hasLength(1));

        await coordinator.stopSession();
        expect(speech.stopCallCount, 1);
        expect(coordinator.activeSessionCount, 0);

        await coordinator.onSnapshot(_snapshot(2100));
        await pumpEventQueue();

        expect(speech.spokenMessages, hasLength(1));
      },
    );

    test('stopSession is idempotent when called twice', () async {
      final speech = _FakeRunSpeechOutput();
      final coordinator = _realCoordinator(speech);

      await coordinator.startSession(_config());
      await expectLater(coordinator.stopSession(), completes);
      await expectLater(coordinator.stopSession(), completes);

      expect(speech.stopCallCount, 2);
      expect(coordinator.activeSessionCount, 0);
    });

    test(
      'a new session after stopSession can announce the first km again',
      () async {
        final speech = _FakeRunSpeechOutput();
        final coordinator = _realCoordinator(speech);

        await coordinator.startSession(_config());
        await coordinator.onSnapshot(_snapshot(980));
        await pumpEventQueue();
        await coordinator.onSnapshot(_snapshot(1020));
        await pumpEventQueue();
        expect(speech.spokenMessages, hasLength(1));

        await coordinator.stopSession();

        await coordinator.startSession(_config());
        expect(coordinator.activeSessionCount, 1);
        await coordinator.onSnapshot(_snapshot(980));
        await pumpEventQueue();
        await coordinator.onSnapshot(_snapshot(1020));
        await pumpEventQueue();

        expect(speech.spokenMessages, hasLength(2));
        expect(
          speech.spokenMessages,
          everyElement('You have completed 1 kilometer.'),
        );
      },
    );

    test(
      'queues distinct pending announcements in FIFO order while a gated '
      'speak is in flight, then drains them in arrival order',
      () async {
        final gate = Completer<void>();
        final speech = _FakeRunSpeechOutput()..gate = gate;
        final scriptedPolicy = _ScriptedPolicy([
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('low', 10)],
            consumedIds: {'low'},
          ),
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('mid', 40)],
            consumedIds: {'mid'},
          ),
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('high', 90)],
            consumedIds: {'high'},
          ),
        ]);
        final coordinator = RunVoiceCoachingCoordinator(
          policy: scriptedPolicy,
          selector: const PriorityRunVoiceAnnouncementSelector(),
          formatter: const _EchoIdMessageFormatter(),
          speechOutput: speech,
        );

        await coordinator.startSession(_config());

        // First evaluate call selects 'low'; nothing is speaking yet, so it
        // starts speaking immediately and blocks on the gate, simulating an
        // in-flight utterance.
        await coordinator.onSnapshot(_snapshot(0));
        await pumpEventQueue();
        expect(speech.spokenMessages, ['low']);
        expect(coordinator.pendingCount, 0);

        // Second evaluate call selects 'mid' (higher priority than 'low')
        // while speaking is still in flight: FIFO means it is enqueued
        // rather than replacing anything — priority no longer matters for
        // queue placement.
        await coordinator.onSnapshot(_snapshot(1));
        await pumpEventQueue();
        expect(coordinator.pendingCount, 1);
        expect(coordinator.pendingAnnouncement!.id, 'mid');

        // Third evaluate call selects 'high' (priority 90). Under the old
        // highest-priority-wins semantics this would have replaced 'mid';
        // under FIFO it is appended after 'mid' instead, and the queue
        // front remains the first-queued item.
        await coordinator.onSnapshot(_snapshot(2));
        await pumpEventQueue();
        expect(coordinator.pendingCount, 2);
        expect(coordinator.pendingAnnouncement!.id, 'mid');

        // Release the gate: the first ('low') utterance finishes, then the
        // drain loop speaks the queued items strictly in arrival order:
        // 'mid' before 'high'.
        gate.complete();
        await pumpEventQueue();

        expect(speech.spokenMessages, ['low', 'mid', 'high']);
        expect(coordinator.pendingCount, 0);
      },
    );

    test(
      'does not enqueue a duplicate id that is already speaking or already '
      'queued',
      () async {
        final gate = Completer<void>();
        final speech = _FakeRunSpeechOutput()..gate = gate;
        final scriptedPolicy = _ScriptedPolicy([
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('a', 10)],
            consumedIds: {'a'},
          ),
          // Duplicate of the announcement currently speaking ('a'): must be
          // dropped, not queued.
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('a', 10)],
            consumedIds: {},
          ),
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('b', 20)],
            consumedIds: {'b'},
          ),
          // Duplicate of an announcement already sitting in the queue
          // ('b'): must also be dropped.
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('b', 20)],
            consumedIds: {},
          ),
        ]);
        final coordinator = RunVoiceCoachingCoordinator(
          policy: scriptedPolicy,
          selector: const PriorityRunVoiceAnnouncementSelector(),
          formatter: const _EchoIdMessageFormatter(),
          speechOutput: speech,
        );

        await coordinator.startSession(_config());

        await coordinator.onSnapshot(_snapshot(0));
        await pumpEventQueue();
        expect(speech.spokenMessages, ['a']);

        await coordinator.onSnapshot(_snapshot(1));
        await pumpEventQueue();
        expect(coordinator.pendingCount, 0);

        await coordinator.onSnapshot(_snapshot(2));
        await pumpEventQueue();
        expect(coordinator.pendingCount, 1);
        expect(coordinator.pendingAnnouncement!.id, 'b');

        await coordinator.onSnapshot(_snapshot(3));
        await pumpEventQueue();
        expect(coordinator.pendingCount, 1);
        expect(coordinator.pendingAnnouncement!.id, 'b');

        gate.complete();
        await pumpEventQueue();

        expect(speech.spokenMessages, ['a', 'b']);
      },
    );

    test(
      'caps the pending queue length, dropping the oldest queued item on '
      'overflow',
      () async {
        final gate = Completer<void>();
        final speech = _FakeRunSpeechOutput()..gate = gate;
        // 1 announcement that starts speaking immediately + 10 distinct
        // announcements that arrive while it is in flight, well past the
        // queue cap of 8.
        final results = <RunVoicePolicyResult>[
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('seed', 0)],
            consumedIds: {'seed'},
          ),
          for (var i = 0; i < 10; i++)
            RunVoicePolicyResult(
              announcements: [_scriptedAnnouncement('q$i', i)],
              consumedIds: {'q$i'},
            ),
        ];
        final scriptedPolicy = _ScriptedPolicy(results);
        final coordinator = RunVoiceCoachingCoordinator(
          policy: scriptedPolicy,
          selector: const PriorityRunVoiceAnnouncementSelector(),
          formatter: const _EchoIdMessageFormatter(),
          speechOutput: speech,
        );

        await coordinator.startSession(_config());

        await coordinator.onSnapshot(_snapshot(0));
        await pumpEventQueue();
        expect(speech.spokenMessages, ['seed']);

        for (var i = 1; i <= 10; i++) {
          await coordinator.onSnapshot(_snapshot(i));
          await pumpEventQueue();
        }

        // The queue never exceeds the cap: the oldest queued items ('q0',
        // 'q1') were dropped to make room for 'q8' and 'q9'.
        expect(coordinator.pendingCount, 8);
        expect(coordinator.pendingAnnouncement!.id, 'q2');

        gate.complete();
        await pumpEventQueue();

        expect(speech.spokenMessages, [
          'seed',
          'q2',
          'q3',
          'q4',
          'q5',
          'q6',
          'q7',
          'q8',
          'q9',
        ]);
      },
    );

    test(
      'starting a new session while a gated speak of the old session is in '
      'flight does not let the stale drain speak into the new session',
      () async {
        final gate = Completer<void>();
        final speech = _FakeRunSpeechOutput()..gate = gate;
        final scriptedPolicy = _ScriptedPolicy([
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('old', 10)],
            consumedIds: {'old'},
          ),
          RunVoicePolicyResult(
            announcements: [_scriptedAnnouncement('old-pending', 20)],
            consumedIds: {'old-pending'},
          ),
        ]);
        final coordinator = RunVoiceCoachingCoordinator(
          policy: scriptedPolicy,
          selector: const PriorityRunVoiceAnnouncementSelector(),
          formatter: const _EchoIdMessageFormatter(),
          speechOutput: speech,
        );

        await coordinator.startSession(_config());

        // First evaluate call selects 'old'; nothing is speaking yet, so it
        // starts speaking immediately and blocks on the gate, simulating an
        // in-flight utterance for the old session generation.
        await coordinator.onSnapshot(_snapshot(0));
        await pumpEventQueue();
        expect(speech.spokenMessages, ['old']);

        // Second evaluate call selects 'old-pending' while speaking is
        // still in flight: it becomes pending for the old generation.
        await coordinator.onSnapshot(_snapshot(1));
        await pumpEventQueue();
        expect(coordinator.pendingCount, 1);

        // Starting a new session bumps the generation and clears pending
        // state synchronously, even though the old drain is still gated.
        await coordinator.startSession(_config());
        expect(coordinator.pendingCount, 0);

        // Releasing the gate lets the stale 'old' speak() call resolve.
        // The stale drain must detect the generation mismatch and stop
        // instead of speaking 'old-pending' into the new session.
        gate.complete();
        await pumpEventQueue();

        expect(speech.spokenMessages, ['old']);
        expect(coordinator.pendingCount, 0);
      },
    );
  });

  group('RunVoiceCoachingCoordinator multi-event announcements', () {
    test(
      'a snapshot crossing a distance milestone and target halfway together '
      'speaks both, distance before halfway',
      () async {
        final speech = _FakeRunSpeechOutput();
        final coordinator = _realCoordinator(speech);
        final config = RunVoiceSessionConfig(
          enabled: true,
          distanceIntervalMeters: 500,
          timeInterval: null,
          includeElapsedTime: false,
          includeAveragePace: false,
          language: RunVoiceLanguage.english,
          targetDistanceMeters: 5000,
        );

        await coordinator.startSession(config);
        await coordinator.onSnapshot(_snapshot(2400)); // baseline
        await pumpEventQueue();
        await coordinator.onSnapshot(_snapshot(2600)); // crosses 2500 + half
        await pumpEventQueue();

        expect(speech.spokenMessages, [
          'You have completed 2.5 kilometers.',
          'You are halfway to your goal.',
        ]);
      },
    );

    test(
      'a snapshot crossing a distance milestone and a time milestone '
      'together speaks both, distance before time',
      () async {
        final speech = _FakeRunSpeechOutput();
        final coordinator = _realCoordinator(speech);
        final config = RunVoiceSessionConfig(
          enabled: true,
          distanceIntervalMeters: 500,
          timeInterval: const Duration(seconds: 500),
          includeElapsedTime: false,
          includeAveragePace: false,
          language: RunVoiceLanguage.english,
          targetDistanceMeters: null,
        );

        await coordinator.startSession(config);
        await coordinator.onSnapshot(_snapshot(400)); // baseline
        await pumpEventQueue();
        await coordinator.onSnapshot(_snapshot(600)); // crosses 500m + 500s
        await pumpEventQueue();

        expect(speech.spokenMessages, [
          'You have completed 0.5 kilometers.',
          '8 minutes elapsed.',
        ]);
      },
    );

    test(
      'a snapshot crossing a distance milestone and target completion '
      'together speaks only the completion message',
      () async {
        final speech = _FakeRunSpeechOutput();
        final coordinator = _realCoordinator(speech);
        final config = RunVoiceSessionConfig(
          enabled: true,
          distanceIntervalMeters: 1000,
          timeInterval: null,
          includeElapsedTime: false,
          includeAveragePace: false,
          language: RunVoiceLanguage.english,
          targetDistanceMeters: 5000,
        );

        await coordinator.startSession(config);
        await coordinator.onSnapshot(_snapshot(4950)); // baseline
        await pumpEventQueue();
        await coordinator.onSnapshot(_snapshot(5030)); // crosses 5000 + goal
        await pumpEventQueue();

        expect(speech.spokenMessages, hasLength(1));
        expect(
          speech.spokenMessages.single,
          contains('You have reached your goal distance.'),
        );
      },
    );
  });
}
