import '../models/run_location_sample.dart';
import '../models/run_tracking_diagnostics.dart';

abstract interface class RunLocationProvider {
  RunTrackingLocationAccuracyStatus get locationAccuracyStatus;

  Future<void> start({required DateTime startedAt});

  Future<void> pause();

  Future<void> resume({
    required DateTime resumedAt,
    required Duration activeOffset,
  });

  Future<void> stop();

  Iterable<RunLocationSample> samplesBetween({
    required Duration fromActiveOffset,
    required Duration toActiveOffset,
    required DateTime startedAt,
  });
}

class RunLocationReplaySample {
  const RunLocationReplaySample({
    required this.activeOffset,
    required this.sample,
  });

  final Duration activeOffset;
  final RunLocationSample sample;
}

class ReplayRunLocationProvider implements RunLocationProvider {
  ReplayRunLocationProvider(
    Iterable<RunLocationReplaySample> samples, {
    this.locationAccuracyStatus = RunTrackingLocationAccuracyStatus.notChecked,
  }) : _samples = List<RunLocationReplaySample>.unmodifiable(
         samples.toList()..sort(
           (left, right) => left.activeOffset.compareTo(right.activeOffset),
         ),
       );

  @override
  final RunTrackingLocationAccuracyStatus locationAccuracyStatus;

  final List<RunLocationReplaySample> _samples;

  @override
  Future<void> start({required DateTime startedAt}) async {}

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
    return _samples
        .where(
          (entry) =>
              (entry.activeOffset >= fromActiveOffset &&
                  entry.activeOffset <= toActiveOffset) ||
              (fromActiveOffset == Duration.zero &&
                  entry.activeOffset == Duration.zero),
        )
        .map((entry) => entry.sample);
  }
}

class ConstantSpeedRunLocationProvider implements RunLocationProvider {
  const ConstantSpeedRunLocationProvider({required this.metersPerSecond});

  static const double _earthRadiusMeters = 6371000;
  static const double _degreesPerRadian = 180 / 3.141592653589793;
  static const double _startLatitude = 1.300000;
  static const double _startLongitude = 103.800000;

  final double metersPerSecond;

  @override
  RunTrackingLocationAccuracyStatus get locationAccuracyStatus =>
      RunTrackingLocationAccuracyStatus.notChecked;

  @override
  Future<void> start({required DateTime startedAt}) async {}

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
    if (toActiveOffset <= fromActiveOffset) {
      return const <RunLocationSample>[];
    }

    final samples = <RunLocationSample>[];
    samples.add(
      _sampleAt(startedAt: startedAt, activeOffset: fromActiveOffset),
    );
    samples.add(_sampleAt(startedAt: startedAt, activeOffset: toActiveOffset));
    return samples;
  }

  RunLocationSample _sampleAt({
    required DateTime startedAt,
    required Duration activeOffset,
  }) {
    final distanceMeters = activeOffset.inMilliseconds / 1000 * metersPerSecond;
    final latitudeDelta =
        distanceMeters / _earthRadiusMeters * _degreesPerRadian;
    return RunLocationSample(
      recordedAt: startedAt.add(activeOffset),
      latitude: _startLatitude + latitudeDelta,
      longitude: _startLongitude,
      horizontalAccuracyMeters: 5,
    );
  }
}
