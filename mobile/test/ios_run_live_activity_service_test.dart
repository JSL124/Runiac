import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/data/ios_run_live_activity_service.dart';
import 'package:runiac_app/features/run/data/platform_run_foreground_service.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_notification_copy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('runiac/run_live_activity');

  group('IosRunLiveActivityService', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('starts updates and stops with display-only payload labels', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      const service = IosRunLiveActivityService(channel: channel);

      await service.start(RunTrackingNotificationCopy.gettingGpsReady);
      await service.update(
        const RunTrackingNotificationCopy(
          title: 'Run paused',
          body: '00:10 • --:-- /km • 0.00 km',
          statusLabel: 'Paused',
          elapsedTimeLabel: '00:10',
          currentPaceLabel: '--:-- /km',
          distanceLabel: '0.00 km',
          supportCopy: 'Tracking is paused until you resume.',
        ),
      );
      await service.stop();

      expect(calls.map((call) => call.method), ['start', 'update', 'stop']);
      expect(calls[0].arguments, {
        'title': 'Runiac is tracking your run',
        'body': '00:00 • --:-- /km • 0.00 km',
        'statusLabel': 'Getting GPS ready',
        'elapsedTimeLabel': '00:00',
        'averagePaceLabel': '--:-- /km',
        'distanceLabel': '0.00 km',
        'supportCopy': 'Keep moving in an open area.',
      });
      expect(calls[1].arguments, {
        'title': 'Run paused',
        'body': '00:10 • --:-- /km • 0.00 km',
        'statusLabel': 'Paused',
        'elapsedTimeLabel': '00:10',
        'averagePaceLabel': '--:-- /km',
        'distanceLabel': '0.00 km',
        'supportCopy': 'Tracking is paused until you resume.',
      });
      expect(calls[2].arguments, isNull);

      for (final call in calls.where((call) => call.arguments != null)) {
        final arguments = call.arguments! as Map<Object?, Object?>;
        expect(arguments.keys, isNot(contains('latitude')));
        expect(arguments.keys, isNot(contains('longitude')));
        expect(arguments.keys, isNot(contains('routeGeometry')));
        expect(arguments.keys, isNot(contains('elapsedSeconds')));
        expect(arguments.keys, isNot(contains('distanceMeters')));
        expect(arguments.keys, isNot(contains('averagePaceSecondsPerKm')));
        expect(arguments.keys, isNot(contains('clientRunSessionId')));
        expect(arguments.keys, isNot(contains('userId')));
        expect(arguments.keys, isNot(contains('xp')));
        expect(arguments.keys, isNot(contains('leaderboardScore')));
      }
    });

    test('does not call native channel on non-iOS platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            callCount += 1;
            return null;
          });
      const service = IosRunLiveActivityService(channel: channel);

      await service.start(RunTrackingNotificationCopy.gettingGpsReady);
      await service.update(RunTrackingNotificationCopy.gettingGpsReady);
      await service.stop();

      expect(callCount, 0);
    });
  });

  group('platformRunForegroundService', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('selects iOS Live Activity service on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(platformRunForegroundService(), isA<IosRunLiveActivityService>());
    });
  });
}
