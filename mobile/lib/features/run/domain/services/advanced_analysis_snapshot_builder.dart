import '../models/advanced_analysis_snapshot.dart';
import '../models/cadence_analysis_derivation.dart';
import '../models/cadence_analysis_series.dart';
import '../models/cadence_graph_snapshot.dart';
import '../models/elevation_analysis_series.dart';
import '../models/elevation_graph_snapshot.dart';
import '../models/pace_graph_snapshot.dart';
import '../models/run_source_display.dart';
import '../models/run_summary_snapshot.dart';
import 'advanced_analysis_performance_overview_builder.dart';
import 'cadence_analysis_deriver.dart';
import 'cadence_graph_data_builder.dart';
import 'elevation_analysis_graph_builder.dart';
import 'pace_analysis_deriver.dart';

/// Assembles everything the Advanced Analysis screen shows from one finished
/// run.
///
/// This is the fan-out point: it hands the summary to each specialist deriver
/// and graph builder (pace, cadence, elevation, splits, performance overview)
/// and collects the results into a single immutable snapshot. Doing it here
/// means the screen never has to know which parts of the analysis were
/// unavailable — each deriver returns its own "unavailable" state with a
/// reason, and the widget just renders whatever it is handed.
class AdvancedAnalysisSnapshotBuilder {
  const AdvancedAnalysisSnapshotBuilder();

  AdvancedAnalysisSnapshot fromRunSummary(RunSummarySnapshot summary) {
    final paceAnalysis = _derivePaceAnalysis(summary);
    final formCadenceAnalysis = _deriveFormCadenceAnalysis(summary);
    final performanceCadenceAnalysis = _derivePerformanceCadenceAnalysis(
      summary,
    );
    final splits = _deriveSplits(summary);
    return AdvancedAnalysisSnapshot(
      performance: const AdvancedAnalysisPerformanceOverviewBuilder().build(
        summary: summary,
        paceAnalysis: paceAnalysis,
        cadenceAnalysis: performanceCadenceAnalysis,
        splits: splits,
      ),
      pace: AdvancedAnalysisPaceAnalysis(
        averagePace: _sourceAwareSummaryMetric(summary.avgPace, summary),
        fastestPace: _derivedPaceMetric(paceAnalysis?.fastestPaceSecondsPerKm),
        slowestPace: _derivedPaceMetric(paceAnalysis?.slowestPaceSecondsPerKm),
        paceStability: _derivedStabilityMetric(
          paceAnalysis?.paceStabilityScore,
        ),
        paceGraph: _paceGraphMetric(summary),
        splits: _splitMetricFromSplits(summary, splits),
      ),
      elevation: _elevationAnalysis(summary),
      formCadence: _formCadenceAnalysis(summary, formCadenceAnalysis),
    );
  }

  AdvancedAnalysisElevationAnalysis _elevationAnalysis(
    RunSummarySnapshot summary,
  ) {
    final graph = const ElevationAnalysisGraphBuilder().build(
      summary.elevationSeries,
    );
    if (!graph.isAvailable) {
      return AdvancedAnalysisElevationAnalysis(
        totalGain: const AdvancedAnalysisMetric<String>.unavailable(
          reason: AdvancedAnalysisMetricReason.missingElevationSource,
        ),
        highestPoint: const AdvancedAnalysisMetric<String>.unavailable(
          reason: AdvancedAnalysisMetricReason.missingElevationSource,
        ),
        lowestPoint: const AdvancedAnalysisMetric<String>.unavailable(
          reason: AdvancedAnalysisMetricReason.missingElevationSource,
        ),
        routeDifficulty: const AdvancedAnalysisMetric<String>.unavailable(
          reason: AdvancedAnalysisMetricReason.undefinedRouteDifficultySource,
        ),
        elevationGraph:
            const AdvancedAnalysisMetric<ElevationGraphSnapshot>.unavailable(
              reason: AdvancedAnalysisMetricReason.missingElevationSource,
            ),
        unavailableReason: graph.unavailableDiagnosticReason,
      );
    }

    final source = _elevationMetricSource(summary.elevationSeries.source);
    return AdvancedAnalysisElevationAnalysis(
      totalGain: _elevationMetric(
        '+${graph.totalGainMeters!.round()} m',
        source: source,
      ),
      highestPoint: _elevationMetric(
        '${graph.highestPointMeters!.round()} m',
        source: source,
      ),
      lowestPoint: _elevationMetric(
        '${graph.lowestPointMeters!.round()} m',
        source: source,
      ),
      routeDifficulty: _elevationMetric(
        _difficultyLabel(graph.difficulty),
        source: source,
      ),
      elevationGraph: AdvancedAnalysisMetric<ElevationGraphSnapshot>.available(
        value: graph,
        source: source,
        confidence: AdvancedAnalysisMetricConfidence.derived,
      ),
      unavailableReason: ElevationUnavailableReason.none,
    );
  }

