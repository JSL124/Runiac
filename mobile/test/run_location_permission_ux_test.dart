import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_location_permission_status.dart';
import 'package:runiac_app/features/run/domain/repositories/run_foreground_service.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_preview_provider.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_provider.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_permission_service.dart';
import 'package:runiac_app/features/run/domain/repositories/run_notification_permission_service.dart';
import 'package:runiac_app/features/run/presentation/run_launch_screen.dart';

class _FakePermissionService implements RunLocationPermissionService {
  _FakePermissionService(this.status);

  RunLocationPermissionStatus status;

  @override
  Future<RunLocationPermissionStatus> checkStatus() async => status;

  @override
  Future<RunLocationPermissionStatus> requestPermission() async => status;
}

class _FakePreviewProvider implements RunLocationPreviewProvider {
  @override
  Future<RunLocationSample> currentLocation() async {
    return RunLocationSample(
      recordedAt: DateTime.utc(2026, 6, 14, 7),
      latitude: 1.3009,
      longitude: 103.8,
      horizontalAccuracyMeters: 5,
    );
  }
}

class _FakeNotificationPermissionService
    implements RunNotificationPermissionService {
  const _FakeNotificationPermissionService(this.status);

  final RunNotificationPermissionStatus status;

  @override
  Future<RunNotificationPermissionStatus> requestPermission() async => status;
}

void main() {
  setUp(() {
    // RunLaunchScreen reads voice-coaching settings from the real
    // SharedPreferences-backed repository (no fake is injected by these
    // widget tests). Without mock initial values, SharedPreferences.
    // getInstance() never resolves in the test harness (no platform-channel
    // responder), which would hang `_startRun`'s settings reload forever.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Run location permission UX', () {
    testWidgets('denied location shows supportive retry message', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            permissionService: _FakePermissionService(
              RunLocationPermissionStatus.denied,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('runPermissionGuidance')),
          matching: find.text(
            'Location helps measure your distance and pace. You can try again when you are ready.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('denied forever shows settings guidance', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            permissionService: _FakePermissionService(
              RunLocationPermissionStatus.deniedForever,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('runPermissionGuidance')),
          matching: find.text(
            'Location is blocked for Runiac. Open app settings to allow location for runs.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('service disabled shows GPS enable guidance', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            permissionService: _FakePermissionService(
              RunLocationPermissionStatus.serviceDisabled,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('runPermissionGuidance')),
          matching: find.text(
            'Turn on location services to track distance and pace during your run.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('unavailable shows safe demo fallback copy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            permissionService: _FakePermissionService(
              RunLocationPermissionStatus.unavailable,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('runPermissionGuidance')),
          matching: find.text(
            'GPS is not available right now. You can still use the demo run mode.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('granted location starts the run normally', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            locationProvider: const ConstantSpeedRunLocationProvider(
              metersPerSecond: 2.4,
            ),
            locationPreviewProvider: _FakePreviewProvider(),
            permissionService: _FakePermissionService(
              RunLocationPermissionStatus.granted,
            ),
            notificationPermissionService:
                const _FakeNotificationPermissionService(
                  RunNotificationPermissionStatus.granted,
                ),
            foregroundService: const NoopRunForegroundService(),
          ),
        ),
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();

      expect(find.text('Pause'), findsOneWidget);
      expect(find.byKey(const Key('runPermissionGuidance')), findsNothing);
    });

    testWidgets('denied notification permission explains background tracking', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            locationProvider: const ConstantSpeedRunLocationProvider(
              metersPerSecond: 2.4,
            ),
            locationPreviewProvider: _FakePreviewProvider(),
            permissionService: _FakePermissionService(
              RunLocationPermissionStatus.granted,
            ),
            notificationPermissionService:
                const _FakeNotificationPermissionService(
                  RunNotificationPermissionStatus.denied,
                ),
          ),
        ),
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('runPermissionGuidance')),
          matching: find.text(
            'Notifications are needed to keep tracking visible while Runiac is in the background.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Pause'), findsNothing);
    });
  });
}
