// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import '../domain/models/run_voice_announcement.dart';
import '../domain/models/run_voice_language.dart';
import '../domain/models/run_voice_session_config.dart';
import '../domain/models/run_voice_snapshot.dart';
import '../domain/ports/run_speech_output.dart';
import '../domain/ports/run_voice_coach.dart';
import '../domain/services/run_voice_announcement_policy.dart';
import '../domain/services/run_voice_announcement_selector.dart';
import '../domain/services/run_voice_message_formatter.dart';

/// Coordinates announcement evaluation, selection, formatting, and speech
/// output for a single run session.
///
/// Snapshot evaluation and bookkeeping (`_previous`/`_consumedIds`) are
/// processed serially through [_tail] so overlapping calls to [onSnapshot]
/// never race each other. Speaking itself is intentionally detached from
/// that serialized queue (see [_speakAndDrain]): TTS wall-clock time must
/// never block evaluating newly-arriving GPS-driven snapshots. Overlap
/// while an utterance is in flight is resolved by enqueueing distinct
/// announcements in a bounded FIFO queue ([_queue]) and draining them, in
/// arrival order, once the current utterance finishes — so multiple
/// announcements that arrive close together all play in order and never
/// overlap. Every in-flight operation is guarded by a session [_generation]
/// counter and a [_stopped] flag so work started by a stale session cannot
/// mutate state after [startSession] or [stopSession] moves on.
class RunVoiceCoachingCoordinator implements RunVoiceCoach {
  RunVoiceCoachingCoordinator({
    required RunVoiceAnnouncementPolicy policy,
    required RunVoiceAnnouncementSelector selector,
    required RunVoiceMessageFormatter formatter,
    required RunSpeechOutput speechOutput,
    Duration speakTimeout = defaultSpeakTimeout,
  }) : _policy = policy,
       _selector = selector,
       _formatter = formatter,
       _speechOutput = speechOutput,
       _speakTimeout = speakTimeout;

  final RunVoiceAnnouncementPolicy _policy;
  final RunVoiceAnnouncementSelector _selector;
  final RunVoiceMessageFormatter _formatter;
  final RunSpeechOutput _speechOutput;
  final Duration _speakTimeout;

  static const int _maxQueue = 8;

  /// Upper bound on how long one utterance may block the drain loop. Chosen to
  /// sit well clear of the longest real announcement (the completion analysis,
  /// a few seconds spoken) so it only ever fires on a platform that has
  /// stopped reporting completion at all. Overridable so tests can exercise
  /// the timeout without waiting for it.
  static const Duration defaultSpeakTimeout = Duration(seconds: 30);

  RunVoiceSessionConfig? _config;
  RunVoiceSnapshot? _previous;
  final Set<String> _consumedIds = {};
  bool _speaking = false;
  String? _speakingId;
  final Queue<RunVoiceAnnouncement> _queue = Queue<RunVoiceAnnouncement>();
  bool _stopped = false;
  int _generation = 0;
  Future<void> _tail = Future<void>.value();

  int _activeSessionCount = 0;

  int get pendingCount => _queue.length;

  RunVoiceAnnouncement? get pendingAnnouncement =>
      _queue.isEmpty ? null : _queue.first;

  int get activeSessionCount => _activeSessionCount;

  @override
  Future<void> startSession(RunVoiceSessionConfig config) async {
    _generation += 1;
    _previous = null;
    _consumedIds.clear();
    _queue.clear();
    _speakingId = null;
    _speaking = false;
    _stopped = false;
    _config = config;
    _activeSessionCount = 1;
  }

  @override
  Future<void> onSnapshot(RunVoiceSnapshot snapshot) async {
    final generation = _generation;
    _tail = _tail.then((_) async {
      if (generation != _generation || _stopped || _config == null) {
        return;
      }
      await _process(snapshot);
    });
    return _tail;
  }

  @override
  Future<void> stopSession() async {
    _generation += 1;
    _stopped = true;
    _queue.clear();
    _speakingId = null;
    _speaking = false;
    _activeSessionCount = 0;
    await _speechOutput.stop();
  }

