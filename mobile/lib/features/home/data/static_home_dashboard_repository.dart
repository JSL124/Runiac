import '../domain/models/home_dashboard_read_model.dart';
import '../domain/repositories/home_dashboard_repository.dart';
import '../presentation/data/home_dashboard_demo_snapshots.dart';

class StaticHomeDashboardRepository implements HomeDashboardRepository {
  @override
  Future<HomeDashboardReadModel> loadHomeDashboard() async {
    const snapshot = homeDashboardDemoSnapshot;

    return HomeDashboardReadModel(
      todayPlanTitle: snapshot.todayPlan.headline,
      todayPlanSubtitle: snapshot.todayPlan.message,
      goalTitle: snapshot.goal.title,
      goalProgressLabel: snapshot.goal.progressLabel,
      streakLabel: snapshot.streak.value,
      xpLabel: snapshot.xp.value,
      levelLabel: snapshot.xp.caption,
      weeklySummaryLabel: snapshot.goal.weekLabel,
    );
  }
}
