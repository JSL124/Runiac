const demoCadenceGraphTargetLabel = 'Demo Target 160-175';
const demoCadenceGraphTargetMinSpm = 160;
const demoCadenceGraphTargetMaxSpm = 175;

enum CadenceGraphTargetKind { demo, personalized }

class CadenceGraphSnapshot {
  const CadenceGraphSnapshot({
    required this.isAvailable,
    required this.points,
    required this.yAxisLabels,
    required this.xAxisLabels,
    this.unavailableReason,
    this.totalDurationSeconds,
    this.averageCadenceSpm,
    this.lowestCadencePoint,
    this.highestCadencePoint,
    this.cadenceRangeMinSpm,
    this.cadenceRangeMaxSpm,
    this.targetMinCadenceSpm,
    this.targetMaxCadenceSpm,
    this.targetLabel,
    this.targetKind,
  });

  const CadenceGraphSnapshot.unavailable({
    this.unavailableReason = 'insufficient_cadence_graph_data',
  }) : isAvailable = false,
       points = const [],
       yAxisLabels = const [],
       xAxisLabels = const [],
       totalDurationSeconds = null,
       averageCadenceSpm = null,
       lowestCadencePoint = null,
       highestCadencePoint = null,
       cadenceRangeMinSpm = null,
       cadenceRangeMaxSpm = null,
       targetMinCadenceSpm = null,
       targetMaxCadenceSpm = null,
       targetLabel = null,
       targetKind = null;

  final bool isAvailable;
  final List<CadenceGraphPoint> points;
  final List<String> yAxisLabels;
  final List<String> xAxisLabels;
  final String? unavailableReason;
  final int? totalDurationSeconds;
  final int? averageCadenceSpm;
  final CadenceGraphPoint? lowestCadencePoint;
  final CadenceGraphPoint? highestCadencePoint;
  final int? cadenceRangeMinSpm;
  final int? cadenceRangeMaxSpm;
  final int? targetMinCadenceSpm;
  final int? targetMaxCadenceSpm;
  final String? targetLabel;
  final CadenceGraphTargetKind? targetKind;
}

class CadenceGraphPoint {
  const CadenceGraphPoint({
    required this.elapsedSeconds,
    required this.progressFraction,
    required this.cadenceSpm,
    this.displayLabel,
  });

  final int elapsedSeconds;
  final double progressFraction;
  final int cadenceSpm;
  final String? displayLabel;
}
