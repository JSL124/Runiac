import '../models/shared_routes_read_model.dart';

abstract interface class SharedRoutesRepository {
  Future<SharedRoutesReadModel> loadSharedRoutes();
}
