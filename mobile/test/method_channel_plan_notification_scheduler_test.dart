import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/notifications/data/method_channel_plan_notification_scheduler.dart';
import 'package:runiac_app/features/notifications/domain/models/plan_notification_schedule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('runiac/plan_notifications');

  group('MethodChannelPlanNotificationScheduler', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'syncs scheduled notification payloads over the platform channel',
      () async {
        // Given
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return null;
            });
        final scheduler = MethodChannelPlanNotificationScheduler(
          channel: channel,
        );

        // When
        await scheduler.syncPlanNotifications([
          ScheduledPlanNotification(
            id: 'plan-1-week-1-tue-easy-run-start-120',
            kind: PlanNotificationKind.planStartReminder,
            scheduledAt: DateTime(2026, 7, 8, 5, 30),
            title: 'Easy Run starts in 2 hours',
            body: 'Open Runiac when you are ready to start.',
            payload: const {'planId': 'plan-1'},
          ),
        ]);

        // Then
        expect(calls, hasLength(1));
        expect(calls.single.method, 'syncPlanNotifications');
        final arguments = calls.single.arguments as Map<Object?, Object?>;
        final notifications = arguments['notifications'] as List<Object?>;
        expect(notifications, hasLength(1));
        expect(notifications.single, {
          'id': 'plan-1-week-1-tue-easy-run-start-120',
          'kind': 'planStartReminder',
          'scheduledAtMillis': DateTime(
            2026,
            7,
            8,
            5,
            30,
          ).millisecondsSinceEpoch,
          'title': 'Easy Run starts in 2 hours',
          'body': 'Open Runiac when you are ready to start.',
          'payload': {'planId': 'plan-1'},
        });
      },
    );

    test(
      'cancels scheduled plan notifications over the platform channel',
      () async {
        // Given
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return null;
            });
        final scheduler = MethodChannelPlanNotificationScheduler(
          channel: channel,
        );

        // When
        await scheduler.cancelPlanNotifications();

        // Then
        expect(calls.single.method, 'cancelPlanNotifications');
      },
    );

    test(
      'schedules one notification without replacing existing native requests',
      () async {
        // Given
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return null;
            });
        final scheduler = MethodChannelPlanNotificationScheduler(
          channel: channel,
        );

        // When
        await scheduler.schedulePlanNotification(
          ScheduledPlanNotification(
            id: 'local-notification-smoke-test',
            kind: PlanNotificationKind.planUpdate,
            scheduledAt: DateTime(2026, 7, 8, 12, 1),
            title: 'Runiac local notification test',
            body: 'If you can see this, iOS local notifications are working.',
            payload: const {'kind': 'localNotificationSmokeTest'},
          ),
        );

        // Then
        expect(calls.single.method, 'schedulePlanNotification');
        expect(calls.single.arguments, {
          'id': 'local-notification-smoke-test',
          'kind': 'planUpdate',
          'scheduledAtMillis': DateTime(
            2026,
            7,
            8,
            12,
            1,
          ).millisecondsSinceEpoch,
          'title': 'Runiac local notification test',
          'body': 'If you can see this, iOS local notifications are working.',
          'payload': {'kind': 'localNotificationSmokeTest'},
        });
      },
    );

    test('passes debug flag to native scheduling when enabled', () async {
      // Given
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      final scheduler = MethodChannelPlanNotificationScheduler(
        channel: channel,
        debugLogs: true,
      );

      // When
      await scheduler.requestPermission();
      await scheduler.schedulePlanNotification(
        ScheduledPlanNotification(
          id: 'local-notification-smoke-test',
          kind: PlanNotificationKind.planUpdate,
          scheduledAt: DateTime(2026, 7, 8, 12, 1),
          title: 'Runiac local notification test',
          body: 'If you can see this, iOS local notifications are working.',
        ),
      );

      // Then
      expect(calls.first.method, 'requestPermission');
      expect(calls.first.arguments, {'debugLogs': true});
      expect(calls.last.method, 'schedulePlanNotification');
      expect(calls.last.arguments, containsPair('debugLogs', true));
    });

    test('skips native calls on unsupported desktop test platforms', () async {
      // Given
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            callCount += 1;
            return null;
          });
      final scheduler = MethodChannelPlanNotificationScheduler(
        channel: channel,
      );

      // When
      await scheduler.syncPlanNotifications(const []);
      await scheduler.schedulePlanNotification(
        ScheduledPlanNotification(
          id: 'local-notification-smoke-test',
          kind: PlanNotificationKind.planUpdate,
          scheduledAt: DateTime(2026, 7, 8, 12, 1),
          title: 'Runiac local notification test',
          body: 'If you can see this, iOS local notifications are working.',
        ),
      );
      await scheduler.cancelPlanNotifications();

      // Then
      expect(callCount, 0);
    });

    test('reads platform delivery reports and drops malformed ones', () async {
      // Given: the platform hands back what it recorded while the app was
      // away, including a record it could not complete.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method != 'consumeDeliveredNotifications') {
              return null;
            }
            return <Object?>[
              <Object?, Object?>{
                'id': 'plan-1-week-1-wed-easy-run-today',
                'deliveredAtMillis': DateTime(
                  2026,
                  7,
                  8,
                  7,
                  31,
                ).millisecondsSinceEpoch,
              },
              <Object?, Object?>{'id': 'missing-timestamp'},
              'not a map',
            ];
          });
      final scheduler = MethodChannelPlanNotificationScheduler(
        channel: channel,
      );

      // When
      final deliveries = await scheduler.consumeDeliveredNotifications();

      // Then
      expect(deliveries, hasLength(1));
      expect(deliveries.single.id, 'plan-1-week-1-wed-easy-run-today');
      expect(deliveries.single.deliveredAt, DateTime(2026, 7, 8, 7, 31));
    });

    test(
      'notifies the listener when the platform reports a delivery',
      () async {
        // Given: a notification presented while the app is running produces no
        // resume event, so the badge would otherwise wait for the next launch.
        var notified = 0;
        final scheduler = MethodChannelPlanNotificationScheduler(
          channel: channel,
        );
        scheduler.onDelivered = () => notified += 1;

        // When: native invokes the callback on the same channel.
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              channel.codec.encodeMethodCall(
                const MethodCall('onPlanNotificationDelivered'),
              ),
              (_) {},
            );

        // Then
        expect(notified, 1);

        // And: clearing the listener detaches the handler.
        scheduler.onDelivered = null;
      },
    );
  });
}
