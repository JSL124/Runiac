import 'package:flutter/foundation.dart';

import '../domain/repositories/run_foreground_service.dart';
import 'android_run_foreground_service.dart';
import 'ios_run_live_activity_service.dart';

RunForegroundService platformRunForegroundService({TargetPlatform? platform}) {
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => const AndroidRunForegroundService(),
    TargetPlatform.iOS => const IosRunLiveActivityService(),
    _ => const NoopRunForegroundService(),
  };
}
