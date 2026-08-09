import 'cadence_analysis_series.dart';
import 'coaching_summary_snapshot.dart';
import 'elevation_analysis_series.dart';
import 'pace_analysis_series.dart';
import 'pace_graph_snapshot.dart';
import 'run_route_snapshot.dart';
import 'run_source_display.dart';
import 'workout_metric_contract.dart';

class RunSummarySnapshot {
  const RunSummarySnapshot({
    required this.title,
    required this.dateLabel,
    required this.timeLabel,
    required this.distanceKm,
    required this.avgPace,
    required this.duration,
    required this.avgHeartRate,
    required this.calories,
    required this.routeName,
    this.hasSufficientData = true,
    this.paceAnalysisSeries,
    this.cadenceAnalysisSeries,
    this.elevationSeries = const ElevationAnalysisSeries.unavailable(),
    this.paceGraph = const PaceGraphSnapshot.unavailable(),
    this.route = RunRouteSnapshot.empty,
    this.sourceType = RunSourceType.runiacGps,
    this.importedMetrics = const <ImportedWorkoutMetricContract>[],
    this.coachingSummary = const CoachingSummarySnapshot(
      source: CoachingSummarySource.ruleBased,
      interpretationId: CoachingInterpretationId.basicCompletionInterpretation,
      headline: 'Run completed',
      message:
          'This run has enough distance, time, and pace data for a simple beginner summary. The safest takeaway is that you completed a measurable run and now have a starting point to repeat. Keep the next step calm and consistent rather than trying to prove anything with speed.',
      nextAction: 'Keep the next run easy and repeatable.',
    ),
  });

  final String title;
  final String dateLabel;
  final String timeLabel;
  final String distanceKm;
  final String avgPace;
  final String duration;
  final String avgHeartRate;
  final String calories;
  final String routeName;
  final bool hasSufficientData;
  final PaceAnalysisSeries? paceAnalysisSeries;
  final CadenceAnalysisSeries? cadenceAnalysisSeries;
  final ElevationAnalysisSeries elevationSeries;
  final PaceGraphSnapshot paceGraph;
  final RunRouteSnapshot route;
  final RunSourceType sourceType;
  final List<ImportedWorkoutMetricContract> importedMetrics;
  final CoachingSummarySnapshot coachingSummary;

  String get dateTimeLabel => '$dateLabel · $timeLabel';
  String get sourceLabel => sourceType.label;

  RunSummarySnapshot copyWith({
    PaceAnalysisSeries? paceAnalysisSeries,
    CadenceAnalysisSeries? cadenceAnalysisSeries,
    ElevationAnalysisSeries? elevationSeries,
    PaceGraphSnapshot? paceGraph,
    RunRouteSnapshot? route,
    RunSourceType? sourceType,
    List<ImportedWorkoutMetricContract>? importedMetrics,
    CoachingSummarySnapshot? coachingSummary,
  }) {
    return RunSummarySnapshot(
      title: title,
      dateLabel: dateLabel,
      timeLabel: timeLabel,
      distanceKm: distanceKm,
      avgPace: avgPace,
      duration: duration,
      avgHeartRate: avgHeartRate,
      calories: calories,
      routeName: routeName,
      hasSufficientData: hasSufficientData,
      paceAnalysisSeries: paceAnalysisSeries ?? this.paceAnalysisSeries,
      cadenceAnalysisSeries:
          cadenceAnalysisSeries ?? this.cadenceAnalysisSeries,
      elevationSeries: elevationSeries ?? this.elevationSeries,
      paceGraph: paceGraph ?? this.paceGraph,
      route: route ?? this.route,
      sourceType: sourceType ?? this.sourceType,
      importedMetrics: importedMetrics ?? this.importedMetrics,
      coachingSummary: coachingSummary ?? this.coachingSummary,
    );
  }
}
