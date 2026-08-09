import 'cadence_graph_snapshot.dart';
import 'elevation_analysis_series.dart';
import 'elevation_graph_snapshot.dart';
import 'pace_graph_snapshot.dart';

/// Everything the Advanced Analysis screen renders, in one immutable value.
///
/// The unit of the screen is [AdvancedAnalysisMetric], and it is never a bare
/// number: each metric carries its availability, its source and a confidence,
/// so the widget layer can render "unavailable", "estimated" and "measured"
/// differently without re-deriving any of that judgement itself.
///
/// That is also why an absent metric is modelled as an unavailable metric with
/// a reason rather than as `null` — the screen explains the gap instead of
/// quietly leaving a hole.
enum AdvancedAnalysisMetricAvailability {
  available,
  unavailable,
  estimated,
  demoOnly,
  pendingSource,
}

enum AdvancedAnalysisMetricSource {
  localRunSummary,
  localGpsDerived,
  phoneSensorEstimated,
  healthKitAppleWatch,
  healthConnect,
  garminWearable,
  backendDerived,
  staticDemo,
  unavailable,
}

enum AdvancedAnalysisMetricConfidence {
  trusted,
  derived,
  estimated,
  demo,
  unavailable,
}

enum AdvancedAnalysisMetricReason {
  none,
  missingSummaryField,
  insufficientPaceSamples,
  missingCadenceSource,
  missingStrideSource,
  missingElevationSource,
  undefinedPerformanceFormula,
  undefinedRouteDifficultySource,
  estimatedFromPhoneSensors,
  demoFixtureOnly,
  pendingBackendAnalysis,
}

enum AdvancedAnalysisScoreSourceMode {
  mobileOnly,
  wearableBacked,
  mixedSource,
  demoOnly,
}

enum AdvancedAnalysisBadgeKind {
  stablePace('Stable Pace'),
  goodEndurance('Good Endurance'),
  strongFinish('Strong Finish'),
  consistentCadence('Consistent Cadence'),
  smoothRhythm('Smooth Rhythm'),
  hillSteady('Hill Steady'),
  negativeSplit('Negative Split'),
  evenSplit('Even Split'),
  firstStep('First Step'),
  goodConsistency('Good Consistency');

  const AdvancedAnalysisBadgeKind(this.label);

  final String label;
}

class AdvancedAnalysisMetric<T> {
  const AdvancedAnalysisMetric({
    required this.availability,
    required this.source,
    required this.confidence,
    this.value,
    this.valueLabel,
    this.reason = AdvancedAnalysisMetricReason.none,
  });

  const AdvancedAnalysisMetric.available({
    required this.source,
    required this.confidence,
    this.value,
    this.valueLabel,
  }) : availability = AdvancedAnalysisMetricAvailability.available,
       reason = AdvancedAnalysisMetricReason.none;

  const AdvancedAnalysisMetric.unavailable({
    this.reason = AdvancedAnalysisMetricReason.pendingBackendAnalysis,
  }) : availability = AdvancedAnalysisMetricAvailability.unavailable,
       source = AdvancedAnalysisMetricSource.unavailable,
       confidence = AdvancedAnalysisMetricConfidence.unavailable,
       value = null,
       valueLabel = null;

  const AdvancedAnalysisMetric.estimated({
    required this.valueLabel,
    required this.source,
    this.reason = AdvancedAnalysisMetricReason.estimatedFromPhoneSensors,
  }) : availability = AdvancedAnalysisMetricAvailability.estimated,
       confidence = AdvancedAnalysisMetricConfidence.estimated,
       value = null;

  const AdvancedAnalysisMetric.demoOnly(this.valueLabel)
    : availability = AdvancedAnalysisMetricAvailability.demoOnly,
      source = AdvancedAnalysisMetricSource.staticDemo,
      confidence = AdvancedAnalysisMetricConfidence.demo,
      value = null,
      reason = AdvancedAnalysisMetricReason.demoFixtureOnly;

  final AdvancedAnalysisMetricAvailability availability;
  final AdvancedAnalysisMetricSource source;
  final AdvancedAnalysisMetricConfidence confidence;
  final T? value;
  final String? valueLabel;
  final AdvancedAnalysisMetricReason reason;

  bool get isAvailable {
    return availability == AdvancedAnalysisMetricAvailability.available ||
        availability == AdvancedAnalysisMetricAvailability.estimated;
  }

