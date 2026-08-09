import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/data/durable_challenge_result_seen_store.dart';
import 'package:runiac_app/features/challenge/domain/challenge_result_seen_store.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_history.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_result_presentation_controller.dart';

import 'support/fake_challenge_repository.dart';

/// A seen-store seam that can be made to fail, standing in for an offline or
/// rules-denied Firestore read/write.
class _FaultyChallengeResultSeenStore implements ChallengeResultSeenStore {
  _FaultyChallengeResultSeenStore({
    this.failReads = false,
    this.failWrites = false,
    int? initialEndedAtMs,
  }) : _lastSeenEndedAtMs = initialEndedAtMs;

  final bool failReads;
  final bool failWrites;
  int? _lastSeenEndedAtMs;
  int writeCount = 0;

  int? get lastWritten => _lastSeenEndedAtMs;

  @override
  Future<int?> lastSeenResultEndedAtMs() async {
    if (failReads) {
      throw StateError('unavailable');
    }
    return _lastSeenEndedAtMs;
  }

  @override
  Future<void> recordSeenResult(int endedAtMs) async {
    writeCount += 1;
    if (failWrites) {
      throw StateError('permission-denied');
    }
    if (_lastSeenEndedAtMs == null || endedAtMs > _lastSeenEndedAtMs!) {
      _lastSeenEndedAtMs = endedAtMs;
    }
  }
}

/// The remote write is fire-and-forget, so let its microtasks drain before
/// asserting on it.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

ChallengeHistoryEntry _entry({required int endedAtMs}) {
  return ChallengeHistoryEntry(
    challengeId: 'c-1',
    tierId: ChallengeTierId.k42,
    mode: ChallengeMode.solo,
    role: ChallengeParticipantRole.owner,
    outcome: ChallengeParticipantStatus.succeeded,
    terminalReason: ChallengeTerminalReason.targetReached,
    teamMeters: 42000,
    personalMeters: 42866,
    targetMeters: 42000,
    personalMinimumMeters: 7000,
    startedAtMs: 0,
    endedAtMs: endedAtMs,
  );
}

final DateTime _now = DateTime.utc(2026, 8, 9, 12);
int _msAgo(Duration age) => _now.subtract(age).millisecondsSinceEpoch;

void main() {
  group('durable seen marker', () {
    test('reads the account marker when the device mirror is empty', () async {
      // The reinstall case: preferences are gone, the account still remembers.
      final store = DurableChallengeResultSeenStore(
        remote: _FaultyChallengeResultSeenStore(initialEndedAtMs: 500),
        local: InMemoryChallengeResultSeenStore(),
      );

      expect(await store.lastSeenResultEndedAtMs(), 500);
    });

    test('records both copies, awaiting only the device mirror', () async {
      final remote = _FaultyChallengeResultSeenStore();
      final local = InMemoryChallengeResultSeenStore();
      final store = DurableChallengeResultSeenStore(
        remote: remote,
        local: local,
      );

      await store.recordSeenResult(700);

      // The mirror is durable before the ceremony opens...
      expect(await local.lastSeenResultEndedAtMs(), 700);
      // ...and the account copy follows without blocking the caller.
      await _settle();
      expect(remote.lastWritten, 700);
    });

    test('back-fills the account marker from a local-only mirror', () async {
      // Installs that celebrated before the account marker existed: without
      // this the very next reinstall would replay the ceremony once more.
      final remote = _FaultyChallengeResultSeenStore();
      final local = InMemoryChallengeResultSeenStore(initialEndedAtMs: 900);
      final store = DurableChallengeResultSeenStore(
        remote: remote,
        local: local,
      );

      expect(await store.lastSeenResultEndedAtMs(), 900);
      await _settle();
      expect(remote.lastWritten, 900);
    });

    test('keeps the newer of the two markers', () async {
      final store = DurableChallengeResultSeenStore(
        remote: _FaultyChallengeResultSeenStore(initialEndedAtMs: 400),
        local: InMemoryChallengeResultSeenStore(initialEndedAtMs: 800),
      );

      expect(await store.lastSeenResultEndedAtMs(), 800);
    });

    test('falls back to the device mirror when the account read fails', () async {
      final store = DurableChallengeResultSeenStore(
        remote: _FaultyChallengeResultSeenStore(failReads: true),
        local: InMemoryChallengeResultSeenStore(initialEndedAtMs: 600),
      );

      expect(await store.lastSeenResultEndedAtMs(), 600);
    });

    test('a failing account write never surfaces to the caller', () async {
      final remote = _FaultyChallengeResultSeenStore(failWrites: true);
      final local = InMemoryChallengeResultSeenStore();
      final store = DurableChallengeResultSeenStore(
        remote: remote,
        local: local,
      );

      await store.recordSeenResult(1000);
      await _settle();

      expect(remote.writeCount, 1);
      expect(await local.lastSeenResultEndedAtMs(), 1000);
    });
  });

  group('presentation after a reinstall', () {
    test('does not replay a result the account already acknowledged', () async {
      // Exactly the reported bug: the app is deleted and reinstalled while a
      // settled result is still inside the seven-day recency window.
      final endedAtMs = _msAgo(const Duration(days: 6));
      final repository = FakeChallengeRepository(
        historyOverride: <ChallengeHistoryEntry>[_entry(endedAtMs: endedAtMs)],
      );
      final controller = ChallengeResultPresentationController(
        repository: repository,
        seenStore: DurableChallengeResultSeenStore(
          remote: _FaultyChallengeResultSeenStore(initialEndedAtMs: endedAtMs),
          // Wiped by the reinstall.
          local: InMemoryChallengeResultSeenStore(),
        ),
      );

      expect(await controller.peekUnseenResult(now: _now), isNull);
    });

    test('still presents a result neither copy has seen', () async {
      final endedAtMs = _msAgo(const Duration(minutes: 1));
      final repository = FakeChallengeRepository(
        historyOverride: <ChallengeHistoryEntry>[_entry(endedAtMs: endedAtMs)],
      );
      final remote = _FaultyChallengeResultSeenStore();
      final controller = ChallengeResultPresentationController(
        repository: repository,
        seenStore: DurableChallengeResultSeenStore(
          remote: remote,
          local: InMemoryChallengeResultSeenStore(),
        ),
      );

      final result = await controller.peekUnseenResult(now: _now);
      expect(result, isNotNull);

      await controller.markSeen(result!.endedAtMs);
      await _settle();

      expect(remote.lastWritten, endedAtMs);
      expect(await controller.peekUnseenResult(now: _now), isNull);
    });
  });
}
