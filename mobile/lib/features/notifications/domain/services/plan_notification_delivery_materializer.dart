import '../models/notification_inbox_item.dart';
import '../repositories/notification_inbox_repository.dart';
import '../repositories/plan_notification_ledger.dart';
import '../repositories/plan_notification_scheduler.dart';

/// Turns local plan notifications that actually fired into inbox items.
///
/// The inbox is a catch-up surface, so an item may only appear once the runner
/// has genuinely missed something. Two signals feed it, in order of trust:
///
/// 1. A platform delivery report. Android records one from the broadcast
///    receiver that posts the notification, iOS from the `willPresent` /
///    `didReceive` delegates plus a sweep of the notification centre.
/// 2. A time-based backstop over the ledger. iOS reports nothing for a
///    notification delivered in the background and never tapped once it has
///    been swiped away, so anything whose scheduled instant has passed and
///    that the platform never mentioned is treated as delivered.
///
/// A notification cancelled before it fired is absent from the ledger by then,
/// so neither path can resurrect it.
class PlanNotificationDeliveryMaterializer {
  const PlanNotificationDeliveryMaterializer({
    required this.ledger,
    required this.deliveryReader,
    required this.inboxRepository,
    required this.ownerUidProvider,
    this.clock = DateTime.now,
    this.debugLog,
  });

  final PlanNotificationLedger ledger;
  final PlanNotificationDeliveryReader deliveryReader;
  final NotificationInboxRepository inboxRepository;
  final String? Function() ownerUidProvider;
  final DateTime Function() clock;
  final void Function(String message)? debugLog;

  Future<void> materializeDeliveries() async {
    final uid = ownerUidProvider();
    if (uid == null || uid.isEmpty) {
      // Draining is destructive, and an inbox write needs an owner. Leave the
      // platform's records in place until someone is signed in to claim them.
      debugLog?.call('materializeDeliveries skipped: signed out');
      return;
    }

    final entries = await ledger.loadEntries();
    final entriesById = <String, PlanNotificationLedgerEntry>{
      for (final entry in entries) entry.id: entry,
    };
    final materialized = <String>{};
    var ownerChanged = false;

    for (final delivery
        in await deliveryReader.consumeDeliveredNotifications()) {
      if (!_stillOwnedBy(uid)) {
        ownerChanged = true;
        break;
      }
      final entry = entriesById[delivery.id];
      if (entry == null || materialized.contains(entry.id)) {
        // Not one of ours, or already handled. Push notifications land here
        // and are ignored: the app writes those to the inbox on receipt.
        continue;
      }
      if (entry.scheduledAt.isAfter(delivery.deliveredAt)) {
        // A notification scheduled for later cannot be the one that was
        // delivered. Ids are deterministic and reused across schedules, and
        // iOS keeps reporting a delivered notification for as long as it sits
        // in the notification centre, so without this an old report would be
        // misattributed to the next schedule sharing its id — marking it
        // delivered early and clearing the read state the runner had set.
        // The time backstop below still covers it once its moment passes.
        continue;
      }
      if (await _write(entry, delivery.deliveredAt)) {
        materialized.add(entry.id);
      }
    }

    final now = clock();
    for (final entry in entries) {
      if (ownerChanged || !_stillOwnedBy(uid)) {
        ownerChanged = true;
        break;
      }
      if (materialized.contains(entry.id) || entry.scheduledAt.isAfter(now)) {
        continue;
      }
      if (await _write(entry, entry.scheduledAt)) {
        materialized.add(entry.id);
      }
    }

    if (ownerChanged) {
      debugLog?.call('materializeDeliveries stopped: owner changed');
    }
    if (materialized.isNotEmpty) {
      debugLog?.call('materializeDeliveries wrote ${materialized.length}');
      await ledger.removeEntries(materialized);
    }
  }

  /// Whether the runner who was signed in when this pass started is still the
  /// one signed in now.
  ///
  /// The owner is captured once, but every write below resolves the owner
  /// again inside the inbox repository, and the awaits between the two are
  /// long enough to span a sign-out and a sign-in on a shared device. Without
  /// this check, the entries drained on behalf of the previous runner landed
  /// in the next runner's inbox. Items already written before the switch are
  /// still dropped from the ledger below — they genuinely reached the previous
  /// owner's inbox — and whatever is left is retried on the next pass.
  bool _stillOwnedBy(String uid) => ownerUidProvider() == uid;

  /// Returns whether the item reached the inbox. A failed write leaves the
  /// ledger entry in place so the next pass retries it.
  Future<bool> _write(
    PlanNotificationLedgerEntry entry,
    DateTime deliveredAt,
  ) async {
    final notification = entry.notification;
    try {
      await inboxRepository.recordDelivery(
        NotificationInboxItem(
          id: notification.id,
          title: notification.title,
          body: notification.body,
          createdAt: deliveredAt,
          data: <String, Object?>{
            'kind': notification.kind.name,
            ...notification.payload,
            // Stamped last so a payload key cannot displace it. The one-time
            // legacy sweep skips items carrying this, which is what stops a
            // second device from wiping a delivery the first device recorded.
            notificationInboxDeliveredAtKey: deliveredAt.millisecondsSinceEpoch,
          },
          clientManaged: true,
        ),
      );
      return true;
    } catch (error) {
      debugLog?.call('materializeDeliveries failed id=${entry.id}: $error');
      return false;
    }
  }
}