  Future<void> _process(RunVoiceSnapshot snapshot) async {
    final config = _config;
    if (config == null) {
      return;
    }

    final previous = _previous ?? snapshot;
    final result = _policy.evaluate(
      previous: previous,
      current: snapshot,
      config: config,
      announcedIds: _consumedIds,
    );
    _previous = snapshot;

    // Mark consumed before speaking so a persistently failing TTS call is
    // never retried for the same milestone.
    _consumedIds.addAll(result.consumedIds);

    final selected = _selector.select(result.announcements);
    if (selected == null) {
      return;
    }

    // A completion subsumes every other announcement crossed in the same
    // snapshot ("you're done" makes a plain distance milestone or halfway
    // callout redundant, or worse, confusing, right before/after it), so
    // only the completion is emitted in that case. In every other case the
    // selector's pick tells us no completion was crossed, so nothing needs
    // to be suppressed: emit the full set the policy produced, in its
    // existing (distance -> time -> halfway) order, so a snapshot that
    // crosses more than one milestone at once doesn't silently lose the
    // others — their ids are already marked consumed above and can never
    // re-cross to be announced later.
    final toEmit = selected.type == RunVoiceAnnouncementType.targetCompleted
        ? [selected]
        : result.announcements;

    for (final announcement in toEmit) {
      _enqueueOrSpeak(announcement);
    }
  }

  /// Routes a single announcement through the single-flight + FIFO-queue +
  /// dedupe(by id) + cap([_maxQueue]) logic: if nothing is currently
  /// speaking, it starts speaking immediately (synchronously flipping
  /// [_speaking] so a subsequent call in the same [_process] loop iteration
  /// enqueues instead of racing); otherwise it is deduped against the
  /// in-flight and queued ids and appended to [_queue].
  void _enqueueOrSpeak(RunVoiceAnnouncement announcement) {
    if (_speaking) {
      // Dedupe: never enqueue an announcement whose id is already being
      // spoken or already sitting in the queue.
      if (announcement.id == _speakingId ||
          _queue.any((queued) => queued.id == announcement.id)) {
        return;
      }
      if (_queue.length >= _maxQueue) {
        _queue.removeFirst();
        developer.log(
          'RUNIAC_VOICE queue overflow, dropped oldest',
          name: 'RunVoiceCoachingCoordinator',
        );
      }
      _queue.add(announcement);
      return;
    }

    _speaking = true;
    _speakingId = announcement.id;
    final g = _generation;
    unawaited(_speakAndDrain(announcement, g));
  }

  Future<void> _speakAndDrain(RunVoiceAnnouncement announcement, int g) async {
    if (g != _generation || _stopped) {
      _speaking = false;
      return;
    }
    await _speak(announcement, g);
    while (true) {
      if (g != _generation || _stopped) {
        _speaking = false;
        return;
      }
      if (_queue.isEmpty) {
        break;
      }
      final next = _queue.removeFirst();
      _speakingId = next.id;
      await _speak(next, g);
    }
    if (g == _generation) {
      _speaking = false;
      _speakingId = null;
    }
  }

  Future<void> _speak(RunVoiceAnnouncement announcement, int g) async {
    if (g != _generation || _stopped) {
      return;
    }
    // `RunSpeechOutput.initialize()` latches internally, and deliberately does
    // NOT latch when the audio session failed to come up, so it can retry.
    // A second latch here would defeat that and leave the runner silent for
    // the whole run after one transient failure.
    await _speechOutput.initialize();
    final config = _config;
    if (config == null) {
      return;
    }
    final message = _formatter.format(announcement, config);
    if (g != _generation || _stopped) {
      return;
    }
    try {
      // `initialize()` sets awaitSpeakCompletion(true), so this future only
      // resolves when the platform reports the utterance finished. When audio
      // is unavailable — an iOS session that never activated, or a backgrounded
      // app without the `audio` background mode — that callback may never
      // arrive, and an unbounded await would leave `_speaking` true for the
      // rest of the run, silently queueing every later announcement behind a
      // drain loop that can no longer advance. The timeout caps the cost of a
      // failed utterance at that one announcement.
      await _speechOutput
          .speak(message, languageTag: config.language.ttsLocale)
          .timeout(_speakTimeout);
    } on TimeoutException {
      developer.log(
        'RUNIAC_VOICE speak did not complete within '
        '${_speakTimeout.inSeconds}s, continuing',
        name: 'RunVoiceCoachingCoordinator',
      );
    } catch (_) {
      // TTS failures are isolated from the run session: swallow silently.
    }
  }
}
