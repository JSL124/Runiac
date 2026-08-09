import 'challenge_parse_exception.dart';

/// Server-owned Challenge enums mirrored as strict Dart unions.
///
/// Each `parse` resolves the exact backend wire string through an exhaustive
/// switch. An unknown value raises [ChallengeParseException]; the client never
/// coerces an unrecognized state into a benign default.

enum ChallengeTierId {
  k10('10K'),
  k20('20K'),
  k42('42K'),
  k100('100K'),
  k200('200K'),
  k250('250K'),
  k300('300K'),
  k500('500K'),
  k1000('1000K');

  const ChallengeTierId(this.wireValue);

  /// The backend catalog tier identifier (e.g. `10K`).
  final String wireValue;

  static ChallengeTierId parse(String value) {
    return switch (value) {
      '10K' => ChallengeTierId.k10,
      '20K' => ChallengeTierId.k20,
      '42K' => ChallengeTierId.k42,
      '100K' => ChallengeTierId.k100,
      '200K' => ChallengeTierId.k200,
      '250K' => ChallengeTierId.k250,
      '300K' => ChallengeTierId.k300,
      '500K' => ChallengeTierId.k500,
      '1000K' => ChallengeTierId.k1000,
      _ => throw ChallengeParseException('unknown_tier_id', field: 'tierId'),
    };
  }
}

enum ChallengeMode {
  solo('SOLO'),
  group('GROUP');

  const ChallengeMode(this.wireValue);

  final String wireValue;

  static ChallengeMode parse(String value) {
    return switch (value) {
      'SOLO' => ChallengeMode.solo,
      'GROUP' => ChallengeMode.group,
      _ => throw ChallengeParseException('unknown_mode', field: 'mode'),
    };
  }
}

enum ChallengeInstanceStatus {
  recruiting('RECRUITING'),
  active('ACTIVE'),
  settling('SETTLING'),
  succeeded('SUCCEEDED'),
  failed('FAILED'),
  cancelled('CANCELLED'),
  expired('EXPIRED');

  const ChallengeInstanceStatus(this.wireValue);

  final String wireValue;

  /// True once the instance has reached a terminal state (no further
  /// contribution or transition is possible).
  bool get isTerminal =>
      this == ChallengeInstanceStatus.succeeded ||
      this == ChallengeInstanceStatus.failed ||
      this == ChallengeInstanceStatus.cancelled ||
      this == ChallengeInstanceStatus.expired;

  static ChallengeInstanceStatus parse(String value) {
    return switch (value) {
      'RECRUITING' => ChallengeInstanceStatus.recruiting,
      'ACTIVE' => ChallengeInstanceStatus.active,
      'SETTLING' => ChallengeInstanceStatus.settling,
      'SUCCEEDED' => ChallengeInstanceStatus.succeeded,
      'FAILED' => ChallengeInstanceStatus.failed,
      'CANCELLED' => ChallengeInstanceStatus.cancelled,
      'EXPIRED' => ChallengeInstanceStatus.expired,
      _ => throw ChallengeParseException('unknown_instance_status',
          field: 'status'),
    };
  }
}

enum ChallengeParticipantRole {
  owner('owner'),
  member('member');

  const ChallengeParticipantRole(this.wireValue);

  final String wireValue;

  static ChallengeParticipantRole parse(String value) {
    return switch (value) {
      'owner' => ChallengeParticipantRole.owner,
      'member' => ChallengeParticipantRole.member,
      _ => throw ChallengeParseException('unknown_participant_role',
          field: 'role'),
    };
  }
}

enum ChallengeParticipantStatus {
  accepted('ACCEPTED'),
  active('ACTIVE'),
  left('LEFT'),
  cancelled('CANCELLED'),
  succeeded('SUCCEEDED'),
  ineligible('INELIGIBLE'),
  failed('FAILED');

  const ChallengeParticipantStatus(this.wireValue);

  final String wireValue;

  static ChallengeParticipantStatus parse(String value) {
    return switch (value) {
      'ACCEPTED' => ChallengeParticipantStatus.accepted,
      'ACTIVE' => ChallengeParticipantStatus.active,
      'LEFT' => ChallengeParticipantStatus.left,
      'CANCELLED' => ChallengeParticipantStatus.cancelled,
      'SUCCEEDED' => ChallengeParticipantStatus.succeeded,
      'INELIGIBLE' => ChallengeParticipantStatus.ineligible,
      'FAILED' => ChallengeParticipantStatus.failed,
      _ => throw ChallengeParseException('unknown_participant_status',
          field: 'status'),
    };
  }
}

enum ChallengeInvitationStatus {
  pending('PENDING'),
  accepted('ACCEPTED'),
  declined('DECLINED'),
  revoked('REVOKED'),
  expired('EXPIRED');

  const ChallengeInvitationStatus(this.wireValue);

  final String wireValue;

  static ChallengeInvitationStatus parse(String value) {
    return switch (value) {
      'PENDING' => ChallengeInvitationStatus.pending,
      'ACCEPTED' => ChallengeInvitationStatus.accepted,
      'DECLINED' => ChallengeInvitationStatus.declined,
      'REVOKED' => ChallengeInvitationStatus.revoked,
      'EXPIRED' => ChallengeInvitationStatus.expired,
      _ => throw ChallengeParseException('unknown_invitation_status',
          field: 'status'),
    };
  }
}

enum ChallengeRewardStatus {
  notEligible('NOT_ELIGIBLE'),
  pending('PENDING'),
  issued('ISSUED');

  const ChallengeRewardStatus(this.wireValue);

  final String wireValue;

  static ChallengeRewardStatus parse(String value) {
    return switch (value) {
      'NOT_ELIGIBLE' => ChallengeRewardStatus.notEligible,
      'PENDING' => ChallengeRewardStatus.pending,
      'ISSUED' => ChallengeRewardStatus.issued,
      _ => throw ChallengeParseException('unknown_reward_status',
          field: 'reward'),
    };
  }
}

enum ChallengeTerminalReason {
  targetReached('TARGET_REACHED'),
  deadlineFailed('DEADLINE_FAILED'),
  ownerAbandoned('OWNER_ABANDONED'),
  lobbyCancelled('LOBBY_CANCELLED'),
  lobbyExpired('LOBBY_EXPIRED'),

  /// The owner's premium subscription lapsed on a premium-only tier and no
  /// remaining participant was eligible to inherit the challenge.
  ownerPremiumLapsed('OWNER_PREMIUM_LAPSED');

  const ChallengeTerminalReason(this.wireValue);

  final String wireValue;

  static ChallengeTerminalReason parse(String value) {
    return switch (value) {
      'TARGET_REACHED' => ChallengeTerminalReason.targetReached,
      'DEADLINE_FAILED' => ChallengeTerminalReason.deadlineFailed,
      'OWNER_ABANDONED' => ChallengeTerminalReason.ownerAbandoned,
      'LOBBY_CANCELLED' => ChallengeTerminalReason.lobbyCancelled,
      'LOBBY_EXPIRED' => ChallengeTerminalReason.lobbyExpired,
      'OWNER_PREMIUM_LAPSED' => ChallengeTerminalReason.ownerPremiumLapsed,
      _ => throw ChallengeParseException('unknown_terminal_reason',
          field: 'terminalReason'),
    };
  }
}
