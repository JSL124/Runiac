import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_center_settings.dart';
import 'package:runiac_app/features/notifications/domain/models/plan_notification_schedule.dart';
import 'package:runiac_app/features/notifications/domain/repositories/notification_center_settings_repository.dart';
import 'package:runiac_app/features/notifications/domain/repositories/notification_inbox_repository.dart';
import 'package:runiac_app/features/notifications/domain/repositories/plan_notification_ledger.dart';
import 'package:runiac_app/features/notifications/domain/repositories/plan_notification_scheduler.dart';
import 'package:runiac_app/features/notifications/domain/services/generated_plan_notification_schedule_builder.dart';
import 'package:runiac_app/features/notifications/domain/services/plan_notification_sync_service.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';

void main() {
  group('PlanNotificationSyncService', () {
    test(
      'cancels scheduled notifications when the user turns notifications off',
      () async {
        // Given: native notifications may already have future plan reminders.
        final settingsRepository = InMemoryNotificationCenterSettingsRepository(
          initialSettings: NotificationCenterSettings.defaults.copyWith(
            notificationsEnabled: false,
          ),
        );
        final scheduler = _RecordingPlanNotificationScheduler();
        final service = PlanNotificationSyncService(
          settingsRepository: settingsRepository,
          scheduler: scheduler,
        );

        // When: the app syncs after the master notification toggle is off.
        await service.syncGeneratedPlan(
          _snapshot(
            startsOnDate: '2026-07-06',
            workout: _workout(dayLabel: 'Wed', scheduleTimeLabel: '7:30 AM'),
          ),
          now: DateTime(2026, 7, 7, 9),
        );

        // Then: scheduled native notifications are cleared, and no new
        // permission prompt or schedule sync can send notifications.
        expect(scheduler.cancelCallCount, 1);
        expect(scheduler.requestPermissionCallCount, 0);
        expect(scheduler.syncedNotifications, isEmpty);
      },
    );

    test(
      'syncs explicit streak-risk notifications with generated plan reminders',
      () async {
        // Given: backend-owned/read streak-risk state is supplied explicitly.
        final settingsRepository = InMemoryNotificationCenterSettingsRepository(
          initialSettings: NotificationCenterSettings.defaults,
        );
        final scheduler = _RecordingPlanNotificationScheduler();
        final service = PlanNotificationSyncService(
          settingsRepository: settingsRepository,
          scheduler: scheduler,
        );

        // When: notification sync receives the explicit read-only risk input.
        await service.syncGeneratedPlan(
          _snapshot(
            startsOnDate: '2026-07-06',
            workout: _workout(dayLabel: 'Wed', scheduleTimeLabel: '7:30 AM'),
          ),
          now: DateTime(2026, 7, 8, 21),
          streakRisk: StreakRiskNotificationInput(
            planId: 'generated-plan',
            riskDate: DateTime(2026, 7, 8),
            streakWouldBreakWithoutValidatedRun: true,
          ),
        );

        // Then: local notifications include streak-risk nudges without client
        // writes or trusted XP/streak/leaderboard payload fields.
        final streakRiskNotifications = scheduler.syncedNotifications.where(
          (notification) =>
              notification.kind == PlanNotificationKind.streakRiskNudge,
        );
        expect(
          streakRiskNotifications.map(
            (notification) => notification.scheduledAt,
          ),
          [DateTime(2026, 7, 8, 22), DateTime(2026, 7, 8, 23)],
        );
        expect(
          streakRiskNotifications.every(
            (notification) =>
                !notification.payload.containsKey('xp') &&
                !notification.payload.containsKey('streak') &&
                !notification.payload.containsKey('leaderboardScore'),
          ),
          isTrue,
        );
      },
    );

    test(
      'records generated local plan reminders in the ledger, never the inbox',
      () async {
        // Given: local plan notifications are enabled for the signed-in runner.
        // The inbox is a catch-up surface for notifications that already fired,
        // so scheduling one must leave it untouched — writing at schedule time
        // is what pinned the unread badge at 99+.
        final settingsRepository = InMemoryNotificationCenterSettingsRepository(
          initialSettings: NotificationCenterSettings.defaults,
        );
        final scheduler = _RecordingPlanNotificationScheduler();
        final inboxRepository = InMemoryNotificationInboxRepository();
        final ledger = InMemoryPlanNotificationLedger();
        final service = PlanNotificationSyncService(
          settingsRepository: settingsRepository,
          scheduler: scheduler,
          ledger: ledger,
        );

        // When: the generated plan reminders are synced to the native scheduler.
        await service.syncGeneratedPlan(
          _snapshot(
            startsOnDate: '2026-07-06',
            workout: _workout(dayLabel: 'Wed', scheduleTimeLabel: '7:30 AM'),
          ),
          now: DateTime(2026, 7, 8, 5),
        );

        // Then: every scheduled reminder is in the ledger, awaiting delivery.
        final entries = await ledger.loadEntries();
        expect(
          entries.map((entry) => entry.id).toSet(),
          scheduler.syncedNotifications
              .map((notification) => notification.id)
              .toSet(),
        );
        expect(entries, isNotEmpty);

        // And: nothing reached the inbox, so the bell badge stays at zero.
        expect(await inboxRepository.listInboxItems(), isEmpty);
      },
    );

    test('clears the ledger when the runner turns notifications off', () async {
      // Given: a ledger holding reminders from an earlier sync.
      final settingsRepository = InMemoryNotificationCenterSettingsRepository(
        initialSettings: NotificationCenterSettings.defaults.copyWith(
          notificationsEnabled: false,
        ),
      );
      final scheduler = _RecordingPlanNotificationScheduler();
      final ledger = InMemoryPlanNotificationLedger(
        entries: [
          PlanNotificationLedgerEntry(
            notification: ScheduledPlanNotification(
              id: 'stale',
              kind: PlanNotificationKind.todaysPlanReminder,
              scheduledAt: DateTime(2026, 7, 9),
              title: 'Stale',
              body: 'Stale',
            ),
            planSyncOwned: true,
          ),
        ],
      );
      final service = PlanNotificationSyncService(
        settingsRepository: settingsRepository,
        scheduler: scheduler,
        ledger: ledger,
      );

      // When
      await service.syncGeneratedPlan(
        _snapshot(
          startsOnDate: '2026-07-06',
          workout: _workout(dayLabel: 'Wed', scheduleTimeLabel: '7:30 AM'),
        ),
        now: DateTime(2026, 7, 7, 9),
      );

      // Then: cancelled notifications cannot later be mistaken for deliveries.
      expect(await ledger.loadEntries(), isEmpty);
    });

    test('keeps a one-off notification when the plan syncs after it', () async {
      // Given: the shell schedules the QA smoke notification and then syncs the
      // generated plan on the same launch. The smoke notification is still in
      // the future and is not part of the plan's set, but the native scheduler
      // does not cancel it — only ids the plan sync registered are cancelled.
      final settingsRepository = InMemoryNotificationCenterSettingsRepository(
        initialSettings: NotificationCenterSettings.defaults,
      );
      final scheduler = _RecordingPlanNotificationScheduler();
      final ledger = InMemoryPlanNotificationLedger();
      final service = PlanNotificationSyncService(
        settingsRepository: settingsRepository,
        scheduler: scheduler,
        ledger: ledger,
      );

      // When
      await service.scheduleSmokeTestNotification(
        now: DateTime(2026, 7, 8, 5),
        delay: const Duration(seconds: 45),
      );
      await service.syncGeneratedPlan(
        _snapshot(
          startsOnDate: '2026-07-06',
          workout: _workout(dayLabel: 'Wed', scheduleTimeLabel: '7:30 AM'),
        ),
        now: DateTime(2026, 7, 8, 5),
      );

      // Then: evicting it would leave the ledger disagreeing with the OS, and
      // the notification would fire with nothing to build an inbox item from.
      final entries = await ledger.loadEntries();
      expect(
        entries.map((entry) => entry.id),
        contains('local-notification-smoke-test'),
      );
    });

    test('schedules a QA smoke notification after a short delay', () async {
      // Given
      final settingsRepository = InMemoryNotificationCenterSettingsRepository(
        initialSettings: NotificationCenterSettings.defaults,
      );
      final scheduler = _RecordingPlanNotificationScheduler();
      final inboxRepository = InMemoryNotificationInboxRepository();
      final ledger = InMemoryPlanNotificationLedger();
      final service = PlanNotificationSyncService(
        settingsRepository: settingsRepository,
        scheduler: scheduler,
        ledger: ledger,
      );

      // When
      await service.scheduleSmokeTestNotification(
        now: DateTime(2026, 7, 8, 12),
        delay: const Duration(seconds: 60),
      );

      // Then
      expect(scheduler.requestPermissionCallCount, 1);
      expect(scheduler.scheduledNotifications.single.toChannelMap(), {
        'id': 'local-notification-smoke-test',
        'kind': 'planUpdate',
        'scheduledAtMillis': DateTime(2026, 7, 8, 12, 1).millisecondsSinceEpoch,
        'title': 'Runiac local notification test',
        'body': 'If you can see this, iOS local notifications are working.',
        'payload': {'kind': 'localNotificationSmokeTest'},
      });
      final entries = await ledger.loadEntries();
      expect(entries.single.id, 'local-notification-smoke-test');
      expect(entries.single.scheduledAt, DateTime(2026, 7, 8, 12, 1));
      expect(await inboxRepository.listInboxItems(), isEmpty);
    });

    test(
      'syncs only the nearest plan notifications when generated reminders exceed the native limit',
      () async {
        // Given: generated plans can produce more reminders than iOS keeps
        // pending for one app.
        final settingsRepository = InMemoryNotificationCenterSettingsRepository(
          initialSettings: NotificationCenterSettings.defaults,
        );
        final scheduler = _RecordingPlanNotificationScheduler();
        final service = PlanNotificationSyncService(
          settingsRepository: settingsRepository,
          scheduler: scheduler,
          scheduleBuilder: const _ManyNotificationScheduleBuilder(),
          maxScheduledNotifications: 48,
        );

        // When
        await service.syncGeneratedPlan(
          _snapshot(
            startsOnDate: '2026-07-06',
            workout: _workout(dayLabel: 'Wed', scheduleTimeLabel: '7:30 AM'),
          ),
          now: DateTime(2026, 7, 8, 12),
        );

        // Then
        expect(scheduler.syncedNotifications, hasLength(48));
        expect(
          scheduler.syncedNotifications.map((notification) => notification.id),
          List.generate(48, (index) => 'many-notification-$index'),
        );
      },
    );
  });
}

