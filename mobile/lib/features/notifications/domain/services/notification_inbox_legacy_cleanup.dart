import '../models/notification_inbox_item.dart';
import '../repositories/notification_inbox_repository.dart';

/// Remembers whether a runner's inbox has already been swept.
abstract class NotificationInboxCleanupStore {
  Future<bool> hasCleaned();

  Future<void> markCleaned();
}

class InMemoryNotificationInboxCleanupStore
    implements NotificationInboxCleanupStore {
  InMemoryNotificationInboxCleanupStore([this._cleaned = false]);

  bool _cleaned;

  @override
  Future<bool> hasCleaned() async => _cleaned;

  @override
  Future<void> markCleaned() async {
    _cleaned = true;
  }
}

/// One-time removal of the inbox backlog produced by the old schedule-time
/// write.
///
/// Every local plan notification used to be written into the inbox the moment
/// it was scheduled, with a future `createdAt`, and nothing ever removed those
/// documents. Existing installs therefore carry hundreds of items for
/// notifications that never fired — the reason the bell badge sits at `99+`
/// and cannot be brought down. Only client-written items are swept; anything a
/// Cloud Function delivered is a real notification the runner may still need
/// to read, and is left alone.
class NotificationInboxLegacyCleanup {
  const NotificationInboxLegacyCleanup({
    required this.inboxRepository,
    required this.cleanupStore,
    required this.ownerUidProvider,
    this.debugLog,
  });

  final NotificationInboxRepository inboxRepository;
  final NotificationInboxCleanupStore cleanupStore;
  final String? Function() ownerUidProvider;
  final void Function(String message)? debugLog;

  Future<void> runOnce() async {
    final uid = ownerUidProvider();
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (await cleanupStore.hasCleaned()) {
      return;
    }

    final List<NotificationInboxItem> items;
    try {
      items = await inboxRepository.listInboxItems();
    } catch (error) {
      // Never mark the sweep done on a read we could not complete.
      debugLog?.call('legacy inbox cleanup could not read items: $error');
      return;
    }

    var removed = 0;
    for (final item in items) {
      if (!item.clientManaged || item.isDeleted || item.recordsDelivery) {
        // A recorded delivery is a notification the runner genuinely missed,
        // never part of the backlog. The sweep marker is per-device but the
        // inbox is per-account, so without this a second device's first
        // launch after the upgrade would wipe deliveries the first device had
        // already surfaced.
        continue;
      }
      try {
        await inboxRepository.softDelete(item.id);
        removed += 1;
      } catch (error) {
        debugLog?.call('legacy inbox cleanup failed id=${item.id}: $error');
        return;
      }
    }

    debugLog?.call('legacy inbox cleanup removed=$removed');
    await cleanupStore.markCleaned();
  }
}
