import '../models/advanced_analysis_snapshot.dart';
import '../models/cadence_analysis_derivation.dart';
import '../models/cadence_analysis_series.dart';
import '../models/run_source_display.dart';
import '../models/run_summary_snapshot.dart';
import 'advanced_analysis_achievement_badge_builder.dart';
import 'pace_analysis_deriver.dart';

/// Builds the header of the Advanced Analysis screen: the performance score,
/// its quality label, and the achievement badges earned by the run.
///
/// The score is always paired with a *source mode* — demo, phone GPS only, or
/// wearable-backed — because the same number means different things depending
/// on where the data came from. The screen shows the mode's confidence label
/// alongside the score so a phone-only run is never presented with the same
/// authority as a wearable-backed one.
class AdvancedAnalysisPerformanceOverviewBuilder {
  const AdvancedAnalysisPerformanceOverviewBuilder();

  AdvancedAnalysisPerformanceOverview build({
    required RunSummarySnapshot summary,
    required PaceAnalysisDerivation? paceAnalysis,
    required CadenceAnalysisDerivation? cadenceAnalysis,
    required List<AdvancedAnalysisSplitSnapshot> splits,
  }) {
    final scoreMode = _scoreMode(summary, cadenceAnalysis);
    final score = _performanceScore(
      summary: summary,
      paceAnalysis: paceAnalysis,
      scoreMode: scoreMode,
    );
    final qualityLabel = _qualityLabel(summary, score.value);
    return AdvancedAnalysisPerformanceOverview(
      score: score,
      duration: _sourceAwareSummaryMetric(summary.duration, summary),
      distance: _sourceAwareSummaryMetric(summary.distanceKm, summary),
      scoreMode: scoreMode,
      scoreConfidenceLabel: _scoreConfidenceLabel(scoreMode),
      qualityLabel: qualityLabel,
      takeaway: _takeaway(summary, qualityLabel),
      nextFocus: _nextFocus(summary, score.value),
      badges: const AdvancedAnalysisAchievementBadgeBuilder().build(
        summary: summary,
        paceAnalysis: paceAnalysis,
        cadenceAnalysis: cadenceAnalysis,
        splits: splits,
      ),
    );
  }

  AdvancedAnalysisScoreSourceMode _scoreMode(
    RunSummarySnapshot summary,
    CadenceAnalysisDerivation? cadenceAnalysis,
  ) {
    if (summary.sourceType == RunSourceType.demoImport) {
      return AdvancedAnalysisScoreSourceMode.demoOnly;
    }
    if (summary.sourceType == RunSourceType.runiacGps) {
      return AdvancedAnalysisScoreSourceMode.mobileOnly;
    }
    if (_hasWearableSource(summary.sourceType)) {
      return AdvancedAnalysisScoreSourceMode.wearableBacked;
    }
    if (cadenceAnalysis?.source == CadenceAnalysisSource.phoneSensorEstimated) {
      return AdvancedAnalysisScoreSourceMode.mixedSource;
    }
    return AdvancedAnalysisScoreSourceMode.mobileOnly;
  }

  String _scoreConfidenceLabel(AdvancedAnalysisScoreSourceMode mode) {
    return switch (mode) {
      AdvancedAnalysisScoreSourceMode.mobileOnly => 'Phone data',
      AdvancedAnalysisScoreSourceMode.wearableBacked => 'Wearable-backed',
      AdvancedAnalysisScoreSourceMode.mixedSource => 'Mixed phone data',
      AdvancedAnalysisScoreSourceMode.demoOnly => 'Demo data',
    };
  }

  String _qualityLabel(RunSummarySnapshot summary, int? qualityValue) {
    if (!summary.hasSufficientData || qualityValue == null) {
      return 'More data needed';
    }
    if (qualityValue >= 92) {
      return 'Steady effort';
    }
    if (qualityValue >= 84) {
      return 'Good foundation run';
    }
    return 'Building consistency';
  }