class _ManyNotificationScheduleBuilder
    extends GeneratedPlanNotificationScheduleBuilder {
  const _ManyNotificationScheduleBuilder();

  @override
  List<ScheduledPlanNotification> notificationsForPlan(
    BeginnerAdaptivePlanSnapshot snapshot, {
    required NotificationCenterSettings settings,
    required DateTime now,
    required Set<String> completedScheduledWorkoutIds,
    StreakRiskNotificationInput? streakRisk,
  }) {
    return [
      for (var index = 69; index >= 0; index -= 1)
        ScheduledPlanNotification(
          id: 'many-notification-$index',
          kind: PlanNotificationKind.planStartReminder,
          scheduledAt: now.add(Duration(minutes: index + 1)),
          title: 'Reminder $index',
          body: 'Body $index',
          payload: <String, String>{'index': '$index'},
        ),
    ];
  }
}

class _RecordingPlanNotificationScheduler implements PlanNotificationScheduler {
  var requestPermissionCallCount = 0;
  var cancelCallCount = 0;
  final syncedNotifications = <ScheduledPlanNotification>[];
  final scheduledNotifications = <ScheduledPlanNotification>[];

  @override
  Future<PlanNotificationPermissionStatus> requestPermission() async {
    requestPermissionCallCount += 1;
    return PlanNotificationPermissionStatus.granted;
  }

