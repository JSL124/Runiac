import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../data/weekly_workout_demo_snapshots.dart';
import '../data/you_overview_demo_snapshots.dart';
import 'weekly_plan_day_row.dart';
import 'you_surface_primitives.dart';

class WeeklyPlanCard extends StatelessWidget {
  const WeeklyPlanCard({required this.onViewWorkout, super.key});

  final ValueChanged<WeeklyWorkoutDetailSnapshot> onViewWorkout;

  @override
  Widget build(BuildContext context) {
    return YouDividerSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: YouCardHeader(
                  Icons.calendar_today_outlined,
                  youPlansSnapshot.weeklyTitle,
                  iconSize: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '2 of 3 done',
                style: YouTextStyles.weeklyPlanProgressLabel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            child: LinearProgressIndicator(
              value: 2 / 3,
              minHeight: 7,
              backgroundColor: RuniacColors.primaryBlue.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation(
                RuniacColors.accentOrange,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: RuniacColors.primaryBlue.withValues(alpha: 0.10),
          ),
          const SizedBox(height: 4),
          for (
            var index = 0;
            index < youPlansSnapshot.scheduleRows.length;
            index++
          )
            WeeklyPlanDayRow(
              youPlansSnapshot.scheduleRows[index],
              showDivider: index > 0,
              onTap: _workoutDetailTap(
                youPlansSnapshot.scheduleRows[index],
                onViewWorkout,
              ),
            ),
        ],
      ),
    );
  }
}

VoidCallback? _workoutDetailTap(
  YouPlanScheduleRow row,
  ValueChanged<WeeklyWorkoutDetailSnapshot> onViewWorkout,
) {
  final detailSnapshot = row.detailSnapshot;
  if (!row.opensWorkoutDetail || detailSnapshot == null) {
    return null;
  }

  return () => onViewWorkout(detailSnapshot);
}
