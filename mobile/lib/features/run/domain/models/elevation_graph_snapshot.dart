import 'elevation_analysis_series.dart';

enum ElevationDifficulty { mostlyFlat, rolling, hilly, unavailable }

class ElevationGraphSnapshot {
  const ElevationGraphSnapshot({
    required this.isAvailable,
    required this.points,
    required this.yAxisLabels,
    required this.xAxisLabels,
    this.unavailableReason,
    this.totalGainMeters,
    this.highestPointMeters,
    this.lowestPointMeters,
    this.difficulty = ElevationDifficulty.unavailable,
    this.unavailableDiagnosticReason = ElevationUnavailableReason.none,
  });

  const ElevationGraphSnapshot.unavailable({
    this.unavailableReason = 'insufficient_elevation_graph_data',
    this.unavailableDiagnosticReason =
        ElevationUnavailableReason.graphUnavailable,
  }) : isAvailable = false,
       points = const <ElevationGraphPoint>[],
       yAxisLabels = const <String>[],
       xAxisLabels = const <String>[],
       totalGainMeters = null,
       highestPointMeters = null,
       lowestPointMeters = null,
       difficulty = ElevationDifficulty.unavailable;

  final bool isAvailable;
  final List<ElevationGraphPoint> points;
  final List<String> yAxisLabels;
  final List<String> xAxisLabels;
  final String? unavailableReason;
  final double? totalGainMeters;
  final double? highestPointMeters;
  final double? lowestPointMeters;
  final ElevationDifficulty difficulty;
  final ElevationUnavailableReason unavailableDiagnosticReason;
}

class ElevationGraphPoint {
  const ElevationGraphPoint({
    required this.distanceKm,
    required this.elevationMeters,
  });

  final double distanceKm;
  final double elevationMeters;
}
