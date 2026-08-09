/// Backend-produced Home dashboard display/read contract.
///
/// XP, level, streak, plan completion, and weekly/monthly XP values are
/// backend-produced outputs here, never client-owned calculations.
class HomeDashboardReadModel {
  const HomeDashboardReadModel({
    required this.todayPlanTitle,
    required this.todayPlanSubtitle,
    required this.goalTitle,
    required this.goalProgressLabel,
    required this.streakLabel,
    required this.xpLabel,
    required this.levelLabel,
    required this.weeklySummaryLabel,
  });

  final String todayPlanTitle;
  final String todayPlanSubtitle;
  final String goalTitle;
  final String goalProgressLabel;
  final String streakLabel;
  final String xpLabel;
  final String levelLabel;
  final String weeklySummaryLabel;
}
