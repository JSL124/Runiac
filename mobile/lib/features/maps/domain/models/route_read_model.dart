/// Backend-produced route card/detail display contract.
///
/// Ownership, popularity, saved counts, completion counts, and trusted route
/// metadata must not be client-mutated through this model.
class RouteReadModel {
  const RouteReadModel({
    required this.routeId,
    required this.title,
    required this.distanceLabel,
    required this.durationLabel,
    required this.difficultyLabel,
    required this.locationLabel,
  });

  final String routeId;
  final String title;
  final String distanceLabel;
  final String durationLabel;
  final String difficultyLabel;
  final String locationLabel;
}
