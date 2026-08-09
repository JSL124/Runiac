import '../models/advanced_analysis_snapshot.dart';
import '../models/run_source_display.dart';
import '../models/run_summary_snapshot.dart';

class ActivityFeedbackPayloadException implements Exception {
  const ActivityFeedbackPayloadException(this.message);

  final String message;

  @override
  String toString() => 'ActivityFeedbackPayloadException: $message';
}

/// Packs a finished run into the request body for the AI activity-feedback
/// callable.
///
/// The build deliberately throws rather than degrading: demo/imported runs are
/// rejected here, at the client, so a fabricated run can never reach the agent
/// and come back as personalised advice the runner did not earn. Treat the
/// exception as a programming error at the call site, not a user-facing state.
class ActivityFeedbackPayloadBuilder {
  const ActivityFeedbackPayloadBuilder();

  Map<String, Object?> build({
    required RunSummarySnapshot summary,
    required AdvancedAnalysisSnapshot analysis,
  }) {
    if (summary.sourceType == RunSourceType.demoImport) {
      throw const ActivityFeedbackPayloadException(
        'Demo-only activity summaries must not be sent to the feedback agent.',
      );
    }

    final payload = <String, Object?>{
      'schemaVersion': 1,
      'summary': <String, Object?>{
        'distanceKm': _distanceKm(summary.distanceKm),
        'durationSeconds': _durationSeconds(summary.duration),
        'averagePaceSecondsPerKm': _paceSecondsPerKm(summary.avgPace),
        ...?_optional('caloriesKcal', _caloriesKcal(summary.calories)),
        'sourceLabel': _sourceLabel(summary.sourceType),
      },
    };

    final performance = _performance(analysis.performance);
    if (performance.isNotEmpty) payload['performance'] = performance;

    final pace = _pace(summary, analysis.pace);
    if (pace.isNotEmpty) payload['pace'] = pace;

    final cadence = _cadence(analysis.formCadence);
    if (cadence.isNotEmpty) payload['cadence'] = cadence;

    final elevation = _elevation(analysis.elevation);
    if (elevation.isNotEmpty) payload['elevation'] = elevation;

    return payload;
  }

  Map<String, Object?> _performance(
    AdvancedAnalysisPerformanceOverview performance,
  ) {
    return <String, Object?>{
      ...?_optional('score', performance.score.value),
      'qualityLabel': performance.qualityLabel,
      'takeaway': performance.takeaway,
      'nextFocus': performance.nextFocus,
      'scoreConfidenceLabel': performance.scoreConfidenceLabel,
    };
  }

  Map<String, Object?> _pace(
    RunSummarySnapshot summary,
    AdvancedAnalysisPaceAnalysis pace,
  ) {
    final analysisSplits = pace.splits.value
        ?.take(24)
        .map(_split)
        .toList(growable: false);
    final sampleSplits = _paceSampleSplits(summary);
    return <String, Object?>{
      ...?_optional(
        'fastestPaceSecondsPerKm',
        _paceSecondsPerKm(pace.fastestPace.valueLabel),
      ),
      ...?_optional(
        'slowestPaceSecondsPerKm',
        _paceSecondsPerKm(pace.slowestPace.valueLabel),
      ),
      ...?_optional('stabilityLabel', pace.paceStability.valueLabel),
      if ((analysisSplits?.isNotEmpty ?? false))
        'splits': analysisSplits
      else if (sampleSplits.isNotEmpty)
        'splits': sampleSplits,
    };
  }

  Map<String, Object?> _split(AdvancedAnalysisSplitSnapshot split) {
    return <String, Object?>{
      'distanceKm': _splitDistanceKm(split.distanceLabel),
      'paceSecondsPerKm': split.paceSecondsPerKm,
      'isPartial': split.isPartial,
      ...?_optional('elevationMeters', _meters(split.elevationLabel)),
    };
  }

