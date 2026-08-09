import 'dart:math' as math;

import '../models/pace_analysis_series.dart';

const paceStabilityToleranceSeconds = 60;

enum PaceAnalysisUnavailableReason {
  none,
  staticDemoSource,
  unavailableSource,
  invalidSource,
  insufficientSamples,
  nonMonotonicSeries,
}

class PaceAnalysisDerivation {
  const PaceAnalysisDerivation._({
    required this.source,
    required this.confidence,
    required this.fastestPaceSecondsPerKm,
    required this.slowestPaceSecondsPerKm,
    required this.paceStabilityScore,
    required this.unavailableReason,
  });

  factory PaceAnalysisDerivation.available({
    required PaceAnalysisSource source,
    required PaceAnalysisConfidence confidence,
    required int fastestPaceSecondsPerKm,
    required int slowestPaceSecondsPerKm,
    required int paceStabilityScore,
  }) {
    _validateAvailableState(source, confidence, paceStabilityScore);
    return PaceAnalysisDerivation._(
      source: source,
      confidence: confidence,
      fastestPaceSecondsPerKm: fastestPaceSecondsPerKm,
      slowestPaceSecondsPerKm: slowestPaceSecondsPerKm,
      paceStabilityScore: paceStabilityScore,
      unavailableReason: PaceAnalysisUnavailableReason.none,
    );
  }

  factory PaceAnalysisDerivation.unavailable({
    required PaceAnalysisUnavailableReason reason,
    PaceAnalysisSource source = PaceAnalysisSource.unavailableUnknown,
    PaceAnalysisConfidence confidence = PaceAnalysisConfidence.unavailable,
  }) {
    _validateUnavailableState(reason);
    return PaceAnalysisDerivation._(
      source: source,
      confidence: confidence,
      fastestPaceSecondsPerKm: null,
      slowestPaceSecondsPerKm: null,
      paceStabilityScore: null,
      unavailableReason: reason,
    );
  }

  final PaceAnalysisSource source;
  final PaceAnalysisConfidence confidence;
  final int? fastestPaceSecondsPerKm;
  final int? slowestPaceSecondsPerKm;
  final int? paceStabilityScore;
  final PaceAnalysisUnavailableReason unavailableReason;

  bool get isAvailable {
    return unavailableReason == PaceAnalysisUnavailableReason.none;
  }

  static void _validateAvailableState(
    PaceAnalysisSource source,
    PaceAnalysisConfidence confidence,
    int paceStabilityScore,
  ) {
    if (source != PaceAnalysisSource.localAccepted ||
        confidence != PaceAnalysisConfidence.derived) {
      throw ArgumentError.value(
        '$source/$confidence',
        'source/confidence',
        'available pace analysis derivations must be local accepted and derived',
      );
    }
    if (paceStabilityScore < 0 || paceStabilityScore > 100) {
      throw ArgumentError.value(
        paceStabilityScore,
        'paceStabilityScore',
        'must be between 0 and 100',
      );
    }
  }

  static void _validateUnavailableState(PaceAnalysisUnavailableReason reason) {
    if (reason == PaceAnalysisUnavailableReason.none) {
      throw ArgumentError.value(
        reason,
        'reason',
        'must explain why the pace analysis derivation is unavailable',
      );
    }
  }
}

class PaceAnalysisDeriver {
  const PaceAnalysisDeriver();

  PaceAnalysisDerivation derive(PaceAnalysisSeries series) {
    final sourceReason = _unavailableReasonForSource(series);
    if (sourceReason != PaceAnalysisUnavailableReason.none) {
      return PaceAnalysisDerivation.unavailable(
        reason: sourceReason,
        source: series.source,
        confidence: series.confidence,
      );
    }

    if (!series.hasMinimumValidSamples()) {
      return PaceAnalysisDerivation.unavailable(
        reason: PaceAnalysisUnavailableReason.insufficientSamples,
        source: series.source,
        confidence: series.confidence,
      );
    }

    if (!series.hasMonotonicValidSamples) {
      return PaceAnalysisDerivation.unavailable(
        reason: PaceAnalysisUnavailableReason.nonMonotonicSeries,
        source: series.source,
        confidence: series.confidence,
      );
    }

    final paceSecondsPerKm = series.validAcceptedSamples
        .map((sample) => sample.paceSecondsPerKm)
        .toList(growable: false);
    return PaceAnalysisDerivation.available(
      source: series.source,
      confidence: series.confidence,
      fastestPaceSecondsPerKm: paceSecondsPerKm.reduce(math.min),
      slowestPaceSecondsPerKm: paceSecondsPerKm.reduce(math.max),
      paceStabilityScore: _stabilityScore(paceSecondsPerKm),
    );
  }

  PaceAnalysisUnavailableReason _unavailableReasonForSource(
    PaceAnalysisSeries series,
  ) {
    if (series.isStaticDemoSource) {
      return PaceAnalysisUnavailableReason.staticDemoSource;
    }
    if (series.isUnavailable) {
      return PaceAnalysisUnavailableReason.unavailableSource;
    }
    if (!series.isLocalAcceptedSource ||
        series.confidence != PaceAnalysisConfidence.derived) {
      return PaceAnalysisUnavailableReason.invalidSource;
    }
    return PaceAnalysisUnavailableReason.none;
  }

  int _stabilityScore(List<int> paceSecondsPerKm) {
    final meanPace =
        paceSecondsPerKm.reduce((a, b) => a + b) / paceSecondsPerKm.length;
    final meanAbsoluteDeviation =
        paceSecondsPerKm
            .map((pace) => (pace - meanPace).abs())
            .reduce((a, b) => a + b) /
        paceSecondsPerKm.length;
    final score =
        100 - (meanAbsoluteDeviation / paceStabilityToleranceSeconds * 100);
    return score.clamp(0, 100).round();
  }
}
