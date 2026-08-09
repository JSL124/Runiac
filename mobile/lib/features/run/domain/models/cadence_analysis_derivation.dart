// The conclusions drawn from a [CadenceAnalysisSeries]: average, range,
// stability and trend.
//
// Kept separate from the series itself so the raw samples stay untouched and
// the interpretation can be re-derived or changed without rewriting stored
// data. Both "stable" and "insufficient data" are explicit outcomes — the UI
// must be able to tell "your cadence held steady" apart from "we could not
// tell", and an unavailable derivation always carries the reason why.

import 'cadence_analysis_series.dart';

// Within 8 spm counts as holding steady; an 8 spm move across the run counts as
// a real trend. Both are deliberately loose — beginners are not metronomes.
const stableCadenceSpreadSpm = 8;
const cadenceTrendDeltaSpm = 8;

enum CadenceStability { stable, variable, insufficientData, unavailable }

enum CadenceTrend { stable, dropping, rising, insufficientData, unavailable }

enum CadenceAnalysisUnavailableReason {
  none,
  staticDemoSource,
  unavailableSource,
  invalidSource,
  insufficientSamples,
  nonMonotonicSeries,
}

class CadenceAnalysisDerivation {
  const CadenceAnalysisDerivation._({
    required this.source,
    required this.confidence,
    required this.averageCadenceSpm,
    required this.lowestCadenceSpm,
    required this.highestCadenceSpm,
    required this.stability,
    required this.trend,
    required this.unavailableReason,
  });

  factory CadenceAnalysisDerivation.available({
    required CadenceAnalysisSource source,
    required CadenceAnalysisConfidence confidence,
    required int averageCadenceSpm,
    required int lowestCadenceSpm,
    required int highestCadenceSpm,
    required CadenceStability stability,
    required CadenceTrend trend,
  }) {
    _validateAvailableState(
      source: source,
      confidence: confidence,
      averageCadenceSpm: averageCadenceSpm,
      lowestCadenceSpm: lowestCadenceSpm,
      highestCadenceSpm: highestCadenceSpm,
      stability: stability,
      trend: trend,
    );
    return CadenceAnalysisDerivation._(
      source: source,
      confidence: confidence,
      averageCadenceSpm: averageCadenceSpm,
      lowestCadenceSpm: lowestCadenceSpm,
      highestCadenceSpm: highestCadenceSpm,
      stability: stability,
      trend: trend,
      unavailableReason: CadenceAnalysisUnavailableReason.none,
    );
  }

  factory CadenceAnalysisDerivation.unavailable({
    required CadenceAnalysisUnavailableReason reason,
    CadenceAnalysisSource source = CadenceAnalysisSource.unavailableUnknown,
    CadenceAnalysisConfidence confidence =
        CadenceAnalysisConfidence.unavailable,
  }) {
    _validateUnavailableState(
      reason: reason,
      source: source,
      confidence: confidence,
    );
    return CadenceAnalysisDerivation._(
      source: source,
      confidence: confidence,
      averageCadenceSpm: null,
      lowestCadenceSpm: null,
      highestCadenceSpm: null,
      stability: reason == CadenceAnalysisUnavailableReason.insufficientSamples
          ? CadenceStability.insufficientData
          : CadenceStability.unavailable,
      trend: reason == CadenceAnalysisUnavailableReason.insufficientSamples
          ? CadenceTrend.insufficientData
          : CadenceTrend.unavailable,
      unavailableReason: reason,
    );
  }

  final CadenceAnalysisSource source;
  final CadenceAnalysisConfidence confidence;
  final int? averageCadenceSpm;
  final int? lowestCadenceSpm;
  final int? highestCadenceSpm;
  final CadenceStability stability;
  final CadenceTrend trend;
  final CadenceAnalysisUnavailableReason unavailableReason;

  bool get isAvailable {
    return unavailableReason == CadenceAnalysisUnavailableReason.none;
  }

