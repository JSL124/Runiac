import '../models/viewer_access_read_model.dart';

abstract interface class ViewerAccessRepository {
  Future<ViewerAccessReadModel> loadViewerAccess();
}
