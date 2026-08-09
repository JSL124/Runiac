import '../models/cadence_analysis_series.dart';
import '../models/cadence_graph_snapshot.dart';

const minVisibleCadenceRangeSpm = 20;
const cadenceGraphRangePaddingSpm = 4;

/// Builds the plotted cadence graph from a cadence series.
///
/// The counterpart to [PaceGraphDataBuilder], with one extra job: cadence is
/// only trustworthy from some sources, so [build] refuses up front for a series
/// whose origin cannot support a graph and returns an unavailable snapshot with
/// a machine-readable reason instead of a half-drawn line.
class CadenceGraphDataBuilder {
  const CadenceGraphDataBuilder();

  CadenceGraphSnapshot build({
    required CadenceAnalysisSeries series,
    required int durationSeconds,
  }) {
    if (durationSeconds <= 0) {
      return const CadenceGraphSnapshot.unavailable(
        unavailableReason: 'invalid_cadence_graph_duration',
      );
    }

    final sourceReason = _unavailableReasonForSource(series);
    if (sourceReason != null) {
      return CadenceGraphSnapshot.unavailable(unavailableReason: sourceReason);
    }

    final validSamples = series.validAcceptedSamples;
    if (validSamples.length < defaultMinimumCadenceAnalysisSamples) {
      return const CadenceGraphSnapshot.unavailable(
        unavailableReason: 'insufficient_cadence_graph_samples',
      );
    }

    if (!_hasStrictlyIncreasingElapsed(validSamples)) {
      return const CadenceGraphSnapshot.unavailable(
        unavailableReason: 'non_monotonic_cadence_graph_samples',
      );
    }

    final graphSamples = validSamples
        .where((sample) => sample.elapsedSeconds <= durationSeconds)
        .toList(growable: false);
    if (graphSamples.length < defaultMinimumCadenceAnalysisSamples) {
      return const CadenceGraphSnapshot.unavailable(
        unavailableReason: 'insufficient_in_duration_cadence_graph_samples',
      );
    }

    final cadenceValues = graphSamples
        .map((sample) => sample.cadenceSpm!)
        .toList(growable: false);
    final lowestCadence = cadenceValues.reduce((a, b) => a < b ? a : b);
    final highestCadence = cadenceValues.reduce((a, b) => a > b ? a : b);
    final cadenceRange = _cadenceAxisRange(
      lowestCadence: lowestCadence,
      highestCadence: highestCadence,
    );
    final points = graphSamples
        .map((sample) {
          final cadenceSpm = sample.cadenceSpm!;
          return CadenceGraphPoint(
            elapsedSeconds: sample.elapsedSeconds,
            progressFraction: sample.elapsedSeconds / durationSeconds,
            cadenceSpm: cadenceSpm,
            displayLabel: '$cadenceSpm spm',
          );
        })
        .toList(growable: false);

    final lowestCadencePoint = points.reduce(
      (a, b) => a.cadenceSpm <= b.cadenceSpm ? a : b,
    );
    final highestCadencePoint = points.reduce(
      (a, b) => a.cadenceSpm >= b.cadenceSpm ? a : b,
    );

    return CadenceGraphSnapshot(
      isAvailable: true,
      points: points,
      yAxisLabels: _cadenceAxisLabels(cadenceRange),
      xAxisLabels: _timeAxisLabels(durationSeconds),
      totalDurationSeconds: durationSeconds,
      averageCadenceSpm: _average(cadenceValues),
      lowestCadencePoint: lowestCadencePoint,
      highestCadencePoint: highestCadencePoint,
      cadenceRangeMinSpm: cadenceRange.minSpm,
      cadenceRangeMaxSpm: cadenceRange.maxSpm,
      targetMinCadenceSpm: demoCadenceGraphTargetMinSpm,
      targetMaxCadenceSpm: demoCadenceGraphTargetMaxSpm,
      targetLabel: demoCadenceGraphTargetLabel,
      targetKind: CadenceGraphTargetKind.demo,
    );
  }

