import 'dart:async';

import 'package:runiac_app/features/challenge/data/static_challenge_repository.dart';
import 'package:runiac_app/features/challenge/domain/models/active_challenge.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_action_results.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_badge_ownership.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_history.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_invitation_summary.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_tier.dart';
import 'package:runiac_app/features/challenge/domain/repositories/challenge_repository.dart';

/// A configurable Challenge repository for widget tests. It delegates to a
/// seeded [StaticChallengeRepository] by default and lets a test override any
/// read/command path, force failures, or record command calls.
class FakeChallengeRepository implements ChallengeRepository {
  FakeChallengeRepository({
    ChallengeScenarioSeed seed = ChallengeScenarioSeed.none,
    this.catalogFailure,
    this.blockCatalog = false,
    this.ownedBadgesFailure,
    this.ownedBadgesOverride,
    this.historyOverride,
    this.historyFailure,
    this.invitationsOverride,
    this.invitationsFailure,
    this.createFailure,
    this.startFailure,
    this.inviteFailure,
    this.respondFailure,
    this.cancelFailure,
    this.withdrawFailure,
    this.leaveFailure,
    this.abandonFailure,
    this.activeOverride,
    this.watchActiveOverride,
    this.watchInvitationsOverride,
  }) : _base = StaticChallengeRepository(seed: seed);

  final StaticChallengeRepository _base;

  final ChallengeFailure? catalogFailure;
  final bool blockCatalog;
  final ChallengeFailure? ownedBadgesFailure;
  final ChallengeBadgeOwnership? ownedBadgesOverride;
  final List<ChallengeHistoryEntry>? historyOverride;
  final ChallengeFailure? historyFailure;
  final List<ChallengeInvitationSummary>? invitationsOverride;
  final ChallengeFailure? invitationsFailure;
  final ChallengeFailure? createFailure;
  final ChallengeFailure? startFailure;
  final ChallengeFailure? inviteFailure;
  final ChallengeFailure? respondFailure;
  final ChallengeFailure? cancelFailure;
  final ChallengeFailure? withdrawFailure;
  final ChallengeFailure? leaveFailure;
  final ChallengeFailure? abandonFailure;
  final ActiveChallenge? Function()? activeOverride;

  /// Injectable live stream for [watchActiveChallenge]; defaults to a
  /// one-shot stream over [activeChallenge] so existing widget tests that
  /// never set this keep working unchanged.
  Stream<ActiveChallenge?>? watchActiveOverride;

  /// Injectable live stream for [watchInvitations]; defaults to a one-shot
  /// stream over [invitations] so existing widget tests that never set this
  /// keep working unchanged.
  Stream<List<ChallengeInvitationSummary>>? watchInvitationsOverride;

  /// Number of upcoming `catalog()` calls that should fail before succeeding.
  /// Lets a test exercise the error-state retry path.
  int catalogFailuresRemaining = 0;

  int catalogCalls = 0;
  int activeCalls = 0;
  final List<ChallengeTierId> createdTiers = <ChallengeTierId>[];
  final List<String> startedChallenges = <String>[];
  final List<String> cancelledChallenges = <String>[];
  final List<String> withdrawnChallenges = <String>[];
  final List<String> leftChallenges = <String>[];
  final List<String> abandonedChallenges = <String>[];
  final List<List<String>> invitedUidBatches = <List<String>>[];
  final List<bool> respondedAccepts = <bool>[];

  @override
  Future<ChallengeCatalog> catalog() async {
    catalogCalls++;
    if (blockCatalog) {
      return Completer<ChallengeCatalog>().future;
    }
    if (catalogFailuresRemaining > 0) {
      catalogFailuresRemaining--;
      throw catalogFailure ??
          const ChallengeFailure(reason: 'CHALLENGE_UNAVAILABLE');
    }
    if (catalogFailure != null) {
      throw catalogFailure!;
    }
    return _base.catalog();
  }

  @override
  Future<CreateLobbyResult> createLobby(ChallengeTierId tierId) async {
    createdTiers.add(tierId);
    if (createFailure != null) {
      throw createFailure!;
    }
    return _base.createLobby(tierId);
  }

  @override
  Future<InviteResult> invite({
    required String challengeId,
    required List<String> uids,
  }) async {
    invitedUidBatches.add(List<String>.from(uids));
    if (inviteFailure != null) {
      throw inviteFailure!;
    }
    return _base.invite(challengeId: challengeId, uids: uids);
  }

  @override
  Future<RespondResult> respondToInvitation({
    required String inviteId,
    required bool accept,
  }) async {
    respondedAccepts.add(accept);
    if (respondFailure != null) {
      throw respondFailure!;
    }
    return _base.respondToInvitation(inviteId: inviteId, accept: accept);
  }

  @override
  Future<WithdrawResult> withdraw({required String challengeId}) async {
    withdrawnChallenges.add(challengeId);
    if (withdrawFailure != null) {
      throw withdrawFailure!;
    }
    return _base.withdraw(challengeId: challengeId);
  }

  @override
  Future<CancelLobbyResult> cancelLobby({required String challengeId}) async {
    cancelledChallenges.add(challengeId);
    if (cancelFailure != null) {
      throw cancelFailure!;
    }
    return _base.cancelLobby(challengeId: challengeId);
  }

  @override
  Future<StartChallengeResult> start({required String challengeId}) async {
    startedChallenges.add(challengeId);
    if (startFailure != null) {
      throw startFailure!;
    }
    return _base.start(challengeId: challengeId);
  }

  @override
  Future<ActiveChallenge?> activeChallenge() async {
    activeCalls++;
    if (activeOverride != null) {
      return activeOverride!();
    }
    return _base.activeChallenge();
  }

  @override
  Future<List<ChallengeInvitationSummary>> invitations() async {
    if (invitationsFailure != null) {
      throw invitationsFailure!;
    }
    if (invitationsOverride != null) {
      return invitationsOverride!;
    }
    return _base.invitations();
  }

  @override
  Future<LeaveChallengeResult> leave({required String challengeId}) async {
    leftChallenges.add(challengeId);
    if (leaveFailure != null) {
      throw leaveFailure!;
    }
    return _base.leave(challengeId: challengeId);
  }

  @override
  Future<AbandonChallengeResult> abandon({required String challengeId}) async {
    abandonedChallenges.add(challengeId);
    if (abandonFailure != null) {
      throw abandonFailure!;
    }
    return _base.abandon(challengeId: challengeId);
  }

  @override
  Stream<ActiveChallenge?> watchActiveChallenge() =>
      watchActiveOverride ?? Stream<ActiveChallenge?>.fromFuture(activeChallenge());

  @override
  Stream<List<ChallengeInvitationSummary>> watchInvitations() =>
      watchInvitationsOverride ??
      Stream<List<ChallengeInvitationSummary>>.fromFuture(invitations());

  int historyCalls = 0;

  @override
  Future<List<ChallengeHistoryEntry>> history() async {
    historyCalls++;
    if (historyFailure != null) {
      throw historyFailure!;
    }
    if (historyOverride != null) {
      return historyOverride!;
    }
    return _base.history();
  }

  @override
  Future<ChallengeBadgeOwnership> ownedBadges() async {
    if (ownedBadgesFailure != null) {
      throw ownedBadgesFailure!;
    }
    if (ownedBadgesOverride != null) {
      return ownedBadgesOverride!;
    }
    return _base.ownedBadges();
  }
}
