import '../domain/models/viewer_access_read_model.dart';
import '../domain/repositories/viewer_access_repository.dart';

class StaticViewerAccessRepository implements ViewerAccessRepository {
  @override
  Future<ViewerAccessReadModel> loadViewerAccess() async {
    return const ViewerAccessReadModel(
      subscriptionStatusLabel: 'Basic',
      userRoleLabel: 'Basic User',
    );
  }
}
