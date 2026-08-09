import '../domain/models/shared_routes_read_model.dart';
import '../domain/repositories/shared_routes_repository.dart';
import '../presentation/data/maps_route_demo_snapshots.dart';

class StaticSharedRoutesRepository implements SharedRoutesRepository {
  @override
  Future<SharedRoutesReadModel> loadSharedRoutes() async {
    return SharedRoutesReadModel(
      selectedRoute: SharedRouteReadModel(
        routeId: 'marina-bay-easy-loop',
        title: selectedRouteDemoSnapshot.title,
        distanceLabel: selectedRouteDemoSnapshot.distance,
        difficultyLabel: selectedRouteDemoSnapshot.difficulty,
        durationLabel: selectedRouteDemoSnapshot.duration,
        likeCountLabel: selectedRouteDemoSnapshot.likeCountLabel,
      ),
      routes: [
        for (final route in sharedRoutesDemoSnapshot.routeCards)
          SharedRouteReadModel(
            routeId: route.keySuffix,
            title: route.title,
            distanceLabel: route.distance,
            difficultyLabel: route.difficulty,
            durationLabel: route.duration,
            likeCountLabel: route.likeCountLabel,
          ),
      ],
    );
  }
}
