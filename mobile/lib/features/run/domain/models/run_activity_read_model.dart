/// Backend-produced run activity row/read contract.
///
/// The Flutter client may display these values, but it must not decide XP,
/// streak impact, contribution eligibility, or official validation status.
class RunActivityReadModel {
  const RunActivityReadModel({
    required this.activityId,
    required this.title,
    required this.completedAtLabel,
    required this.distanceLabel,
    required this.durationLabel,
    required this.avgPaceLabel,
    required this.routeLabel,
  });

  final String activityId;
  final String title;
  final String completedAtLabel;
  final String distanceLabel;
  final String durationLabel;
  final String avgPaceLabel;
  final String routeLabel;
}