  static void _validateAvailableState({
    required CadenceAnalysisSource source,
    required CadenceAnalysisConfidence confidence,
    required int averageCadenceSpm,
    required int lowestCadenceSpm,
    required int highestCadenceSpm,
    required CadenceStability stability,
    required CadenceTrend trend,
  }) {
    if (!_isProductionAnalysisEligible(source, confidence)) {
      throw ArgumentError.value(
        '$source/$confidence',
        'source/confidence',
        'available cadence analysis derivations require eligible source confidence',
      );
    }
    if (stability == CadenceStability.insufficientData ||
        stability == CadenceStability.unavailable) {
      throw ArgumentError.value(
        stability,
        'stability',
        'available cadence analysis derivations require a stability value',
      );
    }
    if (trend == CadenceTrend.insufficientData ||
        trend == CadenceTrend.unavailable) {
      throw ArgumentError.value(
        trend,
        'trend',
        'available cadence analysis derivations require a trend value',
      );
    }
    if (!_isCadenceValueInRange(averageCadenceSpm) ||
        !_isCadenceValueInRange(lowestCadenceSpm) ||
        !_isCadenceValueInRange(highestCadenceSpm)) {
      throw ArgumentError.value(
        '$lowestCadenceSpm/$averageCadenceSpm/$highestCadenceSpm',
        'cadenceSpm',
        'available cadence analysis values require cadence range',
      );
    }
    if (lowestCadenceSpm > averageCadenceSpm ||
        averageCadenceSpm > highestCadenceSpm) {
      throw ArgumentError.value(
        '$lowestCadenceSpm/$averageCadenceSpm/$highestCadenceSpm',
        'cadenceSpm',
        'average cadence expected between lowest and highest cadence',
      );
    }
    final expectedStability =
        highestCadenceSpm - lowestCadenceSpm <= stableCadenceSpreadSpm
        ? CadenceStability.stable
        : CadenceStability.variable;
    if (stability != expectedStability) {
      throw ArgumentError.value(
        stability,
        'stability',
        'stability expected to match the cadence spread',
      );
    }
  }

  static void _validateUnavailableState({
    required CadenceAnalysisUnavailableReason reason,
    required CadenceAnalysisSource source,
    required CadenceAnalysisConfidence confidence,
  }) {
    if (reason == CadenceAnalysisUnavailableReason.none) {
      throw ArgumentError.value(
        reason,
        'reason',
        'expected a reason for unavailable cadence analysis derivation',
      );
    }
    if (!_isUnavailableSourceConsistent(reason, source, confidence)) {
      throw ArgumentError.value(
        '$reason/$source/$confidence',
        'reason/source/confidence',
        'unavailable cadence analysis source expected to match its reason',
      );
    }
  }

  static bool _isCadenceValueInRange(int value) {
    return value >= minCadenceAnalysisSpm && value <= maxCadenceAnalysisSpm;
  }

  static bool _isUnavailableSourceConsistent(
    CadenceAnalysisUnavailableReason reason,
    CadenceAnalysisSource source,
    CadenceAnalysisConfidence confidence,
  ) {
    return switch (reason) {
      CadenceAnalysisUnavailableReason.none => false,
      CadenceAnalysisUnavailableReason.staticDemoSource =>
        source == CadenceAnalysisSource.staticDemo &&
            confidence == CadenceAnalysisConfidence.demo,
      CadenceAnalysisUnavailableReason.unavailableSource =>
        source == CadenceAnalysisSource.unavailableUnknown &&
            confidence == CadenceAnalysisConfidence.unavailable,
      CadenceAnalysisUnavailableReason.insufficientSamples ||
      CadenceAnalysisUnavailableReason.nonMonotonicSeries =>
        _isProductionAnalysisEligible(source, confidence),
      CadenceAnalysisUnavailableReason.invalidSource =>
        !_isCanonicalStaticDemoSource(source, confidence) &&
            !_isCanonicalUnavailableSource(source, confidence) &&
            !_isProductionAnalysisEligible(source, confidence),
    };
  }

  static bool _isProductionAnalysisEligible(
    CadenceAnalysisSource source,
    CadenceAnalysisConfidence confidence,
  ) {
    return switch ((source, confidence)) {
      (
        CadenceAnalysisSource.runiacLocalAccepted,
        CadenceAnalysisConfidence.medium,
      ) ||
      (
        CadenceAnalysisSource.healthKitAppleWatch ||
            CadenceAnalysisSource.healthConnect ||
            CadenceAnalysisSource.garminWearable,
        CadenceAnalysisConfidence.high,
      ) ||
      (
        CadenceAnalysisSource.backendDerived,
        CadenceAnalysisConfidence.medium,
      ) ||
      (
        CadenceAnalysisSource.phoneSensorEstimated,
        CadenceAnalysisConfidence.low,
      ) => true,
      _ => false,
    };
  }

  static bool _isCanonicalStaticDemoSource(
    CadenceAnalysisSource source,
    CadenceAnalysisConfidence confidence,
  ) {
    return source == CadenceAnalysisSource.staticDemo &&
        confidence == CadenceAnalysisConfidence.demo;
  }

  static bool _isCanonicalUnavailableSource(
    CadenceAnalysisSource source,
    CadenceAnalysisConfidence confidence,
  ) {
    return source == CadenceAnalysisSource.unavailableUnknown &&
        confidence == CadenceAnalysisConfidence.unavailable;
  }
}
