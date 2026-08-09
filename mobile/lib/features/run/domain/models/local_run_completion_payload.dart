import '../services/pace_graph_data_builder.dart';
import 'cadence_analysis_series.dart';
import 'elevation_analysis_series.dart';
import 'run_route_snapshot.dart';

class LocalRunCompletionPayload {
  const LocalRunCompletionPayload({
    required this.clientRunSessionId,
    required this.startedAt,
    required this.completedAt,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.avgPaceSecondsPerKm,
    required this.source,
    required this.routePrivacy,
    this.userConfirmedLowDataSave = false,
    this.activityTitle,
    this.routeLabel,
    this.clientAppVersion,
    this.planEnrollmentId,
    this.scheduledWorkoutId,
    this.routeSnapshot = RunRouteSnapshot.empty,
    this.paceGraphSamples = const <PaceGraphSample>[],
    this.cadenceAnalysisSeries,
    this.elevationAnalysisSeries,
    this.elevationUnavailableReason =
        ElevationUnavailableReason.noElevationSeries,
  });

  final String clientRunSessionId;
  final DateTime startedAt;
  final DateTime completedAt;
  final int durationSeconds;
  final int distanceMeters;
  final int avgPaceSecondsPerKm;
  final String source;
  final String routePrivacy;
  final bool userConfirmedLowDataSave;
  final String? activityTitle;
  final String? routeLabel;
  final String? clientAppVersion;
  final String? planEnrollmentId;
  final String? scheduledWorkoutId;
  final RunRouteSnapshot routeSnapshot;
  final List<PaceGraphSample> paceGraphSamples;
  final CadenceAnalysisSeries? cadenceAnalysisSeries;
  final ElevationAnalysisSeries? elevationAnalysisSeries;
  final ElevationUnavailableReason elevationUnavailableReason;

  int get activeDurationSeconds => durationSeconds;

  int get elapsedWallSeconds {
    final wallSeconds = completedAt.difference(startedAt).inSeconds;
    if (wallSeconds < durationSeconds) {
      return durationSeconds;
    }
    return wallSeconds;
  }

  int get pausedDurationSeconds {
    final pausedSeconds = elapsedWallSeconds - activeDurationSeconds;
    if (pausedSeconds < 0) {
      return 0;
    }
    return pausedSeconds;
  }

  Map<String, Object?> toRawClientMap() {
    return <String, Object?>{
      'clientRunSessionId': clientRunSessionId,
      'startedAt': startedAt,
      'completedAt': completedAt,
      'durationSeconds': durationSeconds,
      'activeDurationSeconds': activeDurationSeconds,
      'elapsedWallSeconds': elapsedWallSeconds,
      'pausedDurationSeconds': pausedDurationSeconds,
      'distanceMeters': distanceMeters,
      'avgPaceSecondsPerKm': avgPaceSecondsPerKm,
      'source': source,
      'routePrivacy': routePrivacy,
      if (userConfirmedLowDataSave)
        'userConfirmedLowDataSave': userConfirmedLowDataSave,
      if (activityTitle != null) 'activityTitle': activityTitle,
      if (routeLabel != null) 'routeLabel': routeLabel,
      if (clientAppVersion != null) 'clientAppVersion': clientAppVersion,
      if (planEnrollmentId != null) 'planEnrollmentId': planEnrollmentId,
      if (scheduledWorkoutId != null) 'scheduledWorkoutId': scheduledWorkoutId,
    };
  }

  LocalRunCompletionPayload copyWith({
    bool? userConfirmedLowDataSave,
    RunRouteSnapshot? routeSnapshot,
  }) {
    return LocalRunCompletionPayload(
      clientRunSessionId: clientRunSessionId,
      startedAt: startedAt,
      completedAt: completedAt,
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
      avgPaceSecondsPerKm: avgPaceSecondsPerKm,
      source: source,
      routePrivacy: routePrivacy,
      userConfirmedLowDataSave:
          userConfirmedLowDataSave ?? this.userConfirmedLowDataSave,
      activityTitle: activityTitle,
      routeLabel: routeLabel,
      clientAppVersion: clientAppVersion,
      planEnrollmentId: planEnrollmentId,
      scheduledWorkoutId: scheduledWorkoutId,
      routeSnapshot: routeSnapshot ?? this.routeSnapshot,
      paceGraphSamples: paceGraphSamples,
      cadenceAnalysisSeries: cadenceAnalysisSeries,
      elevationAnalysisSeries: elevationAnalysisSeries,
      elevationUnavailableReason: elevationUnavailableReason,
    );
  }
}
