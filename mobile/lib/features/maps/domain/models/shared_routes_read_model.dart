/// Backend-produced shared route collection display contract.
///
/// Route popularity, saved state, completion counts, and trusted route
/// metadata are read-only backend outputs for the Flutter client.
class SharedRoutesReadModel {
  SharedRoutesReadModel({
    required this.selectedRoute,
    required List<SharedRouteReadModel> routes,
  }) : routes = List.unmodifiable(routes);

  final SharedRouteReadModel selectedRoute;
  final List<SharedRouteReadModel> routes;
}

/// Backend-produced shared route card/detail display contract.
class SharedRouteReadModel {
  const SharedRouteReadModel({
    required this.routeId,
    required this.title,
    required this.distanceLabel,
    required this.difficultyLabel,
    this.durationLabel = '',
    this.likeCountLabel = '',
  });

  final String routeId;
  final String title;
  final String distanceLabel;
  final String difficultyLabel;
  final String durationLabel;
  final String likeCountLabel;
}
