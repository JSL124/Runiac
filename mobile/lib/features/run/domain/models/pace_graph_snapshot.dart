class PaceGraphSnapshot {
  const PaceGraphSnapshot({
    required this.isAvailable,
    required this.points,
    required this.yAxisLabels,
    required this.xAxisLabels,
    this.distanceAxisLabels = const [],
    this.unavailableReason,
    this.totalDurationSeconds,
    this.averagePaceSecondsPerKm,
    this.bestPacePoint,
    this.slowestPacePoint,
    this.paceRangeMinSecondsPerKm,
    this.paceRangeMaxSecondsPerKm,
  });

  const PaceGraphSnapshot.unavailable({
    this.unavailableReason = 'insufficient_pace_graph_data',
  }) : isAvailable = false,
       points = const [],
       yAxisLabels = const [],
       xAxisLabels = const [],
       distanceAxisLabels = const [],
       totalDurationSeconds = null,
       averagePaceSecondsPerKm = null,
       bestPacePoint = null,
       slowestPacePoint = null,
       paceRangeMinSecondsPerKm = null,
       paceRangeMaxSecondsPerKm = null;

  final bool isAvailable;
  final List<PaceGraphPoint> points;
  final List<String> yAxisLabels;
  final List<String> xAxisLabels;
  final List<String> distanceAxisLabels;
  final String? unavailableReason;
  final int? totalDurationSeconds;
  final int? averagePaceSecondsPerKm;
  final PaceGraphPoint? bestPacePoint;
  final PaceGraphPoint? slowestPacePoint;
  final int? paceRangeMinSecondsPerKm;
  final int? paceRangeMaxSecondsPerKm;

  bool get hasDistanceAxis {
    return distanceAxisLabels.isNotEmpty &&
        points.length >= 3 &&
        points.every((point) => point.distanceProgressFraction != null);
  }
}

class PaceGraphPoint {
  const PaceGraphPoint({
    required this.elapsedSeconds,
    required this.progressFraction,
    required this.paceSecondsPerKm,
    this.distanceProgressFraction,
    this.displayLabel,
  });

  final int elapsedSeconds;
  final double progressFraction;
  final int paceSecondsPerKm;
  final double? distanceProgressFraction;
  final String? displayLabel;
}
