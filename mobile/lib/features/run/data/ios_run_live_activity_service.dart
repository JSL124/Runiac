import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/models/run_tracking_notification_copy.dart';
import '../domain/repositories/run_foreground_service.dart';

class IosRunLiveActivityService implements RunForegroundService {
  const IosRunLiveActivityService({this.channel = const MethodChannel(_name)});

  static const _name = 'runiac/run_live_activity';
  static const _startMethod = 'start';
  static const _updateMethod = 'update';
  static const _stopMethod = 'stop';

  final MethodChannel channel;

  @override
  Future<void> start(RunTrackingNotificationCopy copy) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    await channel.invokeMethod<void>(_startMethod, _argumentsFor(copy));
  }

  @override
  Future<void> update(RunTrackingNotificationCopy copy) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    await channel.invokeMethod<void>(_updateMethod, _argumentsFor(copy));
  }

  @override
  Future<void> stop() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    await channel.invokeMethod<void>(_stopMethod);
  }

  Map<String, String> _argumentsFor(RunTrackingNotificationCopy copy) {
    return <String, String>{
      'title': copy.title,
      'body': copy.body,
      'statusLabel': copy.statusLabel,
      'elapsedTimeLabel': copy.elapsedTimeLabel,
      'averagePaceLabel': copy.currentPaceLabel,
      'distanceLabel': copy.distanceLabel,
      'supportCopy': copy.supportCopy ?? '',
    };
  }
}
