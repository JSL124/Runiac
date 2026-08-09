/// Backend-produced run summary/result display contract.
///
/// Rewards, progression, and official saved state remain backend-owned and are
/// not calculated by this Flutter read model.
class RunSummaryReadModel {
  const RunSummaryReadModel({
    required this.summaryId,
    required this.title,
    required this.dateLabel,
    required this.timeLabel,
    required this.distanceLabel,
    required this.avgPaceLabel,
    required this.durationLabel,
    required this.avgHeartRateLabel,
    required this.caloriesLabel,
    required this.routeName,
  });

  final String summaryId;
  final String title;
  final String dateLabel;
  final String timeLabel;
  final String distanceLabel;
  final String avgPaceLabel;
  final String durationLabel;
  final String avgHeartRateLabel;
  final String caloriesLabel;
  final String routeName;
}