  AdvancedAnalysisMetric<String> _elevationMetric(
    String valueLabel, {
    required AdvancedAnalysisMetricSource source,
  }) {
    return AdvancedAnalysisMetric<String>.available(
      value: valueLabel,
      valueLabel: valueLabel,
      source: source,
      confidence: AdvancedAnalysisMetricConfidence.derived,
    );
  }

  String _difficultyLabel(ElevationDifficulty difficulty) {
    return switch (difficulty) {
      ElevationDifficulty.mostlyFlat => 'Mostly Flat',
      ElevationDifficulty.rolling => 'Rolling',
      ElevationDifficulty.hilly => 'Hilly',
      ElevationDifficulty.unavailable => '--',
    };
  }

  AdvancedAnalysisMetricSource _elevationMetricSource(
    ElevationAnalysisSource source,
  ) {
    return switch (source) {
      ElevationAnalysisSource.runiacLocalAccepted =>
        AdvancedAnalysisMetricSource.localGpsDerived,
      ElevationAnalysisSource.backendDerived =>
        AdvancedAnalysisMetricSource.backendDerived,
      ElevationAnalysisSource.staticDemo =>
        AdvancedAnalysisMetricSource.staticDemo,
      ElevationAnalysisSource.unavailableUnknown =>
        AdvancedAnalysisMetricSource.unavailable,
    };
  }

  PaceAnalysisDerivation? _derivePaceAnalysis(RunSummarySnapshot summary) {
    if (summary.sourceType != RunSourceType.runiacGps) {
      return null;
    }
    final series = summary.paceAnalysisSeries;
    if (series == null) {
      return null;
    }
    final derivation = const PaceAnalysisDeriver().derive(series);
    return derivation.isAvailable ? derivation : null;
  }

  CadenceAnalysisDerivation? _deriveFormCadenceAnalysis(
    RunSummarySnapshot summary,
  ) {
    final series = summary.cadenceAnalysisSeries;
    if (series == null) {
      return null;
    }
    if (!_hasFormCadenceSource(summary.sourceType, series.source)) {
      return null;
    }
    final derivation = const CadenceAnalysisDeriver().derive(series);
    return derivation.isAvailable ? derivation : null;
  }

  CadenceAnalysisDerivation? _derivePerformanceCadenceAnalysis(
    RunSummarySnapshot summary,
  ) {
    final series = summary.cadenceAnalysisSeries;
    if (series == null) {
      return null;
    }
    if (!_hasCompatibleCadenceSource(summary.sourceType, series.source)) {
      return null;
    }
    final derivation = const CadenceAnalysisDeriver().derive(series);
    return derivation.isAvailable ? derivation : null;
  }

  AdvancedAnalysisFormCadenceAnalysis _formCadenceAnalysis(
    RunSummarySnapshot summary,
    CadenceAnalysisDerivation? derivation,
  ) {
    return AdvancedAnalysisFormCadenceAnalysis(
      averageCadence: _cadenceValueMetric(
        derivation?.averageCadenceSpm,
        derivation?.source,
      ),
      targetRange: const AdvancedAnalysisMetric<String>.unavailable(
        reason: AdvancedAnalysisMetricReason.missingCadenceSource,
      ),
      strideConsistency: _cadenceTextMetric(
        _stabilityLabel(derivation),
        derivation?.source,
      ),
      cadenceStatus: _cadenceTextMetric(
        _trendLabel(derivation),
        derivation?.source,
      ),
      strideLength: const AdvancedAnalysisMetric<String>.unavailable(
        reason: AdvancedAnalysisMetricReason.missingStrideSource,
      ),
      cadenceGraph: _cadenceGraphMetric(summary),
    );
  }

