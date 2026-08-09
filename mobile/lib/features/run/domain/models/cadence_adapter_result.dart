import 'cadence_analysis_series.dart';

class CadenceAdapterResult {
  CadenceAdapterResult({
    required this.source,
    required this.confidence,
    required List<CadenceAnalysisSample> samples,
    this.summaryCadenceSpm,
    this.unavailableReason,
  }) : samples = List<CadenceAnalysisSample>.unmodifiable(samples) {
    _validate();
  }

  final CadenceAnalysisSource source;
  final CadenceAnalysisConfidence confidence;
  final List<CadenceAnalysisSample> samples;
  final int? summaryCadenceSpm;
  final String? unavailableReason;

  List<CadenceAnalysisSample> get acceptedSamples {
    return List<CadenceAnalysisSample>.unmodifiable(
      samples.where(
        (sample) => sample.status == CadenceAnalysisSampleStatus.accepted,
      ),
    );
  }

  List<CadenceAnalysisSample> get rejectedSamples {
    return List<CadenceAnalysisSample>.unmodifiable(
      samples.where(
        (sample) => sample.status == CadenceAnalysisSampleStatus.rejected,
      ),
    );
  }

  bool get hasSummaryOnlyCadence {
    return summaryCadenceSpm != null && samples.isEmpty;
  }

  bool get affectsBackendOwnedProgression => false;

  CadenceAnalysisSeries toAnalysisSeries() {
    return CadenceAnalysisSeries(
      source: source,
      confidence: confidence,
      samples: samples,
    );
  }

  void _validate() {
    if (summaryCadenceSpm != null && samples.isNotEmpty) {
      throw ArgumentError.value(summaryCadenceSpm, 'summaryCadenceSpm');
    }
    if (unavailableReason != null &&
        (samples.isNotEmpty || summaryCadenceSpm != null)) {
      throw ArgumentError.value(unavailableReason, 'unavailableReason');
    }
  }
}
