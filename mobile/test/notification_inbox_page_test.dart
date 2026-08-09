import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_inbox_item.dart';
import 'package:runiac_app/features/notifications/domain/repositories/notification_inbox_repository.dart';
import 'package:runiac_app/features/notifications/presentation/notification_inbox_page.dart';

void main() {
  testWidgets('renders inbox items with read state and relative time', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotificationInboxRepository(
      items: [
        NotificationInboxItem(
          id: 'unread',
          title: 'Tomorrow run reminder',
          body: 'Your 20 min easy run is ready for 7:00 AM.',
          createdAt: DateTime.utc(2026, 7, 8, 5),
        ),
        NotificationInboxItem(
          id: 'read',
          title: 'Plan updated',
          body: 'Your week 3 plan has been adjusted.',
          createdAt: DateTime.utc(2026, 7, 7, 6),
          readAt: DateTime.utc(2026, 7, 7, 7),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxPage(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Tomorrow run reminder'), findsOneWidget);
    expect(
      find.text('Your 20 min easy run is ready for 7:00 AM.'),
      findsOneWidget,
    );
    expect(find.text('3h ago'), findsOneWidget);
    expect(find.text('Plan updated'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.bySemanticsLabel('Unread notification'), findsOneWidget);
  });

  testWidgets('renders calm empty state when inbox has no items', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxPage(
          repository: InMemoryNotificationInboxRepository(),
          now: () => DateTime.utc(2026, 7, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No notifications yet'), findsOneWidget);
    expect(
      find.text('Plan reminders and app updates will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('onOpenItem still fires after the tap marks the item read', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotificationInboxRepository(
      items: [
        NotificationInboxItem(
          id: 'item-1',
          title: 'Run reminder',
          body: 'Your easy run is ready.',
          createdAt: DateTime.utc(2026, 7, 8, 5),
        ),
      ],
    );
    NotificationInboxItem? openedItem;

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxPage(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 8, 8),
          onOpenItem: (item) => openedItem = item,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(openedItem, isNull);

    await tester.tap(find.text('Run reminder'));
    await tester.pumpAndSettle();

    expect(openedItem?.id, 'item-1');
    final items = await repository.listInboxItems();
    expect(items.single.isRead, isTrue);
  });

  testWidgets(
    'partial swipe reveals delete affordance and full swipe soft deletes',
    (WidgetTester tester) async {
      final repository = InMemoryNotificationInboxRepository(
        items: [
          NotificationInboxItem(
            id: 'item-1',
            title: 'Run reminder',
            body: 'Your easy run is ready.',
            createdAt: DateTime.utc(2026, 7, 8, 5),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationInboxPage(
            repository: repository,
            now: () => DateTime.utc(2026, 7, 8, 8),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.text('Run reminder'), const Offset(-80, 0));
      await tester.pump();

      expect(find.bySemanticsLabel('Delete notification'), findsOneWidget);

      await tester.drag(find.text('Run reminder'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(repository.deletedItemIds, ['item-1']);
      expect(find.text('Run reminder'), findsNothing);
    },
  );

  testWidgets('clear all is offered only while the inbox has items', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxPage(
          repository: InMemoryNotificationInboxRepository(),
          now: () => DateTime.utc(2026, 7, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Clear all'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxPage(
          repository: InMemoryNotificationInboxRepository(
            items: [
              NotificationInboxItem(
                id: 'item-1',
                title: 'Run reminder',
                body: 'Your easy run is ready.',
                createdAt: DateTime.utc(2026, 7, 8, 5),
              ),
            ],
          ),
          now: () => DateTime.utc(2026, 7, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Clear all'), findsOneWidget);
    expect(find.bySemanticsLabel('Clear all notifications'), findsOneWidget);
  });

  testWidgets('cancelling the clear all confirmation keeps every item', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryNotificationInboxRepository(
      items: [
        NotificationInboxItem(
          id: 'item-1',
          title: 'Run reminder',
          body: 'Your easy run is ready.',
          createdAt: DateTime.utc(2026, 7, 8, 5),
        ),
        NotificationInboxItem(
          id: 'item-2',
          title: 'Plan updated',
          body: 'Your week 3 plan has been adjusted.',
          createdAt: DateTime.utc(2026, 7, 7, 5),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxPage(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    expect(find.text('Clear all notifications?'), findsOneWidget);
    expect(
      find.text(
        'This removes all 2 notifications from your inbox. You can’t undo this.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.clearAllCallCount, 0);
    expect(repository.deletedItemIds, isEmpty);
    expect(find.text('Run reminder'), findsOneWidget);
    expect(find.text('Plan updated'), findsOneWidget);
  });

  testWidgets(
    'confirming clear all cascades every row out and reveals the empty state',
    (WidgetTester tester) async {
      final repository = InMemoryNotificationInboxRepository(
        items: [
          NotificationInboxItem(
            id: 'item-1',
            title: 'Run reminder',
            body: 'Your easy run is ready.',
            createdAt: DateTime.utc(2026, 7, 8, 5),
          ),
          NotificationInboxItem(
            id: 'item-2',
            title: 'Plan updated',
            body: 'Your week 3 plan has been adjusted.',
            createdAt: DateTime.utc(2026, 7, 7, 5),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationInboxPage(
            repository: repository,
            now: () => DateTime.utc(2026, 7, 8, 8),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('notification-inbox-clear-confirm')),
      );
      await tester.pump();

      // The rows are still on screen, easing out, while the write is in
      // flight: the cascade is what the runner reads as "these are going".
      expect(find.text('Run reminder'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 80));
      final firstRowOpacity = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((opacity) => opacity.opacity)
          .toList();
      expect(firstRowOpacity.any((opacity) => opacity < 1), isTrue);

      await tester.pumpAndSettle();

      expect(repository.clearAllCallCount, 1);
      expect(repository.deletedItemIds, ['item-1', 'item-2']);
      expect(find.text('Run reminder'), findsNothing);
      expect(find.text('Plan updated'), findsNothing);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.text('Clear all'), findsNothing);
    },
  );

  testWidgets('a failed clear restores the rows and reports the failure', (
    WidgetTester tester,
  ) async {
    final repository = _FailingClearAllInboxRepository(
      InMemoryNotificationInboxRepository(
        items: [
          NotificationInboxItem(
            id: 'item-1',
            title: 'Run reminder',
            body: 'Your easy run is ready.',
            createdAt: DateTime.utc(2026, 7, 8, 5),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxPage(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('notification-inbox-clear-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Run reminder'), findsOneWidget);
    expect(
      find.text('Could not clear your notifications. Please try again.'),
      findsOneWidget,
    );
  });
}

/// Delegates everything except [clearAll], which fails the way an offline or
/// permission-denied write would.
class _FailingClearAllInboxRepository implements NotificationInboxRepository {
  _FailingClearAllInboxRepository(this.inner);

  final InMemoryNotificationInboxRepository inner;

  @override
  Stream<List<NotificationInboxItem>> watchInboxItems() =>
      inner.watchInboxItems();

  @override
  Future<List<NotificationInboxItem>> listInboxItems() =>
      inner.listInboxItems();

  @override
  Stream<int> watchUnreadCount() => inner.watchUnreadCount();

  @override
  Future<void> saveInboxItem(NotificationInboxItem item) =>
      inner.saveInboxItem(item);

  @override
  Future<void> recordDelivery(NotificationInboxItem item) =>
      inner.recordDelivery(item);

  @override
  Future<void> markRead(String itemId) => inner.markRead(itemId);

  @override
  Future<void> softDelete(String itemId) => inner.softDelete(itemId);

  @override
  Future<void> clearAll() async {
    throw StateError('offline');
  }
}
