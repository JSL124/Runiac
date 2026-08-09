import 'dart:math' as math;

import '../models/run_location_sample.dart';

class RunDistanceCalculator {
  const RunDistanceCalculator();

  static const double earthRadiusMeters = 6371000;

  double distanceMeters(RunLocationSample from, RunLocationSample to) {
    if (!_hasFiniteCoordinates(from) || !_hasFiniteCoordinates(to)) {
      return double.nan;
    }

    final fromLatitude = _toRadians(from.latitude);
    final toLatitude = _toRadians(to.latitude);
    final latitudeDelta = _toRadians(to.latitude - from.latitude);
    final longitudeDelta = _toRadians(to.longitude - from.longitude);

    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(fromLatitude) *
            math.cos(toLatitude) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    final clampedHaversine = haversine.clamp(0, 1).toDouble();
    final angularDistance =
        2 *
        math.atan2(
          math.sqrt(clampedHaversine),
          math.sqrt(1 - clampedHaversine),
        );
    return earthRadiusMeters * angularDistance;
  }

  bool _hasFiniteCoordinates(RunLocationSample sample) {
    return sample.latitude.isFinite && sample.longitude.isFinite;
  }

  double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }
}
