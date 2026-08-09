import 'challenge_enums.dart';
import 'challenge_invitation_summary.dart';
import 'challenge_parse.dart';
import 'challenge_parse_exception.dart';
import 'challenge_participant_row.dart';
import 'challenge_rules_snapshot.dart';

/// A RECRUITING lobby view: the instance, its accepted roster, and (when
/// available) the invitation chips an owner sees.
///
/// The `getActiveChallenge` callable returns the instance and participants but
/// not invitations, so [invitations] defaults to empty and is populated only by
/// a caller that has a separate invitation source. Nothing here is computed on
/// the client.
class ChallengeLobby {
  const ChallengeLobby({
    required this.challengeId,
    required this.ownerUid,
    required this.tierId,
    required this.status,
    required this.rules,
    required this.rosterUids,
    required this.maxParticipants,
    required this.lobbyExpiresAtMs,
    required this.participants,
    required this.invitations,
    required this.isCurrentUserOwner,
  });

  final String challengeId;
  final String ownerUid;
  final ChallengeTierId tierId;
  final ChallengeInstanceStatus status;
  final ChallengeRulesSnapshot rules;
  final List<String> rosterUids;
  final int maxParticipants;
  final int lobbyExpiresAtMs;
  final List<ChallengeParticipantRow> participants;
  final List<ChallengeInvitationSummary> invitations;
  final bool isCurrentUserOwner;

  DateTime get lobbyExpiresAt =>
      DateTime.fromMillisecondsSinceEpoch(lobbyExpiresAtMs);

  /// Builds a lobby view from the non-null `challenge` object of an
  /// `ActiveChallengeView`, optionally merging a separately-sourced invitation
  /// list.
  static ChallengeLobby fromChallengeMap(
    Map<String, Object?> map, {
    required String? currentUid,
    List<ChallengeInvitationSummary> invitations =
        const <ChallengeInvitationSummary>[],
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
    final participants = rawParticipants
        .map(
          (entry) => ChallengeParticipantRow.fromMap(
            ChallengeParse.asMap(entry, field: 'participants[]'),
            currentUid: currentUid,
          ),
        )
        .toList(growable: false);

    return ChallengeLobby(
      challengeId: ChallengeParse.string(instance, 'challengeId'),
      ownerUid: ownerUid,
      tierId: ChallengeTierId.parse(ChallengeParse.string(instance, 'tierId')),
      status: ChallengeInstanceStatus.parse(
        ChallengeParse.string(instance, 'status'),
      ),
      rules: ChallengeRulesSnapshot.fromMap(
        ChallengeParse.asMap(instance['rules'], field: 'rules'),
      ),
      rosterUids: List<String>.unmodifiable(rosterUids),
      maxParticipants: ChallengeParse.integer(instance, 'maxParticipants'),
      lobbyExpiresAtMs: ChallengeParse.integer(instance, 'lobbyExpiresAtMs'),
      participants: List<ChallengeParticipantRow>.unmodifiable(participants),
      invitations:
          List<ChallengeInvitationSummary>.unmodifiable(invitations),
      isCurrentUserOwner: currentUid != null && currentUid == ownerUid,
    );
  }
}
