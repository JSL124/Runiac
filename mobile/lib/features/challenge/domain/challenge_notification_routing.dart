/// Pure routing table from a persisted Challenge notification inbox payload to a
/// client destination.
///
/// The backend allowlists exactly six challenge notification `kind` strings and
/// a minimal `data` map (`challengeId`, `tierId`, `kind`, `route`, `outcome`,
/// `creditedMeters`) — see `functions/src/challenge/challengeNotifications.ts`
/// and `functions/src/notifications/types.ts`. This module inspects that map and
/// decides where a tap should navigate. It never inspects trusted state and
/// never computes an outcome; it only maps a delivered kind to a destination.
library;

/// Where a tapped challenge notification should navigate.
enum ChallengeNotificationDestination {
  /// Pending invitations list (`challenge_invitation_received`).
  invitations,

  /// Active-challenge Progress surface (`challenge_started`,
  /// `challenge_participant_left`).
  progress,

  /// Personalized full-screen Result, fetched by `challengeId`
  /// (`challenge_owner_cancelled`, `challenge_result_ready`,
  /// `challenge_badge_issued`).
  result,
}

/// The exact backend `ChallengeNotificationKind` wire strings.
abstract final class ChallengeNotificationKinds {
  static const invitationReceived = 'challenge_invitation_received';
  static const started = 'challenge_started';
  static const participantLeft = 'challenge_participant_left';
  static const ownerCancelled = 'challenge_owner_cancelled';
  static const resultReady = 'challenge_result_ready';
  static const badgeIssued = 'challenge_badge_issued';
}

/// A resolved navigation intent parsed from a notification `data` map.
class ChallengeNotificationTarget {
  const ChallengeNotificationTarget({
    required this.destination,
    required this.challengeId,
  });

  final ChallengeNotificationDestination destination;

  /// The `challengeId` from the payload; empty when the payload omitted it.
  /// The progress/result destinations need it to fetch the right surface.
  final String challengeId;

  @override
  bool operator ==(Object other) =>
      other is ChallengeNotificationTarget &&
      other.destination == destination &&
      other.challengeId == challengeId;

  @override
  int get hashCode => Object.hash(destination, challengeId);
}

/// Resolves a notification inbox `data` map to a challenge destination, or
/// `null` when the payload is not a challenge notification (so non-challenge
/// inbox items keep their existing mark-read-only behaviour).
ChallengeNotificationTarget? challengeNotificationTargetFor(
  Map<String, Object?> data,
) {
  final kind = data['kind'];
  if (kind is! String) {
    return null;
  }
  final destination = switch (kind) {
    ChallengeNotificationKinds.invitationReceived =>
      ChallengeNotificationDestination.invitations,
    ChallengeNotificationKinds.started ||
    ChallengeNotificationKinds.participantLeft =>
      ChallengeNotificationDestination.progress,
    ChallengeNotificationKinds.ownerCancelled ||
    ChallengeNotificationKinds.resultReady ||
    ChallengeNotificationKinds.badgeIssued =>
      ChallengeNotificationDestination.result,
    _ => null,
  };
  if (destination == null) {
    return null;
  }
  final rawChallengeId = data['challengeId'];
  return ChallengeNotificationTarget(
    destination: destination,
    challengeId: rawChallengeId is String ? rawChallengeId : '',
  );
}
