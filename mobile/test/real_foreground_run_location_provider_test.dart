import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:runiac_app/features/run/data/real_foreground_run_location_provider.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_diagnostics.dart';
import 'package:runiac_app/features/run/domain/services/local_run_tracking_session.dart';

void main() {
  _ForegroundPosition position({
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    double? altitude,
    double? accuracy,
    double? speed,
  }) {
    return _ForegroundPosition(
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      accuracy: accuracy,
      speed: speed,
    );
  }

  group('RealForegroundRunLocationProvider', () {
    test(
      'geolocator Android settings include foreground notification config',
      () {
        const adapter = GeolocatorForegroundLocationAdapter(
          platformOverride: TargetPlatform.android,
        );

        final settings = adapter.locationSettingsFor(
          const LocationSettingsRequest(
            distanceFilterMeters: 0,
            androidForegroundNotification:
                AndroidForegroundNotificationSettings(
                  title: 'Runiac is tracking your run',
                  body: 'GPS active • 12:03 • 1.25 km',
                ),
          ),
        );

        expect(settings, isA<geolocator.AndroidSettings>());
        final androidSettings = settings as geolocator.AndroidSettings;
        final notification = androidSettings.foregroundNotificationConfig;
        expect(notification?.notificationTitle, 'Runiac is tracking your run');
        expect(notification?.notificationText, 'GPS active • 12:03 • 1.25 km');
        expect(notification?.notificationChannelName, 'Runiac Run Tracking');
        expect(notification?.notificationIcon.name, 'ic_launcher');
        expect(notification?.notificationIcon.defType, 'mipmap');
        expect(notification?.setOngoing, isTrue);
        expect(androidSettings.distanceFilter, 0);
      },
    );

    test('preview defaults keep one meter distance filter', () async {
      final adapter = _FakeForegroundAdapter();
      final provider = RealForegroundRunLocationPreviewProvider(
        adapter: adapter,
      );

      await provider.currentLocation();

      expect(adapter.lastSettings?.distanceFilterMeters, 1);
    });

    test('active foreground tracking requests every GPS update', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter();
      final provider = RealForegroundRunLocationProvider(adapter: adapter);

      await provider.start(startedAt: startedAt);

      expect(adapter.lastSettings?.distanceFilterMeters, 0);
    });

    test('foreground samples preserve geolocator altitude', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter();
      final provider = RealForegroundRunLocationProvider(adapter: adapter);

      await provider.start(startedAt: startedAt);
      adapter.emit(
        position(
          timestamp: startedAt.add(const Duration(seconds: 10)),
          latitude: 1.300000,
          longitude: 103.800000,
          altitude: 12.5,
        ),
      );

      final samples = provider.samplesBetween(
        fromActiveOffset: Duration.zero,
        toActiveOffset: const Duration(seconds: 10),
        startedAt: startedAt,
      );

      expect(samples.single.altitudeMeters, 12.5);
    });

    test('preview current location preserves geolocator altitude', () async {
      final adapter = _FakeForegroundAdapter()
        ..currentPosition = position(
          timestamp: DateTime.utc(2026, 6, 14, 7),
          latitude: 1.300000,
          longitude: 103.800000,
          altitude: 9.25,
        );
      final provider = RealForegroundRunLocationPreviewProvider(
        adapter: adapter,
      );

      final sample = await provider.currentLocation();

      expect(sample.altitudeMeters, 9.25);
    });

    test(
      'active foreground tracking uses Runiac-owned Android foreground mode',
      () async {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final adapter = _FakeForegroundAdapter();
        final provider = RealForegroundRunLocationProvider(adapter: adapter);

        await provider.start(startedAt: startedAt);

        final notification =
            adapter.lastSettings?.androidForegroundNotification;
        expect(notification?.title, 'Getting GPS ready');
        expect(notification?.body, 'Keep moving in an open area');
        expect(notification?.setOngoing, isTrue);
        expect(
          adapter.lastSettings?.runiacOwnsAndroidForegroundService,
          isTrue,
        );
      },
    );

    test(
      'Runiac-owned foreground mode disables Geolocator notification config',
      () {
        const adapter = GeolocatorForegroundLocationAdapter(
          platformOverride: TargetPlatform.android,
        );

        final settings = adapter.locationSettingsFor(
          const LocationSettingsRequest(
            distanceFilterMeters: 0,
            runiacOwnsAndroidForegroundService: true,
            androidForegroundNotification:
                AndroidForegroundNotificationSettings(
                  title: 'Runiac is tracking your run',
                  body: 'GPS active • 00:01 • 0.00 km',
                ),
          ),
        );

        expect(settings, isA<geolocator.AndroidSettings>());
        final androidSettings = settings as geolocator.AndroidSettings;
        expect(androidSettings.foregroundNotificationConfig, isNull);
        expect(androidSettings.distanceFilter, 0);
      },
    );

    test('iOS settings use active-run background location configuration', () {
      const adapter = GeolocatorForegroundLocationAdapter(
        platformOverride: TargetPlatform.iOS,
      );

      final settings = adapter.locationSettingsFor(
        const LocationSettingsRequest(
          highAccuracy: false,
          distanceFilterMeters: 7,
        ),
      );

      expect(settings, isA<geolocator.AppleSettings>());
      final appleSettings = settings as geolocator.AppleSettings;
      expect(appleSettings.accuracy, geolocator.LocationAccuracy.medium);
      expect(appleSettings.activityType, geolocator.ActivityType.fitness);
      expect(appleSettings.allowBackgroundLocationUpdates, isTrue);
      expect(appleSettings.pauseLocationUpdatesAutomatically, isFalse);
      expect(appleSettings.showBackgroundLocationIndicator, isTrue);
      expect(appleSettings.distanceFilter, 7);
    });

    test('maps one-shot current position without starting stream', () async {
      final adapter = _FakeForegroundAdapter();
      adapter.currentPosition = position(
        timestamp: DateTime.utc(2026, 6, 14, 7),
        latitude: 1.3009,
        longitude: 103.8,
        accuracy: 5,
        speed: 2.4,
      );
      final provider = RealForegroundRunLocationPreviewProvider(
        adapter: adapter,
      );

      final sample = await provider.currentLocation();

      expect(sample.latitude, 1.3009);
      expect(sample.longitude, 103.8);
      expect(sample.horizontalAccuracyMeters, 5);
      expect(sample.speedMetersPerSecond, 2.4);
      expect(adapter.streamStartCount, 0);
    });

    test('maps foreground positions into local run samples', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter();
      final provider = RealForegroundRunLocationProvider(adapter: adapter);

      await provider.start(startedAt: startedAt);
      adapter.emit(
        position(
          timestamp: startedAt,
          latitude: 1.300000,
          longitude: 103.800000,
          accuracy: 6,
          speed: 2.4,
        ),
      );
      adapter.emit(
        position(
          timestamp: startedAt.add(const Duration(seconds: 60)),
          latitude: 1.300899,
          longitude: 103.800000,
          accuracy: 7,
          speed: 2.5,
        ),
      );

      final samples = provider
          .samplesBetween(
            fromActiveOffset: Duration.zero,
            toActiveOffset: const Duration(seconds: 60),
            startedAt: startedAt,
          )
          .toList();

      expect(samples, hasLength(2));
      expect(samples.first.latitude, 1.300000);
      expect(samples.first.longitude, 103.800000);
      expect(samples.first.horizontalAccuracyMeters, 6);
      expect(samples.first.speedMetersPerSecond, 2.4);
      expect(
        samples.last.recordedAt,
        startedAt.add(const Duration(seconds: 60)),
      );
    });

    test('surfaces foreground location accuracy status from adapter', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter(
        locationAccuracyStatus: RunTrackingLocationAccuracyStatus.reduced,
      );
      final provider = RealForegroundRunLocationProvider(adapter: adapter);

      expect(
        provider.locationAccuracyStatus,
        RunTrackingLocationAccuracyStatus.notChecked,
      );

      await provider.start(startedAt: startedAt);

      expect(
        provider.locationAccuracyStatus,
        RunTrackingLocationAccuracyStatus.reduced,
      );
    });

    test('drains a late sample from an already-passed active window', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter();
      final provider = RealForegroundRunLocationProvider(adapter: adapter);

      await provider.start(startedAt: startedAt);

      expect(
        provider.samplesBetween(
          fromActiveOffset: Duration.zero,
          toActiveOffset: const Duration(seconds: 10),
          startedAt: startedAt,
        ),
        isEmpty,
      );

      adapter.emit(
        position(
          timestamp: startedAt.add(const Duration(seconds: 5)),
          latitude: 1.300100,
          longitude: 103.800000,
          accuracy: 6,
        ),
      );

      final samples = provider
          .samplesBetween(
            fromActiveOffset: const Duration(seconds: 10),
            toActiveOffset: const Duration(seconds: 11),
            startedAt: startedAt,
          )
          .toList();

      expect(samples, hasLength(1));
      expect(
        samples.single.recordedAt,
        startedAt.add(const Duration(seconds: 5)),
      );
      expect(samples.single.latitude, 1.300100);
    });

    test('drains multiple late samples in order and only once', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter();
      final provider = RealForegroundRunLocationProvider(adapter: adapter);

      await provider.start(startedAt: startedAt);
      provider
          .samplesBetween(
            fromActiveOffset: Duration.zero,
            toActiveOffset: const Duration(seconds: 10),
            startedAt: startedAt,
          )
          .toList();

      adapter.emit(
        position(
          timestamp: startedAt.add(const Duration(seconds: 8)),
          latitude: 1.300800,
          longitude: 103.800000,
        ),
      );
      adapter.emit(
        position(
          timestamp: startedAt.add(const Duration(seconds: 3)),
          latitude: 1.300300,
          longitude: 103.800000,
        ),
      );

      final firstDrain = provider
          .samplesBetween(
            fromActiveOffset: const Duration(seconds: 10),
            toActiveOffset: const Duration(seconds: 11),
            startedAt: startedAt,
          )
          .toList();
      final secondDrain = provider
          .samplesBetween(
            fromActiveOffset: const Duration(seconds: 11),
            toActiveOffset: const Duration(seconds: 12),
            startedAt: startedAt,
          )
          .toList();

      expect(firstDrain.map((sample) => sample.recordedAt).toList(), [
        startedAt.add(const Duration(seconds: 3)),
        startedAt.add(const Duration(seconds: 8)),
      ]);
      expect(secondDrain, isEmpty);
    });

    test(
      'buffers by active offset and does not emit paused movement',
      () async {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final adapter = _FakeForegroundAdapter();
        final provider = RealForegroundRunLocationProvider(adapter: adapter);

        await provider.start(startedAt: startedAt);
        adapter.emit(
          position(timestamp: startedAt, latitude: 1.3, longitude: 103.8),
        );
        adapter.emit(
          position(
            timestamp: startedAt.add(const Duration(seconds: 60)),
            latitude: 1.300899,
            longitude: 103.8,
          ),
        );
        final session = LocalRunTrackingSession(startedAt: startedAt);
        session.advanceBy(
          const Duration(seconds: 60),
          samples: provider.samplesBetween(
            fromActiveOffset: Duration.zero,
            toActiveOffset: const Duration(seconds: 60),
            startedAt: startedAt,
          ),
        );
        await provider.pause();
        session.pause();
        adapter.emit(
          position(
            timestamp: startedAt.add(const Duration(seconds: 120)),
            latitude: 1.400000,
            longitude: 103.8,
          ),
        );
        session.resume(
          resumedAt: startedAt.add(const Duration(seconds: 180)),
          activeOffset: const Duration(seconds: 60),
        );
        await provider.resume(
          resumedAt: startedAt.add(const Duration(seconds: 180)),
          activeOffset: const Duration(seconds: 60),
        );
        adapter.emit(
          position(
            timestamp: startedAt.add(const Duration(seconds: 180)),
            latitude: 1.400000,
            longitude: 103.8,
          ),
        );
        adapter.emit(
          position(
            timestamp: startedAt.add(const Duration(seconds: 240)),
            latitude: 1.400899,
            longitude: 103.8,
          ),
        );

        session.advanceBy(
          const Duration(seconds: 60),
          samples: provider.samplesBetween(
            fromActiveOffset: const Duration(seconds: 60),
            toActiveOffset: const Duration(seconds: 120),
            startedAt: startedAt,
          ),
        );

        expect(session.distanceMeters, closeTo(200, 3));
      },
    );

    test('leaves poor accuracy rejection to LocalRunTrackingSession', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter();
      final provider = RealForegroundRunLocationProvider(adapter: adapter);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      await provider.start(startedAt: startedAt);
      adapter.emit(
        position(
          timestamp: startedAt,
          latitude: 1.3,
          longitude: 103.8,
          accuracy: 5,
        ),
      );
      adapter.emit(
        position(
          timestamp: startedAt.add(const Duration(seconds: 60)),
          latitude: 1.350000,
          longitude: 103.8,
          accuracy: 250,
        ),
      );
      adapter.emit(
        position(
          timestamp: startedAt.add(const Duration(seconds: 120)),
          latitude: 1.300899,
          longitude: 103.8,
          accuracy: 5,
        ),
      );

      session.advanceBy(
        const Duration(seconds: 120),
        samples: provider.samplesBetween(
          fromActiveOffset: Duration.zero,
          toActiveOffset: const Duration(seconds: 120),
          startedAt: startedAt,
        ),
      );

      expect(session.distanceMeters, closeTo(100, 2));
      expect(session.rejectedSampleCount, 1);
    });

    test('stop cancels safely and clears buffered raw samples', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter();
      final provider = RealForegroundRunLocationProvider(adapter: adapter);

      await provider.start(startedAt: startedAt);
      adapter.emit(
        position(timestamp: startedAt, latitude: 1.3, longitude: 103.8),
      );
      adapter.emit(
        position(
          timestamp: startedAt.add(const Duration(seconds: 60)),
          latitude: 1.300899,
          longitude: 103.8,
        ),
      );

      expect(
        provider.samplesBetween(
          fromActiveOffset: Duration.zero,
          toActiveOffset: const Duration(seconds: 60),
          startedAt: startedAt,
        ),
        hasLength(2),
      );

      await provider.stop();
      await provider.stop();
      adapter.emit(
        position(
          timestamp: startedAt.add(const Duration(seconds: 120)),
          latitude: 1.301798,
          longitude: 103.8,
        ),
      );

      expect(
        provider.samplesBetween(
          fromActiveOffset: Duration.zero,
          toActiveOffset: const Duration(seconds: 120),
          startedAt: startedAt,
        ),
        isEmpty,
      );
    });
  });
}

