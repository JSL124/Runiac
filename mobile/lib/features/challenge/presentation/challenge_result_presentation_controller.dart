import '../domain/challenge_result_seen_store.dart';
import '../domain/models/challenge_history.dart';
import '../domain/repositories/challenge_repository.dart';

/// Drives the one-shot foreground presentation of a terminal Challenge result.
///
/// The host calls [peekUnseenResult] whenever a result may have become
/// available — on mount, on resume, when Home returns to the front, and when a
/// challenge-result notification streams into the inbox. It reads the caller's
/// durable history (newest first) and returns the newest entry that is strictly
/// newer than the locally-persisted "last seen" marker. Terminal state is owned
/// by the backend; this controller only decides whether the already-computed
/// result has been shown yet, and never recomputes eligibility or outcome.
///
/// Peeking does NOT advance the marker. The host calls [markSeen] once the
/// ceremony is actually on screen, so a caller that bails out between the two
/// (an unmounted widget, a navigation race) leaves the result available for the
/// next attempt instead of silently consuming it.
class ChallengeResultPresentationController {
  ChallengeResultPresentationController({
    required this.repository,
    required this.seenStore,
    this.recencyWindow = _defaultRecencyWindow,
  });

  /// How recent a result must be to auto-present.
  ///
  /// A runner whose marker cannot be read — a brand-new account, or a first
  /// launch with no connectivity and no local mirror — would otherwise treat
  /// the newest entry in a long history as unseen and be congratulated on a
  /// challenge they finished months ago. Bounding by age caps that and every
  /// other stale-replay case, and costs nothing in the normal path: a result
  /// settles within roughly a minute of the run that completed it.
  ///
  /// It is a backstop, not the mechanism. Reinstalling the app inside this
  /// window used to replay the ceremony because the marker lived only in device
  /// preferences; the marker is account-scoped now (see
  /// `DurableChallengeResultSeenStore`), so that no longer depends on the
  /// window being short.
  static const Duration _defaultRecencyWindow = Duration(days: 7);

  final ChallengeRepository repository;
  final ChallengeResultSeenStore seenStore;
  final Duration recencyWindow;

  bool _inFlight = false;

  /// Returns the newest unseen, recent terminal result without consuming it, or
  /// `null` when there is nothing to present. Never throws: a read failure
  /// yields `null` so a transient error simply presents nothing.
  Future<ChallengeResult?> peekUnseenResult({DateTime? now}) async {
    if (_inFlight) {
      return null;
    }
    _inFlight = true;
    try {
      final List<ChallengeHistoryEntry> history = await repository.history();
      if (history.isEmpty) {
        return null;
      }
      final int? marker = await seenStore.lastSeenResultEndedAtMs();
      final int oldestPresentableMs =
          (now ?? DateTime.now()).subtract(recencyWindow).millisecondsSinceEpoch;

      ChallengeHistoryEntry? newest;
      for (final entry in history) {
        if (marker != null && entry.endedAtMs <= marker) {
          continue;
        }
        if (entry.endedAtMs < oldestPresentableMs) {
          continue;
        }
        // history() is contractually newest-first (orderBy endedAt desc), but
        // scanning every candidate rather than trusting `history.first` keeps
        // this correct if that ordering ever changes, and makes the "newest
        // unseen" choice explicit.
        if (newest == null || entry.endedAtMs > newest.endedAtMs) {
          newest = entry;
        }
      }
      return newest?.toResult();
    } on ChallengeFailure {
      return null;
    } catch (_) {
      return null;
    } finally {
      _inFlight = false;
    }
  }

  /// Records that the result ending at [endedAtMs] has been shown, so it is not
  /// auto-presented again.
  ///
  /// Called both by the auto-present path once its ceremony is on screen and by
  /// the notification-inbox path, which shows the same ceremony on demand —
  /// without this the inbox route would leave the marker behind and the
  /// ceremony would replay on the next resume.
  Future<void> markSeen(int endedAtMs) async {
    try {
      await seenStore.recordSeenResult(endedAtMs);
    } catch (_) {
      // A marker write failure costs at most one duplicate ceremony; it must
      // never break the presentation the user is already looking at.
    }
  }

}
