import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/domain/models/run_location_permission_status.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_diagnostics.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_state.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_permission_service.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_provider.dart';
import 'package:runiac_app/features/run/presentation/controllers/run_tracking_controller.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';

import 'support/fake_run_voice_coach.dart';

class _FakePermissionService implements RunLocationPermissionService {
  _FakePermissionService(this.status);

  RunLocationPermissionStatus status;

  @override
  Future<RunLocationPermissionStatus> checkStatus() async => status;

  @override
  Future<RunLocationPermissionStatus> requestPermission() async => status;
}

class _ThrowingStartLocationProvider implements RunLocationProvider {
  int startCount = 0;

  @override
  RunTrackingLocationAccuracyStatus get locationAccuracyStatus =>
      RunTrackingLocationAccuracyStatus.notChecked;

  @override
  Future<void> start({required DateTime startedAt}) async {
    startCount += 1;
    throw StateError('GPS provider failed to start');
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume({
    required DateTime resumedAt,
    required Duration activeOffset,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Iterable<RunLocationSample> samplesBetween({
    required Duration fromActiveOffset,
    required Duration toActiveOffset,
    required DateTime startedAt,
  }) {
    return const <RunLocationSample>[];
  }
}

RunVoiceSessionConfig _voiceConfig({required bool enabled}) {
  return RunVoiceSessionConfig(
    enabled: enabled,
    distanceIntervalMeters: 200,
    timeInterval: null,
    includeElapsedTime: true,
    includeAveragePace: true,
    language: RunVoiceLanguage.english,
    targetDistanceMeters: null,
  );
}

void main() {
  group('RunTrackingController voice coach integration', () {
    test('start() with an enabled voiceConfig starts the voice session', () {
      final fakeCoach = FakeRunVoiceCoach();
      final controller = RunTrackingController(
        metersPerSecond: 2.5,
        voiceCoach: fakeCoach,
      );
      final config = _voiceConfig(enabled: true);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-enabled-start',
        voiceConfig: config,
      );

      expect(fakeCoach.startCalls, 1);
      expect(fakeCoach.activeSessionCount, 1);
      expect(fakeCoach.lastConfig, config);
    });

    test(
      'start() with a disabled voiceConfig never starts the voice session',
      () {
        final fakeCoach = FakeRunVoiceCoach();
        final controller = RunTrackingController(
          metersPerSecond: 2.5,
          voiceCoach: fakeCoach,
        );

        controller.start(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'voice-disabled-start',
          voiceConfig: _voiceConfig(enabled: false),
        );

        expect(fakeCoach.startCalls, 0);
        expect(fakeCoach.activeSessionCount, 0);
      },
    );

    test(
      'requestStart() starts the voice session only after providers confirm start',
      () async {
        final fakeCoach = FakeRunVoiceCoach();
        final controller = RunTrackingController(
          metersPerSecond: 2.5,
          voiceCoach: fakeCoach,
          permissionService: _FakePermissionService(
            RunLocationPermissionStatus.granted,
          ),
        );

        final started = await controller.requestStart(
          startedAt: DateTime.utc(2026, 6, 14, 7),
          clientRunSessionId: 'voice-request-start',
          voiceConfig: _voiceConfig(enabled: true),
        );

        expect(started, isTrue);
        expect(fakeCoach.startCalls, 1);
        expect(fakeCoach.activeSessionCount, 1);
      },
    );

    test('advanceBy publishes snapshots that carry the accepted distance', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final fakeCoach = FakeRunVoiceCoach();
      final provider = ReplayRunLocationProvider([
        RunLocationReplaySample(
          activeOffset: Duration.zero,
          sample: RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300000,
            longitude: 103.800000,
          ),
        ),
        RunLocationReplaySample(
          activeOffset: const Duration(seconds: 120),
          sample: RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 120)),
            latitude: 1.302698,
            longitude: 103.800000,
          ),
        ),
      ]);
      final controller = RunTrackingController(
        locationProvider: provider,
        voiceCoach: fakeCoach,
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'voice-accepted-distance',
        voiceConfig: _voiceConfig(enabled: true),
      );
      controller.advanceBy(const Duration(seconds: 120));

      expect(fakeCoach.snapshots, isNotEmpty);
      expect(
        fakeCoach.snapshots.last.distanceMeters,
        controller.state.distanceMeters,
      );
    });

    test('pause() publishes a paused, inactive snapshot', () {
      final fakeCoach = FakeRunVoiceCoach();
      final controller = RunTrackingController(
        metersPerSecond: 2.5,
        voiceCoach: fakeCoach,
      );

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-pause-snapshot',
        voiceConfig: _voiceConfig(enabled: true),
      );
      controller.advanceBy(const Duration(seconds: 60));
      controller.pause();

      expect(fakeCoach.snapshots, isNotEmpty);
      expect(fakeCoach.snapshots.last.isPaused, isTrue);
      expect(fakeCoach.snapshots.last.isActive, isFalse);
    });

    test('finish() stops the voice session', () {
      final fakeCoach = FakeRunVoiceCoach();
      final controller = RunTrackingController(
        metersPerSecond: 2.5,
        voiceCoach: fakeCoach,
      );

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-finish-stop',
        voiceConfig: _voiceConfig(enabled: true),
      );
      controller.advanceBy(const Duration(seconds: 60));
      controller.finish(completedAt: DateTime.utc(2026, 6, 14, 7, 1));

      expect(fakeCoach.stopCalls, greaterThanOrEqualTo(1));
      expect(fakeCoach.activeSessionCount, 0);
    });

    test('voice snapshot failures never break the run (isolation)', () async {
      final fakeCoach = FakeRunVoiceCoach()..throwOnSnapshot = true;
      final controller = RunTrackingController(
        metersPerSecond: 2.5,
        voiceCoach: fakeCoach,
      );

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-isolation-run',
        voiceConfig: _voiceConfig(enabled: true),
      );
      controller.advanceBy(const Duration(seconds: 60));
      final payload = controller.finish(
        completedAt: DateTime.utc(2026, 6, 14, 7, 1),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, RunTrackingPhase.finished);
      expect(payload.clientRunSessionId, 'voice-isolation-run');
    });

    test('failed provider start never leaves a voice session active', () async {
      final provider = _ThrowingStartLocationProvider();
      final fakeCoach = FakeRunVoiceCoach();
      final controller = RunTrackingController(
        locationProvider: provider,
        voiceCoach: fakeCoach,
        permissionService: _FakePermissionService(
          RunLocationPermissionStatus.granted,
        ),
      );

      final started = await controller.requestStart(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-failed-provider-start',
        voiceConfig: _voiceConfig(enabled: true),
      );

      expect(started, isFalse);
      expect(fakeCoach.startCalls, 0);
      expect(fakeCoach.activeSessionCount, 0);
    });
  });
}
