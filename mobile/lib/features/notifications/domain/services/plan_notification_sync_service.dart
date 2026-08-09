import '../../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import '../models/plan_notification_schedule.dart';
import '../repositories/notification_center_settings_repository.dart';
import '../repositories/plan_notification_ledger.dart';
import '../repositories/plan_notification_scheduler.dart';
import 'generated_plan_notification_schedule_builder.dart';

/// Schedules local plan notifications with the OS and records what was
/// scheduled in the [PlanNotificationLedger].
///
/// This service deliberately never touches the notification inbox. It used to
/// write every notification it scheduled, stamping `createdAt` with the future
/// `scheduledAt`; because the policy only emits notifications that have not
/// fired yet, that meant the inbox held nothing but unfired reminders and the
/// unread badge could never be cleared. Inbox items are now written by
/// [PlanNotificationDeliveryMaterializer] once a notification actually fires.
class PlanNotificationSyncService {
  const PlanNotificationSyncService({
    required this.settingsRepository,
    required this.scheduler,
    this.ledger,
    this.debugLog,
    this.scheduleBuilder = const GeneratedPlanNotificationScheduleBuilder(),
    this.maxScheduledNotifications = 48,
  });

  final NotificationCenterSettingsRepository settingsRepository;
  final PlanNotificationScheduler scheduler;
  final PlanNotificationLedger? ledger;
  final void Function(String message)? debugLog;
  final GeneratedPlanNotificationScheduleBuilder scheduleBuilder;
  final int maxScheduledNotifications;

  Future<void> syncGeneratedPlan(
    BeginnerAdaptivePlanSnapshot? snapshot, {
    required DateTime now,
    Set<String> completedScheduledWorkoutIds = const <String>{},
    StreakRiskNotificationInput? streakRisk,
  }) async {
    final settings = await settingsRepository.loadSettings();
    if (!settings.notificationsEnabled || snapshot == null) {
      await scheduler.cancelPlanNotifications();
      await ledger?.clear();
      return;
    }

    final permissionStatus = await scheduler.requestPermission();
    if (permissionStatus == PlanNotificationPermissionStatus.denied) {
      return;
    }

    final notifications = scheduleBuilder.notificationsForPlan(
      snapshot,
      settings: settings,
      now: now,
      completedScheduledWorkoutIds: completedScheduledWorkoutIds,
      streakRisk: streakRisk,
    );
    final nearestNotifications = _nearestNotifications(notifications);
    await scheduler.syncPlanNotifications(nearestNotifications);
    debugLog?.call(
      'ledger replaceScheduled count=${nearestNotifications.length}',
    );
    await ledger?.replaceScheduled(nearestNotifications, now: now);
  }

  Future<void> scheduleSmokeTestNotification({
    required DateTime now,
    required Duration delay,
  }) async {
    final settings = await settingsRepository.loadSettings();
    if (!settings.notificationsEnabled) {
      debugLog?.call(
        'scheduleSmokeTestNotification skipped: notifications disabled',
      );
      return;
    }

    final permissionStatus = await scheduler.requestPermission();
    if (permissionStatus == PlanNotificationPermissionStatus.denied) {
      debugLog?.call(
        'scheduleSmokeTestNotification skipped: permission denied',
      );
      return;
    }

    final notification = ScheduledPlanNotification(
      id: 'local-notification-smoke-test',
      kind: PlanNotificationKind.planUpdate,
      scheduledAt: now.add(delay),
      title: 'Runiac local notification test',
      body: 'If you can see this, iOS local notifications are working.',
      payload: const <String, String>{'kind': 'localNotificationSmokeTest'},
    );
    await scheduler.schedulePlanNotification(notification);
    debugLog?.call(
      'scheduleSmokeTestNotification scheduled id=${notification.id}',
    );
    await ledger?.addScheduled(notification);
  }

  List<ScheduledPlanNotification> _nearestNotifications(
    List<ScheduledPlanNotification> notifications,
  ) {
    if (notifications.length <= maxScheduledNotifications) {
      return notifications;
    }

    final sortedNotifications = [...notifications]
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return sortedNotifications
        .take(maxScheduledNotifications)
        .toList(growable: false);
  }
}
