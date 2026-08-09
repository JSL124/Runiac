import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';

class FirstWeekPreview extends StatelessWidget {
  const FirstWeekPreview({required this.workouts, super.key});

  final List<BeginnerAdaptiveWorkout> workouts;

  @override
  Widget build(BuildContext context) {
    final rows = workouts.map(_FirstWeekPreviewRow.fromWorkout).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _blueWithOpacity(.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(
              'First week preview',
              style: _textStyle(
                size: 13.5,
                weight: FontWeight.w700,
                color: RuniacColors.primaryBlue,
              ),
            ),
          ),
          for (var index = 0; index < rows.length; index++)
            _FirstWeekRow(row: rows[index], showTopBorder: index != 0),
        ],
      ),
    );
  }
}

class _FirstWeekPreviewRow {
  const _FirstWeekPreviewRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  factory _FirstWeekPreviewRow.fromWorkout(BeginnerAdaptiveWorkout workout) {
    return _FirstWeekPreviewRow(
      icon: switch (workout.kind) {
        BeginnerWorkoutKind.easyRun => Icons.directions_run_rounded,
        BeginnerWorkoutKind.runWalk => Icons.auto_awesome_rounded,
        BeginnerWorkoutKind.walkRun => Icons.directions_walk_rounded,
        BeginnerWorkoutKind.recoveryWalk => Icons.favorite_border_rounded,
        BeginnerWorkoutKind.steadyRun ||
        BeginnerWorkoutKind.controlledSteadyRun => Icons.auto_awesome_rounded,
        BeginnerWorkoutKind.longerEasyRun ||
        BeginnerWorkoutKind.recoveryRun => Icons.directions_run_rounded,
        BeginnerWorkoutKind.restOrMobility => Icons.self_improvement_rounded,
      },
      title:
          '${workout.dayLabel} · ${workout.title} · ${workout.durationMinutes} min',
      subtitle: workout.description,
    );
  }

  final IconData icon;
  final String title;
  final String subtitle;
}

class _FirstWeekRow extends StatelessWidget {
  const _FirstWeekRow({required this.row, required this.showTopBorder});

  final _FirstWeekPreviewRow row;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        border: showTopBorder
            ? Border(top: BorderSide(color: _blueWithOpacity(.10)))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _blueWithOpacity(.06),
              shape: BoxShape.circle,
            ),
            child: Icon(row.icon, color: RuniacColors.primaryBlue, size: 19),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: _textStyle(
                    size: 14,
                    weight: FontWeight.w700,
                    color: RuniacColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  row.subtitle,
                  style: _textStyle(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: _blueWithOpacity(.60),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _blueWithOpacity(double opacity) {
  return RuniacColors.primaryBlue.withValues(alpha: opacity);
}

TextStyle _textStyle({
  required double size,
  required FontWeight weight,
  required Color color,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: 0,
  );
}
