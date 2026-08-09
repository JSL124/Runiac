import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/data/sensors_plus_run_motion_provider.dart';
import 'package:runiac_app/features/run/domain/models/run_motion_evidence.dart';

class _FakeMotionSensorAdapter implements RunMotionSensorAdapter {
  final StreamController<double> controller =
      StreamController<double>.broadcast();

  @override
  Stream<double> userAccelerationIntensities() => controller.stream;

  Future<void> emit(double intensity) async {
    controller.add(intensity);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> fail(Object error) async {
    controller.addError(error);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() => controller.close();
}

void main() {
  group('SensorsPlusRunMotionProvider', () {
    late _FakeMotionSensorAdapter adapter;
    late DateTime now;

    SensorsPlusRunMotionProvider provider() {
      return SensorsPlusRunMotionProvider(
        adapter: adapter,
        clock: () => now,
        minimumSamples: 3,
      );
    }

    setUp(() {
      adapter = _FakeMotionSensorAdapter();
      now = DateTime.utc(2026, 6, 14, 7);
    });

    tearDown(() async {
      await adapter.close();
    });

    test('smooths low intensity into stationary scalar evidence', () async {
      final motionProvider = provider();
      await motionProvider.start(startedAt: now);

      await adapter.emit(0.02);
      now = now.add(const Duration(milliseconds: 800));
      await adapter.emit(0.03);
      now = now.add(const Duration(milliseconds: 800));
      await adapter.emit(0.04);

      final evidence = motionProvider
          .evidenceBetween(
            fromTrackingOffset: Duration.zero,
            toTrackingOffset: const Duration(seconds: 2),
            startedAt: DateTime.utc(2026, 6, 14, 7),
          )
          .toList();

      expect(evidence.last.signal, RunMotionSignal.stationary);
      expect(evidence.last.confidence, inInclusiveRange(0, 1));
    });

    test('smooths high intensity into moving scalar evidence', () async {
      final motionProvider = provider();
      await motionProvider.start(startedAt: now);

      await adapter.emit(0.82);
      now = now.add(const Duration(milliseconds: 500));
      await adapter.emit(0.91);
      now = now.add(const Duration(milliseconds: 500));
      await adapter.emit(0.76);

      final evidence = motionProvider
          .evidenceBetween(
            fromTrackingOffset: Duration.zero,
            toTrackingOffset: const Duration(seconds: 2),
            startedAt: DateTime.utc(2026, 6, 14, 7),
          )
          .toList();

      expect(evidence.last.signal, RunMotionSignal.moving);
      expect(evidence.last.confidence, inInclusiveRange(0, 1));
    });

    test('emits unknown until the smoothing minimum is reached', () async {
      final motionProvider = provider();
      await motionProvider.start(startedAt: now);

      await adapter.emit(0.9);
      now = now.add(const Duration(milliseconds: 500));
      await adapter.emit(0.9);

      final evidence = motionProvider
          .evidenceBetween(
            fromTrackingOffset: Duration.zero,
            toTrackingOffset: const Duration(seconds: 1),
            startedAt: DateTime.utc(2026, 6, 14, 7),
          )
          .toList();

      expect(
        evidence.map((entry) => entry.signal),
        everyElement(RunMotionSignal.unknown),
      );
    });

    test('records unavailable evidence on sensor stream error', () async {
      final motionProvider = provider();
      await motionProvider.start(startedAt: now);

      await adapter.fail(StateError('sensor unavailable'));

      final evidence = motionProvider.evidenceBetween(
        fromTrackingOffset: Duration.zero,
        toTrackingOffset: const Duration(seconds: 1),
        startedAt: DateTime.utc(2026, 6, 14, 7),
      );

      expect(evidence.single.signal, RunMotionSignal.unavailable);
    });

    test('drains evidence once by tracking offset', () async {
      final motionProvider = provider();
      await motionProvider.start(startedAt: now);

      await adapter.emit(0.02);

      final firstRead = motionProvider
          .evidenceBetween(
            fromTrackingOffset: Duration.zero,
            toTrackingOffset: const Duration(seconds: 1),
            startedAt: DateTime.utc(2026, 6, 14, 7),
          )
          .toList();
      final secondRead = motionProvider
          .evidenceBetween(
            fromTrackingOffset: Duration.zero,
            toTrackingOffset: const Duration(seconds: 1),
            startedAt: DateTime.utc(2026, 6, 14, 7),
          )
          .toList();

      expect(firstRead, isNotEmpty);
      expect(secondRead, isEmpty);
    });

    test('manual pause cancels collection until resume', () async {
      final motionProvider = SensorsPlusRunMotionProvider(
        adapter: adapter,
        clock: () => now,
        minimumSamples: 1,
      );
      await motionProvider.start(startedAt: now);
      await motionProvider.pause();

      await adapter.emit(0.9);

      final pausedEvidence = motionProvider
          .evidenceBetween(
            fromTrackingOffset: Duration.zero,
            toTrackingOffset: const Duration(seconds: 1),
            startedAt: DateTime.utc(2026, 6, 14, 7),
          )
          .toList();
      expect(pausedEvidence, isEmpty);

      await motionProvider.resume(
        resumedAt: now,
        trackingOffset: Duration.zero,
      );
      await adapter.emit(0.9);

      final resumedEvidence = motionProvider
          .evidenceBetween(
            fromTrackingOffset: Duration.zero,
            toTrackingOffset: const Duration(seconds: 1),
            startedAt: DateTime.utc(2026, 6, 14, 7),
          )
          .toList();
      expect(resumedEvidence.single.signal, RunMotionSignal.moving);
      await motionProvider.stop();
    });
  });
}
