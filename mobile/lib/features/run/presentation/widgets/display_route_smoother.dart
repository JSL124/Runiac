import '../../domain/models/run_location_sample.dart';

class DisplayRouteSmoother {
  const DisplayRouteSmoother._();

  static const double _cornerCutRatio = 0.25;

  static List<List<RunLocationSample>> smoothSegments(
    List<List<RunLocationSample>> segments,
  ) {
    return List<List<RunLocationSample>>.unmodifiable(
      segments.map(_smoothSegment),
    );
  }

  static List<RunLocationSample> _smoothSegment(
    List<RunLocationSample> segment,
  ) {
    if (segment.length <= 2) {
      return List<RunLocationSample>.unmodifiable(segment);
    }

    final smoothed = <RunLocationSample>[segment.first];
    for (var index = 1; index < segment.length - 1; index += 1) {
      final previous = segment[index - 1];
      final current = segment[index];
      final next = segment[index + 1];
      smoothed
        ..add(_interpolate(previous, current, 1 - _cornerCutRatio))
        ..add(_interpolate(current, next, _cornerCutRatio));
    }
    smoothed.add(segment.last);
    return List<RunLocationSample>.unmodifiable(smoothed);
  }

  static RunLocationSample _interpolate(
    RunLocationSample start,
    RunLocationSample end,
    double ratio,
  ) {
    return RunLocationSample(
      recordedAt: _interpolateTime(start.recordedAt, end.recordedAt, ratio),
      latitude: _lerp(start.latitude, end.latitude, ratio),
      longitude: _lerp(start.longitude, end.longitude, ratio),
      horizontalAccuracyMeters: _interpolateNullable(
        start.horizontalAccuracyMeters,
        end.horizontalAccuracyMeters,
        ratio,
      ),
      speedMetersPerSecond: _interpolateNullable(
        start.speedMetersPerSecond,
        end.speedMetersPerSecond,
        ratio,
      ),
    );
  }

  static DateTime _interpolateTime(DateTime start, DateTime end, double ratio) {
    final elapsedMicroseconds = end.difference(start).inMicroseconds;
    return start.add(
      Duration(microseconds: (elapsedMicroseconds * ratio).round()),
    );
  }

  static double _lerp(double start, double end, double ratio) {
    return start + (end - start) * ratio;
  }

  static double? _interpolateNullable(
    double? start,
    double? end,
    double ratio,
  ) {
    if (start == null || end == null || !start.isFinite || !end.isFinite) {
      return null;
    }
    return _lerp(start, end, ratio);
  }
}