  AdvancedAnalysisMetric<String> _cadenceValueMetric(
    int? cadenceSpm,
    CadenceAnalysisSource? source,
  ) {
    if (cadenceSpm == null || source == null) {
      return _unavailableCadenceMetric();
    }
    final valueLabel = '$cadenceSpm spm';
    return AdvancedAnalysisMetric<String>.available(
      value: valueLabel,
      valueLabel: valueLabel,
      source: _cadenceGraphSource(source),
      confidence: _cadenceMetricConfidence(source),
    );
  }

  AdvancedAnalysisMetric<String> _cadenceTextMetric(
    String? valueLabel,
    CadenceAnalysisSource? source,
  ) {
    if (valueLabel == null || source == null) {
      return _unavailableCadenceMetric();
    }
    return AdvancedAnalysisMetric<String>.available(
      value: valueLabel,
      valueLabel: valueLabel,
      source: _cadenceGraphSource(source),
      confidence: _cadenceMetricConfidence(source),
    );
  }

  AdvancedAnalysisMetric<CadenceGraphSnapshot> _cadenceGraphMetric(
    RunSummarySnapshot summary,
  ) {
    final series = summary.cadenceAnalysisSeries;
    final durationSeconds = _durationSeconds(summary.duration);
    if (series == null ||
        durationSeconds == null ||
        !_hasCompatibleCadenceSource(summary.sourceType, series.source)) {
      return const AdvancedAnalysisMetric<CadenceGraphSnapshot>.unavailable(
        reason: AdvancedAnalysisMetricReason.missingCadenceSource,
      );
    }

    final graph = const CadenceGraphDataBuilder().build(
      series: series,
      durationSeconds: durationSeconds,
    );
    if (!graph.isAvailable) {
      return const AdvancedAnalysisMetric<CadenceGraphSnapshot>.unavailable(
        reason: AdvancedAnalysisMetricReason.missingCadenceSource,
      );
    }

    return AdvancedAnalysisMetric<CadenceGraphSnapshot>.available(
      value: graph,
      source: _cadenceGraphSource(series.source),
      confidence: _cadenceMetricConfidence(series.source),
    );
  }

  bool _hasFormCadenceSource(
    RunSourceType sourceType,
    CadenceAnalysisSource cadenceSource,
  ) {
    return sourceType == RunSourceType.runiacGps &&
        (cadenceSource == CadenceAnalysisSource.runiacLocalAccepted ||
            cadenceSource == CadenceAnalysisSource.phoneSensorEstimated ||
            cadenceSource == CadenceAnalysisSource.backendDerived);
  }

  bool _hasCompatibleCadenceSource(
    RunSourceType sourceType,
    CadenceAnalysisSource cadenceSource,
  ) {
    return switch (sourceType) {
      RunSourceType.runiacGps =>
        cadenceSource == CadenceAnalysisSource.runiacLocalAccepted ||
            cadenceSource == CadenceAnalysisSource.phoneSensorEstimated ||
            cadenceSource == CadenceAnalysisSource.backendDerived,
      RunSourceType.appleHealth =>
        cadenceSource == CadenceAnalysisSource.healthKitAppleWatch ||
            cadenceSource == CadenceAnalysisSource.backendDerived,
      RunSourceType.healthConnect =>
        cadenceSource == CadenceAnalysisSource.healthConnect ||
            cadenceSource == CadenceAnalysisSource.backendDerived,
      RunSourceType.garminViaHealth =>
        cadenceSource == CadenceAnalysisSource.garminWearable ||
            cadenceSource == CadenceAnalysisSource.backendDerived,
      RunSourceType.demoImport => false,
    };
  }