class _FakeForegroundAdapter implements ForegroundLocationAdapter {
  _FakeForegroundAdapter({
    this.locationAccuracyStatus = RunTrackingLocationAccuracyStatus.unknown,
  });

  final _controller = StreamController<ForegroundPosition>.broadcast(
    sync: true,
  );
  LocationSettingsRequest? lastSettings;
  final RunTrackingLocationAccuracyStatus locationAccuracyStatus;
  int streamStartCount = 0;
  _ForegroundPosition currentPosition = _ForegroundPosition(
    timestamp: DateTime.utc(2026, 6, 14, 7),
    latitude: 1.3,
    longitude: 103.8,
  );

  void emit(_ForegroundPosition position) {
    _controller.add(position);
  }

  @override
  Future<ForegroundPosition> getCurrentPosition(
    LocationSettingsRequest settings,
  ) async {
    lastSettings = settings;
    return currentPosition;
  }

  @override
  Stream<ForegroundPosition> getPositionStream(
    LocationSettingsRequest settings,
  ) {
    streamStartCount += 1;
    lastSettings = settings;
    return _controller.stream;
  }

  @override
  Future<RunTrackingLocationAccuracyStatus> getLocationAccuracyStatus() async {
    return locationAccuracyStatus;
  }
}

class _ForegroundPosition implements ForegroundPosition {
  const _ForegroundPosition({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
  });

  @override
  final DateTime timestamp;

  @override
  final double latitude;

  @override
  final double longitude;

  @override
  final double? altitude;

  @override
  final double? accuracy;

  @override
  final double? speed;
}
