import 'dart:async';

import '../domain/challenge_result_seen_store.dart';

/// Pairs the account-scoped Result marker with the device-local mirror, so the
/// ceremony is presented once per result per *account* rather than once per
/// installation.
///
/// Read returns the newer of the two markers. That is what makes a reinstall
/// silent: the local mirror is gone, but the account still remembers. Read also
/// back-fills the remote marker when only the local one knows about a result —
/// the migration path for installs that celebrated before the account marker
/// existed, which would otherwise replay exactly once more on their next
/// reinstall.
///
/// Write records the local mirror first and awaits it, because that is the copy
/// the very next check reads and it must be durable before the ceremony opens.
/// The remote write is deliberately NOT awaited: a Firestore write does not
/// complete until the server acknowledges it, so offline it would hang the
/// caller — and `HomeTab` awaits `markSeen` immediately before pushing the
/// ceremony route. Pending writes are queued by the SDK and land on reconnect.
///
/// Every remote failure is swallowed. The worst case degrades to the previous
/// behaviour (a local-only marker), never to a broken celebration.
class DurableChallengeResultSeenStore implements ChallengeResultSeenStore {
  DurableChallengeResultSeenStore({required this.remote, required this.local});

  /// Account-scoped marker; survives reinstalls and reaches every device.
  final ChallengeResultSeenStore remote;

  /// Device-local mirror; survives being offline and answers immediately.
  final ChallengeResultSeenStore local;

  @override
  Future<int?> lastSeenResultEndedAtMs() async {
    final localMs = await _read(local);
    final remoteMs = await _read(remote);
    if (remoteMs == null) {
      if (localMs != null) {
        _recordRemote(localMs);
      }
      return localMs;
    }
    if (localMs == null) {
      return remoteMs;
    }
    if (localMs > remoteMs) {
      _recordRemote(localMs);
      return localMs;
    }
    return remoteMs;
  }

  @override
  Future<void> recordSeenResult(int endedAtMs) async {
    await local.recordSeenResult(endedAtMs);
    _recordRemote(endedAtMs);
  }

  Future<int?> _read(ChallengeResultSeenStore store) async {
    try {
      return await store.lastSeenResultEndedAtMs();
    } catch (_) {
      return null;
    }
  }

  void _recordRemote(int endedAtMs) {
    unawaited(
      Future<void>(() => remote.recordSeenResult(endedAtMs)).catchError((
        Object _,
      ) {
        // A marker write failure costs at most one duplicate ceremony after a
        // reinstall; it must never surface to the runner.
      }),
    );
  }
}
