import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/data/firestore_notification_inbox_repository.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_inbox_item.dart';

void main() {
  group('FirestoreNotificationInboxRepository', () {
    test('streams non-deleted inbox items newest first', () async {
      final store = _FakeNotificationInboxDocumentStore(
        items: [
          _document(
            id: 'deleted',
            title: 'Deleted',
            createdAt: DateTime.utc(2026, 7, 8, 9),
            deletedAt: DateTime.utc(2026, 7, 8, 10),
          ),
          _document(
            id: 'older',
            title: 'Older plan update',
            createdAt: DateTime.utc(2026, 7, 7, 9),
          ),
          _document(
            id: 'newer',
            title: 'Tomorrow run reminder',
            createdAt: DateTime.utc(2026, 7, 8, 8),
          ),
        ],
      );
      final repository = FirestoreNotificationInboxRepository(
        ownerUid: 'runner-1',
        documentStore: store,
      );

      final items = await repository.watchInboxItems().first;

      expect(store.watchedUids, ['runner-1']);
      expect(items.map((item) => item.id), ['newer', 'older']);
      expect(items.first.title, 'Tomorrow run reminder');
    });

    test('streams unread count from non-deleted unread items only', () async {
      final repository = FirestoreNotificationInboxRepository(
        ownerUid: 'runner-1',
        documentStore: _FakeNotificationInboxDocumentStore(
          items: [
            _document(id: 'unread-1'),
            _document(id: 'read', readAt: DateTime.utc(2026, 7, 8, 8)),
            _document(id: 'unread-2'),
            _document(id: 'deleted', deletedAt: DateTime.utc(2026, 7, 8, 9)),
          ],
        ),
      );

      await expectLater(repository.watchUnreadCount(), emits(2));
    });

    test('marks an inbox item read through the owner-scoped store', () async {
      final store = _FakeNotificationInboxDocumentStore();
      final repository = FirestoreNotificationInboxRepository(
        ownerUid: 'runner-1',
        documentStore: store,
        clock: () => DateTime.utc(2026, 7, 8, 12),
      );

      await repository.markRead('item-1');

      expect(store.markReadCalls, [
        _WriteCall('runner-1', 'item-1', DateTime.utc(2026, 7, 8, 12)),
      ]);
    });

    test(
      'saves a received local notification through the owner-scoped store',
      () async {
        final store = _FakeNotificationInboxDocumentStore();
        final repository = FirestoreNotificationInboxRepository(
          ownerUid: 'runner-1',
          documentStore: store,
        );
        final item = _document(
          id: 'local-notification-smoke-test',
          title: 'Runiac local notification test',
          body: 'If you can see this, iOS local notifications are working.',
          createdAt: DateTime.utc(2026, 7, 8, 10, 13, 18),
        ).toReadModel();

        await repository.saveInboxItem(item);

        expect(store.savedItems, [_SaveCall('runner-1', item)]);
      },
    );

    test('does not save a local notification without an owner uid', () async {
      final store = _FakeNotificationInboxDocumentStore();
      final repository = FirestoreNotificationInboxRepository(
        ownerUid: '',
        documentStore: store,
      );

      await repository.saveInboxItem(_document().toReadModel());

      expect(store.savedItems, isEmpty);
    });

    test('soft deletes an inbox item by writing deletedAt', () async {
      final store = _FakeNotificationInboxDocumentStore();
      final repository = FirestoreNotificationInboxRepository(
        ownerUid: 'runner-1',
        documentStore: store,
        clock: () => DateTime.utc(2026, 7, 8, 12, 30),
      );

      await repository.softDelete('item-2');

      expect(store.softDeleteCalls, [
        _WriteCall('runner-1', 'item-2', DateTime.utc(2026, 7, 8, 12, 30)),
      ]);
    });

    test(
      'clears every visible item in one bulk write and skips deleted ones',
      () async {
        final store = _FakeNotificationInboxDocumentStore(
          items: [
            _document(id: 'newer', createdAt: DateTime.utc(2026, 7, 8, 9)),
            _document(id: 'older', createdAt: DateTime.utc(2026, 7, 7, 9)),
            _document(
              id: 'already-deleted',
              createdAt: DateTime.utc(2026, 7, 8, 10),
              deletedAt: DateTime.utc(2026, 7, 8, 11),
            ),
          ],
        );
        final repository = FirestoreNotificationInboxRepository(
          ownerUid: 'runner-1',
          documentStore: store,
          clock: () => DateTime.utc(2026, 7, 8, 13),
        );

        await repository.clearAll();

        expect(store.softDeleteAllCalls, hasLength(1));
        final call = store.softDeleteAllCalls.single;
        expect(call.uid, 'runner-1');
        expect(call.itemIds, ['newer', 'older']);
        expect(call.timestamp, DateTime.utc(2026, 7, 8, 13));
        expect(store.softDeleteCalls, isEmpty);
      },
    );

    test('does not write when there is nothing left to clear', () async {
      final store = _FakeNotificationInboxDocumentStore();
      final repository = FirestoreNotificationInboxRepository(
        ownerUid: 'runner-1',
        documentStore: store,
      );

      await repository.clearAll();

      expect(store.softDeleteAllCalls, isEmpty);
    });

    test('does not clear the inbox without an owner uid', () async {
      final store = _FakeNotificationInboxDocumentStore(
        items: [_document(id: 'item-1')],
      );
      final repository = FirestoreNotificationInboxRepository(
        ownerUid: '',
        documentStore: store,
      );

      await repository.clearAll();

      expect(store.softDeleteAllCalls, isEmpty);
    });
  });
}

