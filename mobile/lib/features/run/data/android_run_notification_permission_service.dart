import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/repositories/run_notification_permission_service.dart';

class AndroidRunNotificationPermissionService
    implements RunNotificationPermissionService {
  const AndroidRunNotificationPermissionService({
    this.channel = const MethodChannel(_channelName),
  });

  static const _channelName = 'runiac/notification_permissions';
  static const _requestPostNotificationsMethod =
      'requestPostNotificationsPermission';

  final MethodChannel channel;

  @override
  Future<RunNotificationPermissionStatus> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return RunNotificationPermissionStatus.notRequired;
    }

    final status = await channel.invokeMethod<String>(
      _requestPostNotificationsMethod,
    );
    return switch (status) {
      'granted' => RunNotificationPermissionStatus.granted,
      'denied' => RunNotificationPermissionStatus.denied,
      'notRequired' => RunNotificationPermissionStatus.notRequired,
      _ => RunNotificationPermissionStatus.denied,
    };
  }
}
