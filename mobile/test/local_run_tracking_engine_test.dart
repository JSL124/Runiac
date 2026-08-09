import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_motion_evidence.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_diagnostics.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_startup_readiness.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_state.dart';
import 'package:runiac_app/features/run/domain/services/local_run_tracking_session.dart';
import 'package:runiac_app/features/run/domain/services/run_distance_calculator.dart';
import 'package:runiac_app/features/run/domain/services/run_movement_classifier.dart';

void main() {
  RunLocationSample sampleAt(
    DateTime startedAt,
    int seconds, {
    required double latitude,
    required double longitude,
    double? horizontalAccuracyMeters,
    double? speedMetersPerSecond,
  }) {
    return RunLocationSample(
      recordedAt: startedAt.add(Duration(seconds: seconds)),
      latitude: latitude,
      longitude: longitude,
      horizontalAccuracyMeters: horizontalAccuracyMeters,
      speedMetersPerSecond: speedMetersPerSecond,
    );
  }

  RunMotionEvidence motionAt(
    DateTime startedAt,
    int seconds,
    RunMotionSignal signal,
  ) {
    return RunMotionEvidence(
      recordedAt: startedAt.add(Duration(seconds: seconds)),
      signal: signal,
      confidence: 1,
    );
  }

  group('RunDistanceCalculator', () {
    test('returns zero meters for the same coordinate', () {
      final calculator = RunDistanceCalculator();
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final first = sampleAt(
        startedAt,
        0,
        latitude: 1.300000,
        longitude: 103.800000,
      );
      final second = sampleAt(
        startedAt,
        30,
        latitude: 1.300000,
        longitude: 103.800000,
      );

      expect(calculator.distanceMeters(first, second), 0);
    });

    test('calculates one degree of longitude at the equator', () {
      final calculator = RunDistanceCalculator();
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      final distanceMeters = calculator.distanceMeters(
        sampleAt(startedAt, 0, latitude: 0, longitude: 0),
        sampleAt(startedAt, 30, latitude: 0, longitude: 1),
      );

      expect(distanceMeters, closeTo(111195, 2));
    });

    test('calculates one degree of latitude at the prime meridian', () {
      final calculator = RunDistanceCalculator();
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      final distanceMeters = calculator.distanceMeters(
        sampleAt(startedAt, 0, latitude: 0, longitude: 0),
        sampleAt(startedAt, 30, latitude: 1, longitude: 0),
      );

      expect(distanceMeters, closeTo(111195, 2));
    });

    test('calculates haversine distance between nearby samples', () {
      final calculator = RunDistanceCalculator();
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final first = RunLocationSample(
        recordedAt: startedAt,
        latitude: 1.300000,
        longitude: 103.800000,
      );
      final second = RunLocationSample(
        recordedAt: startedAt.add(const Duration(seconds: 240)),
        latitude: 1.304497,
        longitude: 103.800000,
      );

      final distanceMeters = calculator.distanceMeters(first, second);

      expect(distanceMeters, closeTo(500, 2));
    });
  });

  group('RunTrackingDiagnostics', () {
    test('buckets horizontal accuracy at deterministic boundaries', () {
      expect(
        RunTrackingDiagnostics.bucketForAccuracy(null),
        RunLocationAccuracyBucket.unknown,
      );
      expect(
        RunTrackingDiagnostics.bucketForAccuracy(25),
        RunLocationAccuracyBucket.good,
      );
      expect(
        RunTrackingDiagnostics.bucketForAccuracy(25.1),
        RunLocationAccuracyBucket.weak,
      );
      expect(
        RunTrackingDiagnostics.bucketForAccuracy(100),
        RunLocationAccuracyBucket.weak,
      );
      expect(
        RunTrackingDiagnostics.bucketForAccuracy(100.1),
        RunLocationAccuracyBucket.unusable,
      );
      expect(
        RunTrackingDiagnostics.bucketForAccuracy(-1),
        RunLocationAccuracyBucket.unusable,
      );
      expect(
        RunTrackingDiagnostics.bucketForAccuracy(double.infinity),
        RunLocationAccuracyBucket.unusable,
      );
    });
  });

  group('LocalRunTrackingSession', () {
    test('moving duration accumulates jittered subsecond advances', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(const Duration(milliseconds: 999));
      expect(session.activeDurationSeconds, 0);

      session.advanceBy(const Duration(milliseconds: 1001));
      expect(session.activeDurationSeconds, 2);

      final halfSecondSession = LocalRunTrackingSession(startedAt: startedAt);
      for (var tick = 0; tick < 4; tick += 1) {
        halfSecondSession.advanceBy(const Duration(milliseconds: 500));
      }
      expect(halfSecondSession.activeDurationSeconds, 2);

      final jitteredSession = LocalRunTrackingSession(startedAt: startedAt);
      for (var tick = 0; tick < 5; tick += 1) {
        jitteredSession.advanceBy(const Duration(milliseconds: 980));
        jitteredSession.advanceBy(const Duration(milliseconds: 1020));
      }
      expect(jitteredSession.activeDurationSeconds, 10);
    });

    test('manual pause suppresses jittered moving duration accumulation', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(const Duration(milliseconds: 999));
      session.advanceBy(const Duration(milliseconds: 1001));
      session.pause();
      session.advanceBy(const Duration(minutes: 3, milliseconds: 999));

      expect(session.activeDurationSeconds, 2);
    });

    test(
      'auto pause suppresses later jittered moving duration accumulation',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final session = LocalRunTrackingSession(startedAt: startedAt);

        session.advanceBy(
          const Duration(seconds: 1),
          samples: [
            sampleAt(
              startedAt,
              1,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ],
        );
        for (var tick = 0; tick < 10; tick += 1) {
          session.advanceBy(const Duration(milliseconds: 500));
        }

        expect(session.movementStatus, RunMovementStatus.autoPaused);
        expect(session.activeDurationSeconds, 5);

        session.advanceBy(const Duration(milliseconds: 999));
        session.advanceBy(const Duration(milliseconds: 1001));

        expect(session.activeDurationSeconds, 5);
      },
    );

    test(
      'abnormal pause suppresses later jittered moving duration accumulation',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final session = LocalRunTrackingSession(startedAt: startedAt);

        session.advanceBy(
          const Duration(seconds: 3),
          samples: [
            sampleAt(
              startedAt,
              0,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
            for (final seconds in [1, 2, 3])
              sampleAt(
                startedAt,
                seconds,
                latitude: 1.300000 + (0.000063 * seconds),
                longitude: 103.800000,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 7,
              ),
          ],
        );

        expect(session.movementStatus, RunMovementStatus.abnormalPaused);
        final activeDurationBeforeJitter = session.activeDurationSeconds;

        session.advanceBy(const Duration(milliseconds: 999));
        session.advanceBy(const Duration(milliseconds: 1001));

        expect(session.activeDurationSeconds, activeDurationBeforeJitter);
      },
    );

    test('keeps the first accepted GPS sample as a zero-distance anchor', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );

      final snapshot = RunTrackingSnapshot.fromState(
        RunTrackingState(
          phase: RunTrackingPhase.active,
          clientRunSessionId: 'anchor-readiness',
          startedAt: startedAt,
          completedAt: null,
          elapsedSeconds: session.activeDurationSeconds,
          distanceMeters: session.distanceMeters,
          averagePaceSecondsPerKm: session.averagePaceSecondsPerKm,
          currentPaceSecondsPerKm: session.currentPaceSecondsPerKm,
          routePrivacy: 'private',
          source: session.source,
          locationStatus: RunTrackingLocationStatus.gpsActive,
          diagnostics: session.diagnostics,
        ),
      );

      expect(session.acceptedSampleCount, 1);
      expect(session.distanceMeters, 0);
      expect(session.averagePaceSecondsPerKm, 0);
      expect(
        snapshot.startupReadiness,
        RunTrackingStartupReadiness.anchoredNoMovement,
      );
      expect(snapshot.averagePaceLabel, '--:--/km');
    });

    test('uses one 50m movement threshold for startup pace readiness', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 20),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
          sampleAt(
            startedAt,
            20,
            latitude: 1.300225,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );

      var snapshot = RunTrackingSnapshot.fromState(
        RunTrackingState(
          phase: RunTrackingPhase.active,
          clientRunSessionId: 'below-threshold-readiness',
          startedAt: startedAt,
          completedAt: null,
          elapsedSeconds: session.activeDurationSeconds,
          distanceMeters: session.distanceMeters,
          averagePaceSecondsPerKm: session.averagePaceSecondsPerKm,
          currentPaceSecondsPerKm: session.currentPaceSecondsPerKm,
          routePrivacy: 'private',
          source: session.source,
          locationStatus: RunTrackingLocationStatus.gpsActive,
          diagnostics: session.diagnostics,
        ),
      );

      expect(session.distanceMeters, greaterThan(0));
      expect(session.distanceMeters, lessThan(50));
      expect(
        snapshot.startupReadiness,
        RunTrackingStartupReadiness.movementBelowThreshold,
      );
      expect(snapshot.averagePaceLabel, '--:--/km');

      session.advanceBy(
        const Duration(seconds: 20),
        samples: [
          sampleAt(
            startedAt,
            40,
            latitude: 1.300450,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );

      snapshot = RunTrackingSnapshot.fromState(
        RunTrackingState(
          phase: RunTrackingPhase.active,
          clientRunSessionId: 'ready-threshold-readiness',
          startedAt: startedAt,
          completedAt: null,
          elapsedSeconds: session.activeDurationSeconds,
          distanceMeters: session.distanceMeters,
          averagePaceSecondsPerKm: session.averagePaceSecondsPerKm,
          currentPaceSecondsPerKm: session.currentPaceSecondsPerKm,
          routePrivacy: 'private',
          source: session.source,
          locationStatus: RunTrackingLocationStatus.gpsActive,
          diagnostics: session.diagnostics,
        ),
      );

      expect(session.distanceMeters, greaterThanOrEqualTo(50));
      expect(snapshot.startupReadiness, RunTrackingStartupReadiness.ready);
      expect(snapshot.averagePaceLabel, isNot('--:--/km'));
    });

    test('records accepted sample diagnostics without raw route data', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
          sampleAt(
            startedAt,
            60,
            latitude: 1.300899,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );

      final diagnostics = session.diagnostics;
      expect(diagnostics.acceptedSampleCount, 2);
      expect(diagnostics.rejectedSampleCount, 0);
      expect(
        diagnostics.lastSampleReceivedAt,
        startedAt.add(const Duration(seconds: 60)),
      );
      expect(
        diagnostics.lastAcceptedSampleAt,
        startedAt.add(const Duration(seconds: 60)),
      );
      expect(diagnostics.lastRejectedSampleAt, isNull);
      expect(
        diagnostics.latestRejectionReason,
        RunLocationRejectionReason.none,
      );
      expect(diagnostics.latestHorizontalAccuracyMeters, 5);
      expect(diagnostics.latestAccuracyBucket, RunLocationAccuracyBucket.good);
      expect(diagnostics.hasReceivedSample, isTrue);
      expect(diagnostics.hasAcceptedSample, isTrue);
    });

    test('suspicious speed spike updates marker without metrics or route', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );
      final movingTimeBeforeSpike = session.activeDurationSeconds;
      final routePointCountBeforeSpike = session.mapViewState.routePointCount;

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300045,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 5,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.activeDurationSeconds, movingTimeBeforeSpike);
      expect(session.distanceMeters, 0);
      expect(session.averagePaceSecondsPerKm, 0);
      expect(session.mapViewState.routePointCount, routePointCountBeforeSpike);
      expect(session.mapViewState.currentPosition?.latitude, 1.300045);
      expect(session.acceptedSampleCount, 2);
      expect(session.rejectedSampleCount, 0);
    });

    test('sustained abnormal speed enters abnormal pause by sample count', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );
      final routePointCountBeforeAbnormal =
          session.mapViewState.routePointCount;

      for (final seconds in [1, 2, 3]) {
        session.advanceBy(
          const Duration(seconds: 1),
          samples: [
            sampleAt(
              startedAt,
              seconds,
              latitude: 1.300000 + (0.000063 * seconds),
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 7,
            ),
          ],
        );
      }

      expect(session.movementStatus, RunMovementStatus.abnormalPaused);
      expect(session.distanceMeters, 0);
      expect(session.averagePaceSecondsPerKm, 0);
      expect(
        session.mapViewState.routePointCount,
        routePointCountBeforeAbnormal,
      );
      expect(
        session.mapViewState.currentPosition?.latitude,
        closeTo(1.300189, 0.000001),
      );
      expect(session.acceptedSampleCount, 4);
      expect(session.rejectedSampleCount, 0);
    });

    test('hard reject over twelve meters per second stays impossible jump', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );
      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300010,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 13,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.currentPosition?.latitude, 1.300000);
      expect(session.acceptedSampleCount, 1);
      expect(session.rejectedSampleCount, 1);
      expect(
        session.diagnostics.latestRejectionReason,
        RunLocationRejectionReason.impossibleJump,
      );
    });

    test('abnormal resume starts a safe segment without a bridge line', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );
      for (final seconds in [1, 2, 3]) {
        session.advanceBy(
          const Duration(seconds: 1),
          samples: [
            sampleAt(
              startedAt,
              seconds,
              latitude: 1.300000 + (0.000063 * seconds),
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 7,
            ),
          ],
        );
      }
      expect(session.movementStatus, RunMovementStatus.abnormalPaused);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            4,
            latitude: 1.300030,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 2,
          ),
        ],
      );
      expect(session.movementStatus, RunMovementStatus.abnormalPaused);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.previewPosition, isNull);
      expect(session.mapViewState.displayPosition?.latitude, 1.300030);
      expect(
        session.mapViewState.acceptedRouteSegments.map(
          (segment) => segment.length,
        ),
        [1],
      );
      expect(session.mapViewState.routeSegments, hasLength(1));

      session.advanceBy(
        const Duration(seconds: 3),
        samples: [
          sampleAt(
            startedAt,
            7,
            latitude: 1.300100,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 2,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.mapViewState.previewPosition, isNull);
      expect(session.mapViewState.displayPosition?.latitude, 1.300100);
      expect(
        session.mapViewState.acceptedRouteSegments.map(
          (segment) => segment.length,
        ),
        [1, 2],
      );
      expect(session.mapViewState.routeSegments, hasLength(2));
      expect(
        session.mapViewState.routeSegments.map((segment) => segment.length),
        [1, 2],
      );
      expect(session.mapViewState.routeSegments.first.last.latitude, 1.300000);
      expect(session.mapViewState.routeSegments.last.first.latitude, 1.300030);
      expect(session.distanceMeters, closeTo(8, 2));
    });

    test('records explicit rejection reasons and timestamps', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      LocalRunTrackingSession sessionWith(List<RunLocationSample> samples) {
        final session = LocalRunTrackingSession(startedAt: startedAt);
        session.advanceBy(const Duration(seconds: 120), samples: samples);
        return session;
      }

      expect(
        sessionWith([
          sampleAt(startedAt, 0, latitude: 1.3, longitude: 103.8),
          sampleAt(startedAt, 10, latitude: 91, longitude: 103.8),
        ]).diagnostics.latestRejectionReason,
        RunLocationRejectionReason.invalidCoordinate,
      );
      expect(
        sessionWith([
          sampleAt(startedAt, 0, latitude: 1.3, longitude: 103.8),
          sampleAt(
            startedAt,
            10,
            latitude: 1.300100,
            longitude: 103.8,
            horizontalAccuracyMeters: 250,
          ),
        ]).diagnostics.latestRejectionReason,
        RunLocationRejectionReason.poorAccuracy,
      );
      expect(
        sessionWith([
          sampleAt(startedAt, 0, latitude: 1.3, longitude: 103.8),
          sampleAt(startedAt, 10, latitude: 1.300100, longitude: 103.8),
          sampleAt(startedAt, 10, latitude: 1.300200, longitude: 103.8),
        ]).diagnostics.latestRejectionReason,
        RunLocationRejectionReason.duplicateOrOutOfOrderTimestamp,
      );
      expect(
        sessionWith([
          sampleAt(startedAt, 0, latitude: 1.3, longitude: 103.8),
          sampleAt(startedAt, 10, latitude: 2.3, longitude: 103.8),
        ]).diagnostics.latestRejectionReason,
        RunLocationRejectionReason.impossibleJump,
      );

      final staleSession = sessionWith([
        RunLocationSample(
          recordedAt: startedAt.subtract(const Duration(seconds: 1)),
          latitude: 1.3,
          longitude: 103.8,
        ),
      ]);
      expect(
        staleSession.diagnostics.latestRejectionReason,
        RunLocationRejectionReason.staleTimestamp,
      );
      expect(
        staleSession.diagnostics.lastRejectedSampleAt,
        startedAt.subtract(const Duration(seconds: 1)),
      );
    });

    test('rejects invalid coordinates and keeps distance finite', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 120),
        samples: [
          sampleAt(startedAt, 0, latitude: 1.300000, longitude: 103.800000),
          sampleAt(startedAt, 10, latitude: 91, longitude: 103.800000),
          sampleAt(startedAt, 20, latitude: -91, longitude: 103.800000),
          sampleAt(startedAt, 30, latitude: 1.300000, longitude: 181),
          sampleAt(startedAt, 40, latitude: 1.300000, longitude: -181),
          sampleAt(startedAt, 50, latitude: double.nan, longitude: 103.800000),
          sampleAt(
            startedAt,
            60,
            latitude: double.infinity,
            longitude: 103.800000,
          ),
          sampleAt(
            startedAt,
            70,
            latitude: 1.300000,
            longitude: double.negativeInfinity,
          ),
          sampleAt(startedAt, 120, latitude: 1.300899, longitude: 103.800000),
        ],
      );

      expect(() => session.distanceMeters, returnsNormally);
      expect(session.distanceMeters.isFinite, isTrue);
      expect(session.distanceMeters, closeTo(100, 2));
      expect(session.acceptedSampleCount, 2);
      expect(session.rejectedSampleCount, 7);
    });

    test('rejects bad horizontal accuracy without inflating distance', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 120),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
          sampleAt(
            startedAt,
            20,
            latitude: 1.300100,
            longitude: 103.800000,
            horizontalAccuracyMeters: -1,
          ),
          sampleAt(
            startedAt,
            40,
            latitude: 1.300200,
            longitude: 103.800000,
            horizontalAccuracyMeters: double.nan,
          ),
          sampleAt(
            startedAt,
            60,
            latitude: 1.300300,
            longitude: 103.800000,
            horizontalAccuracyMeters: double.infinity,
          ),
          sampleAt(
            startedAt,
            80,
            latitude: 1.300400,
            longitude: 103.800000,
            horizontalAccuracyMeters: 250,
          ),
          sampleAt(
            startedAt,
            120,
            latitude: 1.300899,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );

      expect(session.distanceMeters, closeTo(100, 2));
      expect(session.acceptedSampleCount, 2);
      expect(session.rejectedSampleCount, 4);
    });

    test('rejects non-finite segment distance without inflating distance', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(
        startedAt: startedAt,
        distanceCalculator: const _NonFiniteDistanceCalculator(),
      );

      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          sampleAt(startedAt, 0, latitude: 1.300000, longitude: 103.800000),
          sampleAt(startedAt, 60, latitude: 1.300899, longitude: 103.800000),
        ],
      );

      expect(session.distanceMeters, 0);
      expect(session.acceptedSampleCount, 1);
      expect(session.rejectedSampleCount, 1);
      expect(
        session.diagnostics.latestRejectionReason,
        RunLocationRejectionReason.nonFiniteDistance,
      );
      expect(
        session.diagnostics.lastRejectedSampleAt,
        startedAt.add(const Duration(seconds: 60)),
      );
    });

    test('ignores duplicate-time samples', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 120),
        samples: [
          sampleAt(startedAt, 0, latitude: 1.300000, longitude: 103.800000),
          sampleAt(startedAt, 60, latitude: 1.300450, longitude: 103.800000),
          sampleAt(startedAt, 60, latitude: 1.301800, longitude: 103.800000),
          sampleAt(startedAt, 120, latitude: 1.300899, longitude: 103.800000),
        ],
      );

      expect(session.distanceMeters, closeTo(100, 2));
      expect(session.acceptedSampleCount, 3);
      expect(session.rejectedSampleCount, 1);
    });

    test('ignores out-of-order samples', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 120),
        samples: [
          sampleAt(startedAt, 0, latitude: 1.300000, longitude: 103.800000),
          sampleAt(startedAt, 120, latitude: 1.300899, longitude: 103.800000),
          sampleAt(startedAt, 60, latitude: 1.301800, longitude: 103.800000),
        ],
      );

      expect(session.distanceMeters, closeTo(100, 2));
      expect(session.acceptedSampleCount, 2);
      expect(session.rejectedSampleCount, 1);
    });

    test('does not bridge movement while paused after resume', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          sampleAt(startedAt, 0, latitude: 1.300000, longitude: 103.800000),
          sampleAt(startedAt, 60, latitude: 1.300899, longitude: 103.800000),
        ],
      );
      session.pause();
      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          sampleAt(startedAt, 90, latitude: 1.350000, longitude: 103.800000),
          sampleAt(startedAt, 120, latitude: 1.400000, longitude: 103.800000),
        ],
      );
      session.resume(
        resumedAt: startedAt.add(const Duration(seconds: 120)),
        activeOffset: const Duration(seconds: 60),
      );
      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          sampleAt(startedAt, 120, latitude: 1.400000, longitude: 103.800000),
          sampleAt(startedAt, 180, latitude: 1.400899, longitude: 103.800000),
        ],
      );

      expect(session.activeDurationSeconds, 120);
      expect(session.distanceMeters, closeTo(200, 3));
      expect(session.acceptedSampleCount, 4);
      expect(session.rejectedSampleCount, 0);
      expect(session.mapViewState.acceptedRouteSegments, hasLength(2));
      expect(
        session.mapViewState.acceptedRouteSegments.map(
          (segment) => segment.length,
        ),
        [2, 2],
      );
      expect(
        session.mapViewState.acceptedRouteSegments.first.last.latitude,
        1.300899,
      );
      expect(
        session.mapViewState.acceptedRouteSegments.last.first.latitude,
        1.400000,
      );
      expect(
        session
            .paceGraphSamples()
            .map((sample) => sample.elapsedSeconds)
            .every(
              (elapsedSeconds) =>
                  elapsedSeconds <= session.activeDurationSeconds,
            ),
        isTrue,
      );
    });

    test('ignores impossible jumps without corrupting later valid samples', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 120),
        samples: [
          sampleAt(startedAt, 0, latitude: 1.300000, longitude: 103.800000),
          sampleAt(startedAt, 60, latitude: 2.300000, longitude: 103.800000),
          sampleAt(startedAt, 120, latitude: 1.300899, longitude: 103.800000),
        ],
      );

      expect(session.distanceMeters, closeTo(100, 2));
      expect(session.acceptedSampleCount, 2);
      expect(session.rejectedSampleCount, 1);
    });

    test('updates local distance and pace from replay samples', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 120),
        samples: [
          RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300000,
            longitude: 103.800000,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 120)),
            latitude: 1.302698,
            longitude: 103.800000,
          ),
        ],
      );

      expect(session.activeDurationSeconds, 120);
      expect(session.distanceMeters, closeTo(300, 2));
      expect(session.averagePaceSecondsPerKm, closeTo(400, 3));
    });

    test('current pace follows latest accepted movement segment', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 120),
        samples: [
          RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300000,
            longitude: 103.800000,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 60)),
            latitude: 1.301349,
            longitude: 103.800000,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 120)),
            latitude: 1.301799,
            longitude: 103.800000,
          ),
        ],
      );

      expect(session.distanceMeters, closeTo(200, 2));
      expect(session.averagePaceSecondsPerKm, closeTo(600, 4));
      expect(session.currentPaceSecondsPerKm, closeTo(1200, 8));
    });

    test('current pace ignores rejected stationary and paused samples', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300000,
            longitude: 103.800000,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 60)),
            latitude: 1.300899,
            longitude: 103.800000,
          ),
        ],
      );

      final reliableCurrentPace = session.currentPaceSecondsPerKm;
      expect(reliableCurrentPace, closeTo(600, 4));

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 61)),
            latitude: 1.500000,
            longitude: 103.800000,
          ),
        ],
      );
      expect(session.currentPaceSecondsPerKm, reliableCurrentPace);

      session.advanceBy(
        const Duration(seconds: 10),
        samples: [
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 70)),
            latitude: 1.300899,
            longitude: 103.800000,
          ),
        ],
      );
      expect(session.currentPaceSecondsPerKm, reliableCurrentPace);

      session.pause();
      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 130)),
            latitude: 1.301798,
            longitude: 103.800000,
          ),
        ],
      );

      expect(session.currentPaceSecondsPerKm, reliableCurrentPace);
    });

    test('auto pause freezes moving time and suppresses stationary drift', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
          sampleAt(
            startedAt,
            60,
            latitude: 1.300899,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );
      final movingTimeBeforeStop = session.activeDurationSeconds;
      final distanceBeforeStop = session.distanceMeters;
      final paceBeforeStop = session.averagePaceSecondsPerKm;
      final routePointCountBeforeStop = session.mapViewState.routePointCount;

      session.advanceBy(
        const Duration(seconds: 20),
        samples: [
          sampleAt(
            startedAt,
            70,
            latitude: 1.300908,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
          sampleAt(
            startedAt,
            80,
            latitude: 1.300917,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.activeDurationSeconds, movingTimeBeforeStop);
      expect(session.distanceMeters, distanceBeforeStop);
      expect(session.averagePaceSecondsPerKm, paceBeforeStop);
      expect(session.mapViewState.routePointCount, routePointCountBeforeStop);
      expect(session.mapViewState.currentPosition?.latitude, 1.300917);

      session.advanceBy(
        const Duration(seconds: 10),
        samples: [
          sampleAt(
            startedAt,
            90,
            latitude: 1.301000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 1.2,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.activeDurationSeconds, movingTimeBeforeStop);
      expect(session.distanceMeters, distanceBeforeStop);
      expect(session.mapViewState.routeSegments, hasLength(1));

      session.advanceBy(
        const Duration(seconds: 10),
        samples: [
          sampleAt(
            startedAt,
            100,
            latitude: 1.301090,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 1.2,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.activeDurationSeconds, movingTimeBeforeStop);
      expect(session.distanceMeters, greaterThan(distanceBeforeStop));
      expect(session.mapViewState.routeSegments, hasLength(2));
      expect(session.mapViewState.routeSegments.last, hasLength(2));
      expect(session.activeDurationSeconds, movingTimeBeforeStop);
    });

    test('no-op movement classifier preserves GPS-only moving behavior', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(
        startedAt: startedAt,
        movementClassifier: const RunMovementClassifier(),
      );

      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
          sampleAt(
            startedAt,
            60,
            latitude: 1.300899,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.activeDurationSeconds, 60);
      expect(session.distanceMeters, closeTo(100, 2));
      expect(session.mapViewState.routePointCount, 2);
    });

    test(
      'empty sample dwell after first GPS anchor auto pauses without movement artifacts',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final session = LocalRunTrackingSession(startedAt: startedAt);

        session.advanceBy(
          const Duration(seconds: 1),
          samples: [
            sampleAt(
              startedAt,
              1,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ],
        );
        final routePointCountBeforeDwell = session.mapViewState.routePointCount;
        final currentPositionBeforeDwell = session.mapViewState.currentPosition;

        session.advanceBy(const Duration(seconds: 5));

        expect(session.movementStatus, RunMovementStatus.autoPaused);
        expect(session.activeDurationSeconds, 1);
        expect(session.distanceMeters, 0);
        expect(
          session.mapViewState.routePointCount,
          routePointCountBeforeDwell,
        );
        expect(
          session.mapViewState.currentPosition,
          currentPositionBeforeDwell,
        );
        expect(session.acceptedSampleCount, 1);
        expect(session.rejectedSampleCount, 0);
      },
    );

    test(
      'empty sample dwell freezes current moving time instead of resetting',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final session = LocalRunTrackingSession(startedAt: startedAt);

        session.advanceBy(
          const Duration(seconds: 1),
          samples: [
            sampleAt(
              startedAt,
              1,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ],
        );
        for (var tick = 0; tick < 5; tick += 1) {
          session.advanceBy(const Duration(seconds: 1));
        }

        expect(session.movementStatus, RunMovementStatus.autoPaused);
        expect(session.activeDurationSeconds, 5);
        expect(session.distanceMeters, 0);
        expect(session.mapViewState.routePointCount, 1);

        session.advanceBy(const Duration(seconds: 5));

        expect(session.activeDurationSeconds, 5);
        expect(session.distanceMeters, 0);
        expect(session.mapViewState.routePointCount, 1);
      },
    );

    test(
      'phone shaking in place cannot block no-sample auto pause forever',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final session = LocalRunTrackingSession(startedAt: startedAt);

        session.advanceBy(
          const Duration(seconds: 1),
          samples: [
            sampleAt(
              startedAt,
              1,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ],
        );
        final routePointCountBeforeShake = session.mapViewState.routePointCount;
        final currentPositionBeforeShake = session.mapViewState.currentPosition;

        session.advanceBy(
          const Duration(seconds: 7),
          motionEvidence: [motionAt(startedAt, 8, RunMotionSignal.moving)],
        );

        expect(session.movementStatus, RunMovementStatus.moving);
        expect(session.distanceMeters, 0);
        expect(
          session.mapViewState.routePointCount,
          routePointCountBeforeShake,
        );
        expect(
          session.mapViewState.currentPosition,
          currentPositionBeforeShake,
        );

        session.advanceBy(
          const Duration(seconds: 1),
          motionEvidence: [motionAt(startedAt, 9, RunMotionSignal.moving)],
        );

        expect(session.movementStatus, RunMovementStatus.autoPaused);
        expect(session.distanceMeters, 0);
        expect(
          session.mapViewState.routePointCount,
          routePointCountBeforeShake,
        );
        expect(
          session.mapViewState.currentPosition,
          currentPositionBeforeShake,
        );
      },
    );

    test(
      'steady-phone GPS drift with stationary motion does not draw route',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final session = LocalRunTrackingSession(startedAt: startedAt);

        session.advanceBy(
          const Duration(seconds: 1),
          samples: [
            sampleAt(
              startedAt,
              1,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ],
        );

        session.advanceBy(
          const Duration(seconds: 8),
          samples: [
            sampleAt(
              startedAt,
              3,
              latitude: 1.300027,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.7,
            ),
            sampleAt(
              startedAt,
              6,
              latitude: 1.300027,
              longitude: 103.800027,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.7,
            ),
            sampleAt(
              startedAt,
              9,
              latitude: 1.300000,
              longitude: 103.800027,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.7,
            ),
          ],
          motionEvidence: [motionAt(startedAt, 9, RunMotionSignal.stationary)],
        );

        expect(session.movementStatus, RunMovementStatus.autoPaused);
        expect(session.distanceMeters, 0);
        expect(session.averagePaceSecondsPerKm, 0);
        expect(session.mapViewState.routePointCount, 1);
        expect(session.mapViewState.currentPosition?.longitude, 103.800027);
      },
    );

    test(
      'standing-still outdoor GPS jumps do not add distance or zigzag route',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final session = LocalRunTrackingSession(startedAt: startedAt);

        session.advanceBy(
          const Duration(seconds: 1),
          samples: [
            sampleAt(
              startedAt,
              1,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ],
        );

        session.advanceBy(
          const Duration(seconds: 12),
          samples: [
            sampleAt(
              startedAt,
              4,
              latitude: 1.300090,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.2,
            ),
            sampleAt(
              startedAt,
              7,
              latitude: 1.299955,
              longitude: 103.800072,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
            sampleAt(
              startedAt,
              10,
              latitude: 1.300117,
              longitude: 103.799955,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.2,
            ),
            sampleAt(
              startedAt,
              13,
              latitude: 1.299910,
              longitude: 103.800036,
              horizontalAccuracyMeters: 5,
            ),
          ],
          motionEvidence: [motionAt(startedAt, 13, RunMotionSignal.stationary)],
        );

        expect(session.movementStatus, RunMovementStatus.autoPaused);
        expect(session.distanceMeters, 0);
        expect(session.averagePaceSecondsPerKm, 0);
        expect(session.mapViewState.routeSegments, hasLength(1));
        expect(session.mapViewState.routePointCount, 1);
        expect(session.mapViewState.currentPosition?.latitude, 1.299910);
        expect(session.acceptedSampleCount, 5);
      },
    );

    test('table-still GPS jitter with stationary motion still auto pauses', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
      );
      final routePointCountBeforeJitter = session.mapViewState.routePointCount;

      session.advanceBy(
        const Duration(seconds: 8),
        samples: [
          sampleAt(
            startedAt,
            4,
            latitude: 1.300004,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
          sampleAt(
            startedAt,
            7,
            latitude: 1.300000,
            longitude: 103.800004,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
          sampleAt(
            startedAt,
            9,
            latitude: 1.300004,
            longitude: 103.800004,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
        motionEvidence: [motionAt(startedAt, 9, RunMotionSignal.stationary)],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.routePointCount, routePointCountBeforeJitter);
      expect(session.mapViewState.currentPosition?.latitude, 1.300004);
    });

    test('empty samples before first GPS anchor do not auto pause', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(const Duration(seconds: 20));

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.activeDurationSeconds, 20);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.routePointCount, 0);
      expect(session.acceptedSampleCount, 0);
    });

    test('sparse stationary GPS sample counts dwell from first anchor', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
      );

      session.advanceBy(
        const Duration(seconds: 6),
        samples: [
          sampleAt(
            startedAt,
            7,
            latitude: 1.300009,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.activeDurationSeconds, 1);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.routePointCount, 1);
      expect(session.mapViewState.currentPosition?.latitude, 1.300009);
    });

    test(
      'stationary outdoor GPS jitter does not add distance or zigzag route',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final session = LocalRunTrackingSession(startedAt: startedAt);

        session.advanceBy(
          const Duration(seconds: 1),
          samples: [
            sampleAt(
              startedAt,
              1,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ],
        );
        final routePointCountBeforeJitter =
            session.mapViewState.routePointCount;

        session.advanceBy(
          const Duration(seconds: 64),
          samples: [
            sampleAt(
              startedAt,
              16,
              latitude: 1.300090,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
            sampleAt(
              startedAt,
              31,
              latitude: 1.299920,
              longitude: 103.800050,
              horizontalAccuracyMeters: 5,
            ),
            sampleAt(
              startedAt,
              47,
              latitude: 1.300030,
              longitude: 103.799860,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.2,
            ),
            sampleAt(
              startedAt,
              65,
              latitude: 1.299970,
              longitude: 103.800120,
              horizontalAccuracyMeters: 5,
            ),
          ],
        );

        expect(session.movementStatus, RunMovementStatus.autoPaused);
        expect(session.activeDurationSeconds, 1);
        expect(session.distanceMeters, 0);
        expect(session.averagePaceSecondsPerKm, 0);
        expect(session.mapViewState.routeSegments, hasLength(1));
        expect(
          session.mapViewState.routePointCount,
          routePointCountBeforeJitter,
        );
        expect(session.mapViewState.currentPosition?.latitude, 1.299970);
        expect(session.mapViewState.currentPosition?.longitude, 103.800120);
        expect(
          session.diagnostics.lastAcceptedSampleAt,
          startedAt.add(const Duration(seconds: 65)),
        );
        expect(session.diagnostics.latestHorizontalAccuracyMeters, 5);
        expect(
          session.diagnostics.latestAccuracyBucket,
          RunLocationAccuracyBucket.good,
        );
        expect(session.acceptedSampleCount, 5);
        expect(session.rejectedSampleCount, 0);
      },
    );

    test('moving to stopped auto pauses after seven stationary seconds', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          sampleAt(
            startedAt,
            0,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
          sampleAt(
            startedAt,
            60,
            latitude: 1.300899,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );
      final movingTimeBeforeStop = session.activeDurationSeconds;
      final distanceBeforeStop = session.distanceMeters;
      final routePointCountBeforeStop = session.mapViewState.routePointCount;

      session.advanceBy(
        const Duration(seconds: 7),
        samples: [
          sampleAt(
            startedAt,
            67,
            latitude: 1.300908,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.activeDurationSeconds, movingTimeBeforeStop);
      expect(session.distanceMeters, distanceBeforeStop);
      expect(session.mapViewState.routePointCount, routePointCountBeforeStop);
      expect(session.mapViewState.currentPosition?.latitude, 1.300908);
    });

    test('manual pause blocks no-sample dwell and auto resume', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );
      session.pause();
      session.advanceBy(const Duration(seconds: 20));
      session.advanceBy(
        const Duration(seconds: 10),
        samples: [
          sampleAt(
            startedAt,
            30,
            latitude: 1.300899,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.activeDurationSeconds, 1);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.routePointCount, 1);
    });

    test('moving motion alone does not auto resume from auto paused', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );
      session.advanceBy(const Duration(seconds: 5));
      expect(session.movementStatus, RunMovementStatus.autoPaused);
      final routePointCountBeforeMotion = session.mapViewState.routePointCount;

      session.advanceBy(
        const Duration(seconds: 4),
        samples: [
          sampleAt(
            startedAt,
            10,
            latitude: 1.300009,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
        motionEvidence: [motionAt(startedAt, 10, RunMotionSignal.moving)],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.routePointCount, routePointCountBeforeMotion);
      expect(session.mapViewState.currentPosition?.latitude, 1.300009);
    });

    test('single GPS jump with stationary motion stays auto paused', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
      );
      session.advanceBy(const Duration(seconds: 5));
      expect(session.movementStatus, RunMovementStatus.autoPaused);
      final routePointCountBeforeJump = session.mapViewState.routePointCount;

      session.advanceBy(
        const Duration(seconds: 24),
        samples: [
          sampleAt(
            startedAt,
            30,
            latitude: 1.300360,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 4,
          ),
        ],
        motionEvidence: [motionAt(startedAt, 30, RunMotionSignal.stationary)],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.activeDurationSeconds, 1);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.routePointCount, routePointCountBeforeJump);
      expect(session.mapViewState.currentPosition?.latitude, 1.300360);
    });

    test('single GPS speed spike with stationary motion stays auto paused', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
      );
      session.advanceBy(const Duration(seconds: 5));
      expect(session.movementStatus, RunMovementStatus.autoPaused);
      final routePointCountBeforeSpike = session.mapViewState.routePointCount;

      session.advanceBy(
        const Duration(seconds: 24),
        samples: [
          sampleAt(
            startedAt,
            30,
            latitude: 1.300004,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 1.2,
          ),
        ],
        motionEvidence: [motionAt(startedAt, 30, RunMotionSignal.stationary)],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.activeDurationSeconds, 1);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.routePointCount, routePointCountBeforeSpike);
      expect(session.mapViewState.currentPosition?.latitude, 1.300004);
    });

    test('sustained GPS movement resumes without counting candidate jump', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ],
      );
      session.advanceBy(const Duration(seconds: 5));
      expect(session.movementStatus, RunMovementStatus.autoPaused);
      final routePointCountBeforeCandidate =
          session.mapViewState.routePointCount;

      session.advanceBy(
        const Duration(seconds: 24),
        samples: [
          sampleAt(
            startedAt,
            30,
            latitude: 1.300360,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 4,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.distanceMeters, 0);
      expect(
        session.mapViewState.routePointCount,
        routePointCountBeforeCandidate,
      );
      expect(session.mapViewState.currentPosition?.latitude, 1.300360);

      session.advanceBy(
        const Duration(seconds: 10),
        samples: [
          sampleAt(
            startedAt,
            40,
            latitude: 1.300450,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 1,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.distanceMeters, closeTo(10, 2));
      expect(session.mapViewState.routeSegments, hasLength(2));
      expect(session.mapViewState.routeSegments.last, hasLength(2));
    });

    test('auto pauses when stationary from the start without route drift', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 1),
        samples: [
          sampleAt(
            startedAt,
            1,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.routePointCount, 1);

      session.advanceBy(
        const Duration(seconds: 20),
        samples: [
          sampleAt(
            startedAt,
            10,
            latitude: 1.300009,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
          sampleAt(
            startedAt,
            20,
            latitude: 1.300018,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0.1,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.activeDurationSeconds, 1);
      expect(session.distanceMeters, 0);
      expect(session.averagePaceSecondsPerKm, 0);
      expect(session.mapViewState.routeSegments, hasLength(1));
      expect(session.mapViewState.routePointCount, 1);
      expect(session.mapViewState.currentPosition?.latitude, 1.300018);

      session.advanceBy(
        const Duration(seconds: 10),
        samples: [
          sampleAt(
            startedAt,
            30,
            latitude: 1.300100,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 1.2,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.autoPaused);
      expect(session.activeDurationSeconds, 1);
      expect(session.distanceMeters, 0);
      expect(session.mapViewState.routeSegments, hasLength(1));

      session.advanceBy(
        const Duration(seconds: 10),
        samples: [
          sampleAt(
            startedAt,
            40,
            latitude: 1.300190,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 1.2,
          ),
        ],
      );

      expect(session.movementStatus, RunMovementStatus.moving);
      expect(session.activeDurationSeconds, 1);
      expect(session.distanceMeters, greaterThan(0));
      expect(session.mapViewState.routeSegments.last, hasLength(2));
    });

    test('excludes paused time from active duration and pace', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300000,
            longitude: 103.800000,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 60)),
            latitude: 1.301349,
            longitude: 103.800000,
          ),
        ],
      );
      session.pause();
      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 120)),
            latitude: 1.310000,
            longitude: 103.800000,
          ),
        ],
      );
      session.resume(
        resumedAt: startedAt.add(const Duration(seconds: 120)),
        activeOffset: const Duration(seconds: 60),
      );
      session.advanceBy(
        const Duration(seconds: 60),
        samples: [
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 120)),
            latitude: 1.302698,
            longitude: 103.800000,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 180)),
            latitude: 1.304047,
            longitude: 103.800000,
          ),
        ],
      );

      expect(session.activeDurationSeconds, 120);
      expect(session.distanceMeters, closeTo(300, 3));
      expect(session.averagePaceSecondsPerKm, closeTo(400, 4));
      expect(session.currentPaceSecondsPerKm, closeTo(400, 4));
    });

    test('ignores impossible GPS jumps', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final session = LocalRunTrackingSession(startedAt: startedAt);

      session.advanceBy(
        const Duration(seconds: 30),
        samples: [
          RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300000,
            longitude: 103.800000,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 10)),
            latitude: 2.300000,
            longitude: 103.800000,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 30)),
            latitude: 1.300899,
            longitude: 103.800000,
          ),
        ],
      );

      expect(session.activeDurationSeconds, 30);
      expect(session.distanceMeters, closeTo(100, 2));
      expect(session.acceptedSampleCount, 2);
      expect(session.rejectedSampleCount, 1);
    });
  });
}

class _NonFiniteDistanceCalculator extends RunDistanceCalculator {
  const _NonFiniteDistanceCalculator();

  @override
  double distanceMeters(RunLocationSample from, RunLocationSample to) {
    return double.nan;
  }
}
