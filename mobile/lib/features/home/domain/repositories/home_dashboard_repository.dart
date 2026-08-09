import '../models/home_dashboard_read_model.dart';

abstract interface class HomeDashboardRepository {
  Future<HomeDashboardReadModel> loadHomeDashboard();
}
