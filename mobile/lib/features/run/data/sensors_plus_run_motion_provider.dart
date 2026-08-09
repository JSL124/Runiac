import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../domain/models/run_motion_evidence.dart';
import '../domain/repositories/run_motion_provider.dart';

typedef RunMotionClock = DateTime Function();

abstract interface class RunMotionSensorAdapter {
  Stream<double> userAccelerationIntensities();
}

class SensorsPlusMotionSensorAdapter implements RunMotionSensorAdapter {
  const SensorsPlusMotionSensorAdapter();

  @override
  Stream<double> userAccelerationIntensities() {
    return userAccelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).map(
      (event) =>
          math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z),
    );
  }
}

/// Supplies accelerometer evidence that the runner is actually moving.
///
/// GPS alone cannot tell "standing still at a crossing" from "GPS drifting
/// around a stationary phone", so auto-pause needs a second opinion. This
/// provider reduces the raw accelerometer stream to a coarse intensity signal
/// that [RunMovementClassifier] weighs alongside the GPS verdict.
///
/// The clock and the sensor adapter are both injectable — motion tests replay a
/// fixed intensity sequence against a fake clock.
class SensorsPlusRunMotionProvider implements RunMotionProvider {
  SensorsPlusRunMotionProvider({
    this.adapter = const SensorsPlusMotionSensorAdapter(),
    RunMotionClock? clock,
    this.smoothingWindow = const Duration(seconds: 2),
    this.minimumSamples = 3,
    this.stationaryIntensityThreshold = 0.12,
    this.movingIntensityThreshold = 0.45,
  }) : _clock = clock ?? DateTime.now {
    if (smoothingWindow <= Duration.zero) {
      throw ArgumentError.value(
        smoothingWindow,
        'smoothingWindow',
        'must be positive',
      );
    }
    if (minimumSamples < 1) {
      throw ArgumentError.value(
        minimumSamples,
        'minimumSamples',
        'must be at least 1',
      );
    }
    if (stationaryIntensityThreshold < 0 ||
        movingIntensityThreshold <= stationaryIntensityThreshold) {
      throw ArgumentError(
        'movingIntensityThreshold must be greater than '
        'stationaryIntensityThreshold',
      );
    }
  }

  final RunMotionSensorAdapter adapter;
  final RunMotionClock _clock;
  final Duration smoothingWindow;
  final int minimumSamples;
  final double stationaryIntensityThreshold;
  final double movingIntensityThreshold;

  final List<_MotionIntensitySample> _smoothingSamples =
      <_MotionIntensitySample>[];
  final List<RunMotionEvidence> _bufferedEvidence = <RunMotionEvidence>[];
  StreamSubscription<double>? _subscription;
  DateTime? _startedAt;

  @override
  Future<void> start({required DateTime startedAt}) async {
    await stop();
    _startedAt = startedAt;
    _listen();
  }

  @override
  Future<void> pause() async {
    await _cancelSubscription();
    _smoothingSamples.clear();
  }

  @override
  Future<void> resume({
    required DateTime resumedAt,
    required Duration trackingOffset,
  }) async {
    _startedAt ??= resumedAt.subtract(trackingOffset);
    _smoothingSamples.clear();
    _listen();
  }

  @override
  Future<void> stop() async {
    await _cancelSubscription();
    _startedAt = null;
    _smoothingSamples.clear();
    _bufferedEvidence.clear();
  }

  @override
  Iterable<RunMotionEvidence> evidenceBetween({
    required Duration fromTrackingOffset,
    required Duration toTrackingOffset,
    required DateTime startedAt,
  }) {
    final from = startedAt.add(fromTrackingOffset);
    final to = startedAt.add(toTrackingOffset);
    final evidence = _bufferedEvidence
        .where(
          (sample) =>
              !sample.recordedAt.isBefore(from) &&
              !sample.recordedAt.isAfter(to),
        )
        .toList(growable: false);
    _bufferedEvidence.removeWhere((sample) => !sample.recordedAt.isAfter(to));
    return evidence;
  }

  void _listen() {
    if (_subscription != null) {
      return;
    }
    _subscription = adapter.userAccelerationIntensities().listen(
      _recordIntensity,
      onError: (_, _) => _recordUnavailable(),
      cancelOnError: true,
    );
  }

  void _recordIntensity(double intensity) {
    final recordedAt = _clock();
    _smoothingSamples.add(
      _MotionIntensitySample(recordedAt: recordedAt, intensity: intensity),
    );
    _smoothingSamples.removeWhere(
      (entry) => recordedAt.difference(entry.recordedAt) > smoothingWindow,
    );

    if (_smoothingSamples.length < minimumSamples) {
      _bufferedEvidence.add(
        RunMotionEvidence(
          recordedAt: recordedAt,
          signal: RunMotionSignal.unknown,
          confidence: 0,
        ),
      );
      return;
    }

    final smoothedIntensity =
        _smoothingSamples.fold<double>(
          0,
          (sum, entry) => sum + entry.intensity,
        ) /
        _smoothingSamples.length;
    _bufferedEvidence.add(
      RunMotionEvidence(
        recordedAt: recordedAt,
        signal: _signalFor(smoothedIntensity),
        confidence: _confidenceFor(smoothedIntensity),
      ),
    );
  }

  RunMotionSignal _signalFor(double smoothedIntensity) {
    if (smoothedIntensity <= stationaryIntensityThreshold) {
      return RunMotionSignal.stationary;
    }
    if (smoothedIntensity >= movingIntensityThreshold) {
      return RunMotionSignal.moving;
    }
    return RunMotionSignal.unknown;
  }

  double _confidenceFor(double smoothedIntensity) {
    final confidenceRange =
        movingIntensityThreshold - stationaryIntensityThreshold;
    if (smoothedIntensity <= stationaryIntensityThreshold) {
      return ((stationaryIntensityThreshold - smoothedIntensity) /
              stationaryIntensityThreshold)
          .clamp(0, 1)
          .toDouble();
    }
    if (smoothedIntensity >= movingIntensityThreshold) {
      return ((smoothedIntensity - movingIntensityThreshold) / confidenceRange)
          .clamp(0, 1)
          .toDouble();
    }
    return ((smoothedIntensity - stationaryIntensityThreshold) /
            confidenceRange)
        .clamp(0, 1)
        .toDouble();
  }

  void _recordUnavailable() {
    _bufferedEvidence.add(
      RunMotionEvidence(
        recordedAt: _clock(),
        signal: RunMotionSignal.unavailable,
        confidence: 0,
      ),
    );
  }

  Future<void> _cancelSubscription() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}

class _MotionIntensitySample {
  const _MotionIntensitySample({
    required this.recordedAt,
    required this.intensity,
  });

  final DateTime recordedAt;
  final double intensity;
}
