import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/challenge_badge_ownership.dart';
import '../domain/models/challenge_history.dart';
import '../domain/repositories/challenge_repository.dart';

/// Member-scoped Firestore read adapter for the Challenge read paths that have
/// no Cloud Functions callable equivalent, or that need a live stream instead
/// of a one-shot refetch: durable per-user history, per-tier badge ownership,
/// and the two realtime views ([watchActiveChallengeView],
/// [watchPendingInvitationViews]) the lobby/progress/invitations surfaces
/// subscribe to so cross-device actions land without a re-entry refetch.
///
/// This is the only Firestore-touching file in the Challenge feature tree; it
/// is explicitly allowlisted in the backend-owned contract test so every other
/// Challenge file stays Firestore-free. It performs READS ONLY over the exact
/// member-scoped documents the security rules permit
/// (`users/{uid}/challengeHistory`, `users/{uid}/challengeBadges`,
/// `challengeSlots/{uid}`, `challengeInstances/{id}` + its `participants`
/// subcollection, `challengeInvitations`), each bounded by the rules' list
/// limits. It never writes trusted Challenge data; history, badges, rewards,
/// slots, and terminal state are all backend-owned.
class FirestoreChallengeReadStore implements ChallengeReadStore {
  FirestoreChallengeReadStore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const int _listLimit = 30;
  static const int _participantsLimit = 20;
  static const int _invitationsLimit = 20;

