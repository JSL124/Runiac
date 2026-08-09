import 'challenge_enums.dart';
import 'challenge_parse.dart';

/// A durable per-user Challenge history row (`users/{uid}/challengeHistory`).
///
/// All metres are backend-owned integers read back verbatim. Timestamps are
/// normalized to epoch milliseconds by the reading adapter before parsing here,
/// so the model never depends on a Firestore timestamp type.
class ChallengeHistoryEntry {
  const ChallengeHistoryEntry({
    required this.challengeId,
    required this.tierId,
    required this.mode,
    required this.role,
    required this.outcome,
    required this.terminalReason,
    required this.teamMeters,
    required this.personalMeters,
    required this.targetMeters,
    required this.personalMinimumMeters,
    required this.startedAtMs,
    required this.endedAtMs,
  });

  final String challengeId;
  final ChallengeTierId tierId;
  final ChallengeMode mode;
  final ChallengeParticipantRole role;

  /// The recipient's own terminal outcome (SUCCEEDED / INELIGIBLE / FAILED /
  /// CANCELLED / LEFT). Ownership of this value is the backend's.
  final ChallengeParticipantStatus outcome;
  final ChallengeTerminalReason? terminalReason;
  final int teamMeters;
  final int personalMeters;
  final int targetMeters;
  final int personalMinimumMeters;
  final int startedAtMs;
  final int endedAtMs;

  DateTime get startedAt => DateTime.fromMillisecondsSinceEpoch(startedAtMs);

  DateTime get endedAt => DateTime.fromMillisecondsSinceEpoch(endedAtMs);

  /// DISPLAY ONLY. Mirrors whether the user's own metres met the snapshotted
  /// personal minimum for the "Minimum reached" UI state. Reward eligibility
  /// itself is owned by the backend and read through [outcome]; this comparison
  /// never grants, denies, or recomputes eligibility.
  bool get personalMinimumReachedForDisplay =>
      personalMeters >= personalMinimumMeters;

  static ChallengeHistoryEntry fromMap(Map<String, Object?> map) {
    final terminalReasonRaw =
        ChallengeParse.optionalString(map, 'terminalReason');
    return ChallengeHistoryEntry(
      challengeId: ChallengeParse.string(map, 'challengeId'),
      tierId: ChallengeTierId.parse(ChallengeParse.string(map, 'tierId')),
      mode: ChallengeMode.parse(ChallengeParse.string(map, 'mode')),
      role: ChallengeParticipantRole.parse(ChallengeParse.string(map, 'role')),
      outcome:
          ChallengeParticipantStatus.parse(ChallengeParse.string(map, 'outcome')),
      terminalReason: terminalReasonRaw == null
          ? null
          : ChallengeTerminalReason.parse(terminalReasonRaw),
      teamMeters: ChallengeParse.integer(map, 'teamMeters'),
      personalMeters: ChallengeParse.integer(map, 'personalMeters'),
      targetMeters: ChallengeParse.integer(map, 'targetMeters'),
      personalMinimumMeters:
          ChallengeParse.integer(map, 'personalMinimumMeters'),
      startedAtMs: ChallengeParse.integer(map, 'startedAtMs'),
      endedAtMs: ChallengeParse.integer(map, 'endedAtMs'),
    );
  }

  ChallengeResult toResult() => ChallengeResult.fromHistory(this);
}

/// The per-user terminal outcome of a single Challenge, projected from history
/// for the full-screen result surface.
class ChallengeResult {
  const ChallengeResult({
    required this.challengeId,
    required this.tierId,
    required this.mode,
    required this.role,
    required this.outcome,
    required this.terminalReason,
    required this.creditedMeters,
    required this.teamMeters,
    required this.targetMeters,
    required this.personalMinimumMeters,
    required this.startedAtMs,
    required this.endedAtMs,
  });

  final String challengeId;
  final ChallengeTierId tierId;
  final ChallengeMode mode;
  final ChallengeParticipantRole role;
  final ChallengeParticipantStatus outcome;
  final ChallengeTerminalReason? terminalReason;

  /// The user's own credited metres (`personalMeters` in history).
  final int creditedMeters;
  final int teamMeters;
  final int targetMeters;
  final int personalMinimumMeters;
  final int startedAtMs;
  final int endedAtMs;

  bool get earnedBadge => outcome == ChallengeParticipantStatus.succeeded;

  factory ChallengeResult.fromHistory(ChallengeHistoryEntry entry) {
    return ChallengeResult(
      challengeId: entry.challengeId,
      tierId: entry.tierId,
      mode: entry.mode,
      role: entry.role,
      outcome: entry.outcome,
      terminalReason: entry.terminalReason,
      creditedMeters: entry.personalMeters,
      teamMeters: entry.teamMeters,
      targetMeters: entry.targetMeters,
      personalMinimumMeters: entry.personalMinimumMeters,
      startedAtMs: entry.startedAtMs,
      endedAtMs: entry.endedAtMs,
    );
  }
}
