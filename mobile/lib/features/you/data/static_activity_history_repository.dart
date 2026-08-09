import '../domain/models/activity_history_read_model.dart';
import '../domain/repositories/activity_history_repository.dart';
import '../presentation/data/activity_history_demo_snapshots.dart';

class StaticActivityHistoryRepository implements ActivityHistoryRepository {
  const StaticActivityHistoryRepository();

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    final months = activityHistoryDisplayData
        .map(
          (month) => ActivityHistoryMonthReadModel(
            label: month.label,
            activities: month.activities
                .map(
                  (activity) => ActivityHistoryItemReadModel(
                    activityId: activity.summary.title,
                    title: activity.title,
                    completedAtLabel: activity.timeAgoLabel,
                    distanceLabel: activity.distanceLabel,
                    distanceMeters: activity.distanceMeters,
                    paceLabel: activity.paceLabel,
                    durationLabel: activity.durationLabel,
                    timeLabel: activity.summary.timeLabel,
                    routeNameLabel: activity.summary.routeName,
                    hasSufficientData: activity.summary.hasSufficientData,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);

    return ActivityHistoryReadModel(
      recentRuns: months
          .expand((month) => month.activities)
          .take(3)
          .toList(growable: false),
      months: months,
    );
  }
}