  @override
  Future<List<ChallengeHistoryEntry>> loadHistory({
    required String ownerUid,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(ownerUid)
        .collection('challengeHistory')
        .orderBy('endedAt', descending: true)
        .limit(_listLimit)
        .get();

    return List<ChallengeHistoryEntry>.unmodifiable(
      snapshot.docs.map(
        (document) => ChallengeHistoryEntry.fromMap(
          _normalizeHistoryDoc(document.id, document.data()),
        ),
      ),
    );
  }

  @override
  Future<ChallengeBadgeOwnership> loadOwnedBadges({
    required String ownerUid,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(ownerUid)
        .collection('challengeBadges')
        .limit(_listLimit)
        .get();

    return ChallengeBadgeOwnership.fromTierIds(
      snapshot.docs.map((document) => document.id).toList(growable: false),
    );
  }

  @override
  Stream<List<Map<String, Object?>>> watchPendingInvitationViews({
    required String ownerUid,
  }) {
    // Two equality filters + a bound; no `orderBy` so no composite index is
    // required. Newest-first ordering is applied client-side below to match
    // the `getChallengeInvitations` callable's contract.
    return _firestore
        .collection('challengeInvitations')
        .where('recipientUid', isEqualTo: ownerUid)
        .where('status', isEqualTo: 'PENDING')
        .limit(_invitationsLimit)
        .snapshots()
        .map((snapshot) {
      final views = snapshot.docs.map((document) {
        final data = document.data();
        return <String, Object?>{
          'inviteId': data['inviteId'] is String
              ? data['inviteId'] as String
              : document.id,
          'challengeId': data['challengeId'],
          'tierId': data['tierId'],
          'ownerUid': data['ownerUid'],
          'createdAtMs': _millis(data['createdAt']),
          'expiresAtMs': _millis(data['expiresAt']),
        };
      }).toList(growable: false)
        ..sort((a, b) => _asMs(b['createdAtMs']).compareTo(_asMs(a['createdAtMs'])));
      return List<Map<String, Object?>>.unmodifiable(views);
    });
  }

  @override
  Stream<Map<String, Object?>?> watchActiveChallengeView({
    required String ownerUid,
  }) {
    late final StreamController<Map<String, Object?>?> controller;
    StreamSubscription<DocumentSnapshot<Map<String, Object?>>>? slotSubscription;
    StreamSubscription<DocumentSnapshot<Map<String, Object?>>>? instanceSubscription;
    StreamSubscription<QuerySnapshot<Map<String, Object?>>>? participantsSubscription;

    String? subscribedChallengeId;
    DocumentSnapshot<Map<String, Object?>>? latestInstance;
    QuerySnapshot<Map<String, Object?>>? latestParticipants;

    void cancelInnerSubscriptions() {
      unawaited(instanceSubscription?.cancel());
      unawaited(participantsSubscription?.cancel());
      instanceSubscription = null;
      participantsSubscription = null;
      latestInstance = null;
      latestParticipants = null;
    }

    void emitIfReady() {
      final instance = latestInstance;
      final participants = latestParticipants;
      if (instance == null || participants == null) {
        return;
      }
      if (!instance.exists) {
        controller.add(null);
        return;
      }
      controller.add(_buildActiveChallengeView(instance, participants));
    }

    void handleInnerError(Object error, String forChallengeId) {
      if (subscribedChallengeId != forChallengeId) {
        return;
      }
      // The caller lost visibility of this instance (e.g. removed from the
      // roster) — that reads as "no active challenge", not a stream failure.
      // Any other error is forwarded while the slot subscription stays alive.
      if (error is FirebaseException &&
          (error.code == 'permission-denied' || error.code == 'not-found')) {
        cancelInnerSubscriptions();
        controller.add(null);
        return;
      }
      controller.addError(error);
    }

    void subscribeToChallenge(String challengeId) {
      cancelInnerSubscriptions();
      subscribedChallengeId = challengeId;
      final instanceRef =
          _firestore.collection('challengeInstances').doc(challengeId);

      instanceSubscription = instanceRef.snapshots().listen(
        (snapshot) {
          if (subscribedChallengeId != challengeId) {
            return;
          }
          if (!snapshot.exists) {
            cancelInnerSubscriptions();
            controller.add(null);
            return;
          }
          latestInstance = snapshot;
          emitIfReady();
        },
        onError: (Object error) => handleInnerError(error, challengeId),
      );

      participantsSubscription = instanceRef
          .collection('participants')
          .limit(_participantsLimit)
          .snapshots()
          .listen(
        (snapshot) {
          if (subscribedChallengeId != challengeId) {
            return;
          }
          latestParticipants = snapshot;
          emitIfReady();
        },
        onError: (Object error) => handleInnerError(error, challengeId),
      );
    }

    controller = StreamController<Map<String, Object?>?>(
      onListen: () {
        slotSubscription = _firestore
            .collection('challengeSlots')
            .doc(ownerUid)
            .snapshots()
            .listen(
          (slotSnapshot) {
            final data = slotSnapshot.data();
            final challengeId = data == null ? null : data['challengeId'];
            if (!slotSnapshot.exists ||
                challengeId is! String ||
                challengeId.isEmpty) {
              cancelInnerSubscriptions();
              subscribedChallengeId = null;
              controller.add(null);
              return;
            }
            if (challengeId == subscribedChallengeId) {
              return;
            }
            subscribeToChallenge(challengeId);
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await slotSubscription?.cancel();
        await instanceSubscription?.cancel();
        await participantsSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  Map<String, Object?> _buildActiveChallengeView(
    DocumentSnapshot<Map<String, Object?>> instanceDocument,
    QuerySnapshot<Map<String, Object?>> participantsSnapshot,
  ) {
    final data = instanceDocument.data()!;
    final participants = participantsSnapshot.docs.map((document) {
      final row = document.data();
      return <String, Object?>{
        'uid': row['uid'] ?? document.id,
        'role': row['role'],
        'status': row['status'],
        'creditedMeters': row['creditedMeters'],
        'reward': row['reward'],
        'displayNameSnapshot': row['displayNameSnapshot'],
        'avatarInitialsSnapshot': row['avatarInitialsSnapshot'],
      };
    }).toList()
      ..sort((a, b) => (a['uid'] as String).compareTo(b['uid'] as String));

    final instance = <String, Object?>{
      'challengeId': instanceDocument.id,
      'ownerUid': data['ownerUid'],
      'tierId': data['tierId'],
      'catalogVersion': data['catalogVersion'],
      'mode': data['mode'],
      'status': data['status'],
      'rules': data['rules'],
      'rosterUids': data['rosterUids'],
      'maxParticipants': data['maxParticipants'],
      'teamMeters': data['teamMeters'],
      'createdAtMs': _millis(data['createdAt']),
      'lobbyExpiresAtMs': _millis(data['lobbyExpiresAt']),
      'startsAtMs': data['startsAt'] == null ? null : _millis(data['startsAt']),
      'scheduledEndsAtMs': data['scheduledEndsAt'] == null
          ? null
          : _millis(data['scheduledEndsAt']),
      'terminalReason': data['terminalReason'],
    };

    return <String, Object?>{
      'instance': instance,
      'participants': List<Map<String, Object?>>.unmodifiable(participants),
    };
  }

  /// Normalizes a raw history document into the plain map the immutable model
  /// parses: injects the `challengeId` from the doc id and converts Firestore
  /// `Timestamp` fields to epoch milliseconds the model expects.
  Map<String, Object?> _normalizeHistoryDoc(
    String challengeId,
    Map<String, Object?> data,
  ) {
    return <String, Object?>{
      ...data,
      'challengeId': challengeId,
      'startedAtMs': _millis(data['startedAt']),
      'endedAtMs': _millis(data['endedAt']),
    };
  }

  Object? _millis(Object? value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    return value;
  }

  int _asMs(Object? value) => value is int ? value : 0;
}
