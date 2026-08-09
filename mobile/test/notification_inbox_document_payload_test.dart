import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/data/cloud_firestore_notification_inbox_document_store.dart';
import 'package:runiac_app/features/notifications/data/firestore_notification_inbox_repository.dart';

void main() {
  group('notificationInboxDocumentPayload', () {
    test('omits read and delete markers instead of clearing them', () {
      // Given: a re-save of a notification the runner has already read and
      // swiped away. Ids are deterministic, so this happens on every sync.
      final payload = notificationInboxDocumentPayload(
        uid: 'runner-1',
        item: NotificationInboxDocument(
          id: 'plan-1-week-1-wed-easy-run-missed-60',
          title: 'Still planning to run?',
          body: 'Easy Run was scheduled 1 hour ago.',
          createdAt: DateTime.utc(2026, 7, 8, 8, 30),
        ),
        updatedAt: DateTime.utc(2026, 7, 8, 9),
      );

      // Then: writing FieldValue.delete() here is what un-read and un-deleted
      // dismissed notifications, leaving the badge permanently stuck. The
      // merge must be allowed to preserve whatever is stored.
      expect(payload.containsKey('readAt'), isFalse);
      expect(payload.containsKey('deletedAt'), isFalse);
    });

    test('writes read and delete markers when they are set', () {
      // Given
      final payload = notificationInboxDocumentPayload(
        uid: 'runner-1',
        item: NotificationInboxDocument(
          id: 'item',
          title: 'Title',
          body: 'Body',
          createdAt: DateTime.utc(2026, 7, 8, 8, 30),
          readAt: DateTime.utc(2026, 7, 8, 8, 45),
          deletedAt: DateTime.utc(2026, 7, 8, 8, 50),
        ),
        updatedAt: DateTime.utc(2026, 7, 8, 9),
      );

      // Then
      expect(
        payload['readAt'],
        Timestamp.fromDate(DateTime.utc(2026, 7, 8, 8, 45)),
      );
      expect(
        payload['deletedAt'],
        Timestamp.fromDate(DateTime.utc(2026, 7, 8, 8, 50)),
      );
    });

    test('clears read and delete markers when recording a delivery', () {
      // Given: a delivery reusing an id the runner had read and the legacy
      // sweep had deleted.
      final payload = notificationInboxDocumentPayload(
        uid: 'runner-1',
        item: NotificationInboxDocument(
          id: 'item',
          title: 'Title',
          body: 'Body',
          createdAt: DateTime.utc(2026, 7, 8, 8, 30),
        ),
        updatedAt: DateTime.utc(2026, 7, 8, 9),
        clearReadState: true,
      );

      // Then: omitting the keys would preserve the stored state and hide a
      // notification the runner genuinely missed, so they must be deleted.
      expect(payload['readAt'], isA<FieldValue>());
      expect(payload['deletedAt'], isA<FieldValue>());
    });

    test('stays inside the keys the security rules allow', () {
      // Given
      final payload = notificationInboxDocumentPayload(
        uid: 'runner-1',
        item: NotificationInboxDocument(
          id: 'item',
          title: 'Title',
          body: 'Body',
          createdAt: DateTime.utc(2026, 7, 8, 8, 30),
          data: const <String, Object?>{'kind': 'missedRunNudge'},
        ),
        updatedAt: DateTime.utc(2026, 7, 8, 9),
      );

      // Then: firestore.rules pins client writes to exactly this key set.
      expect(payload.keys.toSet(), {
        'ownerUid',
        'clientManaged',
        'title',
        'body',
        'createdAt',
        'data',
        'updatedAt',
      });
      expect(payload['ownerUid'], 'runner-1');
      expect(payload['clientManaged'], isTrue);
    });
  });
}
