import '../../../run/domain/models/cadence_analysis_series.dart';
import '../../../run/domain/models/run_feed_publish_source.dart';
import '../../../run/domain/models/run_summary_snapshot.dart';

class ActivityHistoryReadModel {
  ActivityHistoryReadModel({
    required List<ActivityHistoryItemReadModel> recentRuns,
    List<ActivityHistoryMonthReadModel> months =
        const <ActivityHistoryMonthReadModel>[],
  }) : recentRuns = List.unmodifiable(recentRuns),
       months = List.unmodifiable(months);

  final List<ActivityHistoryItemReadModel> recentRuns;
  final List<ActivityHistoryMonthReadModel> months;
}

class ActivityHistoryMonthReadModel {
  ActivityHistoryMonthReadModel({
    required this.label,
    required List<ActivityHistoryItemReadModel> activities,
  }) : activities = List.unmodifiable(activities);

  final String label;
  final List<ActivityHistoryItemReadModel> activities;
}

class ActivityHistoryItemReadModel {
  const ActivityHistoryItemReadModel({
    required this.activityId,
    this.clientRunSessionId,
    required this.title,
    required this.completedAtLabel,
    required this.distanceLabel,
    required this.distanceMeters,
    required this.paceLabel,
    this.durationLabel = '',
    this.timeLabel = '',
    this.routeNameLabel = '',
    this.hasSufficientData = true,
    this.cadenceAnalysisSeries,
    this.summarySnapshot,
    this.isTrustedPersistedRoutePreview = false,
    this.feedPublishSource = const RunFeedPublishSource.disabled(
      FeedPublishDisabledReason.orphanSummary,
    ),
  });

  final String activityId;
  final String? clientRunSessionId;
  final String title;
  final String completedAtLabel;
  final String distanceLabel;
  final int distanceMeters;
  final String paceLabel;
  final String durationLabel;
  final String timeLabel;
  final String routeNameLabel;
  final bool hasSufficientData;
  final CadenceAnalysisSeries? cadenceAnalysisSeries;
  final RunSummarySnapshot? summarySnapshot;
  final bool isTrustedPersistedRoutePreview;
  final RunFeedPublishSource feedPublishSource;

  ActivityHistoryItemReadModel copyWith({
    RunFeedPublishSource? feedPublishSource,
  }) {
    return ActivityHistoryItemReadModel(
      activityId: activityId,
      clientRunSessionId: clientRunSessionId,
      title: title,
      completedAtLabel: completedAtLabel,
      distanceLabel: distanceLabel,
      distanceMeters: distanceMeters,
      paceLabel: paceLabel,
      durationLabel: durationLabel,
      timeLabel: timeLabel,
      routeNameLabel: routeNameLabel,
      hasSufficientData: hasSufficientData,
      cadenceAnalysisSeries: cadenceAnalysisSeries,
      summarySnapshot: summarySnapshot,
      isTrustedPersistedRoutePreview: isTrustedPersistedRoutePreview,
      feedPublishSource: feedPublishSource ?? this.feedPublishSource,
    );
  }
}
