import '../models/elevation_analysis_series.dart';
import '../models/elevation_graph_snapshot.dart';

class ElevationAnalysisGraphBuilder {
  const ElevationAnalysisGraphBuilder();

  ElevationGraphSnapshot build(ElevationAnalysisSeries series) {
    final sourceReason = _unavailableReasonForSource(series);
    if (sourceReason != null) {
      return ElevationGraphSnapshot.unavailable(
        unavailableReason: sourceReason.label,
        unavailableDiagnosticReason: sourceReason.reason,
      );
    }

    final validSamples = series.validSamples;
    if (validSamples.length < defaultMinimumElevationAnalysisSamples) {
      return const ElevationGraphSnapshot.unavailable(
        unavailableDiagnosticReason:
            ElevationUnavailableReason.tooFewValidAltitudeSamples,
      );
    }
    if (!_hasStrictlyIncreasingDistance(validSamples)) {
      return const ElevationGraphSnapshot.unavailable(
        unavailableReason: 'non_increasing_elevation_distance',
        unavailableDiagnosticReason:
            ElevationUnavailableReason.nonIncreasingDistance,
      );
    }

    final points = validSamples
        .map(
          (sample) => ElevationGraphPoint(
            distanceKm: sample.distanceKm,
            elevationMeters: sample.elevationMeters,
          ),
        )
        .toList(growable: false);
    final elevations = points
        .map((point) => point.elevationMeters)
        .toList(growable: false);
    final lowestPointMeters = elevations.reduce((a, b) => a < b ? a : b);
    final highestPointMeters = elevations.reduce((a, b) => a > b ? a : b);
    final totalGainMeters = _totalGainMeters(points);
    final totalDistanceKm = points.last.distanceKm - points.first.distanceKm;
    final difficulty = _difficulty(
      totalGainMeters: totalGainMeters,
      totalDistanceKm: totalDistanceKm,
      elevationRangeMeters: highestPointMeters - lowestPointMeters,
    );

    return ElevationGraphSnapshot(
      isAvailable: true,
      points: points,
      yAxisLabels: [
        '${highestPointMeters.round()} m',
        '${lowestPointMeters.round()} m',
      ],
      xAxisLabels: _distanceAxisLabels(points.last.distanceKm),
      totalGainMeters: totalGainMeters,
      highestPointMeters: highestPointMeters,
      lowestPointMeters: lowestPointMeters,
      difficulty: difficulty,
    );
  }

  _ElevationGraphUnavailableSourceReason? _unavailableReasonForSource(
    ElevationAnalysisSeries series,
  ) {
    if (series.isStaticDemoSource) {
      return const _ElevationGraphUnavailableSourceReason(
        label: 'static_demo_elevation_graph',
        reason: ElevationUnavailableReason.graphUnavailable,
      );
    }
    if (series.isUnavailable) {
      return _ElevationGraphUnavailableSourceReason(
        label: 'unavailable_elevation_source',
        reason: series.unavailableReason,
      );
    }
    if (!series.isProductionAnalysisEligible) {
      return const _ElevationGraphUnavailableSourceReason(
        label: 'ineligible_elevation_source',
        reason: ElevationUnavailableReason.graphUnavailable,
      );
    }
    return null;
  }

  bool _hasStrictlyIncreasingDistance(List<ElevationAnalysisSample> samples) {
    double? previousDistanceKm;
    for (final sample in samples) {
      if (previousDistanceKm != null &&
          sample.distanceKm <= previousDistanceKm) {
        return false;
      }
      previousDistanceKm = sample.distanceKm;
    }
    return true;
  }

  double _totalGainMeters(List<ElevationGraphPoint> points) {
    var gain = 0.0;
    for (var index = 1; index < points.length; index += 1) {
      final delta =
          points[index].elevationMeters - points[index - 1].elevationMeters;
      if (delta >= elevationGainNoiseThresholdMeters) {
        gain += delta;
      }
    }
    return gain;
  }

  ElevationDifficulty _difficulty({
    required double totalGainMeters,
    required double totalDistanceKm,
    required double elevationRangeMeters,
  }) {
    if (totalDistanceKm <= 0) {
      return ElevationDifficulty.unavailable;
    }
    final gainPerKm = totalGainMeters / totalDistanceKm;
    if (gainPerKm >= 25 || elevationRangeMeters >= 35) {
      return ElevationDifficulty.hilly;
    }
    if (gainPerKm >= 10 || elevationRangeMeters >= 15) {
      return ElevationDifficulty.rolling;
    }
    return ElevationDifficulty.mostlyFlat;
  }

  List<String> _distanceAxisLabels(double totalDistanceKm) {
    final midpointKm = totalDistanceKm / 2;
    return <String>[
      '0 km',
      '${_formatAxisDistance(midpointKm)} km',
      '${_formatAxisDistance(totalDistanceKm)} km',
    ];
  }

  String _formatAxisDistance(double distanceKm) {
    if (distanceKm == distanceKm.roundToDouble()) {
      return distanceKm.round().toString();
    }
    return distanceKm.toStringAsFixed(1);
  }
}

class _ElevationGraphUnavailableSourceReason {
  const _ElevationGraphUnavailableSourceReason({
    required this.label,
    required this.reason,
  });

  final String label;
  final ElevationUnavailableReason reason;
}
