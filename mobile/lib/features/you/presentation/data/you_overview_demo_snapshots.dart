import 'package:flutter/material.dart';

import '../../../run/domain/models/run_activity_display_model.dart';
import '../../../run/presentation/models/recent_running_display_data.dart';
import 'weekly_workout_demo_snapshots.dart';

// Display-only You overview data. Future production values must come from
// backend-owned read models, not client-side trusted-state calculations.
const pastTwelveWeeksDistanceGraphLabels = ['APR', 'MAY', 'JUN'];
const pastTwelveWeeksDistanceGraphValues = [
  0.0,
  0.0,
  5.8,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  0.0,
  13.0,
  0.0,
];

final youProgressSnapshot = YouProgressSnapshot(
  distancePeriodSummaries: [
    YouDistancePeriodSummary('Week', 'Weekly Distance', '12.4', 'km'),
    YouDistancePeriodSummary('Month', 'Monthly Distance', '48.6', 'km'),
    YouDistancePeriodSummary('Year', 'Yearly Distance', '326.8', 'km'),
    YouDistancePeriodSummary('All', 'Total Distance', '1,284.2', 'km'),
  ],
  streakValue: '6 days',
  streakCopy: 'Planned rest days keep your streak protected.',
  runs: recentRunningDisplayData,
  runDayPlaceholders: {
    '2026-5': {1, 3, 5, 8, 10, 12, 15, 17, 20},
  },
);

const youPlansSnapshot = YouPlansSnapshot(
  goalLabel: 'Current Goal',
  goalTitle: '10K Preparation',
  goalBadge: 'Week 3 of 8',
  completionLabel: '43% completed',
  completionPercentLabel: '43%',
  completionProgress: 0.43,
  milestoneLabel: 'Next Milestone',
  milestoneTitle: 'Complete 6 km comfortably',
  goalActionLabel: 'View Goal Plan',
  weeklyTitle: "This Week's Plan",
  scheduleRows: [
    YouPlanScheduleRow('Mon', 'Rest Day', '', Icons.hotel_outlined),
    YouPlanScheduleRow(
      'Tue',
      '15 min walk-run',
      'Completed',
      Icons.check_circle,
      active: true,
    ),
    YouPlanScheduleRow('Wed', 'Rest Day', '', Icons.hotel_outlined),
    YouPlanScheduleRow(
      'Thu',
      '20 min easy run',
      'Upcoming · 7:30 AM',
      Icons.radio_button_unchecked,
      active: true,
      opensWorkoutDetail: true,
      detailSnapshot: weeklyWorkoutDetailSnapshot,
    ),
    YouPlanScheduleRow('Fri', 'Rest Day', '', Icons.hotel_outlined),
    YouPlanScheduleRow(
      'Sat',
      '20 min easy run',
      '',
      Icons.radio_button_unchecked,
      active: true,
      opensWorkoutDetail: true,
      detailSnapshot: saturdayWeeklyWorkoutDetailSnapshot,
    ),
    YouPlanScheduleRow('Sun', 'Rest Day', '', Icons.hotel_outlined),
  ],
);

class YouProgressSnapshot {
  const YouProgressSnapshot({
    required this.distancePeriodSummaries,
    required this.streakValue,
    required this.streakCopy,
    required this.runs,
    required this.runDayPlaceholders,
  });

  final List<YouDistancePeriodSummary> distancePeriodSummaries;
  final String streakValue;
  final String streakCopy;
  final List<RunActivityDisplayModel> runs;
  final Map<String, Set<int>> runDayPlaceholders;
}

class YouDistancePeriodSummary {
  const YouDistancePeriodSummary(
    this.segmentLabel,
    this.title,
    this.distance,
    this.unit,
  );

  final String segmentLabel;
  final String title;
  final String distance;
  final String unit;
}

class YouPlansSnapshot {
  const YouPlansSnapshot({
    required this.goalLabel,
    required this.goalTitle,
    required this.goalBadge,
    required this.completionLabel,
    required this.completionPercentLabel,
    required this.completionProgress,
    required this.milestoneLabel,
    required this.milestoneTitle,
    required this.goalActionLabel,
    required this.weeklyTitle,
    required this.scheduleRows,
  });

  final String goalLabel;
  final String goalTitle;
  final String goalBadge;
  final String completionLabel;
  final String completionPercentLabel;
  final double completionProgress;
  final String milestoneLabel;
  final String milestoneTitle;
  final String goalActionLabel;
  final String weeklyTitle;
  final List<YouPlanScheduleRow> scheduleRows;
}

class YouPlanScheduleRow {
  const YouPlanScheduleRow(
    this.day,
    this.title,
    this.status,
    this.icon, {
    this.active = false,
    this.opensWorkoutDetail = false,
    this.detailSnapshot,
    this.weekdayIndex = 0,
    this.isToday = false,
    this.isPast = false,
    this.isFuture = false,
    this.isRunningSession = false,
    this.canOpenDetail = false,
    this.canStart = false,
    this.canEditSchedule = false,
  });

  final String day;
  final String title;
  final String status;
  final IconData icon;
  final bool active;
  final bool opensWorkoutDetail;
  final WeeklyWorkoutDetailSnapshot? detailSnapshot;
  final int weekdayIndex;
  final bool isToday;
  final bool isPast;
  final bool isFuture;
  final bool isRunningSession;
  final bool canOpenDetail;
  final bool canStart;
  final bool canEditSchedule;
}
