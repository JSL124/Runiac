import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/data/android_run_notification_permission_service.dart';
import 'package:runiac_app/features/run/domain/repositories/run_notification_permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('runiac/notification_permissions');

  group('AndroidRunNotificationPermissionService', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'requests Android POST_NOTIFICATIONS permission over method channel',
      () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return 'granted';
            });
        const service = AndroidRunNotificationPermissionService(
          channel: channel,
        );

        final status = await service.requestPermission();

        expect(status, RunNotificationPermissionStatus.granted);
        expect(calls, hasLength(1));
        expect(calls.single.method, 'requestPostNotificationsPermission');
      },
    );

    test('maps native denial to denied status', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'denied');
      const service = AndroidRunNotificationPermissionService(channel: channel);

      final status = await service.requestPermission();

      expect(status, RunNotificationPermissionStatus.denied);
    });

    test('does not call native channel on non-Android platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            callCount += 1;
            return 'granted';
          });
      const service = AndroidRunNotificationPermissionService(channel: channel);

      final status = await service.requestPermission();

      expect(status, RunNotificationPermissionStatus.notRequired);
      expect(callCount, 0);
    });
  });
}