  AdvancedAnalysisMetricSource _cadenceGraphSource(
    CadenceAnalysisSource source,
  ) {
    return switch (source) {
      CadenceAnalysisSource.runiacLocalAccepted =>
        AdvancedAnalysisMetricSource.localGpsDerived,
      CadenceAnalysisSource.healthKitAppleWatch =>
        AdvancedAnalysisMetricSource.healthKitAppleWatch,
      CadenceAnalysisSource.healthConnect =>
        AdvancedAnalysisMetricSource.healthConnect,
      CadenceAnalysisSource.garminWearable =>
        AdvancedAnalysisMetricSource.garminWearable,
      CadenceAnalysisSource.backendDerived =>
        AdvancedAnalysisMetricSource.backendDerived,
      CadenceAnalysisSource.phoneSensorEstimated =>
        AdvancedAnalysisMetricSource.phoneSensorEstimated,
      CadenceAnalysisSource.staticDemo ||
      CadenceAnalysisSource.unavailableUnknown =>
        AdvancedAnalysisMetricSource.unavailable,
    };
  }

  AdvancedAnalysisMetricConfidence _cadenceMetricConfidence(
    CadenceAnalysisSource source,
  ) {
    return switch (source) {
      CadenceAnalysisSource.phoneSensorEstimated =>
        AdvancedAnalysisMetricConfidence.estimated,
      _ => AdvancedAnalysisMetricConfidence.derived,
    };
  }

  int? _durationSeconds(String durationLabel) {
    final normalized = durationLabel.trim();
    if (normalized.isEmpty || normalized == '--') {
      return null;
    }

    final minuteSecondMatch = RegExp(
      r'^(\d+):([0-5]\d)$',
    ).firstMatch(normalized);
    if (minuteSecondMatch != null) {
      final minutes = int.parse(minuteSecondMatch.group(1)!);
      final seconds = int.parse(minuteSecondMatch.group(2)!);
      final totalSeconds = minutes * 60 + seconds;
      return totalSeconds > 0 ? totalSeconds : null;
    }

    final hourMinuteSecondMatch = RegExp(
      r'^(\d+):([0-5]\d):([0-5]\d)$',
    ).firstMatch(normalized);
    if (hourMinuteSecondMatch == null) {
      return null;
    }
    final hours = int.parse(hourMinuteSecondMatch.group(1)!);
    final minutes = int.parse(hourMinuteSecondMatch.group(2)!);
    final seconds = int.parse(hourMinuteSecondMatch.group(3)!);
    final totalSeconds = hours * 3600 + minutes * 60 + seconds;
    return totalSeconds > 0 ? totalSeconds : null;
  }

  AdvancedAnalysisMetric<String> _unavailableCadenceMetric() {
    return const AdvancedAnalysisMetric<String>.unavailable(
      reason: AdvancedAnalysisMetricReason.missingCadenceSource,
    );
  }

  String? _stabilityLabel(CadenceAnalysisDerivation? derivation) {
    return switch (derivation?.stability) {
      CadenceStability.stable => 'stable',
      CadenceStability.variable => 'variable',
      CadenceStability.insufficientData ||
      CadenceStability.unavailable ||
      null => null,
    };
  }

  String? _trendLabel(CadenceAnalysisDerivation? derivation) {
    return switch (derivation?.trend) {
      CadenceTrend.stable => 'stable',
      CadenceTrend.dropping => 'dropping',
      CadenceTrend.rising => 'rising',
      CadenceTrend.insufficientData || CadenceTrend.unavailable || null => null,
    };
  }

  AdvancedAnalysisMetric<String> _derivedPaceMetric(int? secondsPerKm) {
    if (secondsPerKm == null) {
      return const AdvancedAnalysisMetric<String>.unavailable(
        reason: AdvancedAnalysisMetricReason.insufficientPaceSamples,
      );
    }
    final valueLabel = _formatDuration(secondsPerKm);
    return AdvancedAnalysisMetric<String>.available(
      value: valueLabel,
      valueLabel: valueLabel,
      source: AdvancedAnalysisMetricSource.localGpsDerived,
      confidence: AdvancedAnalysisMetricConfidence.derived,
    );
  }

  AdvancedAnalysisMetric<String> _derivedStabilityMetric(int? stabilityScore) {
    if (stabilityScore == null) {
      return const AdvancedAnalysisMetric<String>.unavailable(
        reason: AdvancedAnalysisMetricReason.insufficientPaceSamples,
      );
    }
    final valueLabel = stabilityScore.toString();
    return AdvancedAnalysisMetric<String>.available(
      value: valueLabel,
      valueLabel: valueLabel,
      source: AdvancedAnalysisMetricSource.localGpsDerived,
      confidence: AdvancedAnalysisMetricConfidence.derived,
    );
  }

