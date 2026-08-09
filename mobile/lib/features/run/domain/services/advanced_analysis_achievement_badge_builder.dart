import '../models/advanced_analysis_snapshot.dart';
import '../models/cadence_analysis_derivation.dart';
import '../models/run_summary_snapshot.dart';
import 'pace_analysis_deriver.dart';

class AdvancedAnalysisAchievementBadgeBuilder {
  const AdvancedAnalysisAchievementBadgeBuilder();

  List<AdvancedAnalysisAchievementBadge> build({
    required RunSummarySnapshot summary,
    required PaceAnalysisDerivation? paceAnalysis,
    required CadenceAnalysisDerivation? cadenceAnalysis,
    required List<AdvancedAnalysisSplitSnapshot> splits,
  }) {
    final badges = <AdvancedAnalysisAchievementBadge>[];
    final durationSeconds = _durationSeconds(summary.duration);
    final distanceKm = _distanceKm(summary.distanceKm);
    final paceStability = paceAnalysis?.paceStabilityScore;

    if (distanceKm != null && distanceKm > 0 && durationSeconds != null) {
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.firstStep,
        ),
      );
    }
    if (paceStability != null && paceStability >= 75) {
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.stablePace,
        ),
      );
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.goodConsistency,
        ),
      );
    }
    if (durationSeconds != null &&
        distanceKm != null &&
        (durationSeconds >= 1200 || distanceKm >= 3) &&
        (paceStability == null || paceStability >= 70)) {
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.goodEndurance,
          highlighted: true,
        ),
      );
    }
    if (_hasStrongFinish(splits)) {
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.strongFinish,
        ),
      );
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.negativeSplit,
        ),
      );
    } else if (_hasEvenSplit(splits)) {
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.evenSplit,
        ),
      );
    }
    if (cadenceAnalysis?.stability == CadenceStability.stable) {
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.consistentCadence,
        ),
      );
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.smoothRhythm,
        ),
      );
    }
    if (summary.elevationSeries.hasMinimumValidSamples() &&
        (paceStability == null || paceStability >= 70)) {
      badges.add(
        const AdvancedAnalysisAchievementBadge(
          kind: AdvancedAnalysisBadgeKind.hillSteady,
        ),
      );
    }

    return List<AdvancedAnalysisAchievementBadge>.unmodifiable(badges);
  }

  bool _hasStrongFinish(List<AdvancedAnalysisSplitSnapshot> splits) {
    if (splits.length < 2) {
      return false;
    }
    final first = splits.first.paceSecondsPerKm;
    final last = splits.last.paceSecondsPerKm;
    return last <= (first * 0.97).round();
  }

  bool _hasEvenSplit(List<AdvancedAnalysisSplitSnapshot> splits) {
    if (splits.length < 2) {
      return false;
    }
    final first = splits.first.paceSecondsPerKm;
    final last = splits.last.paceSecondsPerKm;
    return (last - first).abs() <= (first * 0.05).round();
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
