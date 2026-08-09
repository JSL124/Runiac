import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_cadence_diagnostics.dart';
import 'package:runiac_app/features/run/domain/models/run_cadence_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_location_permission_status.dart';
import 'package:runiac_app/features/run/domain/models/run_motion_evidence.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_diagnostics.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_notification_copy.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_startup_readiness.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_state.dart';
import 'package:runiac_app/features/run/domain/repositories/run_cadence_provider.dart';
import 'package:runiac_app/features/run/domain/repositories/run_foreground_service.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_permission_service.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_provider.dart';
import 'package:runiac_app/features/run/domain/repositories/run_motion_provider.dart';
import 'package:runiac_app/features/run/domain/repositories/run_notification_permission_service.dart';
import 'package:runiac_app/features/run/data/real_foreground_run_location_provider.dart';
import 'package:runiac_app/features/run/presentation/controllers/run_tracking_controller.dart';

class _FakePermissionService implements RunLocationPermissionService {
  _FakePermissionService(this.status);

  RunLocationPermissionStatus status;

  @override
  Future<RunLocationPermissionStatus> checkStatus() async => status;

  @override
  Future<RunLocationPermissionStatus> requestPermission() async => status;
}

class _FakeNotificationPermissionService
    implements RunNotificationPermissionService {
  _FakeNotificationPermissionService(this.status);

  RunNotificationPermissionStatus status;
  int requestCount = 0;

  @override
  Future<RunNotificationPermissionStatus> requestPermission() async {
    requestCount += 1;
    return status;
  }
}

class _FakeRunForegroundService implements RunForegroundService {
  final calls = <String>[];
  final titles = <String>[];
  final bodies = <String>[];

  @override
  Future<void> start(RunTrackingNotificationCopy copy) async {
    calls.add('start');
    titles.add(copy.title);
    bodies.add(copy.body);
  }

  @override
  Future<void> update(RunTrackingNotificationCopy copy) async {
    calls.add('update');
    titles.add(copy.title);
    bodies.add(copy.body);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }
}

class _DelayedRunForegroundService extends _FakeRunForegroundService {
  final startCompleter = Completer<void>();

  @override
  Future<void> start(RunTrackingNotificationCopy copy) async {
    calls.add('start');
    titles.add(copy.title);
    bodies.add(copy.body);
    await startCompleter.future;
  }
}

class _LifecycleTrackingProvider extends ConstantSpeedRunLocationProvider {
  _LifecycleTrackingProvider() : super(metersPerSecond: 2.5);

  int startCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;

  @override
  Future<void> start({required DateTime startedAt}) async {
    startCount += 1;
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
  }

