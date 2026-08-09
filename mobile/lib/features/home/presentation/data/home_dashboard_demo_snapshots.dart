import 'package:flutter/material.dart';

import '../../../../core/assets/runiac_assets.dart';

const homeTodayPlanDemoSnapshot = HomeTodayPlanDemoSnapshot(
  heroAssetPath: RuniacAssets.homeTodayPlanRunner,
  title: 'Today\'s Plan',
  headline: '20 min easy run',
  badgeLabel: 'Goal Mode: First 5K',
  message: 'Build consistency with an easy, comfortable effort.',
  secondaryActionLabel: 'View Plan',
  primaryActionLabel: 'Quick Start',
);

const homeExploreRouteDemoSnapshots = <HomeExploreRouteDemoSnapshot>[
  HomeExploreRouteDemoSnapshot(
    title: 'Haneul Park Trail',
    distance: '3.2 km',
    subtitle: '3.2 km · 25 min · Easy',
  ),
  HomeExploreRouteDemoSnapshot(
    title: 'Olympic Park Loop',
    distance: '5.0 km',
    subtitle: '5.0 km · 40 min · Moderate',
  ),
  HomeExploreRouteDemoSnapshot(
    title: 'Marina Bay Easy Loop',
    distance: '3.2 km',
    subtitle: '3.2 km · 25 min · Easy',
  ),
];

const homeDashboardDemoSnapshot = HomeDashboardDemoSnapshot(
  todayPlan: homeTodayPlanDemoSnapshot,
  goal: HomeGoalProgressDemoSnapshot(
    title: 'First 10K Preparation',
    weekLabel: 'Week 3 of 8',
    progressLabel: '43%',
    milestoneLabel: 'Next Milestone',
    milestoneValue: 'Complete 6 km comfortably',
  ),
  streak: HomeMetricDemoSnapshot(
    title: 'Streak',
    value: '6 days',
    caption: 'Keep it going!',
  ),
  xp: HomeMetricDemoSnapshot(
    title: 'XP',
    value: '1,240 xp',
    caption: '360 XP to Lv.13',
  ),
  insight: HomeInsightDemoSnapshot(
    title: 'Advanced Insight',
    rows: [
      HomeInsightRowDemoSnapshot(
        icon: Icons.show_chart_rounded,
        label: 'Pace rhythm',
        value: 'Improved',
      ),
      HomeInsightRowDemoSnapshot(
        icon: Icons.bar_chart_rounded,
        label: 'Effort balance',
        value: 'Balanced',
      ),
      HomeInsightRowDemoSnapshot(
        icon: Icons.track_changes_rounded,
        label: 'Goal progress',
        value: 'On track',
      ),
    ],
    chartLabels: ['May 6', 'May 13', 'May 20', 'May 27', 'Jun 3'],
    chartValues: [0.42, 0.33, 0.18, 0.36, 0.55, 0.62, 0.72],
  ),
  exploreRoutes: homeExploreRouteDemoSnapshots,
);

class HomeDashboardDemoSnapshot {
  const HomeDashboardDemoSnapshot({
    required this.todayPlan,
    required this.goal,
    required this.streak,
    required this.xp,
    required this.insight,
    required this.exploreRoutes,
  });

  final HomeTodayPlanDemoSnapshot todayPlan;
  final HomeGoalProgressDemoSnapshot goal;
  final HomeMetricDemoSnapshot streak;
  final HomeMetricDemoSnapshot xp;
  final HomeInsightDemoSnapshot insight;
  final List<HomeExploreRouteDemoSnapshot> exploreRoutes;
}

class HomeTodayPlanDemoSnapshot {
  const HomeTodayPlanDemoSnapshot({
    required this.heroAssetPath,
    required this.title,
    required this.headline,
    required this.badgeLabel,
    required this.message,
    required this.secondaryActionLabel,
    required this.primaryActionLabel,
  });

  final String heroAssetPath;
  final String title;
  final String headline;
  final String badgeLabel;
  final String message;
  final String secondaryActionLabel;
  final String primaryActionLabel;
}

class HomeGoalProgressDemoSnapshot {
  const HomeGoalProgressDemoSnapshot({
    required this.title,
    required this.weekLabel,
    required this.progressLabel,
    required this.milestoneLabel,
    required this.milestoneValue,
  });

  final String title;
  final String weekLabel;
  final String progressLabel;
  final String milestoneLabel;
  final String milestoneValue;
}

class HomeMetricDemoSnapshot {
  const HomeMetricDemoSnapshot({
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
  final String value;
  final String caption;
}

class HomeInsightDemoSnapshot {
  const HomeInsightDemoSnapshot({
    required this.title,
    required this.rows,
    required this.chartLabels,
    required this.chartValues,
  });

  final String title;
  final List<HomeInsightRowDemoSnapshot> rows;
  final List<String> chartLabels;

  // Static display-only sample points for the preview chart.
  final List<double> chartValues;
}

class HomeInsightRowDemoSnapshot {
  const HomeInsightRowDemoSnapshot({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class HomeExploreRouteDemoSnapshot {
  const HomeExploreRouteDemoSnapshot({
    required this.title,
    required this.distance,
    required this.subtitle,
  });

  final String title;
  final String distance;
  final String subtitle;
}