  Map<String, Object?> _cadence(AdvancedAnalysisFormCadenceAnalysis cadence) {
    final isEstimated =
        cadence.averageCadence.confidence ==
        AdvancedAnalysisMetricConfidence.estimated;
    return <String, Object?>{
      ...?_optional('averageSpm', _spm(cadence.averageCadence.valueLabel)),
      ...?_optional('status', cadence.cadenceStatus.valueLabel),
      ...?_optional('strideConsistency', cadence.strideConsistency.valueLabel),
      if (isEstimated) ...<String, Object?>{
        'isEstimated': true,
        'confidence': cadence.averageCadence.confidence.name,
        'sourceReason':
            cadence.averageCadence.reason == AdvancedAnalysisMetricReason.none
            ? AdvancedAnalysisMetricReason.estimatedFromPhoneSensors.name
            : cadence.averageCadence.reason.name,
      },
    };
  }

  Map<String, Object?> _elevation(AdvancedAnalysisElevationAnalysis elevation) {
    return <String, Object?>{
      ...?_optional('totalGainMeters', _meters(elevation.totalGain.valueLabel)),
      ...?_optional(
        'highestPointMeters',
        _meters(elevation.highestPoint.valueLabel),
      ),
      ...?_optional(
        'lowestPointMeters',
        _meters(elevation.lowestPoint.valueLabel),
      ),
      ...?_optional('difficulty', elevation.routeDifficulty.valueLabel),
    };
  }

  String _sourceLabel(RunSourceType sourceType) {
    return switch (sourceType) {
      RunSourceType.runiacGps => 'Runiac GPS',
      RunSourceType.appleHealth => 'Apple Health',
      RunSourceType.healthConnect => 'Health Connect',
      RunSourceType.garminViaHealth => 'Garmin via Health',
      RunSourceType.demoImport => throw const ActivityFeedbackPayloadException(
        'Demo-only activity summaries must not be sent.',
      ),
    };
  }

  double _distanceKm(String label) {
    return _firstNumber(label) ?? 0;
  }

  int _durationSeconds(String label) {
    final parts = label.split(':').map(int.tryParse).toList(growable: false);
    if (parts.length == 2 && parts.every((part) => part != null)) {
      return parts[0]! * 60 + parts[1]!;
    }
    if (parts.length == 3 && parts.every((part) => part != null)) {
      return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
    }
    return 0;
  }

  int? _paceSecondsPerKm(String? label) {
    if (label == null || label.trim() == '--') return null;
    final normalized = label
        .replaceAll('’', ':')
        .replaceAll('”', '')
        .replaceAll('"', '')
        .split(RegExp(r'\s+'))
        .first;
    final parts = normalized.split(':').map(int.tryParse).toList();
    if (parts.length != 2 || parts.any((part) => part == null)) return null;
    return parts[0]! * 60 + parts[1]!;
  }

  int? _caloriesKcal(String label) {
    return _firstNumber(label)?.round();
  }

  List<Map<String, Object?>> _paceSampleSplits(RunSummarySnapshot summary) {
    final samples = summary.paceAnalysisSeries?.validAcceptedSamples;
    if (samples == null || samples.length < 2) return const [];
    final derived = <Map<String, Object?>>[];
    var previousDistanceMeters = samples.first.cumulativeDistanceMeters;
    for (final sample in samples.skip(1).take(24)) {
      final deltaKm =
          (sample.cumulativeDistanceMeters - previousDistanceMeters) / 1000;
      previousDistanceMeters = sample.cumulativeDistanceMeters;
      if (!deltaKm.isFinite || deltaKm <= 0) continue;
      derived.add(<String, Object?>{
        'distanceKm': double.parse(deltaKm.toStringAsFixed(2)),
        'paceSecondsPerKm': sample.paceSecondsPerKm,
        'isPartial': deltaKm < 0.95,
      });
    }
    return derived;
  }

  double _splitDistanceKm(String label) {
    return double.tryParse(label) ?? _firstNumber(label) ?? 0;
  }

  int? _meters(String? label) {
    if (label == null || label.trim() == '--') return null;
    return _firstNumber(label)?.round();
  }

  int? _spm(String? label) {
    if (label == null || label.trim() == '--') return null;
    return _firstNumber(label)?.round();
  }

  double? _firstNumber(String label) {
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(label);
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  Map<String, Object?>? _optional(String key, Object? value) {
    return value == null ? null : <String, Object?>{key: value};
  }
}
