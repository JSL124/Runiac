import '../domain/models/active_challenge.dart';
import '../domain/models/challenge_enums.dart';

/// Firebase-free display model for the Home stage-map active-challenge control.
///
/// The Home stage map must never touch a repository or Firestore, so `HomeTab`
/// resolves the caller's live [ActiveChallenge] and hands this plain, immutable
/// projection down. It carries only the tier badge, the server `scheduledEndsAt`
/// (for the injected-clock countdown), and the settling flag — never target,
/// team, or participant data. The control is shown ONLY for ACTIVE or SETTLING
/// instances; every other state ([fromActiveChallenge] returns null) hides it
/// entirely with no reserved gap.
class HomeActiveChallengeDisplay {
  const HomeActiveChallengeDisplay({
    required this.tierId,
    required this.scheduledEndsAtMs,
    required this.isSettling,
  });

  final ChallengeTierId tierId;

  /// Server-owned deadline in epoch millis; null while none is scheduled.
  final int? scheduledEndsAtMs;
  final bool isSettling;

  DateTime? get scheduledEndsAt => scheduledEndsAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(scheduledEndsAtMs!);

  /// Projects a live challenge to the Home control, or null when no control
  /// should render. Only ACTIVE and SETTLING surface a control; RECRUITING
  /// (still a lobby) and every terminal/result-ready state hide it.
  static HomeActiveChallengeDisplay? fromActiveChallenge(
    ActiveChallenge? challenge,
  ) {
    if (challenge == null) {
      return null;
    }
    final status = challenge.status;
    if (status != ChallengeInstanceStatus.active &&
        status != ChallengeInstanceStatus.settling) {
      return null;
    }
    return HomeActiveChallengeDisplay(
      tierId: challenge.tierId,
      scheduledEndsAtMs: challenge.scheduledEndsAtMs,
      isSettling: status == ChallengeInstanceStatus.settling,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HomeActiveChallengeDisplay &&
      other.tierId == tierId &&
      other.scheduledEndsAtMs == scheduledEndsAtMs &&
      other.isSettling == isSettling;

  @override
  int get hashCode => Object.hash(tierId, scheduledEndsAtMs, isSettling);
}
