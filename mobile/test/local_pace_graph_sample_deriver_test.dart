import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/services/local_pace_graph_sample_deriver.dart';
import 'package:runiac_app/features/run/domain/services/pace_graph_data_builder.dart';

void main() {
  group('LocalPaceGraphSampleDeriver', () {
    const deriver = LocalPaceGraphSampleDeriver();

    test('derives graph-safe samples from accepted segment paces', () {
      final startedAt = DateTime.utc(2026, 6, 18, 8);
      final samples = deriver.derive(
        startedAt: startedAt,
        acceptedSampleSegments: [
          [
            _sampleAt(startedAt, 0, latitude: 1.300000),
            _sampleAt(startedAt, 60, latitude: 1.301349),
            _sampleAt(startedAt, 120, latitude: 1.302698),
            _sampleAt(startedAt, 180, latitude: 1.304047),
          ],
        ],
      );

      expect(samples.map((sample) => sample.elapsedSeconds), [60, 120, 180]);
      expect(
        samples.map((sample) => sample.paceSecondsPerKm),
        everyElement(closeTo(400, 2)),
      );
    });

    test('derives graph elapsed from active sample metadata', () {
      final startedAt = DateTime.utc(2026, 6, 18, 8);
      final resumedAt = startedAt.add(const Duration(minutes: 15));
      final samples = deriver.deriveFromActiveElapsedSegments(
        acceptedSampleSegments: [
          [
            (
              sample: _sampleAt(startedAt, 0, latitude: 1.300000),
              activeElapsedSeconds: 0,
            ),
            (
              sample: _sampleAt(startedAt, 60, latitude: 1.301349),
              activeElapsedSeconds: 60,
            ),
            (
              sample: _sampleAt(startedAt, 120, latitude: 1.302698),
              activeElapsedSeconds: 120,
            ),
          ],
          [
            (
              sample: _sampleAt(resumedAt, 0, latitude: 1.400000),
              activeElapsedSeconds: 180,
            ),
            (
              sample: _sampleAt(resumedAt, 60, latitude: 1.401349),
              activeElapsedSeconds: 240,
            ),
            (
              sample: _sampleAt(resumedAt, 120, latitude: 1.402698),
              activeElapsedSeconds: 300,
            ),
          ],
        ],
      );

      expect(samples.map((sample) => sample.elapsedSeconds), [
        60,
        120,
        240,
        300,
      ]);
      expect(
        samples.map((sample) => sample.paceSecondsPerKm),
        everyElement(closeTo(400, 2)),
      );
    });

    test('does not bridge separate accepted route segments', () {
      final startedAt = DateTime.utc(2026, 6, 18, 8);
      final samples = deriver.derive(
        startedAt: startedAt,
        acceptedSampleSegments: [
          [
            _sampleAt(startedAt, 0, latitude: 1.300000),
            _sampleAt(startedAt, 60, latitude: 1.301349),
          ],
          [
            _sampleAt(startedAt, 600, latitude: 1.500000),
            _sampleAt(startedAt, 660, latitude: 1.501349),
          ],
        ],
      );

      expect(samples.map((sample) => sample.elapsedSeconds), [60, 660]);
      expect(
        samples.map((sample) => sample.paceSecondsPerKm),
        everyElement(closeTo(400, 2)),
      );
    });

    test('rejects invalid noisy samples before graph building', () {
      final startedAt = DateTime.utc(2026, 6, 18, 8);
      final samples = deriver.derive(
        startedAt: startedAt,
        acceptedSampleSegments: [
          [
            _sampleAt(startedAt, 40, latitude: 1.300000),
            _sampleAt(startedAt, 100, latitude: 1.301349),
          ],
          [
            _sampleAt(startedAt, 30, latitude: 1.400000),
            _sampleAt(startedAt, 90, latitude: 1.401349),
          ],
          [
            _sampleAt(startedAt, 110, latitude: 1.500000),
            _sampleAt(startedAt, 110, latitude: 1.501349),
          ],
          [
            _sampleAt(startedAt, 120, latitude: 1.600000),
            _sampleAt(startedAt, 180, latitude: 1.600000),
          ],
          [
            _sampleAt(startedAt, 190, latitude: 1.700000),
            _sampleAt(startedAt, 250, latitude: double.nan),
          ],
          [
            _sampleAt(startedAt, 260, latitude: 1.800000),
            _sampleAt(startedAt, 261, latitude: 1.801349),
          ],
          [
            _sampleAt(startedAt, 300, latitude: 1.900000),
            _sampleAt(startedAt, 600, latitude: 1.900090),
          ],
        ],
      );

      expect(samples.map((sample) => sample.elapsedSeconds), [100]);
      expect(samples.single.paceSecondsPerKm, closeTo(400, 2));
    });

    test('uses distance and time instead of reported speed', () {
      final startedAt = DateTime.utc(2026, 6, 18, 8);
      final samples = deriver.derive(
        startedAt: startedAt,
        acceptedSampleSegments: [
          [
            _sampleAt(
              startedAt,
              0,
              latitude: 1.300000,
              speedMetersPerSecond: 15,
            ),
            _sampleAt(
              startedAt,
              60,
              latitude: 1.301349,
              speedMetersPerSecond: 15,
            ),
          ],
        ],
      );

      expect(samples.single.paceSecondsPerKm, closeTo(400, 2));
      expect(samples.single.paceSecondsPerKm, isNot(closeTo(67, 2)));
    });

    test('returns only PaceGraphSample graph values', () {
      final startedAt = DateTime.utc(2026, 6, 18, 8);
      final samples = deriver.derive(
        startedAt: startedAt,
        acceptedSampleSegments: [
          [
            _sampleAt(startedAt, 0, latitude: 1.300000),
            _sampleAt(startedAt, 60, latitude: 1.301349),
          ],
        ],
      );

      final PaceGraphSample graphSample = samples.single;
      expect(graphSample.elapsedSeconds, 60);
      expect(graphSample.paceSecondsPerKm, closeTo(400, 2));
    });
  });
}

RunLocationSample _sampleAt(
  DateTime startedAt,
  int elapsedSeconds, {
  required double latitude,
  double longitude = 103.8,
  double? speedMetersPerSecond,
}) {
  return RunLocationSample(
    recordedAt: startedAt.add(Duration(seconds: elapsedSeconds)),
    latitude: latitude,
    longitude: longitude,
    speedMetersPerSecond: speedMetersPerSecond,
  );
}
