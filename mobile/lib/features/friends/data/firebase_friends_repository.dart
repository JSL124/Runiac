import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../auth/domain/runiac_auth_service.dart';
import '../domain/models/friends_read_model.dart';
import '../domain/repositories/friends_repository.dart';
import 'friend_identity_mapper.dart';
import 'friend_level_resolver.dart';
import 'friends_owner_list_reader.dart';
import 'friends_repository_errors.dart';

export 'friend_identity_mapper.dart' show mapFriendIdentityDocument;
export 'friends_repository_errors.dart';

/// Reads the friends graph from Firestore and performs friend actions through
/// callables.
///
/// The split is deliberate: *reads* go straight to Firestore, but requesting,
/// accepting and removing a friend go through Cloud Functions. A friendship
/// touches two users' documents at once, and only the backend may write both —
/// the rules do not let a client edit someone else's friend list.
///
/// Friends are displayed with their level, which is backend-owned; see
/// `friend_level_resolver.dart` for how that is read rather than computed here.
class FirebaseFriendsRepository implements FriendsRepository {
  FirebaseFriendsRepository({
    required this.authRepository,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FriendLevelResolver? levelResolver,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-southeast1') {
    _levelResolver = levelResolver ?? FriendLevelResolver(_fetchFriendLevels);
  }

  final RuniacAuthRepository authRepository;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  late final FriendLevelResolver _levelResolver;

  Future<Object?> _fetchFriendLevels(List<String> uids) async {
    final result = await _functions.httpsCallable('getFriendLevels').call(
      <String, Object?>{'uids': uids},
    );
    return result.data;
  }

  @override
  Future<FriendsOverviewReadModel> loadFriendsOverview({
    required String ownerUid,
  }) async {
    _requireAuthenticatedOwner(ownerUid);
    try {
      final user = _firestore.collection('users').doc(ownerUid);
      final snapshots = await Future.wait([
        readFriendsOwnerList(user.collection('friends')),
        readFriendsOwnerList(
          user.collection('friendRequests'),
          direction: 'incoming',
        ),
        readFriendsOwnerList(
          user.collection('friendRequests'),
          direction: 'outgoing',
        ),
        readFriendsOwnerList(user.collection('blockedUsers')),
      ]);
      final overview = FriendsOverviewReadModel(
        friends: snapshots[0],
        incomingRequests: snapshots[1],
        outgoingRequests: snapshots[2],
        blockedUsers: snapshots[3],
      );
      return await _levelResolver.resolveOverview(overview);
    } on FriendsRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    } catch (_) {
      throw const FriendsRepositoryException(
        FriendsRepositoryErrorCode.unavailable,
      );
    }
  }

