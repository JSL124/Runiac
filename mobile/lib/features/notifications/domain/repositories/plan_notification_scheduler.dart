import '../models/plan_notification_schedule.dart';

enum PlanNotificationPermissionStatus { granted, denied, notRequired }

abstract interface class PlanNotificationScheduler {
  Future<PlanNotificationPermissionStatus> requestPermission();

  Future<void> syncPlanNotifications(
    List<ScheduledPlanNotification> notifications,
  );

  Future<void> schedulePlanNotification(ScheduledPlanNotification notification);

  Future<void> cancelPlanNotifications();
}

/// One notification the OS actually presented to the runner.
class PlanNotificationDelivery {
  const PlanNotificationDelivery({required this.id, required this.deliveredAt});

  final String id;
  final DateTime deliveredAt;
}

/// Reads the deliveries the platform recorded while the app was closed or in
/// the background.
///
/// This is a pull rather than a stream on purpose: on Android the notification
/// is posted from a `BroadcastReceiver` that can run with no Flutter engine
/// alive, so the only way to learn about it is to ask the platform for what it
/// stored once the engine is back. Draining is destructive — the platform
/// clears what it hands over — so a caller must persist the result before
/// discarding it.
abstract interface class PlanNotificationDeliveryReader {
  Future<List<PlanNotificationDelivery>> consumeDeliveredNotifications();

  /// Fires when a notification is presented while the app is running, so the
  /// badge can update without waiting for the next resume. The payload is not
  /// carried here; listeners re-drain through
  /// [consumeDeliveredNotifications] to keep one source of truth.
  set onDelivered(void Function()? listener);
}

class NoopPlanNotificationScheduler
    implements PlanNotificationScheduler, PlanNotificationDeliveryReader {
  const NoopPlanNotificationScheduler();

  @override
  Future<List<PlanNotificationDelivery>> consumeDeliveredNotifications() async {
    return const <PlanNotificationDelivery>[];
  }

  @override
  set onDelivered(void Function()? listener) {}

  @override
  Future<PlanNotificationPermissionStatus> requestPermission() async {
    return PlanNotificationPermissionStatus.notRequired;
  }

  @override
  Future<void> syncPlanNotifications(
    List<ScheduledPlanNotification> notifications,
  ) async {}

  @override
  Future<void> schedulePlanNotification(
    ScheduledPlanNotification notification,
  ) async {}

  @override
  Future<void> cancelPlanNotifications() async {}
}