  AdvancedAnalysisMetric<String> _sourceAwareSummaryMetric(
    String valueLabel,
    RunSummarySnapshot summary,
  ) {
    if (!_hasDisplayValue(valueLabel)) {
      return const AdvancedAnalysisMetric<String>.unavailable(
        reason: AdvancedAnalysisMetricReason.missingSummaryField,
      );
    }
    if (summary.sourceType == RunSourceType.demoImport) {
      return AdvancedAnalysisMetric<String>.demoOnly(valueLabel);
    }
    return AdvancedAnalysisMetric<String>.available(
      value: valueLabel,
      valueLabel: valueLabel,
      source: _summarySource(summary.sourceType),
      confidence: _summaryConfidence(summary.sourceType),
    );
  }

  AdvancedAnalysisMetricSource _summarySource(RunSourceType sourceType) {
    return switch (sourceType) {
      RunSourceType.runiacGps => AdvancedAnalysisMetricSource.localRunSummary,
      RunSourceType.appleHealth =>
        AdvancedAnalysisMetricSource.healthKitAppleWatch,
      RunSourceType.healthConnect => AdvancedAnalysisMetricSource.healthConnect,
      RunSourceType.garminViaHealth =>
        AdvancedAnalysisMetricSource.garminWearable,
      RunSourceType.demoImport => AdvancedAnalysisMetricSource.staticDemo,
    };
  }

  AdvancedAnalysisMetricConfidence _summaryConfidence(
    RunSourceType sourceType,
  ) {
    return switch (sourceType) {
      RunSourceType.runiacGps => AdvancedAnalysisMetricConfidence.trusted,
      RunSourceType.appleHealth ||
      RunSourceType.healthConnect ||
      RunSourceType.garminViaHealth => AdvancedAnalysisMetricConfidence.derived,
      RunSourceType.demoImport => AdvancedAnalysisMetricConfidence.demo,
    };
  }

  AdvancedAnalysisMetric<PaceGraphSnapshot> _paceGraphMetric(
    RunSummarySnapshot summary,
  ) {
    final graph = summary.paceGraph;
    if (!graph.isAvailable) {
      return const AdvancedAnalysisMetric<PaceGraphSnapshot>.unavailable(
        reason: AdvancedAnalysisMetricReason.insufficientPaceSamples,
      );
    }
    if (summary.sourceType == RunSourceType.demoImport) {
      return AdvancedAnalysisMetric<PaceGraphSnapshot>(
        availability: AdvancedAnalysisMetricAvailability.demoOnly,
        source: AdvancedAnalysisMetricSource.staticDemo,
        confidence: AdvancedAnalysisMetricConfidence.demo,
        value: graph,
        reason: AdvancedAnalysisMetricReason.demoFixtureOnly,
      );
    }
    return AdvancedAnalysisMetric<PaceGraphSnapshot>.available(
      value: graph,
      source: _paceSource(summary),
      confidence: AdvancedAnalysisMetricConfidence.derived,
    );
  }

  AdvancedAnalysisMetric<List<AdvancedAnalysisSplitSnapshot>>
  _splitMetricFromSplits(
    RunSummarySnapshot summary,
    List<AdvancedAnalysisSplitSnapshot> splits,
  ) {
    if (splits.isEmpty) {
      return const AdvancedAnalysisMetric<
        List<AdvancedAnalysisSplitSnapshot>
      >.unavailable(
        reason: AdvancedAnalysisMetricReason.insufficientPaceSamples,
      );
    }
    if (summary.sourceType == RunSourceType.demoImport) {
      return AdvancedAnalysisMetric<List<AdvancedAnalysisSplitSnapshot>>(
        availability: AdvancedAnalysisMetricAvailability.demoOnly,
        source: AdvancedAnalysisMetricSource.staticDemo,
        confidence: AdvancedAnalysisMetricConfidence.demo,
        value: splits,
        reason: AdvancedAnalysisMetricReason.demoFixtureOnly,
      );
    }
    return AdvancedAnalysisMetric<
      List<AdvancedAnalysisSplitSnapshot>
    >.available(
      value: splits,
      source: _paceSource(summary),
      confidence: AdvancedAnalysisMetricConfidence.derived,
    );
  }