  @override
  Future<void> resume({
    required DateTime resumedAt,
    required Duration activeOffset,
  }) async {
    resumeCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

class _ThrowingStartLocationProvider extends _LifecycleTrackingProvider {
  @override
  Future<void> start({required DateTime startedAt}) async {
    startCount += 1;
    throw StateError('GPS provider failed to start');
  }
}

class _LifecycleReplayProvider implements RunLocationProvider {
  _LifecycleReplayProvider(List<RunLocationReplaySample> samples)
    : _delegate = ReplayRunLocationProvider(samples);

  final ReplayRunLocationProvider _delegate;
  final Set<DateTime> _consumedSampleTimes = <DateTime>{};

  int startCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;

  @override
  RunTrackingLocationAccuracyStatus get locationAccuracyStatus =>
      _delegate.locationAccuracyStatus;

  @override
  Future<void> start({required DateTime startedAt}) async {
    startCount += 1;
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
  }

  @override
  Future<void> resume({
    required DateTime resumedAt,
    required Duration activeOffset,
  }) async {
    resumeCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Iterable<RunLocationSample> samplesBetween({
    required Duration fromActiveOffset,
    required Duration toActiveOffset,
    required DateTime startedAt,
  }) {
    final samples = _delegate
        .samplesBetween(
          fromActiveOffset: fromActiveOffset,
          toActiveOffset: toActiveOffset,
          startedAt: startedAt,
        )
        .where((sample) => _consumedSampleTimes.add(sample.recordedAt));
    return samples.toList();
  }
}

class _LifecycleMotionProvider extends NoopRunMotionProvider {
  int startCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;
  int evidenceReadCount = 0;

  @override
  Future<void> start({required DateTime startedAt}) async {
    startCount += 1;
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
  }

  @override
  Future<void> resume({
    required DateTime resumedAt,
    required Duration trackingOffset,
  }) async {
    resumeCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Iterable<RunMotionEvidence> evidenceBetween({
    required Duration fromTrackingOffset,
    required Duration toTrackingOffset,
    required DateTime startedAt,
  }) {
    evidenceReadCount += 1;
    return const <RunMotionEvidence>[];
  }
}

class _ConstantMotionProvider extends NoopRunMotionProvider {
  const _ConstantMotionProvider(this.signal);

  final RunMotionSignal signal;

  @override
  Iterable<RunMotionEvidence> evidenceBetween({
    required Duration fromTrackingOffset,
    required Duration toTrackingOffset,
    required DateTime startedAt,
  }) {
    if (toTrackingOffset <= Duration.zero) {
      return const <RunMotionEvidence>[];
    }
    return [
      RunMotionEvidence(
        recordedAt: startedAt.add(toTrackingOffset),
        signal: signal,
        confidence: 1,
      ),
    ];
  }
}

void main() {
  group('RunTrackingController', () {
    test('starts idle with no trusted completion state', () {
      final controller = RunTrackingController();

      expect(controller.state.phase, RunTrackingPhase.idle);
      expect(controller.state.elapsedSeconds, 0);
      expect(controller.state.distanceMeters, 0);
      expect(controller.state.averagePaceSecondsPerKm, 0);
      expect(controller.state.isPaused, isFalse);
    });

    test('preview current position populates map without trusted metrics', () {
      final controller = RunTrackingController();
      final previewSample = RunLocationSample(
        recordedAt: DateTime.utc(2026, 6, 14, 7),
        latitude: 1.3009,
        longitude: 103.8,
        horizontalAccuracyMeters: 5,
      );

      controller.setPreviewCurrentPosition(previewSample);

      expect(controller.state.phase, RunTrackingPhase.idle);
      expect(controller.state.elapsedSeconds, 0);
      expect(controller.state.distanceMeters, 0);
      expect(controller.state.averagePaceSecondsPerKm, 0);
      expect(controller.mapViewState.previewPosition, previewSample);
      expect(controller.mapViewState.currentPosition, isNull);
      expect(controller.mapViewState.displayPosition, previewSample);
      expect(controller.mapViewState.acceptedRouteSegments, isEmpty);
      expect(controller.mapViewState.routeSegments, isEmpty);
      expect(() => controller.completionPayload(), throwsStateError);
    });

    test(
      'seeded preview current position populates map without trusted metrics',
      () {
        final previewSample = RunLocationSample(
          recordedAt: DateTime.utc(2026, 6, 16, 7),
          latitude: 1.3009,
          longitude: 103.8,
          horizontalAccuracyMeters: 5,
        );
        final controller = RunTrackingController(
          initialPreviewCurrentPosition: previewSample,
        );

        expect(controller.state.phase, RunTrackingPhase.idle);
        expect(controller.state.elapsedSeconds, 0);
        expect(controller.state.distanceMeters, 0);
        expect(controller.state.averagePaceSecondsPerKm, 0);
        expect(controller.mapViewState.previewPosition, previewSample);
        expect(controller.mapViewState.currentPosition, isNull);
        expect(controller.mapViewState.displayPosition, previewSample);
        expect(controller.mapViewState.acceptedRouteSegments, isEmpty);
        expect(controller.mapViewState.routeSegments, isEmpty);
        expect(() => controller.completionPayload(), throwsStateError);
      },
    );

    test(
      'preview current position does not seed active route metrics',
      () async {
        final provider = ReplayRunLocationProvider(const []);
        final controller = RunTrackingController(locationProvider: provider);
        final previewSample = RunLocationSample(
          recordedAt: DateTime.utc(2026, 6, 14, 7),
          latitude: 1.3009,
          longitude: 103.8,
          horizontalAccuracyMeters: 5,
        );

        controller.setPreviewCurrentPosition(previewSample);
        controller.start(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'preview-isolated-run',
        );
        controller.advanceBy(const Duration(seconds: 60));

        expect(controller.state.phase, RunTrackingPhase.active);
        expect(controller.state.elapsedSeconds, 60);
        expect(controller.state.distanceMeters, 0);
        expect(controller.state.averagePaceSecondsPerKm, 0);
        expect(controller.mapViewState.previewPosition, previewSample);
        expect(controller.mapViewState.currentPosition, isNull);
        expect(controller.mapViewState.displayPosition, previewSample);
        expect(controller.mapViewState.acceptedRouteSegments, isEmpty);
        expect(controller.mapViewState.routeSegments, isEmpty);
        expect(
          controller.completionPayload().toRawClientMap().keys,
          isNot(contains('routeSamples')),
        );
      },
    );

    test(
      'seeded preview current position does not seed active route metrics',
      () async {
        final provider = ReplayRunLocationProvider(const []);
        final previewSample = RunLocationSample(
          recordedAt: DateTime.utc(2026, 6, 16, 7),
          latitude: 1.3009,
          longitude: 103.8,
          horizontalAccuracyMeters: 5,
        );
        final controller = RunTrackingController(
          locationProvider: provider,
          initialPreviewCurrentPosition: previewSample,
        );

        controller.start(
          startedAt: DateTime.utc(2026, 6, 16, 7),
          clientRunSessionId: 'seeded-preview-isolated-run',
        );
        controller.advanceBy(const Duration(seconds: 60));

        expect(controller.state.phase, RunTrackingPhase.active);
        expect(controller.state.elapsedSeconds, 60);
        expect(controller.state.distanceMeters, 0);
        expect(controller.state.averagePaceSecondsPerKm, 0);
        expect(controller.mapViewState.previewPosition, previewSample);
        expect(controller.mapViewState.currentPosition, isNull);
        expect(controller.mapViewState.displayPosition, previewSample);
        expect(controller.mapViewState.acceptedRouteSegments, isEmpty);
        expect(controller.mapViewState.routeSegments, isEmpty);
        expect(
          controller.completionPayload().toRawClientMap().keys,
          isNot(contains('routeSamples')),
        );
      },
    );

    test('start creates an active local session', () {
      final controller = RunTrackingController();
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'local-session-1',
      );

      expect(controller.state.phase, RunTrackingPhase.active);
      expect(controller.state.clientRunSessionId, 'local-session-1');
      expect(controller.state.startedAt, startedAt);
      expect(controller.state.source, 'local_simulation');
      expect(controller.state.routePrivacy, 'private');
    });

    test('deterministic tick advances elapsed time, distance, and pace', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'local-session-2',
      );
      controller.advanceBy(const Duration(seconds: 120));

      expect(controller.state.elapsedSeconds, 120);
      expect(controller.state.distanceMeters, 300);
      expect(controller.state.averagePaceSecondsPerKm, 400);
      expect(controller.state.currentPaceSecondsPerKm, 400);
    });

    test('publishes current pace separately from average pace', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final provider = _LifecycleReplayProvider([
        RunLocationReplaySample(
          activeOffset: Duration.zero,
          sample: RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ),
        RunLocationReplaySample(
          activeOffset: const Duration(seconds: 60),
          sample: RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 60)),
            latitude: 1.301349,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ),
        RunLocationReplaySample(
          activeOffset: const Duration(seconds: 120),
          sample: RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 120)),
            latitude: 1.301799,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ),
      ]);
      final controller = RunTrackingController(locationProvider: provider);

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'variable-current-pace-run',
      );
      controller.advanceBy(const Duration(seconds: 60));
      controller.advanceBy(const Duration(seconds: 60));

      expect(controller.state.distanceMeters, closeTo(200, 2));
      expect(controller.state.averagePaceSecondsPerKm, closeTo(600, 4));
      expect(controller.state.currentPaceSecondsPerKm, closeTo(1200, 8));
      expect(
        controller.completionPayload().avgPaceSecondsPerKm,
        controller.state.averagePaceSecondsPerKm,
      );
    });

    test('jittered moving ticks accumulate without losing display seconds', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'jittered-moving-run',
      );

      controller.advanceBy(const Duration(milliseconds: 999));
      expect(controller.state.elapsedSeconds, 0);

      controller.advanceBy(const Duration(milliseconds: 1001));
      expect(controller.state.elapsedSeconds, 2);

      final payload = controller.completionPayload(
        completedAt: startedAt.add(const Duration(seconds: 2)),
      );
      expect(payload.durationSeconds, 2);
      expect(
        RunTrackingSnapshot.fromState(controller.state).elapsedTimeLabel,
        '00:02',
      );
      expect(
        RunTrackingNotificationCopy.fromState(
          controller.state,
        ).elapsedTimeLabel,
        '00:02',
      );
    });

    test('half-second moving ticks accumulate to display seconds', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'half-second-moving-run',
      );

      for (var tick = 0; tick < 4; tick += 1) {
        controller.advanceBy(const Duration(milliseconds: 500));
      }

      expect(controller.state.elapsedSeconds, 2);
    });

    test('GPS sample sparsity does not block moving time ticks', () {
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider(const []),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'sparse-gps-moving-time-run',
      );

      for (var tick = 0; tick < 4; tick += 1) {
        controller.advanceBy(const Duration(milliseconds: 500));
      }

      expect(controller.state.isAutoPaused, isFalse);
      expect(controller.state.elapsedSeconds, 2);
      expect(controller.state.distanceMeters, 0);
      expect(controller.mapViewState.routePointCount, 0);
    });

    test('manual pause suppresses jittered wall clock accumulation', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'manual-pause-jitter-run',
      );
      controller.syncTo(startedAt.add(const Duration(milliseconds: 999)));
      controller.syncTo(startedAt.add(const Duration(milliseconds: 2000)));
      controller.pause(pausedAt: startedAt.add(const Duration(seconds: 2)));

      controller.syncTo(startedAt.add(const Duration(minutes: 3)));

      expect(controller.state.isPaused, isTrue);
      expect(controller.state.elapsedSeconds, 2);
      expect(controller.completionPayload().durationSeconds, 2);
    });

    test('wall clock sync reconciles an inactive foreground gap', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'wall-clock-gap-run',
      );

      controller.syncTo(startedAt.add(const Duration(seconds: 120)));

      final payload = controller.completionPayload(
        completedAt: startedAt.add(const Duration(seconds: 120)),
      );
      expect(controller.state.elapsedSeconds, 120);
      expect(controller.state.distanceMeters, 300);
      expect(controller.state.averagePaceSecondsPerKm, 400);
      expect(payload.durationSeconds, 120);
      expect(payload.distanceMeters, 300);
      expect(payload.avgPaceSecondsPerKm, 400);
    });

    test('manual pause blocks wall clock sync during an inactive gap', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'manual-pause-gap-run',
      );
      controller.syncTo(startedAt.add(const Duration(seconds: 30)));
      controller.pause(pausedAt: startedAt.add(const Duration(seconds: 30)));

      controller.syncTo(startedAt.add(const Duration(minutes: 10)));

      final payload = controller.completionPayload(
        completedAt: startedAt.add(const Duration(minutes: 10)),
      );
      expect(controller.state.phase, RunTrackingPhase.paused);
      expect(controller.state.elapsedSeconds, 30);
      expect(controller.state.distanceMeters, 75);
      expect(controller.state.averagePaceSecondsPerKm, 400);
      expect(payload.durationSeconds, 30);
      expect(payload.activeDurationSeconds, 30);
      expect(payload.elapsedWallSeconds, 600);
      expect(payload.pausedDurationSeconds, 570);
      expect(payload.distanceMeters, 75);
      expect(payload.avgPaceSecondsPerKm, 400);
    });

    test(
      'no-op motion provider lifecycle is safe and preserves GPS behavior',
      () {
        final motionProvider = _LifecycleMotionProvider();
        final controller = RunTrackingController(
          metersPerSecond: 2.5,
          motionProvider: motionProvider,
        );

        controller.start(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'motion-noop-run',
        );
        controller.advanceBy(const Duration(seconds: 60));

        expect(controller.state.elapsedSeconds, 60);
        expect(controller.state.distanceMeters, 150);
        expect(controller.state.averagePaceSecondsPerKm, 399);
        expect(motionProvider.startCount, 1);
        expect(motionProvider.evidenceReadCount, 1);

        controller.pause();
        controller.resume();
        controller.finish(completedAt: DateTime.utc(2026, 6, 14, 7, 2));

        expect(motionProvider.pauseCount, 1);
        expect(motionProvider.resumeCount, 1);
        expect(motionProvider.stopCount, 1);
      },
    );

    test('live pace is hidden below 50 meters while time keeps running', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'small-distance-run',
      );
      controller.advanceBy(const Duration(seconds: 10));

      final snapshot = RunTrackingSnapshot.fromState(controller.state);
      expect(controller.state.elapsedSeconds, 10);
      expect(controller.state.distanceMeters, 25);
      expect(controller.state.averagePaceSecondsPerKm, 400);
      expect(snapshot.elapsedTimeLabel, '00:10');
      expect(snapshot.distanceLabel, '0.03 km');
      expect(snapshot.averagePaceLabel, '--:--/km');
    });

    test('live pace is formatted normally at 50 meters', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'ready-distance-run',
      );
      controller.advanceBy(const Duration(seconds: 20));

      final snapshot = RunTrackingSnapshot.fromState(controller.state);
      expect(controller.state.distanceMeters, 50);
      expect(controller.state.averagePaceSecondsPerKm, 399);
      expect(snapshot.averagePaceLabel, '06:39/km');
    });

    test('completion payload remains numeric below live pace threshold', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'tiny-completion-run',
      );
      controller.advanceBy(const Duration(seconds: 10));

      final payload = controller.completionPayload(
        completedAt: DateTime.utc(2026, 6, 14, 7, 1),
      );

      expect(payload.distanceMeters, 25);
      expect(payload.durationSeconds, 10);
      expect(payload.avgPaceSecondsPerKm, 400);
      expect(payload.toRawClientMap().keys, isNot(contains('routeSamples')));
      expect(payload.toRawClientMap().keys, isNot(contains('xp')));
    });

    test('pause stops progression and resume continues from a new anchor', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'local-session-3',
      );
      controller.advanceBy(const Duration(seconds: 60));
      controller.pause();
      controller.advanceBy(const Duration(seconds: 60));

      expect(controller.state.phase, RunTrackingPhase.paused);
      expect(controller.state.elapsedSeconds, 60);
      expect(controller.state.distanceMeters, 150);

      controller.resume();
      controller.advanceBy(const Duration(seconds: 60));

      expect(controller.state.phase, RunTrackingPhase.active);
      expect(controller.state.elapsedSeconds, 120);
      expect(controller.state.distanceMeters, 150);

      controller.advanceBy(const Duration(seconds: 60));

      expect(controller.state.elapsedSeconds, 180);
      expect(controller.state.distanceMeters, 300);
    });

    test(
      'auto pause stays active-local and manual pause remains higher priority',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final provider = _LifecycleReplayProvider([
          RunLocationReplaySample(
            activeOffset: Duration.zero,
            sample: RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 60),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 60)),
              latitude: 1.300899,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 70),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 70)),
              latitude: 1.300908,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 80),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 80)),
              latitude: 1.300917,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 90),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 90)),
              latitude: 1.301000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 1.2,
            ),
          ),
        ]);
        final controller = RunTrackingController(locationProvider: provider);

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'auto-pause-controller-run',
        );
        controller.advanceBy(const Duration(seconds: 60));
        final movingTimeBeforeStop = controller.state.elapsedSeconds;
        final distanceBeforeStop = controller.state.distanceMeters;
        final paceBeforeStop = controller.state.averagePaceSecondsPerKm;

        controller.advanceBy(const Duration(seconds: 20));

        expect(controller.state.isAutoPaused, isTrue);
        expect(controller.state.isPaused, isFalse);
        expect(controller.state.phase, RunTrackingPhase.active);
        expect(
          RunTrackingSnapshot.fromState(controller.state).guidance,
          'You can pause anytime.',
        );
        expect(controller.state.elapsedSeconds, movingTimeBeforeStop);
        expect(controller.state.distanceMeters, distanceBeforeStop);
        expect(controller.state.averagePaceSecondsPerKm, paceBeforeStop);
        expect(provider.pauseCount, 0);

        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 80)),
        );
        final payloadMap = payload.toRawClientMap();
        expect(payload.durationSeconds, movingTimeBeforeStop);
        expect(payload.distanceMeters, distanceBeforeStop);
        expect(payload.avgPaceSecondsPerKm, paceBeforeStop);
        expect(payloadMap.keys, isNot(contains('routeSamples')));
        expect(payloadMap.keys, isNot(contains('gpsSamples')));
        expect(payloadMap.keys, isNot(contains('leaderboardScore')));
        expect(payloadMap.keys, isNot(contains('validatedActivity')));

        controller.pause();
        controller.advanceBy(const Duration(seconds: 10));

        expect(controller.state.isPaused, isTrue);
        expect(controller.state.isAutoPaused, isFalse);
        expect(provider.pauseCount, 1);
        expect(controller.state.elapsedSeconds, movingTimeBeforeStop);
        expect(controller.state.distanceMeters, distanceBeforeStop);

        controller.resume();

        expect(provider.resumeCount, 1);
        expect(controller.state.phase, RunTrackingPhase.active);
        expect(controller.state.isAutoPaused, isFalse);
      },
    );

    test('abnormal pause suppresses summary and keeps providers running', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final provider = _LifecycleReplayProvider([
        RunLocationReplaySample(
          activeOffset: Duration.zero,
          sample: RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ),
        for (final seconds in [1, 2, 3])
          RunLocationReplaySample(
            activeOffset: Duration(seconds: seconds),
            sample: RunLocationSample(
              recordedAt: startedAt.add(Duration(seconds: seconds)),
              latitude: 1.300000 + (0.000063 * seconds),
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 7,
            ),
          ),
      ]);
      final motionProvider = _LifecycleMotionProvider();
      final controller = RunTrackingController(
        locationProvider: provider,
        motionProvider: motionProvider,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'abnormal-controller-run',
      );
      controller.advanceBy(const Duration(seconds: 3));

      expect(controller.state.isAbnormalPaused, isTrue);
      expect(controller.state.isPaused, isFalse);
      expect(controller.state.isAutoPaused, isFalse);
      expect(controller.state.phase, RunTrackingPhase.active);
      expect(
        RunTrackingSnapshot.fromState(controller.state).guidance,
        abnormalMovementGuidance,
      );
      expect(controller.state.distanceMeters, 0);
      expect(controller.state.averagePaceSecondsPerKm, 0);
      expect(controller.mapViewState.routePointCount, 1);
      expect(provider.pauseCount, 0);
      expect(motionProvider.pauseCount, 0);

      final payload = controller.completionPayload(
        completedAt: startedAt.add(const Duration(seconds: 3)),
      );
      final payloadMap = payload.toRawClientMap();
      expect(payload.distanceMeters, 0);
      expect(payload.avgPaceSecondsPerKm, 0);
      expect(payloadMap.keys, isNot(contains('routeSamples')));
      expect(payloadMap.keys, isNot(contains('gpsSamples')));
      expect(payloadMap.keys, isNot(contains('rawMotion')));
      expect(payloadMap.keys, isNot(contains('classifierEvidence')));
      expect(payloadMap.keys, isNot(contains('abnormalMovement')));
      expect(payloadMap.keys, isNot(contains('leaderboardScore')));
      expect(payloadMap.keys, isNot(contains('validatedActivity')));

      controller.resume();

      expect(provider.resumeCount, 1);
      expect(motionProvider.resumeCount, 1);
      expect(controller.state.phase, RunTrackingPhase.active);
      expect(controller.state.movementStatus, RunMovementStatus.moving);
      expect(controller.state.isAbnormalPaused, isFalse);
    });

    test(
      'stationary from start auto pauses without distance and manual pause wins',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final provider = _LifecycleReplayProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 10),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 10)),
              latitude: 1.300009,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 20),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 20)),
              latitude: 1.300018,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 30),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 30)),
              latitude: 1.300100,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 1.2,
            ),
          ),
        ]);
        final controller = RunTrackingController(locationProvider: provider);

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'start-stationary-controller-run',
        );
        controller.advanceBy(const Duration(seconds: 21));

        final snapshot = RunTrackingSnapshot.fromState(controller.state);
        expect(controller.state.isAutoPaused, isTrue);
        expect(controller.state.isPaused, isFalse);
        expect(controller.state.elapsedSeconds, 0);
        expect(controller.state.distanceMeters, 0);
        expect(controller.state.averagePaceSecondsPerKm, 0);
        expect(controller.mapViewState.routePointCount, 1);
        expect(controller.mapViewState.currentPosition?.latitude, 1.300018);
        expect(snapshot.averagePaceLabel, '--:--/km');
        expect(snapshot.guidance, 'You can pause anytime.');
        expect(provider.pauseCount, 0);

        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 21)),
        );
        final payloadMap = payload.toRawClientMap();
        expect(payload.durationSeconds, 0);
        expect(payload.distanceMeters, 0);
        expect(payload.avgPaceSecondsPerKm, 0);
        expect(payloadMap.keys, isNot(contains('routeSamples')));
        expect(payloadMap.keys, isNot(contains('gpsSamples')));
        expect(payloadMap.keys, isNot(contains('leaderboardScore')));
        expect(payloadMap.keys, isNot(contains('validatedActivity')));

        controller.pause();
        controller.advanceBy(const Duration(seconds: 10));

        expect(controller.state.isPaused, isTrue);
        expect(controller.state.isAutoPaused, isFalse);
        expect(controller.state.elapsedSeconds, 0);
        expect(controller.state.distanceMeters, 0);
        expect(provider.pauseCount, 1);
      },
    );

    test('finish creates only raw client-observed completion payload', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final completedAt = DateTime.utc(2026, 6, 14, 7, 2);

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'local-session-4',
        routeLabel: 'Easy local route',
      );
      controller.advanceBy(const Duration(seconds: 120));

      final payload = controller.finish(completedAt: completedAt);
      final payloadMap = payload.toRawClientMap();

      expect(payload, isA<LocalRunCompletionPayload>());
      expect(payload.clientRunSessionId, 'local-session-4');
      expect(payload.startedAt, startedAt);
      expect(payload.completedAt, completedAt);
      expect(payload.durationSeconds, 120);
      expect(payload.distanceMeters, 300);
      expect(payload.avgPaceSecondsPerKm, 400);
      expect(payload.source, 'local_simulation');
      expect(payload.routePrivacy, 'private');
      expect(payload.routeLabel, 'Easy local route');
      expect(controller.state.phase, RunTrackingPhase.finished);
      expect(payloadMap.keys, isNot(contains('xp')));
      expect(payloadMap.keys, isNot(contains('streak')));
      expect(payloadMap.keys, isNot(contains('level')));
      expect(payloadMap.keys, isNot(contains('rank')));
      expect(payloadMap.keys, isNot(contains('leaderboardScore')));
      expect(payloadMap.keys, isNot(contains('weeklyXp')));
      expect(payloadMap.keys, isNot(contains('monthlyXp')));
      expect(
        payloadMap.keys,
        isNot(
          contains(
            'validation'
            'Status',
          ),
        ),
      );
      expect(
        payloadMap.keys,
        isNot(
          contains(
            'countsToward'
            'Progression',
          ),
        ),
      );
    });

    test('completionPayload does not mark the local run finished', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final completedAt = DateTime.utc(2026, 6, 14, 7, 2);

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'local-session-5',
        routeLabel: 'Easy local route',
      );
      controller.advanceBy(const Duration(seconds: 120));
      controller.pause();

      final payload = controller.completionPayload(completedAt: completedAt);

      expect(payload.clientRunSessionId, 'local-session-5');
      expect(payload.startedAt, startedAt);
      expect(payload.completedAt, completedAt);
      expect(payload.durationSeconds, 120);
      expect(payload.distanceMeters, 300);
      expect(payload.avgPaceSecondsPerKm, 400);
      expect(payload.source, 'local_simulation');
      expect(payload.routePrivacy, 'private');
      expect(payload.routeLabel, 'Easy local route');
      expect(controller.state.phase, RunTrackingPhase.paused);
      expect(controller.state.completedAt, isNull);
    });

    test(
      'does not start real provider when foreground permission is denied',
      () async {
        final provider = _LifecycleTrackingProvider();
        final controller = RunTrackingController(
          locationProvider: provider,
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.denied,
          ),
        );

        final started = await controller.requestStart(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'permission-denied-run',
        );

        expect(started, isFalse);
        expect(
          controller.locationPermissionStatus,
          RunLocationPermissionStatus.denied,
        );
        expect(controller.state.phase, RunTrackingPhase.idle);
        expect(provider.startCount, 0);
      },
    );

    test(
      'starts real provider only when foreground permission is granted',
      () async {
        final provider = _LifecycleTrackingProvider();
        final controller = RunTrackingController(
          locationProvider: provider,
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.granted,
          ),
        );

        final started = await controller.requestStart(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'permission-granted-run',
        );

        expect(started, isTrue);
        expect(
          controller.locationPermissionStatus,
          RunLocationPermissionStatus.granted,
        );
        expect(controller.state.phase, RunTrackingPhase.active);
        expect(provider.startCount, 1);

        controller.pause();
        controller.resume();
        controller.finish(completedAt: DateTime.utc(2026, 6, 14, 7, 1));

        expect(provider.pauseCount, 1);
        expect(provider.resumeCount, 1);
        expect(provider.stopCount, 1);
      },
    );

    test(
      'requests notification permission before starting real provider',
      () async {
        final provider = _LifecycleTrackingProvider();
        final notificationPermissionService =
            _FakeNotificationPermissionService(
              RunNotificationPermissionStatus.granted,
            );
        final controller = RunTrackingController(
          locationProvider: provider,
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.granted,
          ),
          notificationPermissionService: notificationPermissionService,
        );

        final started = await controller.requestStart(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'notification-permission-granted-run',
        );

        expect(started, isTrue);
        expect(notificationPermissionService.requestCount, 1);
        expect(controller.state.phase, RunTrackingPhase.active);
        expect(provider.startCount, 1);
      },
    );

    test(
      'does not start real provider when notification permission is denied',
      () async {
        final provider = _LifecycleTrackingProvider();
        final notificationPermissionService =
            _FakeNotificationPermissionService(
              RunNotificationPermissionStatus.denied,
            );
        final controller = RunTrackingController(
          locationProvider: provider,
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.granted,
          ),
          notificationPermissionService: notificationPermissionService,
        );

        final started = await controller.requestStart(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'notification-permission-denied-run',
        );

        expect(started, isFalse);
        expect(notificationPermissionService.requestCount, 1);
        expect(
          controller.locationPermissionStatus,
          RunLocationPermissionStatus.notificationDenied,
        );
        expect(
          controller.locationPermissionMessage,
          'Notifications are needed to keep tracking visible while Runiac is in the background.',
        );
        expect(controller.state.phase, RunTrackingPhase.idle);
        expect(provider.startCount, 0);
      },
    );

    test(
      'starts updates and stops Runiac foreground service without changing math',
      () async {
        final provider = _LifecycleTrackingProvider();
        final foregroundService = _FakeRunForegroundService();
        final controller = RunTrackingController(
          locationProvider: provider,
          foregroundService: foregroundService,
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.granted,
          ),
          notificationPermissionService: _FakeNotificationPermissionService(
            RunNotificationPermissionStatus.granted,
          ),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        final started = await controller.requestStart(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'runiac-foreground-service-run',
        );

        expect(started, isTrue);
        expect(provider.startCount, 1);
        expect(foregroundService.calls, ['start']);
        expect(foregroundService.titles, hasLength(1));
        expect(foregroundService.bodies, hasLength(1));

        controller.advanceBy(const Duration(seconds: 1));
        controller.pause(pausedAt: DateTime.utc(2026, 6, 14, 7, 0, 1));
        controller.resume(resumedAt: DateTime.utc(2026, 6, 14, 7, 0, 2));
        final payload = controller.finish(
          completedAt: DateTime.utc(2026, 6, 14, 7, 0, 3),
        );
        await Future<void>.delayed(Duration.zero);

        expect(payload.clientRunSessionId, 'runiac-foreground-service-run');
        expect(payload.durationSeconds, 1);
        expect(payload.distanceMeters, 3);
        expect(foregroundService.calls, [
          'start',
          'update',
          'update',
          'update',
          'stop',
        ]);
        expect(foregroundService.titles, hasLength(4));
        expect(foregroundService.bodies, hasLength(4));
      },
    );

    test(
      'stops Runiac foreground service when provider startup fails',
      () async {
        final provider = _ThrowingStartLocationProvider();
        final foregroundService = _FakeRunForegroundService();
        final controller = RunTrackingController(
          locationProvider: provider,
          foregroundService: foregroundService,
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.granted,
          ),
          notificationPermissionService: _FakeNotificationPermissionService(
            RunNotificationPermissionStatus.granted,
          ),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        final started = await controller.requestStart(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'provider-start-failure-run',
        );

        expect(started, isFalse);
        expect(controller.state.phase, RunTrackingPhase.idle);
        expect(
          controller.locationPermissionStatus,
          RunLocationPermissionStatus.unavailable,
        );
        expect(provider.startCount, 1);
        expect(provider.stopCount, 1);
        expect(foregroundService.calls, ['start', 'stop']);
      },
    );

    test('reports why run tracking provider startup failed', () async {
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      final provider = _ThrowingStartLocationProvider();
      final controller = RunTrackingController(
        locationProvider: provider,
        foregroundService: _FakeRunForegroundService(),
        permissionService: _FakePermissionService(
          RunLocationPermissionStatus.granted,
        ),
        notificationPermissionService: _FakeNotificationPermissionService(
          RunNotificationPermissionStatus.granted,
        ),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      final started = await controller.requestStart(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'provider-start-report-run',
      );

      expect(started, isFalse);
      expect(reported, hasLength(1));
      final details = reported.single;
      expect(details.exception, isA<StateError>());
      expect(details.library, 'runiac run tracking');

      final context = details.context.toString();
      expect(context, contains('starting run tracking providers'));
      // The run session id is the correlation key that ties this failure to
      // the rest of that run's flow.
      expect(context, contains('provider-start-report-run'));
      // Diagnostics must stay scalar: no coordinates, tokens, or account
      // values may ride along in the reported context.
      expect(context, isNot(contains('latitude')));
      expect(context, isNot(contains('longitude')));
      expect(context, isNot(contains('routeSamples')));
    });

    test(
      'provider startup cleanup survives a failing error reporter',
      () async {
        final previousOnError = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          throw StateError('diagnostic sink failed');
        };
        addTearDown(() => FlutterError.onError = previousOnError);

        final provider = _ThrowingStartLocationProvider();
        final foregroundService = _FakeRunForegroundService();
        final controller = RunTrackingController(
          locationProvider: provider,
          foregroundService: foregroundService,
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.granted,
          ),
          notificationPermissionService: _FakeNotificationPermissionService(
            RunNotificationPermissionStatus.granted,
          ),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        // A failing diagnostic sink must not escape to the caller, and must
        // not skip the provider/foreground-service cleanup that follows it.
        final started = await controller.requestStart(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'provider-start-sink-failure-run',
        );

        expect(started, isFalse);
        expect(controller.state.phase, RunTrackingPhase.idle);
        expect(provider.stopCount, 1);
        expect(foregroundService.calls, ['start', 'stop']);
      },
    );

    test(
      'stops Runiac foreground service after dispose during startup',
      () async {
        final provider = _LifecycleTrackingProvider();
        final foregroundService = _DelayedRunForegroundService();
        final controller = RunTrackingController(
          locationProvider: provider,
          foregroundService: foregroundService,
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.granted,
          ),
          notificationPermissionService: _FakeNotificationPermissionService(
            RunNotificationPermissionStatus.granted,
          ),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        final startFuture = controller.requestStart(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'disposed-during-foreground-start-run',
        );
        await Future<void>.delayed(Duration.zero);

        controller.dispose();
        foregroundService.startCompleter.complete();
        final started = await startFuture;

        expect(started, isFalse);
        expect(provider.startCount, 0);
        expect(foregroundService.calls, ['start', 'stop']);
      },
    );

    test('default local simulation starts in demo mode', () {
      final controller = RunTrackingController();

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'demo-run',
      );

      expect(controller.state.locationStatus, RunTrackingLocationStatus.demo);
    });

    test('foreground GPS mode waits before any accepted sample', () {
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider(const []),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'waiting-gps-run',
      );
      controller.advanceBy(const Duration(seconds: 1));

      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.waitingForGps,
      );
      expect(controller.state.diagnostics.hasReceivedSample, isFalse);
      expect(controller.state.diagnostics.acceptedSampleCount, 0);
    });

    test('startup readiness waits before any GPS sample is received', () {
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider(const []),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'readiness-waiting-run',
      );
      controller.advanceBy(const Duration(seconds: 1));

      final snapshot = RunTrackingSnapshot.fromState(controller.state);
      expect(
        snapshot.startupReadiness,
        RunTrackingStartupReadiness.waitingForFirstSample,
      );
      expect(
        snapshot.startupReadinessMessage,
        'Getting GPS ready. Keep the app open while we find your signal.',
      );
      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.waitingForGps,
      );
    });

    test('foreground GPS mode becomes active after an accepted sample', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.3,
              longitude: 103.8,
              horizontalAccuracyMeters: 5,
            ),
          ),
        ]),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'active-gps-run',
      );
      controller.advanceBy(const Duration(seconds: 1));

      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.gpsActive,
      );
      expect(controller.state.diagnostics.acceptedSampleCount, 1);
      expect(
        controller.state.diagnostics.latestAccuracyBucket,
        RunLocationAccuracyBucket.good,
      );
    });

    test('startup readiness anchors on the first accepted GPS sample', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.3,
              longitude: 103.8,
              horizontalAccuracyMeters: 5,
            ),
          ),
        ]),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'readiness-anchor-run',
      );
      controller.advanceBy(const Duration(seconds: 1));

      final snapshot = RunTrackingSnapshot.fromState(controller.state);
      expect(controller.state.distanceMeters, 0);
      expect(
        snapshot.startupReadiness,
        RunTrackingStartupReadiness.anchoredNoMovement,
      );
      expect(
        snapshot.startupReadinessMessage,
        'GPS is ready. Start moving to measure distance.',
      );
    });

    test(
      'empty samples after first GPS anchor auto pause without route or payload growth',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final anchor = RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 1)),
          latitude: 1.3,
          longitude: 103.8,
          horizontalAccuracyMeters: 5,
        );
        final controller = RunTrackingController(
          locationProvider: _LifecycleReplayProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: anchor,
            ),
          ]),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'empty-dwell-run',
        );
        controller.advanceBy(const Duration(seconds: 1));
        final routePointCountBeforeDwell =
            controller.mapViewState.routePointCount;
        final currentPositionBeforeDwell =
            controller.mapViewState.currentPosition;

        for (var tick = 0; tick < 5; tick += 1) {
          controller.advanceBy(const Duration(seconds: 1));
        }

        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 6)),
        );
        final payloadMap = payload.toRawClientMap();
        expect(controller.state.isAutoPaused, isTrue);
        expect(controller.state.isPaused, isFalse);
        expect(controller.state.elapsedSeconds, 5);
        expect(controller.state.distanceMeters, 0);
        expect(
          controller.mapViewState.routePointCount,
          routePointCountBeforeDwell,
        );
        expect(
          controller.mapViewState.currentPosition,
          currentPositionBeforeDwell,
        );
        expect(payload.durationSeconds, 5);
        expect(payload.distanceMeters, 0);
        expect(payloadMap.keys, isNot(contains('gpsSamples')));
        expect(payloadMap.keys, isNot(contains('motionEvidence')));
        expect(payloadMap.keys, isNot(contains('motionConfidence')));
        expect(payloadMap.keys, isNot(contains('accelerometer')));
        expect(payloadMap.keys, isNot(contains('userAccelerometer')));
        expect(payloadMap.keys, isNot(contains('routeTrace')));
        expect(payloadMap.keys, isNot(contains('xp')));
        expect(payloadMap.keys, isNot(contains('leaderboardScore')));
        expect(payloadMap.keys, isNot(contains('validatedActivity')));
      },
    );

    test('steady-phone GPS drift stays distance-free with GPS active', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: _LifecycleReplayProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 3),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 3)),
              latitude: 1.300027,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.7,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 6),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 6)),
              latitude: 1.300027,
              longitude: 103.800027,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.7,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 9),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 9)),
              latitude: 1.300000,
              longitude: 103.800027,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.7,
            ),
          ),
        ]),
        motionProvider: const _ConstantMotionProvider(
          RunMotionSignal.stationary,
        ),
        locationStatus: RunTrackingLocationStatus.gpsActive,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'steady-phone-drift-run',
      );
      controller.advanceBy(const Duration(seconds: 9));

      expect(controller.state.isAutoPaused, isTrue);
      expect(controller.state.movementStatus, RunMovementStatus.autoPaused);
      expect(controller.state.distanceMeters, 0);
      expect(controller.state.averagePaceSecondsPerKm, 0);
      expect(controller.mapViewState.routePointCount, 1);
      expect(controller.mapViewState.currentPosition?.longitude, 103.800027);
      expect(
        controller.completionPayload().toRawClientMap().keys,
        isNot(contains('motionEvidence')),
      );
    });

    test('auto pause does not stop the motion provider', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final motionProvider = _LifecycleMotionProvider();
      final controller = RunTrackingController(
        locationProvider: _LifecycleReplayProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.3,
              longitude: 103.8,
              horizontalAccuracyMeters: 5,
            ),
          ),
        ]),
        motionProvider: motionProvider,
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'auto-pause-motion-lifecycle-run',
      );
      controller.advanceBy(const Duration(seconds: 1));
      for (var tick = 0; tick < 5; tick += 1) {
        controller.advanceBy(const Duration(seconds: 1));
      }

      expect(controller.state.isAutoPaused, isTrue);
      expect(motionProvider.startCount, 1);
      expect(motionProvider.pauseCount, 0);
      expect(motionProvider.stopCount, 0);

      controller.pause();

      expect(controller.state.isPaused, isTrue);
      expect(motionProvider.pauseCount, 1);
    });

    test('manual resume and finish work from auto-paused active state', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final provider = _LifecycleReplayProvider([
        RunLocationReplaySample(
          activeOffset: const Duration(seconds: 1),
          sample: RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 1)),
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ),
        RunLocationReplaySample(
          activeOffset: const Duration(seconds: 20),
          sample: RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 20)),
            latitude: 1.300090,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 1.2,
          ),
        ),
        RunLocationReplaySample(
          activeOffset: const Duration(seconds: 21),
          sample: RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 21)),
            latitude: 1.300180,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 1.2,
          ),
        ),
      ]);
      final controller = RunTrackingController(
        locationProvider: provider,
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'auto-paused-resume-finish-run',
      );
      controller.advanceBy(const Duration(seconds: 1));
      for (var tick = 0; tick < 5; tick += 1) {
        controller.advanceBy(const Duration(seconds: 1));
      }

      expect(controller.state.isAutoPaused, isTrue);
      expect(controller.state.phase, RunTrackingPhase.active);
      expect(controller.state.elapsedSeconds, 5);

      controller.resume();

      expect(provider.resumeCount, 1);
      expect(controller.state.phase, RunTrackingPhase.active);
      expect(controller.state.isAutoPaused, isFalse);
      expect(controller.state.movementStatus, RunMovementStatus.moving);

      controller.advanceBy(const Duration(seconds: 15));
      expect(controller.state.distanceMeters, greaterThan(0));

      final payload = controller.finish(
        completedAt: startedAt.add(const Duration(seconds: 21)),
      );
      final payloadMap = payload.toRawClientMap();

      expect(payload.clientRunSessionId, 'auto-paused-resume-finish-run');
      expect(payload.distanceMeters, greaterThan(0));
      expect(payloadMap.keys, isNot(contains('gpsSamples')));
      expect(payloadMap.keys, isNot(contains('motionEvidence')));
      expect(payloadMap.keys, isNot(contains('leaderboardScore')));
      expect(payloadMap.keys, isNot(contains('validatedActivity')));
    });

    test(
      'stationary GPS jump while auto paused keeps payload and route protected',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final provider = _LifecycleReplayProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 30),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 30)),
              latitude: 1.300360,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 4,
            ),
          ),
        ]);
        final controller = RunTrackingController(
          locationProvider: provider,
          motionProvider: const _ConstantMotionProvider(
            RunMotionSignal.stationary,
          ),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'stationary-gps-jump-run',
        );
        controller.advanceBy(const Duration(seconds: 1));
        controller.advanceBy(const Duration(seconds: 5));
        expect(controller.state.isAutoPaused, isTrue);
        final routePointCountBeforeJump =
            controller.mapViewState.routePointCount;

        controller.advanceBy(const Duration(seconds: 24));

        expect(controller.state.isAutoPaused, isTrue);
        expect(controller.state.isPaused, isFalse);
        expect(controller.state.elapsedSeconds, 1);
        expect(controller.state.distanceMeters, 0);
        expect(controller.state.averagePaceSecondsPerKm, 0);
        expect(
          controller.mapViewState.routePointCount,
          routePointCountBeforeJump,
        );
        expect(
          controller.mapViewState.acceptedRouteSegments
              .expand((segment) => segment)
              .map((sample) => sample.latitude),
          isNot(contains(1.300360)),
        );
        expect(controller.mapViewState.displayPosition?.latitude, 1.300360);
        expect(controller.mapViewState.currentPosition?.latitude, 1.300360);
        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 30)),
        );
        final payloadMap = payload.toRawClientMap();
        expect(payload.durationSeconds, 1);
        expect(payload.distanceMeters, 0);
        expect(payload.avgPaceSecondsPerKm, 0);
        expect(payloadMap.keys, isNot(contains('gpsSamples')));
        expect(payloadMap.keys, isNot(contains('routeSegments')));
        expect(payloadMap.keys, isNot(contains('acceptedRouteSegments')));
        expect(payloadMap.keys, isNot(contains('motionEvidence')));
        expect(payloadMap.keys, isNot(contains('gpsSamples')));
        expect(payloadMap.keys, isNot(contains('routeSamples')));
        expect(payloadMap.keys, isNot(contains('motionEvidence')));
        expect(payloadMap.keys, isNot(contains('classifierEvidence')));
        expect(payloadMap.keys, isNot(contains('leaderboardScore')));
        expect(payloadMap.keys, isNot(contains('validatedActivity')));
      },
    );

    test('empty samples before first GPS anchor do not auto pause', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider(const []),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'no-anchor-empty-dwell-run',
      );
      controller.advanceBy(const Duration(seconds: 20));

      expect(controller.state.isAutoPaused, isFalse);
      expect(controller.state.elapsedSeconds, 20);
      expect(controller.state.distanceMeters, 0);
      expect(controller.mapViewState.routePointCount, 0);
      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.waitingForGps,
      );
    });

    test('manual pause blocks no-sample dwell auto-pause and auto-resume', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final provider = _LifecycleReplayProvider([
        RunLocationReplaySample(
          activeOffset: const Duration(seconds: 1),
          sample: RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 1)),
            latitude: 1.300000,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ),
        RunLocationReplaySample(
          activeOffset: const Duration(seconds: 30),
          sample: RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 30)),
            latitude: 1.300899,
            longitude: 103.800000,
            horizontalAccuracyMeters: 5,
          ),
        ),
      ]);
      final controller = RunTrackingController(
        locationProvider: provider,
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'manual-pause-empty-dwell-run',
      );
      controller.advanceBy(const Duration(seconds: 1));
      controller.pause();
      controller.advanceBy(const Duration(seconds: 29));

      expect(controller.state.isPaused, isTrue);
      expect(controller.state.isAutoPaused, isFalse);
      expect(controller.state.elapsedSeconds, 1);
      expect(controller.state.distanceMeters, 0);
      expect(controller.mapViewState.routePointCount, 1);
    });

    test('foreground GPS mode becomes weak after rejected accuracy', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.3,
              longitude: 103.8,
              horizontalAccuracyMeters: 250,
            ),
          ),
        ]),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'weak-gps-run',
      );
      controller.advanceBy(const Duration(seconds: 1));

      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.gpsWeak,
      );
      expect(
        controller.state.diagnostics.latestRejectionReason,
        RunLocationRejectionReason.poorAccuracy,
      );
      expect(controller.state.diagnostics.rejectedSampleCount, 1);
    });

    test('startup readiness reports weak GPS after latest rejected sample', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.3,
              longitude: 103.8,
              horizontalAccuracyMeters: 250,
            ),
          ),
        ]),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'readiness-weak-run',
      );
      controller.advanceBy(const Duration(seconds: 1));

      final snapshot = RunTrackingSnapshot.fromState(controller.state);
      expect(snapshot.startupReadiness, RunTrackingStartupReadiness.gpsWeak);
      expect(
        snapshot.startupReadinessMessage,
        'GPS signal is weak. Keep moving in an open area.',
      );
    });

    test('startup readiness keeps pace hidden below the 50m threshold', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 20),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 20)),
              latitude: 1.300225,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ),
        ]),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'readiness-below-threshold-run',
      );
      controller.advanceBy(const Duration(seconds: 20));

      final snapshot = RunTrackingSnapshot.fromState(controller.state);
      expect(controller.state.distanceMeters, greaterThan(0));
      expect(controller.state.distanceMeters, lessThan(50));
      expect(
        snapshot.startupReadiness,
        RunTrackingStartupReadiness.movementBelowThreshold,
      );
      expect(snapshot.averagePaceLabel, '--:--/km');
      expect(
        snapshot.startupReadinessMessage,
        'Keep going. Pace appears after a little more movement.',
      );
    });

    test('startup readiness becomes ready at the 50m movement threshold', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 20),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 20)),
              latitude: 1.300450,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ),
        ]),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'readiness-ready-run',
      );
      controller.advanceBy(const Duration(seconds: 20));

      final snapshot = RunTrackingSnapshot.fromState(controller.state);
      expect(controller.state.distanceMeters, greaterThanOrEqualTo(50));
      expect(snapshot.startupReadiness, RunTrackingStartupReadiness.ready);
      expect(snapshot.averagePaceLabel, isNot('--:--/km'));
      expect(
        snapshot.startupReadinessMessage,
        'GPS active. Distance and pace are updating.',
      );
    });

    test('foreground GPS mode follows latest active and weak samples', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.3,
              longitude: 103.8,
              horizontalAccuracyMeters: 5,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 2),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 2)),
              latitude: 1.30001,
              longitude: 103.8,
              horizontalAccuracyMeters: 250,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 3),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 3)),
              latitude: 1.30002,
              longitude: 103.8,
              horizontalAccuracyMeters: 5,
            ),
          ),
        ]),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'latest-gps-quality-run',
      );
      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.waitingForGps,
      );

      controller.advanceBy(const Duration(seconds: 1));
      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.gpsActive,
      );

      controller.advanceBy(const Duration(seconds: 1));
      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.gpsWeak,
      );

      controller.advanceBy(const Duration(seconds: 1));
      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.gpsActive,
      );
    });

    test(
      'foreground GPS mode shows approximate location only when reduced',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 1)),
                latitude: 1.3,
                longitude: 103.8,
                horizontalAccuracyMeters: 5,
              ),
            ),
          ], locationAccuracyStatus: RunTrackingLocationAccuracyStatus.reduced),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'approximate-gps-run',
        );
        controller.advanceBy(const Duration(seconds: 1));

        expect(
          controller.state.locationStatus,
          RunTrackingLocationStatus.approximateLocation,
        );
        expect(
          controller.state.diagnostics.locationAccuracyStatus,
          RunTrackingLocationAccuracyStatus.reduced,
        );

        final snapshot = RunTrackingSnapshot.fromState(controller.state);
        expect(
          snapshot.startupReadiness,
          RunTrackingStartupReadiness.approximateLocation,
        );
        expect(
          snapshot.startupReadinessMessage,
          'Approximate location is on. Distance may take longer to settle.',
        );
      },
    );

    test('foreground GPS mode follows latest sample in one advance batch', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 1),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 1)),
              latitude: 1.3,
              longitude: 103.8,
              horizontalAccuracyMeters: 5,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 2),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 2)),
              latitude: 1.30001,
              longitude: 103.8,
              horizontalAccuracyMeters: 250,
            ),
          ),
        ]),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'batched-latest-gps-quality-run',
      );
      controller.advanceBy(const Duration(seconds: 2));

      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.gpsWeak,
      );
    });

    test(
      'foreground GPS mode shows weak for later duplicate timestamp rejection',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 1)),
                latitude: 1.3,
                longitude: 103.8,
                horizontalAccuracyMeters: 5,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 2),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 1)),
                latitude: 1.3001,
                longitude: 103.8,
                horizontalAccuracyMeters: 5,
              ),
            ),
          ]),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'duplicate-timestamp-quality-run',
        );
        controller.advanceBy(const Duration(seconds: 2));

        expect(
          controller.state.locationStatus,
          RunTrackingLocationStatus.gpsWeak,
        );
        expect(
          controller.state.diagnostics.latestRejectionReason,
          RunLocationRejectionReason.duplicateOrOutOfOrderTimestamp,
        );
      },
    );

    test('real foreground late accepted samples advance distance', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter();
      final controller = RunTrackingController(
        locationProvider: RealForegroundRunLocationProvider(adapter: adapter),
        permissionService: _FakePermissionService(
          RunLocationPermissionStatus.granted,
        ),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      final started = await controller.requestStart(
        startedAt: startedAt,
        clientRunSessionId: 'late-real-gps-run',
      );
      expect(started, isTrue);
      controller.advanceBy(const Duration(seconds: 10));

      adapter.emit(
        _ForegroundPosition(
          timestamp: startedAt.add(const Duration(seconds: 1)),
          latitude: 1.300000,
          longitude: 103.800000,
          accuracy: 5,
        ),
      );
      adapter.emit(
        _ForegroundPosition(
          timestamp: startedAt.add(const Duration(seconds: 10)),
          latitude: 1.300270,
          longitude: 103.800000,
          accuracy: 5,
        ),
      );

      controller.advanceBy(const Duration(seconds: 1));

      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.gpsActive,
      );
      expect(controller.state.distanceMeters, closeTo(30, 2));
    });

    test('real foreground late rejected sample surfaces GPS weak', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final adapter = _FakeForegroundAdapter();
      final controller = RunTrackingController(
        locationProvider: RealForegroundRunLocationProvider(adapter: adapter),
        permissionService: _FakePermissionService(
          RunLocationPermissionStatus.granted,
        ),
        locationStatus: RunTrackingLocationStatus.waitingForGps,
      );

      await controller.requestStart(
        startedAt: startedAt,
        clientRunSessionId: 'late-weak-gps-run',
      );
      controller.advanceBy(const Duration(seconds: 10));

      adapter.emit(
        _ForegroundPosition(
          timestamp: startedAt.add(const Duration(seconds: 2)),
          latitude: 1.300000,
          longitude: 103.800000,
          accuracy: 250,
        ),
      );

      controller.advanceBy(const Duration(seconds: 1));

      expect(
        controller.state.locationStatus,
        RunTrackingLocationStatus.gpsWeak,
      );
      expect(controller.state.distanceMeters, 0);
      expect(
        controller.state.diagnostics.latestRejectionReason,
        RunLocationRejectionReason.poorAccuracy,
      );
    });

    test(
      'real foreground unconsumed pre-pause sample does not bridge after resume',
      () async {
        final startedAt = DateTime.now().subtract(const Duration(minutes: 1));
        final adapter = _FakeForegroundAdapter();
        final controller = RunTrackingController(
          locationProvider: RealForegroundRunLocationProvider(adapter: adapter),
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.granted,
          ),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        await controller.requestStart(
          startedAt: startedAt,
          clientRunSessionId: 'no-bridge-late-pause-run',
        );
        adapter.emit(
          _ForegroundPosition(
            timestamp: startedAt.add(const Duration(seconds: 1)),
            latitude: 1.300000,
            longitude: 103.800000,
            accuracy: 5,
          ),
        );

        controller.pause();
        controller.resume();
        adapter.emit(
          _ForegroundPosition(
            timestamp: DateTime.now().add(const Duration(seconds: 1)),
            latitude: 1.300899,
            longitude: 103.800000,
            accuracy: 5,
          ),
        );

        controller.advanceBy(const Duration(seconds: 2));

        expect(
          controller.state.locationStatus,
          RunTrackingLocationStatus.gpsActive,
        );
        expect(controller.state.distanceMeters, 0);
        expect(controller.mapViewState.routeSegments, hasLength(1));
        expect(controller.mapViewState.routeSegments.single, hasLength(1));
      },
    );

    test(
      'records cadence permission denied diagnostics without blocking run',
      () async {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final cadenceProvider = _DiagnosticsRunCadenceProvider();
        final controller = RunTrackingController(
          cadenceProvider: cadenceProvider,
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 1)),
                latitude: 1.3,
                longitude: 103.8,
                horizontalAccuracyMeters: 5,
              ),
            ),
          ]),
          locationStatus: RunTrackingLocationStatus.waitingForGps,
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'cadence-denied-run',
        );
        await Future<void>.delayed(Duration.zero);
        cadenceProvider.emitDiagnostics(
          const RunCadenceDiagnostics(
            permissionStatus: RunCadencePermissionStatus.denied,
            latestReason: RunCadenceDiagnosticReason.permissionDenied,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        controller.advanceBy(const Duration(seconds: 1));

        expect(controller.state.isActive, isTrue);
        expect(
          controller.state.diagnostics.cadence.permissionStatus,
          RunCadencePermissionStatus.denied,
        );
        expect(
          controller.state.diagnostics.cadence.latestReason,
          RunCadenceDiagnosticReason.permissionDenied,
        );
        expect(controller.state.diagnostics.acceptedSampleCount, 1);

        controller.finish(
          completedAt: startedAt.add(const Duration(seconds: 1)),
        );
        expect(controller.state.phase, RunTrackingPhase.finished);
        await cadenceProvider.dispose();
      },
    );

    test('dispose stops the active location provider', () async {
      final provider = _LifecycleTrackingProvider();
      final controller = RunTrackingController(locationProvider: provider);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'dispose-run',
      );
      controller.dispose();

      expect(provider.startCount, 1);
      expect(provider.stopCount, 1);
    });

    test(
      'repeated finish keeps the same client run session id for backend dedupe',
      () {
        // Pins current behavior: finish() has no phase guard, so a second
        // call (e.g. a double-tap racing navigation) must not throw and must
        // reuse the SAME clientRunSessionId — that shared id is the invariant
        // that lets backend idempotency dedupe the duplicate completion.
        final controller = RunTrackingController(metersPerSecond: 2.5);
        final startedAt = DateTime.utc(2026, 6, 14, 7);

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'double-finish-run',
        );
        controller.advanceBy(const Duration(seconds: 120));

        final firstPayload = controller.finish(
          completedAt: DateTime.utc(2026, 6, 14, 7, 2),
        );
        expect(controller.state.phase, RunTrackingPhase.finished);

        late LocalRunCompletionPayload secondPayload;
        expect(
          () => secondPayload = controller.finish(
            completedAt: DateTime.utc(2026, 6, 14, 7, 3),
          ),
          returnsNormally,
        );

        expect(secondPayload.clientRunSessionId, 'double-finish-run');
        expect(
          secondPayload.clientRunSessionId,
          firstPayload.clientRunSessionId,
        );
        expect(secondPayload.startedAt, startedAt);
        expect(secondPayload.durationSeconds, firstPayload.durationSeconds);
        expect(secondPayload.distanceMeters, firstPayload.distanceMeters);
        expect(secondPayload.distanceMeters, 300);
        expect(
          secondPayload.avgPaceSecondsPerKm,
          firstPayload.avgPaceSecondsPerKm,
        );

        // The controller stays finished with its trusted-loop-free local
        // metrics intact.
        expect(controller.state.phase, RunTrackingPhase.finished);
        expect(controller.state.startedAt, startedAt);
        expect(controller.state.elapsedSeconds, 120);
        expect(controller.state.distanceMeters, 300);
      },
    );
  });
}

