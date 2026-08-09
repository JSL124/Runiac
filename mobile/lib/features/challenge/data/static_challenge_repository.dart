import '../domain/models/active_challenge.dart';
import '../domain/models/challenge_action_results.dart';
import '../domain/models/challenge_badge_ownership.dart';
import '../domain/models/challenge_enums.dart';
import '../domain/models/challenge_history.dart';
import '../domain/models/challenge_invitation_summary.dart';
import '../domain/models/challenge_participant_row.dart';
import '../domain/models/challenge_rules_snapshot.dart';
import '../domain/models/challenge_tier.dart';
import '../domain/repositories/challenge_repository.dart';

/// The lifecycle a [StaticChallengeRepository] renders for previews / widget
/// tests.
enum ChallengeScenarioSeed {
  /// No active challenge (Home control absent).
  none,
  recruiting,
  active,
  settling,
  succeeded,
  failed,
  cancelled,

  /// An ACTIVE group instance the current user has left (non-owner member).
  left,
}

/// Deterministic local Challenge repository for previews and widget tests.
///
/// Production wiring supplies [FirebaseChallengeRepository]. This fake carries
/// only demo/fixture data and backend-shaped read models; it performs no target,
/// minimum, eligibility, or reward calculation, and it never writes trusted
/// Challenge documents.
class StaticChallengeRepository implements ChallengeRepository {
  const StaticChallengeRepository({
    this.seed = ChallengeScenarioSeed.recruiting,
  });

  final ChallengeScenarioSeed seed;

  static const String _catalogVersion = 'challenge-distance-v1';
  static const String _currentUid = 'runner-current';
  static const String _friendUid = 'runner-friend';
  static const String _demoChallengeId = 'static-challenge';
  static const int _demoStartsAtMs = 1752307200000; // 2025-07-12T08:00:00Z
  static const int _demoLobbyExpiresAtMs = 1752393600000;

  @override
  Future<ChallengeCatalog> catalog() async {
    return const ChallengeCatalog(
      version: _catalogVersion,
      tiers: _demoTiers,
      premiumOnlyTierIds: _demoPremiumOnlyTierIds,
    );
  }

  @override
  Future<CreateLobbyResult> createLobby(ChallengeTierId tierId) async {
    return const CreateLobbyResult(
      challengeId: _demoChallengeId,
      status: ChallengeInstanceStatus.recruiting,
      idempotent: false,
    );
  }

  @override
  Future<InviteResult> invite({
    required String challengeId,
    required List<String> uids,
  }) async {
    return InviteResult(
      challengeId: challengeId,
      invited: List<String>.unmodifiable(uids),
      alreadyPending: const <String>[],
    );
  }

  @override
  Future<RespondResult> respondToInvitation({
    required String inviteId,
    required bool accept,
  }) async {
    return RespondResult(
      challengeId: _demoChallengeId,
      accepted: accept,
      idempotent: false,
    );
  }

  @override
  Future<WithdrawResult> withdraw({required String challengeId}) async {
    return WithdrawResult(challengeId: challengeId, idempotent: false);
  }

  @override
  Future<CancelLobbyResult> cancelLobby({required String challengeId}) async {
    return CancelLobbyResult(challengeId: challengeId, idempotent: false);
  }

  @override
  Future<StartChallengeResult> start({required String challengeId}) async {
    return StartChallengeResult(
      challengeId: challengeId,
      mode: ChallengeMode.solo,
      rosterUids: const <String>[_currentUid],
      startsAtMs: _demoStartsAtMs,
      scheduledEndsAtMs: _demoStartsAtMs + _demoRules.durationMs,
      idempotent: false,
    );
  }

  @override
  Future<ActiveChallenge?> activeChallenge() async {
    return _activeForSeed();
  }

  @override
  Future<List<ChallengeInvitationSummary>> invitations() async {
    return const <ChallengeInvitationSummary>[
      ChallengeInvitationSummary(
        inviteId: '${_demoChallengeId}__$_currentUid',
        challengeId: _demoChallengeId,
        tierId: ChallengeTierId.k42,
        ownerUid: _friendUid,
        status: ChallengeInvitationStatus.pending,
        createdAtMs: _demoStartsAtMs,
        expiresAtMs: _demoLobbyExpiresAtMs,
        rules: _demoRules42,
      ),
    ];
  }

  @override
  Stream<ActiveChallenge?> watchActiveChallenge() =>
      Stream<ActiveChallenge?>.fromFuture(activeChallenge());

