import 'package:cloud_functions/cloud_functions.dart';

import '../domain/models/active_challenge.dart';
import '../domain/models/challenge_action_results.dart';
import '../domain/models/challenge_badge_ownership.dart';
import '../domain/models/challenge_enums.dart';
import '../domain/models/challenge_history.dart';
import '../domain/models/challenge_invitation_summary.dart';
import '../domain/models/challenge_parse.dart';
import '../domain/models/challenge_parse_exception.dart';
import '../domain/models/challenge_participant_row.dart';
import '../domain/models/challenge_premium_hold.dart';
import '../domain/models/challenge_rules_snapshot.dart';
import '../domain/models/challenge_tier.dart';
import '../domain/repositories/challenge_repository.dart';

/// Pure: applies the hybrid level-label and avatar seeds to a store view and
/// parses it.
///
/// [levelLabelSeed] maps participant uid to the level label last read from a
/// full `activeChallenge()` callable response; a uid the seed never saw
/// renders `''` (surfaces trim it and fall back to `Lv.0`, or hide the pill).
/// This used to substitute a single space, because
/// [ChallengeParticipantRow.fromMap] once rejected an empty label; it parses
/// one leniently now, so the placeholder is gone and an unseeded uid reads
/// exactly like a backend-resolved empty label.
///
/// [avatarUrlSeed] does the same for the participant's avatar photo URL. It
/// accepts the same documented limitation as the level label: a
/// stream-only update (no fresh `activeChallenge()` call) shows no avatar for
/// a uid the seed never saw, rather than growing new machinery to close that
/// gap.
///
/// [levelProgressPercentSeed] does the same for the participant's XP-ring
/// progress, under the same limitation and the same benign fallback as the
/// avatar: an unseeded uid renders `0`, an empty ring.
ActiveChallenge? mapActiveChallengeView(
  Map<String, Object?>? view, {
  required Map<String, String> levelLabelSeed,
  required String? currentUid,
  Map<String, String> avatarUrlSeed = const <String, String>{},
  Map<String, int> levelProgressPercentSeed = const <String, int>{},
  ChallengePremiumHold? premiumHold,
}) {
  if (view == null) {
    return null;
  }
  try {
    final rawParticipants =
        ChallengeParse.asList(view['participants'], field: 'participants');
    final seededParticipants = rawParticipants.map((entry) {
      final participant =
          ChallengeParse.asMap(entry, field: 'participants[]');
      final uid = ChallengeParse.string(participant, 'uid');
      return <String, Object?>{
        ...participant,
        'levelLabelSnapshot': levelLabelSeed[uid] ?? '',
        'avatarUrlSnapshot': avatarUrlSeed[uid] ?? '',
        'levelProgressPercentSnapshot': levelProgressPercentSeed[uid] ?? 0,
      };
    }).toList(growable: false);
    final seededView = <String, Object?>{
      ...view,
      'participants': seededParticipants,
    };
    return ActiveChallenge.fromChallengeMap(
      seededView,
      currentUid: currentUid,
      premiumHold: premiumHold,
    );
  } on ChallengeParseException catch (error) {
    throw ChallengeFailure(
      reason: 'INVALID_RESPONSE',
      message: error.toString(),
    );
  }
}

/// Pure: applies the per-tier rules seed to store invitation views.
///
/// [rulesSeed] maps tier id to the rules snapshot last read from a full
/// `getChallengeInvitations()` callable response; a tier the seed never saw
/// renders `rules: null` (the detail screen already tolerates that).
List<ChallengeInvitationSummary> mapPendingInvitationViews(
  List<Map<String, Object?>> views, {
  required Map<ChallengeTierId, ChallengeRulesSnapshot> rulesSeed,
}) {
  try {
    final summaries = views.map((view) {
      final tierId = ChallengeTierId.parse(ChallengeParse.string(view, 'tierId'));
      return ChallengeInvitationSummary(
        inviteId: ChallengeParse.string(view, 'inviteId'),
        challengeId: ChallengeParse.string(view, 'challengeId'),
        tierId: tierId,
        ownerUid: ChallengeParse.string(view, 'ownerUid'),
        status: ChallengeInvitationStatus.pending,
        createdAtMs: ChallengeParse.integer(view, 'createdAtMs'),
        expiresAtMs: ChallengeParse.integer(view, 'expiresAtMs'),
        rules: rulesSeed[tierId],
      );
    }).toList(growable: false);
    return List<ChallengeInvitationSummary>.unmodifiable(summaries);
  } on ChallengeParseException catch (error) {
    throw ChallengeFailure(
      reason: 'INVALID_RESPONSE',
      message: error.toString(),
    );
  }
}

/// Resolves the currently-authenticated uid (used to flag the caller's own
/// participant row). Returns `null` when signed out.
typedef ChallengeCurrentUid = String? Function();

