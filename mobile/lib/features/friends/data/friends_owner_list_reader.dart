import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/friends_read_model.dart';
import 'friend_identity_mapper.dart';

Future<List<FriendUserReadModel>> readFriendsOwnerList(
  CollectionReference<Map<String, Object?>> collection, {
  String? direction,
}) async {
  final snapshot = await _ownerListFilter(collection, direction: direction)
      .orderBy('listSortKey')
      .orderBy('listSortTieBreaker')
      .limit(30)
      .get();
  return _mapOwnerListSnapshot(snapshot, direction: direction);
}

/// Snapshot-backed live equivalent of [readFriendsOwnerList]. Builds the
/// identical bounded query (same filters, ordering, and limit) and maps
/// every emitted [QuerySnapshot] through the same identity pipeline.
Stream<List<FriendUserReadModel>> watchFriendsOwnerList(
  CollectionReference<Map<String, Object?>> collection, {
  String? direction,
}) {
  return _ownerListFilter(collection, direction: direction)
      .orderBy('listSortKey')
      .orderBy('listSortTieBreaker')
      .limit(30)
      .snapshots()
      .map((snapshot) => _mapOwnerListSnapshot(snapshot, direction: direction));
}

/// Shared filter stage for [readFriendsOwnerList] and [watchFriendsOwnerList]
/// so the one-shot and live-query paths cannot drift.
Query<Map<String, Object?>> _ownerListFilter(
  CollectionReference<Map<String, Object?>> collection, {
  String? direction,
}) {
  Query<Map<String, Object?>> query = collection;
  if (direction != null) {
    query = query
        .where('status', isEqualTo: 'PENDING')
        .where('direction', isEqualTo: direction);
  }
  return query;
}

List<FriendUserReadModel> _mapOwnerListSnapshot(
  QuerySnapshot<Map<String, Object?>> snapshot, {
  String? direction,
}) {
  return snapshot.docs
      .map((document) {
        final data = document.data();
        return mapFriendIdentityDocument(
          data,
          fallbackUid: document.id,
          requestDirection: direction,
          requestCreatedAt: direction == null
              ? null
              : friendRequestCreatedAtValue(data['createdAt']),
        );
      })
      .whereType<FriendUserReadModel>()
      .toList(growable: false);
}

/// Defensively converts the `createdAt` field carried by friend-request
/// documents into a plain [DateTime]. A missing or non-`Timestamp` value
/// returns `null` rather than falling back to any default instant, so a
/// malformed document never renders a bogus relative-time Requests-tab
/// subtitle (e.g. a spurious "56 years ago" from an epoch fallback).
/// Firestore's `Timestamp` type is handled only here (and in the repository
/// this file backs), keeping the rest of the friends feature Firestore-free.
DateTime? friendRequestCreatedAtValue(Object? value) {
  return value is Timestamp ? value.toDate() : null;
}
