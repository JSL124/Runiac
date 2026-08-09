import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M4-B foreground location native config', () {
    test('pubspec uses approved geolocator dependency', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(pubspec, contains('geolocator: ^14.0.3'));
    });

    test(
      'Android declares background tracking V1-B foreground permissions only',
      () {
        final manifest = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();

        expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
        expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
        expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
        expect(
          manifest,
          contains('android.permission.FOREGROUND_SERVICE_LOCATION'),
        );
        expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
        expect(
          manifest,
          isNot(contains('android.permission.ACCESS_BACKGROUND_LOCATION')),
        );
      },
    );

    test('Android declares Runiac-owned location foreground service', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('.RuniacRunTrackingService'));
      expect(manifest, contains('android:exported="false"'));
      expect(manifest, contains('android:foregroundServiceType="location"'));
    });

    test(
      'Android requests notification runtime permission through MainActivity',
      () {
        final activity = File(
          'android/app/src/main/kotlin/com/runiac/runiac_app/MainActivity.kt',
        ).readAsStringSync();

        expect(activity, contains('Manifest.permission.POST_NOTIFICATIONS'));
        expect(activity, contains('requestPostNotificationsPermission'));
        expect(activity, contains('requestPermissions('));
        expect(activity, contains('Build.VERSION_CODES.TIRAMISU'));
      },
    );

    test('Android foreground service bridge avoids Geolocator private IDs', () {
      final activity = File(
        'android/app/src/main/kotlin/com/runiac/runiac_app/MainActivity.kt',
      ).readAsStringSync();
      final service = File(
        'android/app/src/main/kotlin/com/runiac/runiac_app/RuniacRunTrackingService.kt',
      ).readAsStringSync();

      expect(activity, contains('runiac/run_foreground_service'));
      expect(activity, contains('RuniacRunTrackingService::class.java'));
      expect(service, contains('runiac_run_tracking'));
      expect(service, contains('Runiac Run Tracking'));
      expect(service, contains('runiac_run_open_intent'));
      expect(service, contains('RUN_OPEN_INTENT_NOTIFICATION'));
      expect(service, isNot(contains('75415')));
      expect(service, isNot(contains('geolocator_channel_01')));
    });

    test(
      'Android app module explicitly declares NotificationCompat support',
      () {
        final gradle = File('android/app/build.gradle.kts').readAsStringSync();

        expect(gradle, contains('androidx.core:core:1.16.0'));
      },
    );

    test('iOS declares active-run scoped background location mode', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('NSLocationWhenInUseUsageDescription'));
      expect(plist, contains('while you are using the app'));
      expect(
        plist,
        contains(
          RegExp(
            r'<key>UIBackgroundModes</key>\s*<array>\s*<string>location</string>',
          ),
        ),
      );
      expect(plist, isNot(contains('while the app is open')));
    });

    test('iOS background foundation declares Always usage copy', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('NSLocationAlwaysAndWhenInUseUsageDescription'));
      expect(plist, contains('including when the screen is locked'));
      expect(plist, contains('app is in the background'));
      expect(plist, isNot(contains('NSLocationAlwaysUsageDescription')));
    });

    test('iOS-B declares display-only Live Activity support', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final liveActivityPlist = File(
        'ios/RunnerLiveActivity/Info.plist',
      ).readAsStringSync();
      final attributes = File(
        'ios/RunnerLiveActivity/RuniacRunActivityAttributes.swift',
      ).readAsStringSync();
      final widget = File(
        'ios/RunnerLiveActivity/RuniacRunLiveActivityWidget.swift',
      ).readAsStringSync();

      expect(plist, contains('NSSupportsLiveActivities'));
      expect(plist, contains('FLUTTER_BUILD_NAME'));
      expect(plist, contains('FLUTTER_BUILD_NUMBER'));
      expect(liveActivityPlist, contains('FLUTTER_BUILD_NAME'));
      expect(liveActivityPlist, contains('CURRENT_PROJECT_VERSION'));
      expect(liveActivityPlist, isNot(contains('MARKETING_VERSION')));
      expect(project, contains('RunnerLiveActivity.appex'));
      expect(project, contains('com.apple.product-type.app-extension'));
      expect(
        project,
        contains(
          '97C147051CF9000F007C117D /* Build configuration list '
          'for PBXNativeTarget "Runner" */',
        ),
      );
      expect(project, contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0'));
      expect(project, contains('IPHONEOS_DEPLOYMENT_TARGET = 16.1'));
      expect(attributes, contains('ActivityAttributes'));
      expect(attributes, contains('title: String'));
      expect(attributes, contains('statusLabel: String'));
      expect(attributes, contains('elapsedTimeLabel: String'));
      expect(attributes, contains('averagePaceLabel: String'));
      expect(attributes, contains('distanceLabel: String'));
      expect(attributes, contains('supportCopy: String'));
      expect(widget, contains('ActivityConfiguration'));
      expect(widget, contains('DynamicIsland'));
      expect(widget, isNot(contains('latitude')));
      expect(widget, isNot(contains('longitude')));
      expect(widget, isNot(contains('routeGeometry')));
      expect(widget, isNot(contains('elapsedSeconds')));
      expect(widget, isNot(contains('distanceMeters')));
      expect(widget, isNot(contains('averagePaceSecondsPerKm')));
      expect(widget, isNot(contains('clientRunSessionId')));
      expect(widget, isNot(contains('userId')));
      expect(widget, isNot(contains('xpLabel')));
      expect(widget, isNot(contains('XP')));
      expect(widget, isNot(contains('leaderboardScore')));
    });
  });
}
