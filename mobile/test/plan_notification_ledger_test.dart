import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/domain/models/plan_notification_schedule.dart';
import 'package:runiac_app/features/notifications/domain/repositories/plan_notification_ledger.dart';

void main() {
  group('mergePlanNotificationLedger', () {
    test('keeps a due entry the new schedule no longer lists', () {
      // Given: a reminder that fired shortly before the app was opened. The
      // policy only emits future notifications, so the next sync cannot list
      // it — but it may not have been materialized yet.
      final fired = _entry(
        id: 'fired',
        scheduledAt: DateTime(2026, 7, 8, 7, 30),
      );
      final upcoming = _notification(
        id: 'upcoming',
        scheduledAt: DateTime(2026, 7, 9, 7, 30),
      );

      // When
      final merged = mergePlanNotificationLedger(
        [fired],
        [upcoming],
        now: DateTime(2026, 7, 8, 7, 35),
      );

      // Then: dropping it here would lose the delivery for good.
      expect(merged.map((entry) => entry.id), ['fired', 'upcoming']);
    });

    test('drops a future plan-owned entry the new schedule omits', () {
      // Given: a missed-run nudge for a workout the runner has since completed.
      final cancelled = _entry(
        id: 'cancelled',
        scheduledAt: DateTime(2026, 7, 9, 8, 30),
      );

      // When
      final merged = mergePlanNotificationLedger(
        [cancelled],
        const <ScheduledPlanNotification>[],
        now: DateTime(2026, 7, 8, 7, 35),
      );

      // Then: a cancelled notification must never become an inbox row.
      expect(merged, isEmpty);
    });

    test('keeps a future entry the plan sync does not own', () {
      // Given: a notification scheduled outside the plan sync. The native
      // scheduler does not cancel it when the plan re-syncs, so evicting it
      // here would leave the ledger disagreeing with the OS — and the
      // notification would fire with nothing left to build an inbox item from.
      final oneOff = _entry(
        id: 'local-notification-smoke-test',
        scheduledAt: DateTime(2026, 7, 8, 7, 36),
        planSyncOwned: false,
      );

      // When: the plan sync runs while it is still in the future.
      final merged = mergePlanNotificationLedger(
        [oneOff],
        const <ScheduledPlanNotification>[],
        now: DateTime(2026, 7, 8, 7, 35),
      );

      // Then
      expect(merged.single.id, 'local-notification-smoke-test');
    });

    test('lets the new schedule replace an entry with the same id', () {
      // Given
      final original = _entry(
        id: 'shared',
        scheduledAt: DateTime(2026, 7, 9, 7, 30),
        title: 'Original',
      );
      final rescheduled = _notification(
        id: 'shared',
        scheduledAt: DateTime(2026, 7, 9, 9),
        title: 'Rescheduled',
      );

      // When
      final merged = mergePlanNotificationLedger(
        [original],
        [rescheduled],
        now: DateTime(2026, 7, 8),
      );

      // Then
      expect(merged.single.notification.title, 'Rescheduled');
      expect(merged.single.scheduledAt, DateTime(2026, 7, 9, 9));
    });
  });

  group('InMemoryPlanNotificationLedger', () {
    test('adds one notification without disturbing the rest', () async {
      // Given
      final ledger = InMemoryPlanNotificationLedger(
        entries: [_entry(id: 'existing', scheduledAt: DateTime(2026, 7, 9))],
      );

      // When
      await ledger.addScheduled(
        _notification(id: 'smoke-test', scheduledAt: DateTime(2026, 7, 8, 12)),
      );

      // Then
      expect((await ledger.loadEntries()).map((entry) => entry.id), [
        'smoke-test',
        'existing',
      ]);
    });

    test('removes only the requested entries', () async {
      // Given
      final ledger = InMemoryPlanNotificationLedger(
        entries: [
          _entry(id: 'a', scheduledAt: DateTime(2026, 7, 8)),
          _entry(id: 'b', scheduledAt: DateTime(2026, 7, 9)),
        ],
      );

      // When
      await ledger.removeEntries(['a']);

      // Then
      expect((await ledger.loadEntries()).single.id, 'b');
    });
  });

  group('ScheduledPlanNotification ledger serialization', () {
    test('round-trips every field the inbox item needs', () {
      // Given
      final notification = _notification(
        id: 'plan-1-week-1-wed-easy-run-missed-60',
        scheduledAt: DateTime(2026, 7, 8, 8, 30),
        title: 'Still planning to run?',
      );

      // When
      final restored = ScheduledPlanNotification.fromLedgerJson(
        notification.toLedgerJson(),
      );

      // Then
      expect(restored, isNotNull);
      expect(restored!.id, notification.id);
      expect(restored.kind, notification.kind);
      expect(restored.scheduledAt, notification.scheduledAt);
      expect(restored.title, notification.title);
      expect(restored.body, notification.body);
      expect(restored.payload, notification.payload);
    });

    test('rejects a malformed record instead of throwing', () {
      expect(
        ScheduledPlanNotification.fromLedgerJson({'id': 'missing-the-rest'}),
        isNull,
      );
      expect(ScheduledPlanNotification.fromLedgerJson('not a map'), isNull);
    });

    test('round-trips plan-sync ownership', () {
      // Given
      final entry = _entry(
        id: 'local-notification-smoke-test',
        scheduledAt: DateTime(2026, 7, 8, 12, 1),
        planSyncOwned: false,
      );

      // When
      final restored = PlanNotificationLedgerEntry.fromLedgerJson(
        entry.toLedgerJson(),
      );

      // Then
      expect(restored!.planSyncOwned, isFalse);
      expect(restored.id, 'local-notification-smoke-test');
    });

    test('treats a record written before ownership existed as plan-owned', () {
      // Given: a ledger persisted by an earlier build.
      final legacy = _notification(
        id: 'legacy',
        scheduledAt: DateTime(2026, 7, 8, 12),
      ).toLedgerJson();

      // Then: the old merge rule applied to everything, so keep that meaning.
      expect(
        PlanNotificationLedgerEntry.fromLedgerJson(legacy)!.planSyncOwned,
        isTrue,
      );
    });
  });
}

PlanNotificationLedgerEntry _entry({
  required String id,
  required DateTime scheduledAt,
  String title = 'Reminder',
  bool planSyncOwned = true,
}) {
  return PlanNotificationLedgerEntry(
    notification: _notification(id: id, scheduledAt: scheduledAt, title: title),
    planSyncOwned: planSyncOwned,
  );
}

ScheduledPlanNotification _notification({
  required String id,
  required DateTime scheduledAt,
  String title = 'Reminder',
}) {
  return ScheduledPlanNotification(
    id: id,
    kind: PlanNotificationKind.missedRunNudge,
    scheduledAt: scheduledAt,
    title: title,
    body: 'Body',
    payload: const <String, String>{
      'planId': 'plan-1',
      'scheduledWorkoutId': 'week-1-wed-easy-run',
    },
  );
}
