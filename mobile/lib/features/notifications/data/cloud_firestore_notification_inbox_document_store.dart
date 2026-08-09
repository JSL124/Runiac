import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_notification_inbox_repository.dart';

/// Builds the merge payload for a client-written inbox document.
///
/// `readAt` and `deletedAt` are omitted rather than cleared when null. An
/// earlier version wrote `FieldValue.delete()` for them, which meant re-saving
/// a document with a deterministic id — every local plan notification has one —
/// silently un-read and un-deleted whatever the runner had already dismissed,
/// so the unread badge could never be brought down. Omitting the keys lets the
/// merge preserve them. `firestore.rules` validates both conditionally
/// (`!('readAt' in request.resource.data) || ...`), so their absence is allowed.
/// When [clearReadState] is true the two keys are cleared instead, which is how
/// a fresh delivery reuses an id the one-time legacy sweep already marked
/// deleted.
Map<String, Object?> notificationInboxDocumentPayload({
  required String uid,
  required NotificationInboxDocument item,
  required DateTime updatedAt,
  bool clearReadState = false,
}) {
  return <String, Object?>{
    'ownerUid': uid,
    'clientManaged': true,
    'title': item.title,
    'body': item.body,
    'createdAt': Timestamp.fromDate(item.createdAt.toUtc()),
    if (clearReadState)
      'readAt': FieldValue.delete()
    else if (item.readAt != null)
      'readAt': Timestamp.fromDate(item.readAt!.toUtc()),
    if (clearReadState)
      'deletedAt': FieldValue.delete()
    else if (item.deletedAt != null)
      'deletedAt': Timestamp.fromDate(item.deletedAt!.toUtc()),
    'data': item.data,
    'updatedAt': Timestamp.fromDate(updatedAt.toUtc()),
  };
}

class CloudFirestoreNotificationInboxDocumentStore
    implements NotificationInboxDocumentStore {
  CloudFirestoreNotificationInboxDocumentStore({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Kept under Firestore's 500-write batch ceiling with room to spare; an
  /// inbox large enough to need a second batch is already an outlier.
  static const int _maxWritesPerBatch = 400;

  CollectionReference<Map<String, dynamic>> _items(String uid) {
    return _firestore
        .collection('notificationInbox')
        .doc(uid)
        .collection('items');
  }

  @override
  Stream<List<NotificationInboxDocument>> watchInboxItems({
    required String uid,
  }) {
    return _items(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) => _fromSnapshot(document))
              .where((document) => document != null)
              .cast<NotificationInboxDocument>()
              .toList(growable: false),
        );
  }

  @override
  Future<void> saveInboxItem({
    required String uid,
    required NotificationInboxDocument item,
    bool clearReadState = false,
  }) {
    return _items(uid)
        .doc(item.id)
        .set(
          notificationInboxDocumentPayload(
            uid: uid,
            item: item,
            updatedAt: DateTime.now(),
            clearReadState: clearReadState,
          ),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> markRead({
    required String uid,
    required String itemId,
    required DateTime readAt,
  }) {
    return _items(uid).doc(itemId).update({
      'readAt': Timestamp.fromDate(readAt.toUtc()),
      'updatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
    });
  }

  @override
  Future<void> softDelete({
    required String uid,
    required String itemId,
    required DateTime deletedAt,
  }) {
    return _items(uid).doc(itemId).update({
      'deletedAt': Timestamp.fromDate(deletedAt.toUtc()),
      'updatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
    });
  }

  @override
  Future<void> softDeleteAll({
    required String uid,
    required List<String> itemIds,
    required DateTime deletedAt,
  }) async {
    if (itemIds.isEmpty) {
      return;
    }
    final collection = _items(uid);
    final deletedTimestamp = Timestamp.fromDate(deletedAt.toUtc());
    final updatedTimestamp = Timestamp.fromDate(DateTime.now().toUtc());
    for (var start = 0; start < itemIds.length; start += _maxWritesPerBatch) {
      final end = (start + _maxWritesPerBatch) < itemIds.length
          ? start + _maxWritesPerBatch
          : itemIds.length;
      final batch = _firestore.batch();
      for (final itemId in itemIds.sublist(start, end)) {
        batch.update(collection.doc(itemId), {
          'deletedAt': deletedTimestamp,
          'updatedAt': updatedTimestamp,
        });
      }
      await batch.commit();
    }
  }

  NotificationInboxDocument? _fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final createdAt = _readTimestamp(data['createdAt']);
    final title = data['title'];
    final body = data['body'];
    if (createdAt == null || title is! String || body is! String) {
      return null;
    }

    return NotificationInboxDocument(
      id: snapshot.id,
      title: title,
      body: body,
      createdAt: createdAt,
      readAt: _readTimestamp(data['readAt']),
      deletedAt: _readTimestamp(data['deletedAt']),
      data: _readMap(data['data']),
      clientManaged: data['clientManaged'] == true,
    );
  }

  DateTime? _readTimestamp(Object? value) {
    return switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime dateTime => dateTime,
      _ => null,
    };
  }

  Map<String, Object?> _readMap(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}