class _DiagnosticsRunCadenceProvider implements RunCadenceProvider {
  final _cadenceController = StreamController<RunCadenceSample>.broadcast();
  final _diagnosticsController =
      StreamController<RunCadenceDiagnostics>.broadcast();

  @override
  Stream<RunCadenceSample> get cadenceStream => _cadenceController.stream;

  @override
  Stream<RunCadenceDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  void emitDiagnostics(RunCadenceDiagnostics diagnostics) {
    _diagnosticsController.add(diagnostics);
  }

  Future<void> dispose() async {
    await _cadenceController.close();
    await _diagnosticsController.close();
  }
}

class _FakeForegroundAdapter implements ForegroundLocationAdapter {
  final _controller = StreamController<ForegroundPosition>.broadcast(
    sync: true,
  );
  _ForegroundPosition? currentPosition;

  void emit(_ForegroundPosition position) {
    _controller.add(position);
  }

  @override
  Future<ForegroundPosition> getCurrentPosition(
    LocationSettingsRequest settings,
  ) async {
    return currentPosition ??
        _ForegroundPosition(
          timestamp: DateTime.utc(2026, 6, 14, 7),
          latitude: 1.3,
          longitude: 103.8,
        );
  }

  @override
  Stream<ForegroundPosition> getPositionStream(
    LocationSettingsRequest settings,
  ) {
    return _controller.stream;
  }

  @override
  Future<RunTrackingLocationAccuracyStatus> getLocationAccuracyStatus() async {
    return RunTrackingLocationAccuracyStatus.precise;
  }
}

class _ForegroundPosition implements ForegroundPosition {
  const _ForegroundPosition({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });

  @override
  final DateTime timestamp;

  @override
  final double latitude;

  @override
  final double longitude;

  @override
  double? get altitude => null;

  @override
  final double? accuracy;

  @override
  double? get speed => null;
}
