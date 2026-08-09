import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../data/you_overview_demo_snapshots.dart';

/// One day of the training plan, as a row in the You tab's week view.
///
/// [WeeklyPlanDayRowState] is the whole design of this widget: rest, completed,
/// completed today, missed and the upcoming states are separate cases rather
/// than a boolean, because a missed session and a rest day must never look
/// alike to a beginner — one is the plan working, the other is not.
enum WeeklyPlanDayRowState {
  rest,
  completed,
  completedToday,
  missed,
  todayUpcoming,
  futureUpcoming,
  inactive,
}

class WeeklyPlanDayRow extends StatelessWidget {
  const WeeklyPlanDayRow(
    this.display, {
    required this.showDivider,
    this.onTap,
    super.key,
  });

  final YouPlanScheduleRow display;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null;
    final state = _stateFor(display, tappable: tappable);
    final rowColor = switch (state) {
      WeeklyPlanDayRowState.completedToday ||
      WeeklyPlanDayRowState.todayUpcoming =>
        RuniacColors.accentOrange.withValues(alpha: 0.06),
      WeeklyPlanDayRowState.futureUpcoming =>
        RuniacColors.primaryBlue.withValues(alpha: 0.06),
      WeeklyPlanDayRowState.missed => RuniacColors.textSecondary.withValues(
        alpha: 0.08,
      ),
      _ => null,
    };
    final usesTodayTreatment =
        state == WeeklyPlanDayRowState.completedToday ||
        state == WeeklyPlanDayRowState.todayUpcoming;
    final usesBlueActiveTreatment =
        state == WeeklyPlanDayRowState.completed ||
        state == WeeklyPlanDayRowState.futureUpcoming;
    final missed = state == WeeklyPlanDayRowState.missed;
    final dayColor = missed
        ? RuniacColors.textSecondary
        : usesTodayTreatment
        ? const Color(0xFFE8550A)
        : usesBlueActiveTreatment
        ? RuniacColors.primaryBlue
        : RuniacColors.primaryBlue.withValues(alpha: 0.45);
    final subtitleColor = missed
        ? RuniacColors.textSecondary
        : usesTodayTreatment
        ? const Color(0xFFE8550A)
        : RuniacColors.primaryBlue.withValues(alpha: 0.60);
    final status = display.status;
    final row = Container(
      key: missed
          ? ValueKey('weekly_plan_missed_${display.weekdayIndex}')
          : null,
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: rowColor,
        border:
            showDivider &&
                state != WeeklyPlanDayRowState.todayUpcoming &&
                state != WeeklyPlanDayRowState.futureUpcoming
            ? Border(
                top: BorderSide(
                  color: RuniacColors.primaryBlue.withValues(alpha: 0.10),
                ),
              )
            : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              display.day,
              style: TextStyle(
                color: dayColor,
                fontSize: 13,
                fontWeight: usesTodayTreatment || usesBlueActiveTreatment
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 30, child: WeeklyPlanStatusNode(state: state)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display.title,
                  style: TextStyle(
                    color: missed
                        ? RuniacColors.textSecondary
                        : state == WeeklyPlanDayRowState.rest
                        ? RuniacColors.primaryBlue.withValues(alpha: 0.75)
                        : RuniacColors.primaryBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (status.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    status,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 12,
                      fontWeight:
                          state == WeeklyPlanDayRowState.todayUpcoming ||
                              state == WeeklyPlanDayRowState.completedToday
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (tappable) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              key: const ValueKey('weekly_workout_detail_chevron'),
              color: usesTodayTreatment
                  ? RuniacColors.accentOrange
                  : RuniacColors.primaryBlue.withValues(alpha: 0.45),
              size: 20,
            ),
          ],
        ],
      ),
    );

    if (!tappable) {
      return row;
    }

    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: row,
        ),
      ),
    );
  }
}

class WeeklyPlanStatusNode extends StatelessWidget {
  const WeeklyPlanStatusNode({required this.state, super.key});

  final WeeklyPlanDayRowState state;

  @override
  Widget build(BuildContext context) {
    if (state == WeeklyPlanDayRowState.completed ||
        state == WeeklyPlanDayRowState.completedToday) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: RuniacColors.primaryBlue,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: RuniacColors.primaryBlue.withValues(alpha: 0.24),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.check_rounded,
          color: RuniacColors.white,
          size: 17,
        ),
      );
    }

    if (state == WeeklyPlanDayRowState.todayUpcoming ||
        state == WeeklyPlanDayRowState.futureUpcoming) {
      final today = state == WeeklyPlanDayRowState.todayUpcoming;
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: today
              ? RuniacColors.accentOrange.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            width: today ? 2.3 : 2,
            color: today
                ? RuniacColors.accentOrange
                : RuniacColors.primaryBlue.withValues(alpha: 0.30),
          ),
        ),
      );
    }

    if (state == WeeklyPlanDayRowState.rest) {
      return Icon(
        Icons.hotel_outlined,
        color: RuniacColors.primaryBlue.withValues(alpha: 0.45),
        size: 24,
      );
    }

    if (state == WeeklyPlanDayRowState.missed) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: RuniacColors.textSecondary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: RuniacColors.textSecondary.withValues(alpha: 0.35),
          ),
        ),
        child: const Icon(
          Icons.remove_rounded,
          color: RuniacColors.textSecondary,
          size: 17,
        ),
      );
    }

    return const SizedBox(width: 28, height: 28);
  }
}

WeeklyPlanDayRowState _stateFor(
  YouPlanScheduleRow display, {
  required bool tappable,
}) {
  final completed = display.status == 'Completed';
  if (completed && display.isToday) {
    return WeeklyPlanDayRowState.completedToday;
  }
  if (completed) {
    return WeeklyPlanDayRowState.completed;
  }
  if (display.isPast && display.isRunningSession) {
    return WeeklyPlanDayRowState.missed;
  }
  if (display.title == 'Rest Day') {
    return WeeklyPlanDayRowState.rest;
  }
  final upcomingStatus = display.status.startsWith('Upcoming · ');
  final legacyCurrentUpcoming = upcomingStatus && display.weekdayIndex == 0;
  if ((display.isToday || legacyCurrentUpcoming) &&
      (display.isRunningSession || upcomingStatus)) {
    return WeeklyPlanDayRowState.todayUpcoming;
  }
  if (tappable || upcomingStatus || display.active) {
    return WeeklyPlanDayRowState.futureUpcoming;
  }
  return WeeklyPlanDayRowState.inactive;
}
