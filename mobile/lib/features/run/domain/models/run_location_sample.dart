class RunLocationSample {
  const RunLocationSample({
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.horizontalAccuracyMeters,
    this.speedMetersPerSecond,
  });

  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final double? horizontalAccuracyMeters;
  final double? speedMetersPerSecond;
}
