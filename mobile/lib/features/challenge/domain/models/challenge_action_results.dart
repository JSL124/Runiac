import 'challenge_enums.dart';
import 'challenge_parse.dart';
import 'challenge_parse_exception.dart';

/// Result of `createChallengeLobby`.
class CreateLobbyResult {
  const CreateLobbyResult({
    required this.challengeId,
    required this.status,
    required this.idempotent,
  });

  final String challengeId;
  final ChallengeInstanceStatus status;
  final bool idempotent;

  static CreateLobbyResult fromMap(Map<String, Object?> map) {
    return CreateLobbyResult(
      challengeId: ChallengeParse.string(map, 'challengeId'),
      status:
          ChallengeInstanceStatus.parse(ChallengeParse.string(map, 'status')),
      idempotent: ChallengeParse.optionalBoolean(map, 'idempotent',
          orElse: false),
    );
  }
}

/// Result of `inviteChallengeFriends`.
class InviteResult {
  const InviteResult({
    required this.challengeId,
    required this.invited,
    required this.alreadyPending,
  });

  final String challengeId;
  final List<String> invited;
  final List<String> alreadyPending;

  static InviteResult fromMap(Map<String, Object?> map) {
    return InviteResult(
      challengeId: ChallengeParse.string(map, 'challengeId'),
      invited: _stringList(map['invited'], field: 'invited'),
      alreadyPending:
          _stringList(map['alreadyPending'], field: 'alreadyPending'),
    );
  }
}

/// Result of `respondToChallengeInvitation`.
class RespondResult {
  const RespondResult({
    required this.challengeId,
    required this.accepted,
    required this.idempotent,
  });

  final String challengeId;

  /// `true` when the recipient accepted, `false` when they declined.
  final bool accepted;
  final bool idempotent;

  static RespondResult fromMap(Map<String, Object?> map) {
    final outcome = ChallengeParse.string(map, 'outcome');
    final accepted = switch (outcome) {
      'accepted' => true,
      'declined' => false,
      _ => throw const ChallengeParseException(
          'unknown_respond_outcome',
          field: 'outcome',
        ),
    };
    return RespondResult(
      challengeId: ChallengeParse.string(map, 'challengeId'),
      accepted: accepted,
      idempotent: ChallengeParse.optionalBoolean(map, 'idempotent',
          orElse: false),
    );
  }
}

/// Result of `withdrawFromChallengeLobby`.
class WithdrawResult {
  const WithdrawResult({required this.challengeId, required this.idempotent});

  final String challengeId;
  final bool idempotent;

  static WithdrawResult fromMap(Map<String, Object?> map) {
    return WithdrawResult(
      challengeId: ChallengeParse.string(map, 'challengeId'),
      idempotent: ChallengeParse.optionalBoolean(map, 'idempotent',
          orElse: false),
    );
  }
}

/// Result of `cancelChallengeLobby`.
class CancelLobbyResult {
  const CancelLobbyResult({required this.challengeId, required this.idempotent});

  final String challengeId;
  final bool idempotent;

  static CancelLobbyResult fromMap(Map<String, Object?> map) {
    return CancelLobbyResult(
      challengeId: ChallengeParse.string(map, 'challengeId'),
      idempotent: ChallengeParse.optionalBoolean(map, 'idempotent',
          orElse: false),
    );
  }
}

/// Result of `startChallenge`.
class StartChallengeResult {
  const StartChallengeResult({
    required this.challengeId,
    required this.mode,
    required this.rosterUids,
    required this.startsAtMs,
    required this.scheduledEndsAtMs,
    required this.idempotent,
  });

  final String challengeId;
  final ChallengeMode mode;
  final List<String> rosterUids;
  final int startsAtMs;
  final int scheduledEndsAtMs;
  final bool idempotent;

  static StartChallengeResult fromMap(Map<String, Object?> map) {
    return StartChallengeResult(
      challengeId: ChallengeParse.string(map, 'challengeId'),
      mode: ChallengeMode.parse(ChallengeParse.string(map, 'mode')),
      rosterUids: _stringList(map['rosterUids'], field: 'rosterUids'),
      startsAtMs: ChallengeParse.integer(map, 'startsAtMs'),
      scheduledEndsAtMs: ChallengeParse.integer(map, 'scheduledEndsAtMs'),
      idempotent: ChallengeParse.optionalBoolean(map, 'idempotent',
          orElse: false),
    );
  }
}

/// Result of `leaveChallenge`.
class LeaveChallengeResult {
  const LeaveChallengeResult({
    required this.challengeId,
    required this.idempotent,
  });

  final String challengeId;
  final bool idempotent;

  static LeaveChallengeResult fromMap(Map<String, Object?> map) {
    return LeaveChallengeResult(
      challengeId: ChallengeParse.string(map, 'challengeId'),
      idempotent: ChallengeParse.optionalBoolean(map, 'idempotent',
          orElse: false),
    );
  }
}

/// Result of `abandonChallenge`.
class AbandonChallengeResult {
  const AbandonChallengeResult({
    required this.challengeId,
    required this.idempotent,
  });

  final String challengeId;
  final bool idempotent;

  static AbandonChallengeResult fromMap(Map<String, Object?> map) {
    return AbandonChallengeResult(
      challengeId: ChallengeParse.string(map, 'challengeId'),
      idempotent: ChallengeParse.optionalBoolean(map, 'idempotent',
          orElse: false),
    );
  }
}

List<String> _stringList(Object? value, {required String field}) {
  final list = ChallengeParse.asList(value, field: field);
  return List<String>.unmodifiable(
    list.map(
      (entry) => entry is String
          ? entry
          : throw ChallengeParseException('expected_string', field: field),
    ),
  );
}