NotificationInboxDocument _document({
  String id = 'item',
  String title = 'Plan reminder',
  String body = 'Your easy run is ready.',
  DateTime? createdAt,
  DateTime? readAt,
  DateTime? deletedAt,
}) {
  return NotificationInboxDocument(
    id: id,
    title: title,
    body: body,
    createdAt: createdAt ?? DateTime.utc(2026, 7, 8, 7),
    readAt: readAt,
    deletedAt: deletedAt,
    data: const {'route': '/run'},
  );
}

class _FakeNotificationInboxDocumentStore
    implements NotificationInboxDocumentStore {
  _FakeNotificationInboxDocumentStore({this.items = const []});

  final List<NotificationInboxDocument> items;
  final watchedUids = <String>[];
  final savedItems = <_SaveCall>[];
  final clearReadStateCalls = <bool>[];
  final markReadCalls = <_WriteCall>[];
  final softDeleteCalls = <_WriteCall>[];
  final softDeleteAllCalls = <_BulkWriteCall>[];

  @override
  Stream<List<NotificationInboxDocument>> watchInboxItems({
    required String uid,
  }) {
    watchedUids.add(uid);
    return Stream.value(items);
  }

  @override
  Future<void> saveInboxItem({
    required String uid,
    required NotificationInboxDocument item,
    bool clearReadState = false,
  }) async {
    savedItems.add(_SaveCall(uid, item.toReadModel()));
    clearReadStateCalls.add(clearReadState);
  }

  @override
  Future<void> markRead({
    required String uid,
    required String itemId,
    required DateTime readAt,
  }) async {
    markReadCalls.add(_WriteCall(uid, itemId, readAt));
  }

  @override
  Future<void> softDelete({
    required String uid,
    required String itemId,
    required DateTime deletedAt,
  }) async {
    softDeleteCalls.add(_WriteCall(uid, itemId, deletedAt));
  }

  @override
  Future<void> softDeleteAll({
    required String uid,
    required List<String> itemIds,
    required DateTime deletedAt,
  }) async {
    softDeleteAllCalls.add(_BulkWriteCall(uid, itemIds, deletedAt));
  }
}

class _BulkWriteCall {
  const _BulkWriteCall(this.uid, this.itemIds, this.timestamp);

  final String uid;
  final List<String> itemIds;
  final DateTime timestamp;
}

class _SaveCall {
  const _SaveCall(this.uid, this.item);

  final String uid;
  final NotificationInboxItem item;

  @override
  bool operator ==(Object other) {
    return other is _SaveCall &&
        other.uid == uid &&
        other.item.id == item.id &&
        other.item.title == item.title &&
        other.item.body == item.body &&
        other.item.createdAt == item.createdAt &&
        other.item.readAt == item.readAt &&
        other.item.deletedAt == item.deletedAt &&
        _mapsEqual(other.item.data, item.data);
  }

  @override
  int get hashCode => Object.hash(uid, item);

  @override
  String toString() => '_SaveCall($uid, $item)';
}

bool _mapsEqual(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

class _WriteCall {
  const _WriteCall(this.uid, this.itemId, this.at);

  final String uid;
  final String itemId;
  final DateTime at;

  @override
  bool operator ==(Object other) {
    return other is _WriteCall &&
        other.uid == uid &&
        other.itemId == itemId &&
        other.at == at;
  }

  @override
  int get hashCode => Object.hash(uid, itemId, at);

  @override
  String toString() => '_WriteCall($uid, $itemId, $at)';
}
