/// The caller's own premium-lapse grace window, as relayed by the
/// `getActiveChallenge` callable.
///
/// The server opens a hold when a runner drops to Basic while participating in
/// a premium-only tier, and evicts them from the challenge if they are still
/// Basic when [graceExpiresAt] passes. The client only ever RENDERS this
/// deadline: it never computes eligibility, never decides eviction, and cannot
/// read the underlying `challengePremiumHolds/{uid}` document, which
/// `firestore.rules` denies to every client so that one runner's subscription
/// state is not visible to their lobby-mates.
class ChallengePremiumHold {
  const ChallengePremiumHold({required this.graceExpiresAtMs});

  final int graceExpiresAtMs;

  DateTime get graceExpiresAt =>
      DateTime.fromMillisecondsSinceEpoch(graceExpiresAtMs);

  /// The non-negative time left before the server may evict the runner.
  Duration remaining(DateTime now) {
    final difference = graceExpiresAt.difference(now);
    return difference.isNegative ? Duration.zero : difference;
  }

  bool hasExpired(DateTime now) => remaining(now) == Duration.zero;

  /// A coarse, human-readable window such as `23 hours` or `45 minutes`, or
  /// null when less than a minute remains — at which point the surface says
  /// removal is imminent rather than counting down to zero. Coarse on purpose:
  /// the exact instant depends on when the one-minute sweep next runs, so a
  /// ticking second-by-second countdown would promise a precision the backend
  /// does not offer.
  String? remainingLabel(DateTime now) {
    final left = remaining(now);
    if (left.inMinutes < 1) {
      return null;
    }
    if (left.inHours >= 1) {
      final hours = left.inHours;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    final minutes = left.inMinutes;
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  /// Reads the callable's `premiumHold` field. Returns null for an absent,
  /// malformed, or unreadable payload rather than throwing: a warning banner
  /// failing to parse must never take the whole active-challenge screen down
  /// with it.
  static ChallengePremiumHold? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final value = raw['graceExpiresAtMs'];
    if (value is int) {
      return ChallengePremiumHold(graceExpiresAtMs: value);
    }
    if (value is num) {
      return ChallengePremiumHold(graceExpiresAtMs: value.toInt());
    }
    return null;
  }
}