/// Cloud Functions callable adapter for the Challenge distance system.
///
/// Mirrors the app's callable convention: a region-`asia-southeast1`
/// [FirebaseFunctions] instance (the same one the bootstrap points at the
/// emulator when `RUNIAC_FIREBASE_EMULATOR=true`), stable failure codes read
/// from `HttpsError.details.reason`, and strict response parsing. This class
/// touches no Firestore APIs; the two read paths without a callable (history,
/// badges) delegate to an injected [ChallengeReadStore].
class FirebaseChallengeRepository implements ChallengeRepository {
  FirebaseChallengeRepository({
    required this.currentUid,
    FirebaseFunctions? functions,
    this.readStore,
  }) : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// Resolves the signed-in uid; `null` when signed out.
  final ChallengeCurrentUid currentUid;

  /// Firestore-free read source for history/badges; `null` until wired.
  final ChallengeReadStore? readStore;

  final FirebaseFunctions _functions;

  @override
  Future<ChallengeCatalog> catalog() async {
    final data = await _call('getChallengeCatalog');
    return _map(() => ChallengeCatalog.fromMap(data));
  }

  @override
  Future<CreateLobbyResult> createLobby(ChallengeTierId tierId) async {
    final data = await _call('createChallengeLobby', <String, Object?>{
      'tierId': tierId.wireValue,
    });
    return _map(() => CreateLobbyResult.fromMap(data));
  }

  @override
  Future<InviteResult> invite({
    required String challengeId,
    required List<String> uids,
  }) async {
    final data = await _call('inviteChallengeFriends', <String, Object?>{
      'challengeId': challengeId,
      'uids': uids,
    });
    return _map(() => InviteResult.fromMap(data));
  }

  @override
  Future<RespondResult> respondToInvitation({
    required String inviteId,
    required bool accept,
  }) async {
    final data = await _call('respondToChallengeInvitation', <String, Object?>{
      'inviteId': inviteId,
      'response': accept ? 'accept' : 'decline',
    });
    return _map(() => RespondResult.fromMap(data));
  }

  @override
  Future<WithdrawResult> withdraw({required String challengeId}) async {
    final data = await _call('withdrawFromChallengeLobby', <String, Object?>{
      'challengeId': challengeId,
    });
    return _map(() => WithdrawResult.fromMap(data));
  }

  @override
  Future<CancelLobbyResult> cancelLobby({required String challengeId}) async {
    final data = await _call('cancelChallengeLobby', <String, Object?>{
      'challengeId': challengeId,
    });
    return _map(() => CancelLobbyResult.fromMap(data));
  }

  @override
  Future<StartChallengeResult> start({required String challengeId}) async {
    final data = await _call('startChallenge', <String, Object?>{
      'challengeId': challengeId,
    });
    return _map(() => StartChallengeResult.fromMap(data));
  }

  @override
  Future<ActiveChallenge?> activeChallenge() async {
    final data = await _call('getActiveChallenge');
    return _map(() {
      final challenge = data['challenge'];
      if (challenge == null) {
        return null;
      }
      return ActiveChallenge.fromChallengeMap(
        ChallengeParse.asMap(challenge, field: 'challenge'),
        currentUid: currentUid(),
        // Sibling of `challenge`, scoped to the caller by the callable. The
        // hold document itself is unreadable from any client, so this response
        // is the only channel through which the app can learn about it.
        premiumHold: ChallengePremiumHold.fromMap(data['premiumHold']),
      );
    });
  }

  @override
  Future<List<ChallengeInvitationSummary>> invitations() async {
    final data = await _call('getChallengeInvitations');
    return _map(() {
      final raw =
          ChallengeParse.asList(data['invitations'], field: 'invitations');
      final invitations = raw
          .map(
            (entry) => ChallengeInvitationSummary.fromPendingView(
              ChallengeParse.asMap(entry, field: 'invitations[]'),
            ),
          )
          .toList(growable: false);
      return List<ChallengeInvitationSummary>.unmodifiable(invitations);
    });
  }

  @override
  Future<LeaveChallengeResult> leave({required String challengeId}) async {
    final data = await _call('leaveChallenge', <String, Object?>{
      'challengeId': challengeId,
    });
    return _map(() => LeaveChallengeResult.fromMap(data));
  }

  @override
  Future<AbandonChallengeResult> abandon({required String challengeId}) async {
    final data = await _call('abandonChallenge', <String, Object?>{
      'challengeId': challengeId,
    });
    return _map(() => AbandonChallengeResult.fromMap(data));
  }

  @override
  Stream<ActiveChallenge?> watchActiveChallenge() {
    final store = readStore;
    if (store == null) {
      return Stream<ActiveChallenge?>.error(
        const ChallengeFailure(reason: ChallengeFailure.unavailableReason),
      );
    }
    final uid = currentUid();
    if (uid == null || uid.isEmpty) {
      return Stream<ActiveChallenge?>.error(
        const ChallengeFailure(reason: 'UNAUTHENTICATED'),
      );
    }
    return _watchActiveChallenge(store, uid);
  }