  AdvancedAnalysisMetricSource _paceSource(RunSummarySnapshot summary) {
    return switch (summary.sourceType) {
      RunSourceType.runiacGps => AdvancedAnalysisMetricSource.localGpsDerived,
      RunSourceType.appleHealth =>
        AdvancedAnalysisMetricSource.healthKitAppleWatch,
      RunSourceType.healthConnect => AdvancedAnalysisMetricSource.healthConnect,
      RunSourceType.garminViaHealth =>
        AdvancedAnalysisMetricSource.garminWearable,
      RunSourceType.demoImport => AdvancedAnalysisMetricSource.staticDemo,
    };
  }

  List<AdvancedAnalysisSplitSnapshot> _deriveSplits(
    RunSummarySnapshot summary,
  ) {
    final graph = summary.paceGraph;
    final totalDurationSeconds =
        graph.totalDurationSeconds ?? _durationSeconds(summary.duration);
    final totalDistanceKm = _distanceKm(summary.distanceKm);
    if (!graph.isAvailable ||
        totalDurationSeconds == null ||
        totalDistanceKm == null ||
        totalDistanceKm <= 0) {
      return const [];
    }

    if (graph.hasDistanceAxis) {
      final graphSplits = _buildSplitsFromAnchors(
        _splitAnchors(
          graph: graph,
          totalDistanceKm: totalDistanceKm,
          totalDurationSeconds: totalDurationSeconds,
        ),
        totalDistanceKm: totalDistanceKm,
        totalDurationSeconds: totalDurationSeconds,
      );
      if (graphSplits.isNotEmpty) {
        return graphSplits;
      }
    }

    return _buildSplitsFromAnchors(
      _splitAnchorsFromLocalPaceSeries(
        summary: summary,
        totalDistanceKm: totalDistanceKm,
        totalDurationSeconds: totalDurationSeconds,
      ),
      totalDistanceKm: totalDistanceKm,
      totalDurationSeconds: totalDurationSeconds,
    );
  }

  List<AdvancedAnalysisSplitSnapshot> _buildSplitsFromAnchors(
    List<_SplitAnchor> anchors, {
    required double totalDistanceKm,
    required int totalDurationSeconds,
  }) {
    if (anchors.length < 2 || !_isMonotonicDistance(anchors)) {
      return const [];
    }

    final splits = <AdvancedAnalysisSplitSnapshot>[];
    var previousDistanceKm = 0.0;
    var previousElapsedSeconds = 0;
    final fullKilometres = totalDistanceKm.floor();

    for (var kilometre = 1; kilometre <= fullKilometres; kilometre += 1) {
      final elapsedSeconds = _elapsedAtDistance(anchors, kilometre.toDouble());
      if (elapsedSeconds == null || elapsedSeconds <= previousElapsedSeconds) {
        return const [];
      }
      final segmentSeconds = elapsedSeconds - previousElapsedSeconds;
      splits.add(
        AdvancedAnalysisSplitSnapshot(
          distanceLabel: '$kilometre km',
          paceLabel: _formatDuration(segmentSeconds),
          paceSecondsPerKm: segmentSeconds,
          isPartial: false,
        ),
      );
      previousDistanceKm = kilometre.toDouble();
      previousElapsedSeconds = elapsedSeconds;
    }

    final remainingDistanceKm = totalDistanceKm - previousDistanceKm;
    if (remainingDistanceKm >= 0.01) {
      final segmentSeconds = totalDurationSeconds - previousElapsedSeconds;
      if (segmentSeconds <= 0) {
        return const [];
      }
      splits.add(
        AdvancedAnalysisSplitSnapshot(
          distanceLabel: '${remainingDistanceKm.toStringAsFixed(2)} km',
          paceLabel: _formatDuration(segmentSeconds),
          paceSecondsPerKm: segmentSeconds,
          isPartial: true,
        ),
      );
    }

    return splits;
  }