  @override
  Stream<List<ChallengeInvitationSummary>> watchInvitations() =>
      Stream<List<ChallengeInvitationSummary>>.fromFuture(invitations());

  @override
  Future<LeaveChallengeResult> leave({required String challengeId}) async {
    return LeaveChallengeResult(challengeId: challengeId, idempotent: false);
  }

  @override
  Future<AbandonChallengeResult> abandon({required String challengeId}) async {
    return AbandonChallengeResult(challengeId: challengeId, idempotent: false);
  }

  @override
  Future<List<ChallengeHistoryEntry>> history() async {
    return const <ChallengeHistoryEntry>[
      ChallengeHistoryEntry(
        challengeId: 'static-history-succeeded',
        tierId: ChallengeTierId.k10,
        mode: ChallengeMode.group,
        role: ChallengeParticipantRole.owner,
        outcome: ChallengeParticipantStatus.succeeded,
        terminalReason: ChallengeTerminalReason.targetReached,
        teamMeters: 10000,
        personalMeters: 6200,
        targetMeters: 10000,
        personalMinimumMeters: 3000,
        startedAtMs: _demoStartsAtMs,
        endedAtMs: _demoStartsAtMs + 259200000,
      ),
      ChallengeHistoryEntry(
        challengeId: 'static-history-failed',
        tierId: ChallengeTierId.k20,
        mode: ChallengeMode.solo,
        role: ChallengeParticipantRole.owner,
        outcome: ChallengeParticipantStatus.failed,
        terminalReason: ChallengeTerminalReason.deadlineFailed,
        teamMeters: 12400,
        personalMeters: 12400,
        targetMeters: 20000,
        personalMinimumMeters: 5000,
        startedAtMs: _demoStartsAtMs,
        endedAtMs: _demoStartsAtMs + 1209600000,
      ),
    ];
  }

  @override
  Future<ChallengeBadgeOwnership> ownedBadges() async {
    return ChallengeBadgeOwnership(
      ownedTierIds: <ChallengeTierId>{ChallengeTierId.k10},
    );
  }

