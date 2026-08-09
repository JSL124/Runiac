import '../models/plan_notification_schedule.dart';

/// One notification handed to the OS, plus who scheduled it.
class PlanNotificationLedgerEntry {
  const PlanNotificationLedgerEntry({
    required this.notification,
    required this.planSyncOwned,
  });

  final ScheduledPlanNotification notification;

  /// True when the plan sync scheduled it. Only plan-owned entries are evicted
  /// when a later sync stops listing them, mirroring the native side: the
  /// scheduler's `cancelPlanNotifications` only cancels ids the plan sync
  /// registered, so a one-off schedule survives natively and must survive here
  /// too. Without this the ledger and the OS disagree, and a notification that
  /// really does fire never reaches the inbox.
  final bool planSyncOwned;

  String get id => notification.id;

  DateTime get scheduledAt => notification.scheduledAt;

  Map<String, Object?> toLedgerJson() {
    return <String, Object?>{
      ...notification.toLedgerJson(),
      'planSyncOwned': planSyncOwned,
    };
  }

  static PlanNotificationLedgerEntry? fromLedgerJson(Object? json) {
    final notification = ScheduledPlanNotification.fromLedgerJson(json);
    if (notification == null) {
      return null;
    }
    return PlanNotificationLedgerEntry(
      notification: notification,
      // Records written before ownership was tracked were all plan-owned.
      planSyncOwned: json is Map ? json['planSyncOwned'] != false : true,
    );
  }
}

/// A local record of the plan notifications actually handed to the OS.
///
/// The inbox is a catch-up surface for notifications the runner missed, so an
/// item may only be written once a notification has genuinely fired. That
/// leaves a gap: at delivery time the OS tells us an identifier and nothing
/// else. This ledger keeps the title, body, kind, and payload alongside that
/// identifier so a delivery can be turned back into an inbox item, and so a
/// notification cancelled before it ever fired can be recognised and dropped.
abstract class PlanNotificationLedger {
  Future<List<PlanNotificationLedgerEntry>> loadEntries();

  /// Records the set just handed to the OS, per [mergePlanNotificationLedger].
  Future<void> replaceScheduled(
    List<ScheduledPlanNotification> scheduled, {
    required DateTime now,
  });

  /// Records one notification scheduled outside the plan sync, without
  /// disturbing the rest of the ledger.
  Future<void> addScheduled(ScheduledPlanNotification notification);

  Future<void> removeEntries(Iterable<String> ids);

  Future<void> clear();
}

/// Merges a freshly scheduled set into the existing ledger.
///
/// Entries already due (`scheduledAt <= now`) survive even when the new set
/// omits them, because they may have fired while the app was closed and not
/// been materialized yet. Without that carry-over, a notification that fired
/// five minutes before launch would be dropped by the sync that runs on the
/// shell's first build and would never reach the inbox.
///
/// A plan-owned entry still in the future that the new set omits is dropped —
/// that is exactly a cancelled notification (a completed workout's missed-run
/// nudge, say), and it must never become an inbox row. Entries scheduled
/// outside the plan sync are never evicted here, because this sync does not
/// cancel them natively either.
List<PlanNotificationLedgerEntry> mergePlanNotificationLedger(
  List<PlanNotificationLedgerEntry> existing,
  List<ScheduledPlanNotification> scheduled, {
  required DateTime now,
}) {
  final merged = <String, PlanNotificationLedgerEntry>{
    for (final entry in existing)
      if (!entry.planSyncOwned || !entry.scheduledAt.isAfter(now))
        entry.id: entry,
  };
  for (final notification in scheduled) {
    merged[notification.id] = PlanNotificationLedgerEntry(
      notification: notification,
      planSyncOwned: true,
    );
  }
  final entries = merged.values.toList()
    ..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
  return List<PlanNotificationLedgerEntry>.unmodifiable(entries);
}

/// Test double and the no-op used wherever local plan notifications are off.
class InMemoryPlanNotificationLedger implements PlanNotificationLedger {
  InMemoryPlanNotificationLedger({
    List<PlanNotificationLedgerEntry> entries =
        const <PlanNotificationLedgerEntry>[],
  }) : _entries = List<PlanNotificationLedgerEntry>.of(entries);

  List<PlanNotificationLedgerEntry> _entries;

  @override
  Future<List<PlanNotificationLedgerEntry>> loadEntries() async {
    return List<PlanNotificationLedgerEntry>.unmodifiable(_entries);
  }

  @override
  Future<void> replaceScheduled(
    List<ScheduledPlanNotification> scheduled, {
    required DateTime now,
  }) async {
    _entries = mergePlanNotificationLedger(_entries, scheduled, now: now);
  }

  @override
  Future<void> addScheduled(ScheduledPlanNotification notification) async {
    _entries = [
      ..._entries.where((entry) => entry.id != notification.id),
      PlanNotificationLedgerEntry(
        notification: notification,
        planSyncOwned: false,
      ),
    ]..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
  }

  @override
  Future<void> removeEntries(Iterable<String> ids) async {
    final removed = ids.toSet();
    _entries = _entries
        .where((entry) => !removed.contains(entry.id))
        .toList(growable: false);
  }

  @override
  Future<void> clear() async {
    _entries = const <PlanNotificationLedgerEntry>[];
  }
}