  List<_SplitAnchor> _splitAnchorsFromLocalPaceSeries({
    required RunSummarySnapshot summary,
    required double totalDistanceKm,
    required int totalDurationSeconds,
  }) {
    final series = summary.paceAnalysisSeries;
    if (summary.sourceType != RunSourceType.runiacGps ||
        series == null ||
        !series.isLocalAcceptedSource ||
        !series.hasMinimumValidSamples() ||
        !series.hasMonotonicValidSamples) {
      return const [];
    }

    final anchors = <_SplitAnchor>[
      const _SplitAnchor(distanceKm: 0, elapsedSeconds: 0),
    ];

    for (final sample in series.validAcceptedSamples) {
      final distanceKm = sample.cumulativeDistanceMeters / 1000;
      if (!distanceKm.isFinite ||
          distanceKm < 0 ||
          sample.elapsedSeconds < 0 ||
          sample.elapsedSeconds > totalDurationSeconds) {
        continue;
      }
      anchors.add(
        _SplitAnchor(
          distanceKm: distanceKm.clamp(0.0, totalDistanceKm).toDouble(),
          elapsedSeconds: sample.elapsedSeconds,
        ),
      );
    }

    anchors.add(
      _SplitAnchor(
        distanceKm: totalDistanceKm,
        elapsedSeconds: totalDurationSeconds,
      ),
    );
    anchors.sort((a, b) {
      final distanceOrder = a.distanceKm.compareTo(b.distanceKm);
      if (distanceOrder != 0) {
        return distanceOrder;
      }
      return a.elapsedSeconds.compareTo(b.elapsedSeconds);
    });
    return anchors;
  }

  List<_SplitAnchor> _splitAnchors({
    required PaceGraphSnapshot graph,
    required double totalDistanceKm,
    required int totalDurationSeconds,
  }) {
    final anchors = <_SplitAnchor>[
      const _SplitAnchor(distanceKm: 0, elapsedSeconds: 0),
    ];

    for (final point in graph.points) {
      final distanceProgress = point.distanceProgressFraction;
      if (distanceProgress == null ||
          distanceProgress < 0 ||
          distanceProgress > 1 ||
          point.elapsedSeconds < 0 ||
          point.elapsedSeconds > totalDurationSeconds) {
        continue;
      }
      anchors.add(
        _SplitAnchor(
          distanceKm: distanceProgress * totalDistanceKm,
          elapsedSeconds: point.elapsedSeconds,
        ),
      );
    }

    anchors.add(
      _SplitAnchor(
        distanceKm: totalDistanceKm,
        elapsedSeconds: totalDurationSeconds,
      ),
    );
    anchors.sort((a, b) {
      final distanceOrder = a.distanceKm.compareTo(b.distanceKm);
      if (distanceOrder != 0) {
        return distanceOrder;
      }
      return a.elapsedSeconds.compareTo(b.elapsedSeconds);
    });
    return anchors;
  }

  bool _isMonotonicDistance(List<_SplitAnchor> anchors) {
    var lastDistanceKm = -1.0;
    var lastElapsedSeconds = -1;
    for (final anchor in anchors) {
      if (anchor.distanceKm < lastDistanceKm ||
          anchor.elapsedSeconds < lastElapsedSeconds) {
        return false;
      }
      lastDistanceKm = anchor.distanceKm;
      lastElapsedSeconds = anchor.elapsedSeconds;
    }
    return true;
  }

  int? _elapsedAtDistance(List<_SplitAnchor> anchors, double distanceKm) {
    for (var index = 1; index < anchors.length; index += 1) {
      final before = anchors[index - 1];
      final after = anchors[index];
      if (distanceKm < before.distanceKm || distanceKm > after.distanceKm) {
        continue;
      }
      final distanceDelta = after.distanceKm - before.distanceKm;
      if (distanceDelta <= 0) {
        return after.elapsedSeconds;
      }
      final ratio = (distanceKm - before.distanceKm) / distanceDelta;
      return (before.elapsedSeconds +
              ratio * (after.elapsedSeconds - before.elapsedSeconds))
          .round();
    }
    return null;
  }

  double? _distanceKm(String label) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(label.trim());
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(1)!);
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes’${remainingSeconds.toString().padLeft(2, '0')}”';
  }

  bool _hasDisplayValue(String valueLabel) {
    final normalized = valueLabel.trim();
    return normalized.isNotEmpty && normalized != '--';
  }
}

class _SplitAnchor {
  const _SplitAnchor({required this.distanceKm, required this.elapsedSeconds});

  final double distanceKm;
  final int elapsedSeconds;
}
