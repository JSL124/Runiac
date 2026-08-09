import '../models/run_tracking_notification_copy.dart';

abstract interface class RunForegroundService {
  Future<void> start(RunTrackingNotificationCopy copy);

  Future<void> update(RunTrackingNotificationCopy copy);

  Future<void> stop();
}

class NoopRunForegroundService implements RunForegroundService {
  const NoopRunForegroundService();

  @override
  Future<void> start(RunTrackingNotificationCopy copy) async {}

  @override
  Future<void> update(RunTrackingNotificationCopy copy) async {}

  @override
  Future<void> stop() async {}
}
