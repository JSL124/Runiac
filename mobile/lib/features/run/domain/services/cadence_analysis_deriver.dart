import 'dart:math' as math;

import '../models/cadence_analysis_derivation.dart';
import '../models/cadence_analysis_series.dart';

class CadenceAnalysisDeriver {
  const CadenceAnalysisDeriver();

  CadenceAnalysisDerivation derive(CadenceAnalysisSeries series) {
    final sourceReason = _unavailableReasonForSource(series);
    if (sourceReason != CadenceAnalysisUnavailableReason.none) {
      return CadenceAnalysisDerivation.unavailable(
        reason: sourceReason,
        source: series.source,
        confidence: series.confidence,
      );
    }

    if (!series.hasMinimumValidSamples()) {
      return CadenceAnalysisDerivation.unavailable(
        reason: CadenceAnalysisUnavailableReason.insufficientSamples,
        source: series.source,
        confidence: series.confidence,
      );
    }

    if (!series.hasMonotonicValidSamples) {
      return CadenceAnalysisDerivation.unavailable(
        reason: CadenceAnalysisUnavailableReason.nonMonotonicSeries,
        source: series.source,
        confidence: series.confidence,
      );
    }

    final cadenceValues = series.validAcceptedSamples
        .map((sample) => sample.cadenceSpm!)
        .toList(growable: false);
    final lowestCadence = cadenceValues.reduce(math.min);
    final highestCadence = cadenceValues.reduce(math.max);
    return CadenceAnalysisDerivation.available(
      source: series.source,
      confidence: series.confidence,
      averageCadenceSpm: _average(cadenceValues),
      lowestCadenceSpm: lowestCadence,
      highestCadenceSpm: highestCadence,
      stability: _stability(
        lowestCadence: lowestCadence,
        highestCadence: highestCadence,
      ),
      trend: _trend(cadenceValues),
    );
  }

  CadenceAnalysisUnavailableReason _unavailableReasonForSource(
    CadenceAnalysisSeries series,
  ) {
    if (series.isStaticDemoSource) {
      return CadenceAnalysisUnavailableReason.staticDemoSource;
    }
    if (series.isUnavailable) {
      return CadenceAnalysisUnavailableReason.unavailableSource;
    }
    if (!series.isProductionAnalysisEligible) {
      return CadenceAnalysisUnavailableReason.invalidSource;
    }
    return CadenceAnalysisUnavailableReason.none;
  }

  int _average(List<int> cadenceValues) {
    return (cadenceValues.reduce((a, b) => a + b) / cadenceValues.length)
        .round();
  }

  CadenceStability _stability({
    required int lowestCadence,
    required int highestCadence,
  }) {
    return highestCadence - lowestCadence <= stableCadenceSpreadSpm
        ? CadenceStability.stable
        : CadenceStability.variable;
  }

  CadenceTrend _trend(List<int> cadenceValues) {
    final midpoint = cadenceValues.length ~/ 2;
    final firstHalf = cadenceValues.take(midpoint).toList(growable: false);
    final secondHalf = cadenceValues.skip(midpoint).toList(growable: false);
    final delta = _average(secondHalf) - _average(firstHalf);
    if (delta <= -cadenceTrendDeltaSpm) {
      return CadenceTrend.dropping;
    }
    if (delta >= cadenceTrendDeltaSpm) {
      return CadenceTrend.rising;
    }
    return CadenceTrend.stable;
  }
}