  ActiveChallenge? _activeForSeed() {
    switch (seed) {
      case ChallengeScenarioSeed.none:
        return null;
      case ChallengeScenarioSeed.recruiting:
        return _instance(
          status: ChallengeInstanceStatus.recruiting,
          mode: ChallengeMode.solo,
          teamMeters: 0,
          participants: <ChallengeParticipantRow>[_ownerRow(meters: 0)],
          rosterUids: const <String>[_currentUid],
          scheduled: false,
          terminalReason: null,
          currentIsOwner: true,
          ownerUid: _currentUid,
        );
      case ChallengeScenarioSeed.active:
        return _instance(
          status: ChallengeInstanceStatus.active,
          mode: ChallengeMode.group,
          teamMeters: 6000,
          participants: <ChallengeParticipantRow>[
            _ownerRow(meters: 4000),
            _memberRow(meters: 2000, status: ChallengeParticipantStatus.active),
          ],
          rosterUids: const <String>[_currentUid, _friendUid],
          scheduled: true,
          terminalReason: null,
          currentIsOwner: true,
          ownerUid: _currentUid,
        );
      case ChallengeScenarioSeed.settling:
        return _instance(
          status: ChallengeInstanceStatus.settling,
          mode: ChallengeMode.group,
          teamMeters: 10000,
          participants: <ChallengeParticipantRow>[
            _ownerRow(meters: 6200),
            _memberRow(meters: 3800, status: ChallengeParticipantStatus.active),
          ],
          rosterUids: const <String>[_currentUid, _friendUid],
          scheduled: true,
          terminalReason: null,
          currentIsOwner: true,
          ownerUid: _currentUid,
        );
      case ChallengeScenarioSeed.succeeded:
        return _instance(
          status: ChallengeInstanceStatus.succeeded,
          mode: ChallengeMode.group,
          teamMeters: 10000,
          participants: <ChallengeParticipantRow>[
            _ownerRow(
              meters: 6200,
              status: ChallengeParticipantStatus.succeeded,
              reward: ChallengeRewardStatus.issued,
            ),
            _memberRow(
              meters: 3800,
              status: ChallengeParticipantStatus.succeeded,
              reward: ChallengeRewardStatus.issued,
            ),
          ],
          rosterUids: const <String>[_currentUid, _friendUid],
          scheduled: true,
          terminalReason: ChallengeTerminalReason.targetReached,
          currentIsOwner: true,
          ownerUid: _currentUid,
        );
      case ChallengeScenarioSeed.failed:
        return _instance(
          status: ChallengeInstanceStatus.failed,
          mode: ChallengeMode.solo,
          teamMeters: 6400,
          participants: <ChallengeParticipantRow>[
            _ownerRow(meters: 6400, status: ChallengeParticipantStatus.failed),
          ],
          rosterUids: const <String>[_currentUid],
          scheduled: true,
          terminalReason: ChallengeTerminalReason.deadlineFailed,
          currentIsOwner: true,
          ownerUid: _currentUid,
        );
      case ChallengeScenarioSeed.cancelled:
        return _instance(
          status: ChallengeInstanceStatus.cancelled,
          mode: ChallengeMode.group,
          teamMeters: 2000,
          participants: <ChallengeParticipantRow>[
            _ownerRow(
              meters: 2000,
              status: ChallengeParticipantStatus.cancelled,
            ),
            _memberRow(
              meters: 0,
              status: ChallengeParticipantStatus.cancelled,
            ),
          ],
          rosterUids: const <String>[_currentUid, _friendUid],
          scheduled: true,
          terminalReason: ChallengeTerminalReason.ownerAbandoned,
          currentIsOwner: true,
          ownerUid: _currentUid,
        );
      case ChallengeScenarioSeed.left:
        return _instance(
          status: ChallengeInstanceStatus.active,
          mode: ChallengeMode.group,
          teamMeters: 7000,
          participants: <ChallengeParticipantRow>[
            const ChallengeParticipantRow(
              uid: _friendUid,
              displayNameSnapshot: 'Sam Runner',
              avatarInitialsSnapshot: 'SR',
              levelLabelSnapshot: 'Lv.8',
              role: ChallengeParticipantRole.owner,
              status: ChallengeParticipantStatus.active,
              creditedMeters: 5000,
              reward: ChallengeRewardStatus.notEligible,
              isCurrentUser: false,
            ),
            const ChallengeParticipantRow(
              uid: _currentUid,
              displayNameSnapshot: 'You',
              avatarInitialsSnapshot: 'YO',
              levelLabelSnapshot: 'Lv.3',
              role: ChallengeParticipantRole.member,
              status: ChallengeParticipantStatus.left,
              creditedMeters: 2000,
              reward: ChallengeRewardStatus.notEligible,
              isCurrentUser: true,
            ),
          ],
          rosterUids: const <String>[_friendUid],
          scheduled: true,
          terminalReason: null,
          currentIsOwner: false,
          ownerUid: _friendUid,
        );
    }
  }

  ActiveChallenge _instance({
    required ChallengeInstanceStatus status,
    required ChallengeMode mode,
    required int teamMeters,
    required List<ChallengeParticipantRow> participants,
    required List<String> rosterUids,
    required bool scheduled,
    required ChallengeTerminalReason? terminalReason,
    required bool currentIsOwner,
    required String ownerUid,
  }) {
    return ActiveChallenge(
      challengeId: _demoChallengeId,
      ownerUid: ownerUid,
      tierId: ChallengeTierId.k10,
      mode: mode,
      status: status,
      rules: _demoRules,
      rosterUids: List<String>.unmodifiable(rosterUids),
      maxParticipants: _demoRules.maxParticipants,
      teamMeters: teamMeters,
      createdAtMs: _demoStartsAtMs,
      lobbyExpiresAtMs: _demoLobbyExpiresAtMs,
      startsAtMs: scheduled ? _demoStartsAtMs : null,
      scheduledEndsAtMs:
          scheduled ? _demoStartsAtMs + _demoRules.durationMs : null,
      terminalReason: terminalReason,
      participants: List<ChallengeParticipantRow>.unmodifiable(participants),
      isCurrentUserOwner: currentIsOwner,
    );
  }

  ChallengeParticipantRow _ownerRow({
    required int meters,
    ChallengeParticipantStatus status = ChallengeParticipantStatus.active,
    ChallengeRewardStatus reward = ChallengeRewardStatus.notEligible,
  }) {
    return ChallengeParticipantRow(
      uid: _currentUid,
      displayNameSnapshot: 'You',
      avatarInitialsSnapshot: 'YO',
      levelLabelSnapshot: 'Lv.5',
      role: ChallengeParticipantRole.owner,
      status: status,
      creditedMeters: meters,
      reward: reward,
      isCurrentUser: true,
    );
  }

