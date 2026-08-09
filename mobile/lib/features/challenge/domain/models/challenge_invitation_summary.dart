import 'challenge_enums.dart';
import 'challenge_parse.dart';
import 'challenge_rules_snapshot.dart';

/// A Challenge invitation as seen by a recipient (pending inbox) or an owner
/// (lobby roster chip).
///
/// [rules] may be absent when the backend could not resolve the tier's rules.
class ChallengeInvitationSummary {
  const ChallengeInvitationSummary({
    required this.inviteId,
    required this.challengeId,
    required this.tierId,
    required this.ownerUid,
    required this.status,
    required this.createdAtMs,
    required this.expiresAtMs,
    required this.rules,
  });

  final String inviteId;
  final String challengeId;
  final ChallengeTierId tierId;
  final String ownerUid;
  final ChallengeInvitationStatus status;
  final int createdAtMs;
  final int expiresAtMs;
  final ChallengeRulesSnapshot? rules;

  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch(expiresAtMs);

  /// Parses one entry of the `getChallengeInvitations` result. That callable
  /// returns only PENDING invitations and omits an explicit `status` field, so
  /// PENDING here is the callable's contract, not a fabricated default.
  static ChallengeInvitationSummary fromPendingView(Map<String, Object?> map) {
    final rawRules = map['rules'];
    return ChallengeInvitationSummary(
      inviteId: ChallengeParse.string(map, 'inviteId'),
      challengeId: ChallengeParse.string(map, 'challengeId'),
      tierId: ChallengeTierId.parse(ChallengeParse.string(map, 'tierId')),
      ownerUid: ChallengeParse.string(map, 'ownerUid'),
      status: ChallengeInvitationStatus.pending,
      createdAtMs: ChallengeParse.integer(map, 'createdAtMs'),
      expiresAtMs: ChallengeParse.integer(map, 'expiresAtMs'),
      rules: rawRules == null
          ? null
          : ChallengeRulesSnapshot.fromMap(
              ChallengeParse.asMap(rawRules, field: 'rules'),
            ),
    );
  }

  /// Parses an invitation whose `status` is carried explicitly (e.g. an owner's
  /// lobby roster chip view). Strict: an unknown/missing status is a failure.
  static ChallengeInvitationSummary fromMap(Map<String, Object?> map) {
    final rawRules = map['rules'];
    return ChallengeInvitationSummary(
      inviteId: ChallengeParse.string(map, 'inviteId'),
      challengeId: ChallengeParse.string(map, 'challengeId'),
      tierId: ChallengeTierId.parse(ChallengeParse.string(map, 'tierId')),
      ownerUid: ChallengeParse.string(map, 'ownerUid'),
      status:
          ChallengeInvitationStatus.parse(ChallengeParse.string(map, 'status')),
      createdAtMs: ChallengeParse.integer(map, 'createdAtMs'),
      expiresAtMs: ChallengeParse.integer(map, 'expiresAtMs'),
      rules: rawRules == null
          ? null
          : ChallengeRulesSnapshot.fromMap(
              ChallengeParse.asMap(rawRules, field: 'rules'),
            ),
    );
  }
}
