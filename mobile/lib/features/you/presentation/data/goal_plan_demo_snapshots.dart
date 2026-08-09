import 'weekly_workout_demo_snapshots.dart';

enum GoalPlanWeekStatus { completed, current, upcoming, goalWeek }

// Display-only goal plan preview. Future production progress/status must be
// supplied by backend-owned read models.
const goalPlanDisplaySnapshot = GoalPlanDisplaySnapshot(
  title: '10K Goal Plan',
  planName: '10K Preparation',
  weekSummary: 'Week 3 of 8',
  progressValue: 0.43,
  progressPercentLabel: '43%',
  progressLabel: '43% completed',
  currentPhaseLabel: 'Current Phase',
  currentPhase: 'Base Endurance',
  weeks: [
    GoalPlanWeekDisplaySnapshot(
      weekLabel: 'Week 1',
      title: 'Build Routine',
      status: GoalPlanWeekStatus.completed,
    ),
    GoalPlanWeekDisplaySnapshot(
      weekLabel: 'Week 2',
      title: 'Easy Distance',
      status: GoalPlanWeekStatus.completed,
    ),
    GoalPlanWeekDisplaySnapshot(
      weekLabel: 'Week 3',
      title: 'Base Endurance',
      status: GoalPlanWeekStatus.current,
    ),
    GoalPlanWeekDisplaySnapshot(
      weekLabel: 'Week 4',
      title: '6 km Milestone',
      status: GoalPlanWeekStatus.upcoming,
    ),
    GoalPlanWeekDisplaySnapshot(
      weekLabel: 'Week 5',
      title: 'Longer Effort',
      status: GoalPlanWeekStatus.upcoming,
    ),
    GoalPlanWeekDisplaySnapshot(
      weekLabel: 'Week 6',
      title: '8 km Progression',
      status: GoalPlanWeekStatus.upcoming,
    ),
    GoalPlanWeekDisplaySnapshot(
      weekLabel: 'Week 7',
      title: '10K Preparation',
      status: GoalPlanWeekStatus.upcoming,
    ),
    GoalPlanWeekDisplaySnapshot(
      weekLabel: 'Week 8',
      title: '10K Attempt',
      status: GoalPlanWeekStatus.goalWeek,
    ),
  ],
);

const sampleGoalPlanDailyRows = [
  GoalPlanDayDisplaySnapshot(
    weekday: 'Monday',
    workoutType: 'Easy Run',
    distanceOrTime: '3 km',
  ),
  GoalPlanDayDisplaySnapshot(
    weekday: 'Tuesday',
    workoutType: 'Rest',
    distanceOrTime: '0 min',
  ),
  GoalPlanDayDisplaySnapshot(
    weekday: 'Wednesday',
    workoutType: 'Tempo Run',
    distanceOrTime: '25 min',
  ),
  GoalPlanDayDisplaySnapshot(
    weekday: 'Thursday',
    workoutType: 'Rest',
    distanceOrTime: '0 min',
  ),
  GoalPlanDayDisplaySnapshot(
    weekday: 'Friday',
    workoutType: 'Easy Run',
    distanceOrTime: '4 km',
  ),
  GoalPlanDayDisplaySnapshot(
    weekday: 'Saturday',
    workoutType: 'Long Run',
    distanceOrTime: '5 km',
  ),
  GoalPlanDayDisplaySnapshot(
    weekday: 'Sunday',
    workoutType: 'Rest',
    distanceOrTime: '0 min',
  ),
];

class GoalPlanDisplaySnapshot {
  const GoalPlanDisplaySnapshot({
    required this.title,
    required this.planName,
    required this.weekSummary,
    required this.progressValue,
    required this.progressPercentLabel,
    required this.progressLabel,
    required this.currentPhaseLabel,
    required this.currentPhase,
    required this.weeks,
    this.showProgress = true,
  });

  final String title;
  final String planName;
  final String weekSummary;
  final double progressValue;
  final String progressPercentLabel;
  final String progressLabel;
  final String currentPhaseLabel;
  final String currentPhase;
  final List<GoalPlanWeekDisplaySnapshot> weeks;
  final bool showProgress;
}

class GoalPlanWeekDisplaySnapshot {
  const GoalPlanWeekDisplaySnapshot({
    required this.weekLabel,
    required this.title,
    required this.status,
    this.dailyPlan = sampleGoalPlanDailyRows,
  });

  final String weekLabel;
  final String title;
  final GoalPlanWeekStatus status;
  final List<GoalPlanDayDisplaySnapshot> dailyPlan;
}

class GoalPlanDayDisplaySnapshot {
  const GoalPlanDayDisplaySnapshot({
    required this.weekday,
    required this.workoutType,
    required this.distanceOrTime,
    this.workoutDetail,
  });

  final String weekday;
  final String workoutType;
  final String distanceOrTime;
  final WeeklyWorkoutDetailSnapshot? workoutDetail;
}
