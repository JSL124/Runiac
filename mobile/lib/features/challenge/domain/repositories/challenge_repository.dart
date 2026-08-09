import '../models/active_challenge.dart';
import '../models/challenge_action_results.dart';
import '../models/challenge_badge_ownership.dart';
import '../models/challenge_enums.dart';
import '../models/challenge_history.dart';
import '../models/challenge_invitation_summary.dart';
import '../models/challenge_tier.dart';

/// Read/command surface over the server-owned Challenge distance system.
///
/// Every method either reads a backend-owned projection or invokes a trusted
/// Cloud Functions callable. The client never calculates or writes target
/// progress, contribution, eligibility, completion, reward/slot ownership, or
/// terminal state — those live entirely behind these operations.
abstract interface class ChallengeRepository {
  /// The versioned nine-tier catalog (`getChallengeCatalog`).
  Future<ChallengeCatalog> catalog();

  /// Creates a RECRUITING solo lobby the caller owns (`createChallengeLobby`).
  Future<CreateLobbyResult> createLobby(ChallengeTierId tierId);

  /// Invites reciprocal friends to a lobby (`inviteChallengeFriends`).
  Future<InviteResult> invite({
    required String challengeId,
    required List<String> uids,
  });

  /// Accepts or declines an invitation (`respondToChallengeInvitation`).
  Future<RespondResult> respondToInvitation({
    required String inviteId,
    required bool accept,
  });

  /// Withdraws the caller from a RECRUITING lobby (`withdrawFromChallengeLobby`).
  Future<WithdrawResult> withdraw({required String challengeId});

  /// Owner-cancels a RECRUITING lobby (`cancelChallengeLobby`).
  Future<CancelLobbyResult> cancelLobby({required String challengeId});

  /// Owner-starts a lobby, locking mode/rules (`startChallenge`).
  Future<StartChallengeResult> start({required String challengeId});

  /// The caller's current recruiting/active/settling challenge, or `null`
  /// (`getActiveChallenge`). One-shot; live surfaces should prefer
  /// [watchActiveChallenge] instead.
  Future<ActiveChallenge?> activeChallenge();

  /// The caller's PENDING invitations (`getChallengeInvitations`).
  Future<List<ChallengeInvitationSummary>> invitations();

  /// Live view of the caller's current challenge (recruiting, active, or
  /// settling), or `null` when the caller has none. Backed by a read-side
  /// stream over the caller's slot document and, once it names a challenge,
  /// the linked instance and its participant list — so membership, role,
  /// headcount, status, and metres update the moment another device's write
  /// lands, without a re-entry refetch. Participant level labels are
  /// best-effort: seeded once from the last [activeChallenge] result per uid
  /// and held fixed thereafter; a participant the seed never saw renders a
  /// blank label (surfaces already fall back to the display-only `Lv.0`
  /// placeholder).
  Stream<ActiveChallenge?> watchActiveChallenge();

  /// Live PENDING invitations for the caller. Backed by a read-side stream
  /// over the caller's invitation inbox, newest first. Per-tier rules are
  /// seeded once from the last [invitations] result; an invitation for a tier
  /// the seed never saw carries `rules: null` (the detail screen already
  /// tolerates that by hiding the rules card).
  Stream<List<ChallengeInvitationSummary>> watchInvitations();

  /// Non-owner leaves an ACTIVE challenge (`leaveChallenge`).
  Future<LeaveChallengeResult> leave({required String challengeId});

  /// Owner abandons an ACTIVE challenge for everyone (`abandonChallenge`).
  Future<AbandonChallengeResult> abandon({required String challengeId});

  /// The caller's durable challenge history, newest first.
  Future<List<ChallengeHistoryEntry>> history();

  /// The caller's owned tier badges.
  Future<ChallengeBadgeOwnership> ownedBadges();
}

/// Typed failure for every Challenge repository operation.
///
/// [reason] carries the backend `CHALLENGE_REASON` code when present
/// (parsed from `HttpsError.details.reason`), otherwise the coarse transport
/// code. Surfaces map it to user copy; they never inspect the raw message for
/// control flow.
class ChallengeFailure implements Exception {
  const ChallengeFailure({required this.reason, this.message});

  final String reason;
  final String? message;

  /// Sentinel reason used when a required read path is not yet wired.
  static const String unavailableReason = 'CHALLENGE_UNAVAILABLE';

  @override
  String toString() => 'ChallengeFailure(reason: $reason)';
}

/// Firestore-free port for the two read paths that have no callable: durable
/// history and badge ownership.
///
/// The Challenge feature tree is kept entirely free of Firestore data APIs
/// (enforced by the backend-owned contract test), so the concrete member-scoped
/// Firestore read adapter for these lives outside `lib/features/challenge/**`
/// and is injected here. Until it is wired, callers receive a
/// [ChallengeFailure] with [ChallengeFailure.unavailableReason].
abstract interface class ChallengeReadStore {
  Future<List<ChallengeHistoryEntry>> loadHistory({required String ownerUid});

  Future<ChallengeBadgeOwnership> loadOwnedBadges({required String ownerUid});

  /// Emits the caller's current challenge as a callable-view-shaped map
  /// (`{'instance': ..., 'participants': [...]}`) WITHOUT `levelLabelSnapshot`,
  /// or `null` when the caller has no visible challenge.
  Stream<Map<String, Object?>?> watchActiveChallengeView({
    required String ownerUid,
  });

  /// Emits the caller's PENDING invitations as callable-view-shaped maps
  /// (`inviteId`, `challengeId`, `tierId`, `ownerUid`, `createdAtMs`,
  /// `expiresAtMs`), newest first, WITHOUT `rules`.
  Stream<List<Map<String, Object?>>> watchPendingInvitationViews({
    required String ownerUid,
  });
}