  String _takeaway(RunSummarySnapshot summary, String qualityLabel) {
    if (!summary.hasSufficientData) {
      return 'This run was a useful start, but there is not enough movement data yet to give a detailed overview.';
    }
    return switch (qualityLabel) {
      'Steady effort' =>
        'Your distance, duration, and pace data point to a steady run today. Missing wearable data does not lower this overview.',
      'Good foundation run' =>
        'You completed a measurable run with enough phone data for a simple overview. Missing wearable data does not lower this overview.',
      _ =>
        'This run gives Runiac enough phone data to suggest one calm next step. Missing wearable data does not lower this overview.',
    };
  }

  String _nextFocus(RunSummarySnapshot summary, int? qualityValue) {
    if (!summary.hasSufficientData || qualityValue == null) {
      return 'Try a slightly longer easy run so Runiac can give more useful feedback.';
    }
    if (qualityValue >= 92) {
      return 'Keep the next run comfortable and repeatable.';
    }
    return 'Aim for another easy run with a similar steady feel.';
  }

  AdvancedAnalysisMetric<int> _performanceScore({
    required RunSummarySnapshot summary,
    required PaceAnalysisDerivation? paceAnalysis,
    required AdvancedAnalysisScoreSourceMode scoreMode,
  }) {
    final distanceKm = _distanceKm(summary.distanceKm);
    final durationSeconds = _durationSeconds(summary.duration);
    if (!summary.hasSufficientData ||
        distanceKm == null ||
        durationSeconds == null) {
      return const AdvancedAnalysisMetric<int>.unavailable(
        reason: AdvancedAnalysisMetricReason.missingSummaryField,
      );
    }

    final paceStability = paceAnalysis?.paceStabilityScore;

    final score = switch (scoreMode) {
      AdvancedAnalysisScoreSourceMode.mobileOnly =>
        45 +
            (distanceKm * 6).round().clamp(0, 24) +
            (durationSeconds / 120).round().clamp(0, 16) +
            ((paceStability ?? 50) * 0.15).round(),
      AdvancedAnalysisScoreSourceMode.mixedSource =>
        48 +
            (distanceKm * 5).round().clamp(0, 20) +
            (durationSeconds / 150).round().clamp(0, 13) +
            ((paceStability ?? 50) * 0.13).round(),
      AdvancedAnalysisScoreSourceMode.wearableBacked =>
        42 +
            (distanceKm * 4).round().clamp(0, 18) +
            (durationSeconds / 180).round().clamp(0, 10) +
            ((paceStability ?? 50) * 0.12).round(),
      AdvancedAnalysisScoreSourceMode.demoOnly =>
        40 +
            (distanceKm * 4).round().clamp(0, 18) +
            (durationSeconds / 180).round().clamp(0, 10),
    };

    final clampedScore = score.clamp(0, 100).toInt();
    if (scoreMode == AdvancedAnalysisScoreSourceMode.demoOnly) {
      return AdvancedAnalysisMetric<int>(
        availability: AdvancedAnalysisMetricAvailability.demoOnly,
        source: AdvancedAnalysisMetricSource.staticDemo,
        confidence: AdvancedAnalysisMetricConfidence.demo,
        value: clampedScore,
        valueLabel: '$clampedScore',
        reason: AdvancedAnalysisMetricReason.demoFixtureOnly,
      );
    }
    return AdvancedAnalysisMetric<int>.available(
      value: clampedScore,
      valueLabel: '$clampedScore',
      source: scoreMode == AdvancedAnalysisScoreSourceMode.wearableBacked
          ? _summarySource(summary.sourceType)
          : AdvancedAnalysisMetricSource.localRunSummary,
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

  bool _hasWearableSource(RunSourceType sourceType) {
    return switch (sourceType) {
      RunSourceType.appleHealth ||
      RunSourceType.healthConnect ||
      RunSourceType.garminViaHealth => true,
      RunSourceType.runiacGps || RunSourceType.demoImport => false,
    };
  }

  bool _hasDisplayValue(String valueLabel) {
    final normalized = valueLabel.trim();
    return normalized.isNotEmpty && normalized != '--';
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

  double? _distanceKm(String label) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(label.trim());
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(1)!);
  }
}
