import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/models/plan_notification_schedule.dart';
import '../domain/repositories/plan_notification_scheduler.dart';

class MethodChannelPlanNotificationScheduler
    implements PlanNotificationScheduler, PlanNotificationDeliveryReader {
  MethodChannelPlanNotificationScheduler({
    this.channel = const MethodChannel(_channelName),
    this.debugLogs = const bool.fromEnvironment(
      'RUNIAC_LOCAL_NOTIFICATION_DEBUG_LOGS',
    ),
  });

  static const _channelName = 'runiac/plan_notifications';
  static const _deliveredMethod = 'onPlanNotificationDelivered';

  final MethodChannel channel;
  final bool debugLogs;
  void Function()? _onDelivered;

  @override
  set onDelivered(void Function()? listener) {
    _onDelivered = listener;
    channel.setMethodCallHandler(listener == null ? null : _handleNativeCall);
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == _deliveredMethod) {
      _log('onPlanNotificationDelivered received');
      _onDelivered?.call();
    }
    return null;
  }

  @override
  Future<List<PlanNotificationDelivery>> consumeDeliveredNotifications() async {
    if (!_supportsNativeNotifications) {
      return const <PlanNotificationDelivery>[];
    }
    final delivered = await channel.invokeListMethod<Object?>(
      'consumeDeliveredNotifications',
      _debugArguments(),
    );
    final deliveries = <PlanNotificationDelivery>[
      for (final item in delivered ?? const <Object?>[]) ?_deliveryFrom(item),
    ];
    _log('consumeDeliveredNotifications <- count=${deliveries.length}');
    return deliveries;
  }

  PlanNotificationDelivery? _deliveryFrom(Object? item) {
    if (item is! Map) {
      return null;
    }
    final id = item['id'];
    final deliveredAtMillis = item['deliveredAtMillis'];
    if (id is! String || id.isEmpty || deliveredAtMillis is! int) {
      return null;
    }
    return PlanNotificationDelivery(
      id: id,
      deliveredAt: DateTime.fromMillisecondsSinceEpoch(deliveredAtMillis),
    );
  }

  @override
  Future<PlanNotificationPermissionStatus> requestPermission() async {
    if (!_supportsNativeNotifications) {
      _log('requestPermission skipped: unsupported platform');
      return PlanNotificationPermissionStatus.notRequired;
    }
    _log('requestPermission -> native');
    final status = await channel.invokeMethod<String>(
      'requestPermission',
      _debugArguments(),
    );
    final permissionStatus = switch (status) {
      'granted' => PlanNotificationPermissionStatus.granted,
      'denied' => PlanNotificationPermissionStatus.denied,
      'notRequired' => PlanNotificationPermissionStatus.notRequired,
      _ => PlanNotificationPermissionStatus.denied,
    };
    _log('requestPermission <- $status');
    return permissionStatus;
  }

  @override
  Future<void> syncPlanNotifications(
    List<ScheduledPlanNotification> notifications,
  ) async {
    if (!_supportsNativeNotifications) {
      _log('syncPlanNotifications skipped: unsupported platform');
      return;
    }
    _log('syncPlanNotifications count=${notifications.length}');
    await channel.invokeMethod<void>('syncPlanNotifications', {
      'notifications': [
        for (final notification in notifications) notification.toChannelMap(),
      ],
      if (debugLogs) 'debugLogs': true,
    });
  }

  @override
  Future<void> schedulePlanNotification(
    ScheduledPlanNotification notification,
  ) async {
    if (!_supportsNativeNotifications) {
      _log('schedulePlanNotification skipped: unsupported platform');
      return;
    }
    _log(
      'schedulePlanNotification id=${notification.id} '
      'scheduledAt=${notification.scheduledAt.toIso8601String()}',
    );
    await channel.invokeMethod<void>('schedulePlanNotification', {
      ...notification.toChannelMap(),
      if (debugLogs) 'debugLogs': true,
    });
  }

  @override
  Future<void> cancelPlanNotifications() async {
    if (!_supportsNativeNotifications) {
      _log('cancelPlanNotifications skipped: unsupported platform');
      return;
    }
    _log('cancelPlanNotifications -> native');
    await channel.invokeMethod<void>(
      'cancelPlanNotifications',
      _debugArguments(),
    );
  }

  bool get _supportsNativeNotifications {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Map<String, Object?>? _debugArguments() {
    return debugLogs ? const <String, Object?>{'debugLogs': true} : null;
  }

  void _log(String message) {
    if (!debugLogs) {
      return;
    }
    debugPrint('[RuniacLocalNotifications][Dart] $message');
  }
}