  ChallengeParticipantRow _memberRow({
    required int meters,
    required ChallengeParticipantStatus status,
    ChallengeRewardStatus reward = ChallengeRewardStatus.notEligible,
  }) {
    return ChallengeParticipantRow(
      uid: _friendUid,
      displayNameSnapshot: 'Sam Runner',
      avatarInitialsSnapshot: 'SR',
      levelLabelSnapshot: 'Lv.8',
      role: ChallengeParticipantRole.member,
      status: status,
      creditedMeters: meters,
      reward: reward,
      isCurrentUser: false,
    );
  }
}

const ChallengeRulesSnapshot _demoRules = ChallengeRulesSnapshot(
  tierId: ChallengeTierId.k10,
  catalogVersion: 'challenge-distance-v1',
  difficultyLabel: 'Beginner',
  durationDays: 7,
  durationMs: 604800000,
  maxParticipants: 2,
  maxInvitedFriends: 1,
  targetMeters: 10000,
  personalMinimumMeters: 3000,
);

const ChallengeRulesSnapshot _demoRules42 = ChallengeRulesSnapshot(
  tierId: ChallengeTierId.k42,
  catalogVersion: 'challenge-distance-v1',
  difficultyLabel: 'Normal',
  durationDays: 21,
  durationMs: 1814400000,
  maxParticipants: 3,
  maxInvitedFriends: 2,
  targetMeters: 42000,
  personalMinimumMeters: 7000,
);

/// Demo premium gating mirroring `DEFAULT_CHALLENGE_ACCESS_CONFIG` in
/// `functions/src/config/configLoader.ts` (10K/20K/42K free, the rest
/// premium-only). Static fixture values, not an entitlement decision.
const Set<ChallengeTierId> _demoPremiumOnlyTierIds = <ChallengeTierId>{
  ChallengeTierId.k100,
  ChallengeTierId.k200,
  ChallengeTierId.k250,
  ChallengeTierId.k300,
  ChallengeTierId.k500,
  ChallengeTierId.k1000,
};

/// Demo catalog mirroring the backend `challenge-distance-v1` tiers. These are
/// static fixture values, not a client-side computation of targets or minimums.
const List<ChallengeTier> _demoTiers = <ChallengeTier>[
  ChallengeTier(
    tierId: ChallengeTierId.k10,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Beginner',
    durationDays: 7,
    maxParticipants: 2,
    maxInvitedFriends: 1,
    targetMeters: 10000,
    personalMinimumMeters: 3000,
  ),
  ChallengeTier(
    tierId: ChallengeTierId.k20,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Easy',
    durationDays: 14,
    maxParticipants: 2,
    maxInvitedFriends: 1,
    targetMeters: 20000,
    personalMinimumMeters: 5000,
  ),
  ChallengeTier(
    tierId: ChallengeTierId.k42,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Normal',
    durationDays: 21,
    maxParticipants: 3,
    maxInvitedFriends: 2,
    targetMeters: 42000,
    personalMinimumMeters: 7000,
  ),
  ChallengeTier(
    tierId: ChallengeTierId.k100,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Challenging',
    durationDays: 28,
    maxParticipants: 4,
    maxInvitedFriends: 3,
    targetMeters: 100000,
    personalMinimumMeters: 13000,
  ),
  ChallengeTier(
    tierId: ChallengeTierId.k200,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Hard',
    durationDays: 42,
    maxParticipants: 5,
    maxInvitedFriends: 4,
    targetMeters: 200000,
    personalMinimumMeters: 20000,
  ),
  ChallengeTier(
    tierId: ChallengeTierId.k250,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Hard+',
    durationDays: 49,
    maxParticipants: 5,
    maxInvitedFriends: 4,
    targetMeters: 250000,
    personalMinimumMeters: 25000,
  ),
  ChallengeTier(
    tierId: ChallengeTierId.k300,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Very Hard',
    durationDays: 56,
    maxParticipants: 5,
    maxInvitedFriends: 4,
    targetMeters: 300000,
    personalMinimumMeters: 30000,
  ),
  ChallengeTier(
    tierId: ChallengeTierId.k500,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Extreme',
    durationDays: 63,
    maxParticipants: 7,
    maxInvitedFriends: 6,
    targetMeters: 500000,
    personalMinimumMeters: 36000,
  ),
  ChallengeTier(
    tierId: ChallengeTierId.k1000,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: 'Legend',
    durationDays: 98,
    maxParticipants: 8,
    maxInvitedFriends: 7,
    targetMeters: 1000000,
    personalMinimumMeters: 63000,
  ),
];
