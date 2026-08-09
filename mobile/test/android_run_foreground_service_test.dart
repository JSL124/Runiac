import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/data/android_run_foreground_service.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_notification_copy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('runiac/run_foreground_service');

  group('AndroidRunForegroundService', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'starts updates and stops over the Runiac foreground channel',
      () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return null;
            });
        const service = AndroidRunForegroundService(channel: channel);

        await service.start(RunTrackingNotificationCopy.gettingGpsReady);
        await service.update(
          const RunTrackingNotificationCopy(
            title: 'Runiac is tracking your run',
            body: '00:01 • --:-- /km • 0.00 km',
            statusLabel: 'GPS active',
            elapsedTimeLabel: '00:01',
            currentPaceLabel: '--:-- /km',
            distanceLabel: '0.00 km',
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
          'title': 'Runiac is tracking your run',
          'body': '00:01 • --:-- /km • 0.00 km',
          'statusLabel': 'GPS active',
          'elapsedTimeLabel': '00:01',
          'averagePaceLabel': '--:-- /km',
          'distanceLabel': '0.00 km',
          'supportCopy': '',
        });
        expect(calls[2].arguments, isNull);
      },
    );

    test('does not call native channel on non-Android platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            callCount += 1;
            return null;
          });
      const service = AndroidRunForegroundService(channel: channel);

      await service.start(
        const RunTrackingNotificationCopy(title: 'Title', body: 'Body'),
      );
      await service.update(
        const RunTrackingNotificationCopy(title: 'Title', body: 'Body'),
      );
      await service.stop();

      expect(callCount, 0);
    });

    test('expanded notification labels active pace as current pace', () {
      final layout = File(
        'android/app/src/main/res/layout/'
        'runiac_run_tracking_notification_expanded.xml',
      ).readAsStringSync();

      expect(layout, contains('CURRENT PACE'));
      expect(layout, isNot(contains('AVG PACE')));
    });
  });
}