  @override
  Stream<FriendsOverviewReadModel> watchFriendsOverview({
    required String ownerUid,
  }) {
    _requireAuthenticatedOwner(ownerUid);
    final user = _firestore.collection('users').doc(ownerUid);
    late final StreamController<FriendsOverviewReadModel> controller;
    final subscriptions = <StreamSubscription<void>>[];

    List<FriendUserReadModel>? friends;
    List<FriendUserReadModel>? incomingRequests;
    List<FriendUserReadModel>? outgoingRequests;
    List<FriendUserReadModel>? blockedUsers;
    var resolveGeneration = 0;

    Future<void> emitIfReady() async {
      final currentFriends = friends;
      final currentIncoming = incomingRequests;
      final currentOutgoing = outgoingRequests;
      final currentBlocked = blockedUsers;
      if (currentFriends == null ||
          currentIncoming == null ||
          currentOutgoing == null ||
          currentBlocked == null) {
        return;
      }
      // Every combined emission re-resolves live levels so a level-up or an
      // admin-console XP/level correction shows up on the next push rather
      // than being pinned forever.
      final generation = ++resolveGeneration;
      final overview = await _levelResolver.resolveOverview(
        FriendsOverviewReadModel(
          friends: currentFriends,
          incomingRequests: currentIncoming,
          outgoingRequests: currentOutgoing,
          blockedUsers: currentBlocked,
        ),
      );
      // A newer emission (or a cancelled subscription) superseded this one
      // while the resolve was in flight; drop this stale result.
      if (controller.isClosed || generation != resolveGeneration) return;
      controller.add(overview);
    }

    void handleError(Object error) {
      if (error is FirebaseException) {
        controller.addError(_mapFirebaseError(error));
      } else {
        controller.addError(
          const FriendsRepositoryException(
            FriendsRepositoryErrorCode.unavailable,
          ),
        );
      }
    }

    controller = StreamController<FriendsOverviewReadModel>(
      onListen: () {
        subscriptions.addAll([
          watchFriendsOwnerList(user.collection('friends')).listen((value) {
            friends = value;
            unawaited(emitIfReady());
          }, onError: handleError),
          watchFriendsOwnerList(
            user.collection('friendRequests'),
            direction: 'incoming',
          ).listen((value) {
            incomingRequests = value;
            unawaited(emitIfReady());
          }, onError: handleError),
          watchFriendsOwnerList(
            user.collection('friendRequests'),
            direction: 'outgoing',
          ).listen((value) {
            outgoingRequests = value;
            unawaited(emitIfReady());
          }, onError: handleError),
          watchFriendsOwnerList(user.collection('blockedUsers')).listen((
            value,
          ) {
            blockedUsers = value;
            unawaited(emitIfReady());
          }, onError: handleError),
        ]);
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<FriendUserReadModel>> searchFriends({
    required String ownerUid,
    required String nickname,
  }) async {
    _requireAuthenticatedOwner(ownerUid);
    try {
      final data = await _call('searchFriends', <String, Object?>{
        'nickname': nickname,
      });
      final rawResults = data['results'];
      if (rawResults is! List<Object?>) {
        throw const FriendsRepositoryException(
          FriendsRepositoryErrorCode.unavailable,
        );
      }
      return rawResults
          .map(_mapIdentity)
          .whereType<FriendUserReadModel>()
          .take(1)
          .toList(growable: false);
    } on FriendsRepositoryException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _mapCallableError(error);
    } catch (_) {
      throw const FriendsRepositoryException(
        FriendsRepositoryErrorCode.unavailable,
      );
    }
  }

  @override
  Future<FriendsMutationResult> sendFriendRequest({
    required String ownerUid,
    required String targetUid,
  }) async {
    _requireAuthenticatedOwner(ownerUid);
    final data = await _callSafely('sendFriendRequest', <String, Object?>{
      'targetUid': targetUid,
    });
    return FriendsMutationResult(
      changed: data['created'] == true,
      status: friendStringValue(data['status']),
    );
  }

  @override
  Future<FriendsMutationResult> cancelFriendRequest({
    required String ownerUid,
    required String targetUid,
  }) async {
    _requireAuthenticatedOwner(ownerUid);
    final data = await _callSafely('cancelFriendRequest', <String, Object?>{
      'targetUid': targetUid,
    });
    return FriendsMutationResult(changed: data['cancelled'] == true);
  }

  @override
  Future<FriendsMutationResult> respondToFriendRequest({
    required String ownerUid,
    required String senderUid,
    required FriendRequestResponseAction action,
  }) async {
    _requireAuthenticatedOwner(ownerUid);
    final data = await _callSafely('respondToFriendRequest', <String, Object?>{
      'senderUid': senderUid,
      'action': action.name,
    });
    return FriendsMutationResult(
      changed: data['status'] is String,
      status: friendStringValue(data['status']),
    );
  }

  @override
  Future<FriendsMutationResult> removeFriend({
    required String ownerUid,
    required String friendUid,
  }) async {
    _requireAuthenticatedOwner(ownerUid);
    final data = await _callSafely('removeFriend', <String, Object?>{
      'friendUid': friendUid,
    });
    return FriendsMutationResult(changed: data['removed'] == true);
  }

  @override
  Future<FriendsMutationResult> blockUser({
    required String ownerUid,
    required String targetUid,
  }) async {
    _requireAuthenticatedOwner(ownerUid);
    final data = await _callSafely('blockUser', <String, Object?>{
      'targetUid': targetUid,
    });
    return FriendsMutationResult(changed: data['blocked'] == true);
  }

  @override
  Future<FriendsMutationResult> unblockUser({
    required String ownerUid,
    required String targetUid,
  }) async {
    _requireAuthenticatedOwner(ownerUid);
    final data = await _callSafely('unblockUser', <String, Object?>{
      'targetUid': targetUid,
    });
    return FriendsMutationResult(changed: data['unblocked'] == true);
  }

  Future<Map<String, Object?>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    final result = await _functions.httpsCallable(name).call(payload);
    final data = result.data;
    if (data is! Map<Object?, Object?>) {
      throw const FriendsRepositoryException(
        FriendsRepositoryErrorCode.unavailable,
      );
    }
    return <String, Object?>{
      for (final entry in data.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
  }

  Future<Map<String, Object?>> _callSafely(
    String name,
    Map<String, Object?> payload,
  ) async {
    try {
      return await _call(name, payload);
    } on FriendsRepositoryException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _mapCallableError(error);
    } catch (_) {
      throw const FriendsRepositoryException(
        FriendsRepositoryErrorCode.unavailable,
      );
    }
  }

  void _requireAuthenticatedOwner(String ownerUid) {
    if (authRepository.currentUser?.uid != ownerUid) {
      throw const FriendsRepositoryException(
        FriendsRepositoryErrorCode.authRequired,
      );
    }
  }

  FriendUserReadModel? _mapIdentity(Object? raw, {String? fallbackUid}) {
    if (raw is! Map<Object?, Object?>) return null;
    return mapFriendIdentityDocument(<String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    }, fallbackUid: fallbackUid);
  }

  FriendsRepositoryException _mapCallableError(
    FirebaseFunctionsException error,
  ) {
    return mapFriendsCallableError(
      transportCode: error.code,
      details: error.details,
    );
  }

  FriendsRepositoryException _mapFirebaseError(FirebaseException error) {
    return mapFriendsFirestoreError(error.code);
  }
}
