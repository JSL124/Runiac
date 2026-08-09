import 'cadence_analysis_series.dart';

enum CadenceSource { phoneMotion, wearable, importedWorkout }

enum CadenceConfidence { high, estimated, low, unavailable }

class RunCadenceSample {
  const RunCadenceSample({
    required this.recordedAt,
    required this.stepsPerMinute,
    required this.source,
    required this.confidence,
  });

  final DateTime recordedAt;
  final double stepsPerMinute;
  final CadenceSource source;
  final CadenceConfidence confidence;

  bool get isUsable {
    return stepsPerMinute.isFinite &&
        stepsPerMinute >= 40 &&
        stepsPerMinute <= maxCadenceAnalysisSpm &&
        confidence != CadenceConfidence.unavailable;
  }
}
