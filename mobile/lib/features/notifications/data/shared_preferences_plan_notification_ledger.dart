import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/plan_notification_schedule.dart';
import '../domain/repositories/plan_notification_ledger.dart';

/// Durable per-user ledger backed by the app's existing `shared_preferences`
/// dependency — the same uid-scoped local-flag pattern as
/// [SharedPreferencesPlanCompletionSeenStore].
///
/// Scoping by uid matters on a shared device: a delivery reported by the OS
/// carries only an identifier, and matching it against the signed-in runner's
/// own ledger is what stops another account's reminder from landing in this
/// runner's inbox.
class SharedPreferencesPlanNotificationLedger
    implements PlanNotificationLedger {
  SharedPreferencesPlanNotificationLedger({
    required this.uidProvider,
    this.keyPrefix = 'runiac.planNotifications.ledger',
  });

  /// Resolves the signed-in uid; `null` when signed out (no ledger I/O).
  final String? Function() uidProvider;
  final String keyPrefix;

  String? _key() {
    final uid = uidProvider();
    if (uid == null || uid.isEmpty) {
      return null;
    }
    return '$keyPrefix.$uid';
  }

  @override
  Future<List<PlanNotificationLedgerEntry>> loadEntries() async {
    final key = _key();
    if (key == null) {
      return const <PlanNotificationLedgerEntry>[];
    }
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(key));
  }

  @override
  Future<void> replaceScheduled(
    List<ScheduledPlanNotification> scheduled, {
    required DateTime now,
  }) async {
    final key = _key();
    if (key == null) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final merged = mergePlanNotificationLedger(
      _decode(preferences.getString(key)),
      scheduled,
      now: now,
    );
    await _write(preferences, key, merged);
  }

  @override
  Future<void> addScheduled(ScheduledPlanNotification notification) async {
    final key = _key();
    if (key == null) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final entries = [
      ..._decode(
        preferences.getString(key),
      ).where((entry) => entry.id != notification.id),
      PlanNotificationLedgerEntry(
        notification: notification,
        planSyncOwned: false,
      ),
    ]..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
    await _write(preferences, key, entries);
  }

  @override
  Future<void> removeEntries(Iterable<String> ids) async {
    final key = _key();
    if (key == null) {
      return;
    }
    final removed = ids.toSet();
    if (removed.isEmpty) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final remaining = _decode(
      preferences.getString(key),
    ).where((entry) => !removed.contains(entry.id)).toList(growable: false);
    await _write(preferences, key, remaining);
  }

  @override
  Future<void> clear() async {
    final key = _key();
    if (key == null) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }

  Future<void> _write(
    SharedPreferences preferences,
    String key,
    List<PlanNotificationLedgerEntry> entries,
  ) async {
    if (entries.isEmpty) {
      await preferences.remove(key);
      return;
    }
    await preferences.setString(
      key,
      jsonEncode([for (final entry in entries) entry.toLedgerJson()]),
    );
  }

  List<PlanNotificationLedgerEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <PlanNotificationLedgerEntry>[];
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const <PlanNotificationLedgerEntry>[];
    }
    if (decoded is! List) {
      return const <PlanNotificationLedgerEntry>[];
    }
    return [
      for (final item in decoded)
        ?PlanNotificationLedgerEntry.fromLedgerJson(item),
    ];
  }
}
