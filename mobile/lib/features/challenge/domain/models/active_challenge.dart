import 'challenge_enums.dart';
import 'challenge_parse.dart';
import 'challenge_parse_exception.dart';
import 'challenge_participant_row.dart';
import 'challenge_premium_hold.dart';
import 'challenge_rules_snapshot.dart';

/// The caller's current live Challenge (recruiting, active, or settling), as
/// returned by the `getActiveChallenge` callable.
///
/// [teamMeters] is the backend-clamped exposed total (it stops at the target
/// the instant the target is reached). The client reads it verbatim and never
/// re-sums participant metres to derive team progress.
class ActiveChallenge {
  const ActiveChallenge({
    required this.challengeId,
    required this.ownerUid,
    required this.tierId,
    required this.mode,
    required this.status,
    required this.rules,
    required this.rosterUids,
    required this.maxParticipants,
    required this.teamMeters,
    required this.createdAtMs,
    required this.lobbyExpiresAtMs,
    required this.startsAtMs,
    required this.scheduledEndsAtMs,
    required this.terminalReason,
    required this.participants,
    required this.isCurrentUserOwner,
    this.premiumHold,
  });

  final String challengeId;
  final String ownerUid;
  final ChallengeTierId tierId;
  final ChallengeMode mode;
  final ChallengeInstanceStatus status;
  final ChallengeRulesSnapshot rules;
  final List<String> rosterUids;
  final int maxParticipants;

  /// Backend-clamped team total in integer metres (never client-recomputed).
  final int teamMeters;
  final int createdAtMs;
  final int lobbyExpiresAtMs;
  final int? startsAtMs;
  final int? scheduledEndsAtMs;
  final ChallengeTerminalReason? terminalReason;
  final List<ChallengeParticipantRow> participants;
  final bool isCurrentUserOwner;

  /// The CALLER's own premium-lapse grace window, or null. Never any other
  /// roster member's: it is relayed as a sibling of `challenge` in the
  /// `getActiveChallenge` response and is scoped to the caller server-side.
  final ChallengePremiumHold? premiumHold;

  bool get isSettling => status == ChallengeInstanceStatus.settling;

  DateTime? get scheduledEndsAt => scheduledEndsAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(scheduledEndsAtMs!);

  DateTime? get startsAt => startsAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(startsAtMs!);

  /// Parses the non-null `challenge` object of an `ActiveChallengeView`.
  static ActiveChallenge fromChallengeMap(
    Map<String, Object?> map, {
    required String? currentUid,
    ChallengePremiumHold? premiumHold,
  }) {
    final instance = ChallengeParse.asMap(map['instance'], field: 'instance');
    final rawParticipants =
        ChallengeParse.asList(map['participants'], field: 'participants');
    final ownerUid = ChallengeParse.string(instance, 'ownerUid');
    final rosterRaw =
        ChallengeParse.asList(instance['rosterUids'], field: 'rosterUids');
    final rosterUids = rosterRaw
        .map((entry) => entry is String
            ? entry
            : throw const ChallengeParseException(
                'expected_string',
                field: 'rosterUids[]',
              ))
        .toList(growable: false);
    final terminalReasonRaw =
        ChallengeParse.optionalString(instance, 'terminalReason');
    final participants = rawParticipants
        .map(
          (entry) => ChallengeParticipantRow.fromMap(
            ChallengeParse.asMap(entry, field: 'participants[]'),
            currentUid: currentUid,
          ),
        )
        .toList(growable: false);

    return ActiveChallenge(
      challengeId: ChallengeParse.string(instance, 'challengeId'),
      ownerUid: ownerUid,
      tierId: ChallengeTierId.parse(ChallengeParse.string(instance, 'tierId')),
      mode: ChallengeMode.parse(ChallengeParse.string(instance, 'mode')),
      status: ChallengeInstanceStatus.parse(
        ChallengeParse.string(instance, 'status'),
      ),
      rules: ChallengeRulesSnapshot.fromMap(
        ChallengeParse.asMap(instance['rules'], field: 'rules'),
      ),
      rosterUids: List<String>.unmodifiable(rosterUids),
      maxParticipants: ChallengeParse.integer(instance, 'maxParticipants'),
      teamMeters: ChallengeParse.integer(instance, 'teamMeters'),
      createdAtMs: ChallengeParse.integer(instance, 'createdAtMs'),
      lobbyExpiresAtMs: ChallengeParse.integer(instance, 'lobbyExpiresAtMs'),
      startsAtMs: ChallengeParse.optionalInteger(instance, 'startsAtMs'),
      scheduledEndsAtMs:
          ChallengeParse.optionalInteger(instance, 'scheduledEndsAtMs'),
      terminalReason: terminalReasonRaw == null
          ? null
          : ChallengeTerminalReason.parse(terminalReasonRaw),
      participants: List<ChallengeParticipantRow>.unmodifiable(participants),
      isCurrentUserOwner: currentUid != null && currentUid == ownerUid,
      premiumHold: premiumHold,
    );
  }
}
