import 'challenge_enums.dart';
import 'challenge_parse.dart';

/// Immutable mirror of the server-authored rules snapshot recorded on an
/// instance at start (or attached to a catalog/invitation view).
///
/// All numbers are backend-owned integers. The client reads them back for
/// display; it never recomputes a target or a personal minimum.
class ChallengeRulesSnapshot {
  const ChallengeRulesSnapshot({
    required this.tierId,
    required this.catalogVersion,
    required this.difficultyLabel,
    required this.durationDays,
    required this.durationMs,
    required this.maxParticipants,
    required this.maxInvitedFriends,
    required this.targetMeters,
    required this.personalMinimumMeters,
  });

  final ChallengeTierId tierId;
  final String catalogVersion;

  /// Difficulty label as authored by the backend catalog (used verbatim).
  final String difficultyLabel;
  final int durationDays;
  final int durationMs;
  final int maxParticipants;
  final int maxInvitedFriends;
  final int targetMeters;
  final int personalMinimumMeters;

  static ChallengeRulesSnapshot fromMap(Map<String, Object?> map) {
    return ChallengeRulesSnapshot(
      tierId: ChallengeTierId.parse(ChallengeParse.string(map, 'tierId')),
      catalogVersion: ChallengeParse.string(map, 'catalogVersion'),
      difficultyLabel: ChallengeParse.string(map, 'difficultyLabel'),
      durationDays: ChallengeParse.integer(map, 'durationDays'),
      durationMs: ChallengeParse.integer(map, 'durationMs'),
      maxParticipants: ChallengeParse.integer(map, 'maxParticipants'),
      maxInvitedFriends: ChallengeParse.integer(map, 'maxInvitedFriends'),
      targetMeters: ChallengeParse.integer(map, 'targetMeters'),
      personalMinimumMeters:
          ChallengeParse.integer(map, 'personalMinimumMeters'),
    );
  }
}
