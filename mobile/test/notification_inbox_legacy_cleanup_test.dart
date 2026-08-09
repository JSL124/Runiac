import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_inbox_item.dart';
import 'package:runiac_app/features/notifications/domain/repositories/notification_inbox_repository.dart';
import 'package:runiac_app/features/notifications/domain/services/notification_inbox_legacy_cleanup.dart';

void main() {
  group('NotificationInboxLegacyCleanup', () {
    test('clears the client-written backlog but keeps server items', () async {
      // Given: the backlog the old schedule-time write produced, alongside a
      // real challenge notification a Cloud Function delivered.
      final inbox = InMemoryNotificationInboxRepository(
        items: [
          _item(id: 'plan-1-week-1-wed-easy-run-today', clientManaged: true),
          _item(id: 'plan-1-week-1-wed-easy-run-start-60', clientManaged: true),
          _item(id: 'challenge_result_ready_abc', clientManaged: false),
        ],
      );
      final cleanup = NotificationInboxLegacyCleanup(
        inboxRepository: inbox,
        cleanupStore: InMemoryNotificationInboxCleanupStore(),
        ownerUidProvider: () => 'runner-1',
      );

      // When
      await cleanup.runOnce();

      // Then: the badge drops to what the runner actually missed.
      expect(inbox.deletedItemIds, [
        'plan-1-week-1-wed-easy-run-today',
        'plan-1-week-1-wed-easy-run-start-60',
      ]);
      expect(
        (await inbox.listInboxItems()).single.id,
        'challenge_result_ready_abc',
      );
    });

    test('keeps a recorded delivery another device already surfaced', () async {
      // Given: the runner upgraded on one device, which swept its backlog and
      // later recorded a real delivery. This is the second device's first
      // launch after the upgrade, so its own sweep marker is still unset.
      final inbox = InMemoryNotificationInboxRepository(
        items: [
          _item(id: 'legacy-backlog', clientManaged: true),
          NotificationInboxItem(
            id: 'plan-1-week-1-wed-easy-run-today',
            title: 'Today has a planned run',
            body: 'Easy Run is scheduled for today.',
            createdAt: DateTime(2026, 7, 8, 7, 30),
            clientManaged: true,
            data: const <String, Object?>{
              'kind': 'todaysPlanReminder',
              notificationInboxDeliveredAtKey: 1783000000000,
            },
          ),
        ],
      );
      final cleanup = NotificationInboxLegacyCleanup(
        inboxRepository: inbox,
        cleanupStore: InMemoryNotificationInboxCleanupStore(),
        ownerUidProvider: () => 'runner-1',
      );

      // When
      await cleanup.runOnce();

      // Then: only the backlog goes.
      expect(inbox.deletedItemIds, ['legacy-backlog']);
      expect(
        (await inbox.listInboxItems()).single.id,
        'plan-1-week-1-wed-easy-run-today',
      );
    });

    test('runs at most once for a runner', () async {
      // Given
      final inbox = InMemoryNotificationInboxRepository(
        items: [_item(id: 'legacy', clientManaged: true)],
      );
      final store = InMemoryNotificationInboxCleanupStore();
      final cleanup = NotificationInboxLegacyCleanup(
        inboxRepository: inbox,
        cleanupStore: store,
        ownerUidProvider: () => 'runner-1',
      );

      // When: a later launch materializes a genuinely delivered notification,
      // then runs maintenance again.
      await cleanup.runOnce();
      await inbox.saveInboxItem(
        _item(id: 'delivered-later', clientManaged: true),
      );
      await cleanup.runOnce();

      // Then: the second pass must not wipe the new delivery.
      expect((await inbox.listInboxItems()).single.id, 'delivered-later');
    });

    test('does nothing while signed out', () async {
      // Given
      final inbox = InMemoryNotificationInboxRepository(
        items: [_item(id: 'legacy', clientManaged: true)],
      );
      final store = InMemoryNotificationInboxCleanupStore();
      final cleanup = NotificationInboxLegacyCleanup(
        inboxRepository: inbox,
        cleanupStore: store,
        ownerUidProvider: () => null,
      );

      // When
      await cleanup.runOnce();

      // Then: the sweep is not recorded, so the real owner still gets it.
      expect(inbox.deletedItemIds, isEmpty);
      expect(await store.hasCleaned(), isFalse);
    });
  });
}

NotificationInboxItem _item({required String id, required bool clientManaged}) {
  return NotificationInboxItem(
    id: id,
    title: 'Title',
    body: 'Body',
    createdAt: DateTime(2026, 7, 8, 8),
    clientManaged: clientManaged,
  );
}