  @override
  Future<void> syncPlanNotifications(
    List<ScheduledPlanNotification> notifications,
  ) async {
    syncedNotifications.addAll(notifications);
  }

  @override
  Future<void> schedulePlanNotification(
    ScheduledPlanNotification notification,
  ) async {
    scheduledNotifications.add(notification);
  }

  @override
  Future<void> cancelPlanNotifications() async {
    cancelCallCount += 1;
  }
}

BeginnerAdaptivePlanSnapshot _snapshot({
  required String startsOnDate,
  required BeginnerAdaptiveWorkout workout,
}) {
  return BeginnerAdaptivePlanSnapshot(
    id: 'generated-plan',
    title: 'Generated plan',
    subtitle: 'Beginner schedule',
    planKind: BeginnerAdaptivePlanKind.onboardingBased,
    sourceLabel: 'Generated onboarding plan',
    startsOnDate: startsOnDate,
    durationWeeks: 1,
    safetyBand: BeginnerPlanSafetyBand.clear,
    templateKind: BeginnerPlanTemplateKind.standardBeginnerStart,
    family: null,
    familyCategory: null,
    familyReason: 'Test fixture',
    supportStyleLabel: 'Gentle',
    weeklyFrequencyLabel: '3 days',
    preferredScheduleLabel: workout.dayLabel,
    sessionDurationLabel: '20 min',
    safetyNote: 'Stop if anything feels wrong.',
    weeks: [
      BeginnerAdaptivePlanWeek(
        weekNumber: 1,
        title: 'Week 1',
        focus: 'Start easy',
        workouts: [workout],
      ),
    ],
  );
}

BeginnerAdaptiveWorkout _workout({
  required String dayLabel,
  String? scheduleTimeLabel,
}) {
  return BeginnerAdaptiveWorkout(
    dayLabel: dayLabel,
    title: 'Easy Run',
    durationMinutes: 20,
    kind: BeginnerWorkoutKind.easyRun,
    intensity: BeginnerPlanIntensity.gentle,
    description: 'Easy effort',
    steps: const ['Warm up', 'Run easy'],
    supportiveNote: 'Keep it relaxed.',
    detail: BeginnerAdaptiveWorkoutDetail(
      metrics: const [
        BeginnerAdaptiveWorkoutMetric(label: 'Time', value: '20 min'),
      ],
      breakdown: const [
        BeginnerAdaptiveWorkoutBreakdownStep(
          kind: BeginnerAdaptiveWorkoutBreakdownStepKind.run,
          title: 'Easy run',
          detail: 'Run relaxed.',
        ),
      ],
      effortGuide: 'Easy',
      coachNotes: const ['Stay conversational.'],
    ),
    scheduleTimeLabel: scheduleTimeLabel,
  );
}
