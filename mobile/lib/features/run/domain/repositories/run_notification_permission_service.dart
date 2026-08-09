enum RunNotificationPermissionStatus { granted, denied, notRequired }

abstract interface class RunNotificationPermissionService {
  Future<RunNotificationPermissionStatus> requestPermission();
}

class NoopRunNotificationPermissionService
    implements RunNotificationPermissionService {
  const NoopRunNotificationPermissionService();

  @override
  Future<RunNotificationPermissionStatus> requestPermission() async {
    return RunNotificationPermissionStatus.notRequired;
  }
}