  Stream<ActiveChallenge?> _watchActiveChallenge(
    ChallengeReadStore store,
    String uid,
  ) async* {
    var levelLabelSeed = const <String, String>{};
    var avatarUrlSeed = const <String, String>{};
    var levelProgressPercentSeed = const <String, int>{};
    // Same hybrid as the level/avatar seeds: the live Firestore snapshots
    // cannot carry the premium hold, because `challengePremiumHolds` is denied
    // to every client, so the callable seed is the only source. A runner who
    // lapses DURING an open stream therefore sees the warning on the next
    // callable refresh rather than instantly — an accepted limitation, and a
    // benign one against a 24-hour window.
    ChallengePremiumHold? premiumHoldSeed;
    try {
      final seeded = await activeChallenge();
      premiumHoldSeed = seeded?.premiumHold;
      levelLabelSeed = <String, String>{
        for (final row
            in seeded?.participants ?? const <ChallengeParticipantRow>[])
          row.uid: row.levelLabelSnapshot,
      };
      avatarUrlSeed = <String, String>{
        for (final row
            in seeded?.participants ?? const <ChallengeParticipantRow>[])
          row.uid: row.avatarUrlSnapshot,
      };
      levelProgressPercentSeed = <String, int>{
        for (final row
            in seeded?.participants ?? const <ChallengeParticipantRow>[])
          row.uid: row.levelProgressPercentSnapshot,
      };
      yield seeded;
    } on ChallengeFailure {
      // The callable seed is unavailable; fall through to the live view with
      // an empty seed rather than failing the whole stream over it.
    }

    yield* store.watchActiveChallengeView(ownerUid: uid).map(
          (view) => mapActiveChallengeView(
            view,
            levelLabelSeed: levelLabelSeed,
            avatarUrlSeed: avatarUrlSeed,
            levelProgressPercentSeed: levelProgressPercentSeed,
            currentUid: currentUid(),
            premiumHold: premiumHoldSeed,
          ),
        );
  }

  @override
  Stream<List<ChallengeInvitationSummary>> watchInvitations() {
    final store = readStore;
    if (store == null) {
      return Stream<List<ChallengeInvitationSummary>>.error(
        const ChallengeFailure(reason: ChallengeFailure.unavailableReason),
      );
    }
    final uid = currentUid();
    if (uid == null || uid.isEmpty) {
      return Stream<List<ChallengeInvitationSummary>>.error(
        const ChallengeFailure(reason: 'UNAUTHENTICATED'),
      );
    }
    return _watchInvitations(store, uid);
  }

  Stream<List<ChallengeInvitationSummary>> _watchInvitations(
    ChallengeReadStore store,
    String uid,
  ) async* {
    var rulesSeed = const <ChallengeTierId, ChallengeRulesSnapshot>{};
    try {
      final seeded = await invitations();
      rulesSeed = <ChallengeTierId, ChallengeRulesSnapshot>{
        for (final summary in seeded)
          if (summary.rules != null) summary.tierId: summary.rules!,
      };
      yield seeded;
    } on ChallengeFailure {
      // The callable seed is unavailable; fall through to the live view with
      // an empty seed rather than failing the whole stream over it.
    }

    yield* store.watchPendingInvitationViews(ownerUid: uid).map(
          (views) => mapPendingInvitationViews(views, rulesSeed: rulesSeed),
        );
  }

  @override
  Future<List<ChallengeHistoryEntry>> history() {
    final store = _requireReadStore();
    return store.loadHistory(ownerUid: _requireUid());
  }

  @override
  Future<ChallengeBadgeOwnership> ownedBadges() {
    final store = _requireReadStore();
    return store.loadOwnedBadges(ownerUid: _requireUid());
  }

  Future<Map<String, Object?>> _call(
    String name, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    try {
      final result = await _functions.httpsCallable(name).call(payload);
      return _asStringMap(result.data);
    } on FirebaseFunctionsException catch (error) {
      throw _failure(error);
    }
  }

  Map<String, Object?> _asStringMap(Object? data) {
    if (data is Map) {
      return <String, Object?>{
        for (final entry in data.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    throw const ChallengeFailure(reason: 'INVALID_RESPONSE');
  }

  ChallengeReadStore _requireReadStore() {
    final store = readStore;
    if (store == null) {
      throw const ChallengeFailure(reason: ChallengeFailure.unavailableReason);
    }
    return store;
  }

  String _requireUid() {
    final uid = currentUid();
    if (uid == null || uid.isEmpty) {
      throw const ChallengeFailure(reason: 'UNAUTHENTICATED');
    }
    return uid;
  }

  T _map<T>(T Function() parse) {
    try {
      return parse();
    } on ChallengeParseException catch (error) {
      throw ChallengeFailure(
        reason: 'INVALID_RESPONSE',
        message: error.toString(),
      );
    }
  }

  ChallengeFailure _failure(FirebaseFunctionsException error) {
    final details = error.details;
    String? reason;
    if (details is Map) {
      final raw = details['reason'];
      if (raw is String && raw.isNotEmpty) {
        reason = raw;
      }
    }
    return ChallengeFailure(
      reason: reason ?? error.code,
      message: error.message,
    );
  }
}
