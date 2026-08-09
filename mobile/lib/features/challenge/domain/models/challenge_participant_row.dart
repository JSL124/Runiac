import 'challenge_enums.dart';
import 'challenge_parse.dart';

/// A privacy-safe participant row for lobby and progress surfaces.
///
/// Identity is limited to the backend-authored `displayNameSnapshot` and
/// `avatarInitialsSnapshot`; the raw uid is retained only to resolve
/// [isCurrentUser] and to order the roster (You first). No routes, coordinates,
/// run timestamps, or activity history are ever exposed here. `creditedMeters`
/// is the backend-owned value read back verbatim.
class ChallengeParticipantRow {
  const ChallengeParticipantRow({
    required this.uid,
    required this.displayNameSnapshot,
    required this.avatarInitialsSnapshot,
    required this.levelLabelSnapshot,
    required this.role,
    required this.status,
    required this.creditedMeters,
    required this.reward,
    required this.isCurrentUser,
    this.avatarUrlSnapshot = '',
    this.levelProgressPercentSnapshot = 0,
  });

  /// Backend uid. Not for display — used only for self-detection and ordering.
  final String uid;
  final String displayNameSnapshot;
  final String avatarInitialsSnapshot;

  /// Raw, not-yet-sanitised avatar photo URL resolved live from the
  /// participant's profile, exactly like [levelLabelSnapshot]. Empty is the
  /// common case (no photo set), so unlike the other snapshot fields this is
  /// never parsed through [ChallengeParse.string]/[ChallengeParse.optionalString]
  /// (both reject an empty string) — see [fromMap].
  final String avatarUrlSnapshot;

  /// Backend-owned level label (e.g. `Lv.2`) read back verbatim for display.
  /// May be empty when the backend cannot resolve a level; callers fall back
  /// to the display-only `Lv.0` placeholder, or hide the level pill entirely.
  ///
  /// Empty is a NORMAL value here, not a malformed response: the backend
  /// resolves this live from `userProfiles/{uid}`, where `level`/`levelLabel`
  /// are written only once a run has awarded XP, so every runner who has never
  /// completed a run resolves to `""`. It is therefore parsed leniently, like
  /// [avatarUrlSnapshot] and [levelProgressPercentSnapshot] — see [fromMap].
  final String levelLabelSnapshot;

  /// Backend-owned progress toward the next level, 0..100, resolved live from
  /// the participant's profile alongside [levelLabelSnapshot]. Surfaces divide
  /// it by 100 to paint the XP ring around the roster avatar. Read back
  /// verbatim; never computed on the client. `0` — an empty ring — is the
  /// normal case for a profile with no progress on record, so like
  /// [avatarUrlSnapshot] this is parsed leniently rather than strictly.
  final int levelProgressPercentSnapshot;
  final ChallengeParticipantRole role;
  final ChallengeParticipantStatus status;
  final int creditedMeters;
  final ChallengeRewardStatus reward;
  final bool isCurrentUser;

  bool get hasLeft => status == ChallengeParticipantStatus.left;

  static ChallengeParticipantRow fromMap(
    Map<String, Object?> map, {
    required String? currentUid,
  }) {
    final uid = ChallengeParse.string(map, 'uid');
    return ChallengeParticipantRow(
      uid: uid,
      displayNameSnapshot: ChallengeParse.string(map, 'displayNameSnapshot'),
      avatarInitialsSnapshot:
          ChallengeParse.string(map, 'avatarInitialsSnapshot'),
      levelLabelSnapshot: _levelLabelSnapshot(map),
      role: ChallengeParticipantRole.parse(ChallengeParse.string(map, 'role')),
      status:
          ChallengeParticipantStatus.parse(ChallengeParse.string(map, 'status')),
      creditedMeters: ChallengeParse.integer(map, 'creditedMeters'),
      reward: ChallengeRewardStatus.parse(ChallengeParse.string(map, 'reward')),
      isCurrentUser: currentUid != null && currentUid == uid,
      avatarUrlSnapshot: _avatarUrlSnapshot(map),
      levelProgressPercentSnapshot: _levelProgressPercentSnapshot(map),
    );
  }

  /// Lenient read of `levelLabelSnapshot`, for the same reason as
  /// [_avatarUrlSnapshot]: the backend emits `""` for any runner whose profile
  /// carries no resolved level (nobody writes `level` until a run awards XP),
  /// so an empty label is normal data, not a malformed response.
  ///
  /// This used to be parsed through [ChallengeParse.string], which rejects an
  /// empty string. One level-less member on the roster therefore failed the
  /// whole `getActiveChallenge` response, and the Challenge hub — which parses
  /// that callable result directly — showed "Something went wrong. Please try
  /// again." for EVERY member of the lobby, permanently, since the cause is
  /// stored data that a relaunch cannot clear. Only the realtime lobby path
  /// survived, because it substitutes its own placeholder before parsing.
  static String _levelLabelSnapshot(Map<String, Object?> map) {
    final value = map['levelLabelSnapshot'];
    return value is String ? value : '';
  }

  /// Lenient read of `avatarUrlSnapshot`: unlike the strictly-parsed fields
  /// here, an empty string is the NORMAL case (no photo set), not a malformed
  /// response, so this never throws — a missing or non-string value simply
  /// resolves to `''`, the same as an explicitly empty one.
  static String _avatarUrlSnapshot(Map<String, Object?> map) {
    final value = map['avatarUrlSnapshot'];
    return value is String ? value : '';
  }

  /// Lenient read of `levelProgressPercentSnapshot`, for the same reason as
  /// [_avatarUrlSnapshot]: a participant whose profile carries no progress is
  /// normal, not a malformed response, and so is a response from a backend
  /// revision predating this field. Both resolve to `0` (an empty ring) rather
  /// than throwing. Clamped to 0..100 so a corrupt stored value cannot
  /// overdraw the ring.
  static int _levelProgressPercentSnapshot(Map<String, Object?> map) {
    final value = map['levelProgressPercentSnapshot'];
    if (value is! num || !value.isFinite) {
      return 0;
    }
    return value.round().clamp(0, 100);
  }
}