  bool get isTrustedProduction {
    return availability == AdvancedAnalysisMetricAvailability.available &&
        confidence == AdvancedAnalysisMetricConfidence.trusted &&
        source != AdvancedAnalysisMetricSource.staticDemo &&
        source != AdvancedAnalysisMetricSource.unavailable;
  }
}

class AdvancedAnalysisSnapshot {
  const AdvancedAnalysisSnapshot({
    required this.performance,
    required this.pace,
    required this.elevation,
    required this.formCadence,
  });

  final AdvancedAnalysisPerformanceOverview performance;
  final AdvancedAnalysisPaceAnalysis pace;
  final AdvancedAnalysisElevationAnalysis elevation;
  final AdvancedAnalysisFormCadenceAnalysis formCadence;
}

class AdvancedAnalysisPerformanceOverview {
  const AdvancedAnalysisPerformanceOverview({
    required this.score,
    required this.duration,
    required this.distance,
    required this.scoreMode,
    required this.scoreConfidenceLabel,
    required this.qualityLabel,
    required this.takeaway,
    required this.nextFocus,
    this.badges = const <AdvancedAnalysisAchievementBadge>[],
  });

  final AdvancedAnalysisMetric<int> score;
  final AdvancedAnalysisMetric<String> duration;
  final AdvancedAnalysisMetric<String> distance;
  final AdvancedAnalysisScoreSourceMode scoreMode;
  final String scoreConfidenceLabel;
  final String qualityLabel;
  final String takeaway;
  final String nextFocus;
  final List<AdvancedAnalysisAchievementBadge> badges;
}

class AdvancedAnalysisAchievementBadge {
  const AdvancedAnalysisAchievementBadge({
    required this.kind,
    this.highlighted = false,
  });

  final AdvancedAnalysisBadgeKind kind;
  final bool highlighted;
}

class AdvancedAnalysisPaceAnalysis {
  const AdvancedAnalysisPaceAnalysis({
    required this.averagePace,
    required this.fastestPace,
    required this.slowestPace,
    required this.paceStability,
    required this.paceGraph,
    required this.splits,
  });

  final AdvancedAnalysisMetric<String> averagePace;
  final AdvancedAnalysisMetric<String> fastestPace;
  final AdvancedAnalysisMetric<String> slowestPace;
  final AdvancedAnalysisMetric<String> paceStability;
  final AdvancedAnalysisMetric<PaceGraphSnapshot> paceGraph;
  final AdvancedAnalysisMetric<List<AdvancedAnalysisSplitSnapshot>> splits;
}

class AdvancedAnalysisSplitSnapshot {
  const AdvancedAnalysisSplitSnapshot({
    required this.distanceLabel,
    required this.paceLabel,
    required this.paceSecondsPerKm,
    required this.isPartial,
    this.elevationLabel = '--',
    this.heartRateLabel = '--',
    this.barScalePaceSecondsPerKm,
  });

  final String distanceLabel;
  final String paceLabel;
  final int paceSecondsPerKm;
  final bool isPartial;
  final String elevationLabel;
  final String heartRateLabel;
  final int? barScalePaceSecondsPerKm;
}

class AdvancedAnalysisElevationAnalysis {
  const AdvancedAnalysisElevationAnalysis({
    required this.totalGain,
    required this.highestPoint,
    required this.lowestPoint,
    required this.routeDifficulty,
    required this.elevationGraph,
    required this.unavailableReason,
  });

  final AdvancedAnalysisMetric<String> totalGain;
  final AdvancedAnalysisMetric<String> highestPoint;
  final AdvancedAnalysisMetric<String> lowestPoint;
  final AdvancedAnalysisMetric<String> routeDifficulty;
  final AdvancedAnalysisMetric<ElevationGraphSnapshot> elevationGraph;
  final ElevationUnavailableReason unavailableReason;
}

class AdvancedAnalysisFormCadenceAnalysis {
  const AdvancedAnalysisFormCadenceAnalysis({
    required this.averageCadence,
    required this.targetRange,
    required this.strideConsistency,
    required this.cadenceStatus,
    required this.strideLength,
    required this.cadenceGraph,
  });

  final AdvancedAnalysisMetric<String> averageCadence;
  final AdvancedAnalysisMetric<String> targetRange;
  final AdvancedAnalysisMetric<String> strideConsistency;
  final AdvancedAnalysisMetric<String> cadenceStatus;
  final AdvancedAnalysisMetric<String> strideLength;
  final AdvancedAnalysisMetric<CadenceGraphSnapshot> cadenceGraph;
}