  String? _unavailableReasonForSource(CadenceAnalysisSeries series) {
    if (series.isStaticDemoSource) {
      return 'static_demo_cadence_graph';
    }
    if (series.isUnavailable) {
      return 'unavailable_cadence_source';
    }
    if (!series.isProductionAnalysisEligible) {
      return 'ineligible_cadence_source';
    }
    return null;
  }

  bool _hasStrictlyIncreasingElapsed(List<CadenceAnalysisSample> samples) {
    int? previousElapsedSeconds;
    for (final sample in samples) {
      final elapsedSeconds = sample.elapsedSeconds;
      if (previousElapsedSeconds != null &&
          elapsedSeconds <= previousElapsedSeconds) {
        return false;
      }
      previousElapsedSeconds = elapsedSeconds;
    }
    return true;
  }

  int _average(List<int> cadenceValues) {
    return (cadenceValues.reduce((a, b) => a + b) / cadenceValues.length)
        .round();
  }

  _CadenceAxisRange _cadenceAxisRange({
    required int lowestCadence,
    required int highestCadence,
  }) {
    final sampleRangeMin = _roundDownToTen(
      lowestCadence - cadenceGraphRangePaddingSpm,
    );
    final sampleRangeMax = _roundUpToTen(
      highestCadence + cadenceGraphRangePaddingSpm,
    );
    final targetRangeMin = _roundDownToTen(demoCadenceGraphTargetMinSpm);
    final targetRangeMax = _roundUpToTen(demoCadenceGraphTargetMaxSpm);
    var rangeMin = sampleRangeMin < targetRangeMin
        ? sampleRangeMin
        : targetRangeMin;
    var rangeMax = sampleRangeMax > targetRangeMax
        ? sampleRangeMax
        : targetRangeMax;

    if (rangeMax - rangeMin < minVisibleCadenceRangeSpm) {
      final midpoint = ((rangeMin + rangeMax) / 2).round();
      rangeMin = _roundDownToTen(midpoint - (minVisibleCadenceRangeSpm ~/ 2));
      rangeMax = _roundUpToTen(rangeMin + minVisibleCadenceRangeSpm);
      if (rangeMax - rangeMin < minVisibleCadenceRangeSpm) {
        rangeMin = _roundDownToTen(rangeMax - minVisibleCadenceRangeSpm);
      }
    }

    return _CadenceAxisRange(minSpm: rangeMin, maxSpm: rangeMax);
  }

  List<String> _cadenceAxisLabels(_CadenceAxisRange cadenceRange) {
    final midpoint = ((cadenceRange.minSpm + cadenceRange.maxSpm) / 2).round();
    return <String>[
      cadenceRange.minSpm.toString(),
      midpoint.toString(),
      cadenceRange.maxSpm.toString(),
    ];
  }

  List<String> _timeAxisLabels(int durationSeconds) {
    if (durationSeconds < 900) {
      return <String>[
        _formatTime(0),
        _formatTime(_roundDownToMinute(durationSeconds ~/ 2)),
        _formatTime(durationSeconds),
      ];
    }

    return <String>[
      _formatTime(0),
      _formatTime(_roundDownToMinute(durationSeconds ~/ 3)),
      _formatTime(_roundDownToMinute((durationSeconds * 2) ~/ 3)),
      _formatTime(durationSeconds),
    ];
  }

  int _roundDownToTen(int value) {
    final safeValue = value < minCadenceAnalysisSpm
        ? minCadenceAnalysisSpm
        : value;
    return safeValue - (safeValue % 10);
  }

  int _roundUpToTen(int value) {
    final safeValue = value > maxCadenceAnalysisSpm
        ? maxCadenceAnalysisSpm
        : value;
    final remainder = safeValue % 10;
    return remainder == 0 ? safeValue : safeValue + (10 - remainder);
  }

  int _roundDownToMinute(int value) {
    return value - (value % 60);
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _CadenceAxisRange {
  const _CadenceAxisRange({required this.minSpm, required this.maxSpm});

  final int minSpm;
  final int maxSpm;
}
