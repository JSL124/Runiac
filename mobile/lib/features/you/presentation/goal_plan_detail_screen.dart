import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/runiac_back_header.dart';
import 'data/goal_plan_demo_snapshots.dart';
import 'data/weekly_workout_demo_snapshots.dart';

class GoalPlanDetailScreen extends StatefulWidget {
  const GoalPlanDetailScreen({
    required this.onBack,
    this.onWorkoutSelected,
    this.snapshot = goalPlanDisplaySnapshot,
    super.key,
  });

  final VoidCallback onBack;
  final ValueChanged<WeeklyWorkoutDetailSnapshot>? onWorkoutSelected;
  final GoalPlanDisplaySnapshot snapshot;

  @override
  State<GoalPlanDetailScreen> createState() => _GoalPlanDetailScreenState();
}

class _GoalPlanDetailScreenState extends State<GoalPlanDetailScreen> {
  final _expandedWeekIndexes = <int>{};

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RuniacColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: widget.snapshot.title,
              tooltip: 'Back to Plans',
              onBack: widget.onBack,
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(overscroll: false),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _GoalPlanDetailAccentStrip(),
                      const SizedBox(height: 14),
                      _GoalPlanSummaryCard(widget.snapshot),
                      const SizedBox(height: 12),
                      _GoalPlanTimelineCard(
                        weeks: widget.snapshot.weeks,
                        expandedWeekIndexes: _expandedWeekIndexes,
                        onWorkoutSelected: widget.onWorkoutSelected,
                        onWeekSelected: (index) {
                          setState(() {
                            if (_expandedWeekIndexes.contains(index)) {
                              _expandedWeekIndexes.remove(index);
                            } else {
                              _expandedWeekIndexes.add(index);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalPlanDetailAccentStrip extends StatelessWidget {
  const _GoalPlanDetailAccentStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('goal_plan_detail_header_accent_strip'),
      children: [
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: RuniacColors.primaryBlue,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 34,
          height: 4,
          decoration: BoxDecoration(
            color: RuniacColors.accentOrange,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _GoalPlanSummaryCard extends StatelessWidget {
  const _GoalPlanSummaryCard(this.snapshot);

  final GoalPlanDisplaySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: RuniacColors.border),
                ),
                child: const Icon(
                  Icons.directions_run,
                  color: RuniacColors.primaryBlue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(snapshot.planName, style: _cardTitleStyle),
                    const SizedBox(height: 3),
                    Text(snapshot.weekSummary, style: _bodyStyle),
                    const SizedBox(height: 8),
                    _GoalPlanProgress(snapshot),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: RuniacColors.border),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: _softIconDecoration,
                child: const Icon(
                  Icons.stacked_bar_chart,
                  color: RuniacColors.primaryBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(snapshot.currentPhaseLabel, style: _smallBodyStyle),
                    const SizedBox(height: 2),
                    Text(snapshot.currentPhase, style: _bodyStrongStyle),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalPlanProgress extends StatelessWidget {
  const _GoalPlanProgress(this.snapshot);

  final GoalPlanDisplaySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (!snapshot.showProgress) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: RuniacColors.cardBorder),
          ),
          child: Text(snapshot.progressLabel, style: _smallBodyStyle),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              child: LinearProgressIndicator(
                value: snapshot.progressValue,
                minHeight: 12,
                backgroundColor: const Color(0xFFE8EEF8),
                valueColor: const AlwaysStoppedAnimation(
                  RuniacColors.accentOrange,
                ),
              ),
            ),
            Text(snapshot.progressPercentLabel, style: _progressInsideStyle),
          ],
        ),
        const SizedBox(height: 6),
        Text(snapshot.progressLabel, style: _smallBodyStyle),
      ],
    );
  }
}

class _GoalPlanTimelineCard extends StatelessWidget {
  const _GoalPlanTimelineCard({
    required this.weeks,
    required this.expandedWeekIndexes,
    required this.onWeekSelected,
    this.onWorkoutSelected,
  });

  final List<GoalPlanWeekDisplaySnapshot> weeks;
  final Set<int> expandedWeekIndexes;
  final ValueChanged<int> onWeekSelected;
  final ValueChanged<WeeklyWorkoutDetailSnapshot>? onWorkoutSelected;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        children: [
          for (var index = 0; index < weeks.length; index++) ...[
            _GoalPlanTimelineRow(
              display: weeks[index],
              isExpanded: expandedWeekIndexes.contains(index),
              onSelected: () => onWeekSelected(index),
              onWorkoutSelected: onWorkoutSelected,
            ),
            if (index < weeks.length - 1)
              const Divider(height: 1, color: RuniacColors.border),
          ],
        ],
      ),
    );
  }
}

class _GoalPlanTimelineRow extends StatelessWidget {
  const _GoalPlanTimelineRow({
    required this.display,
    required this.isExpanded,
    required this.onSelected,
    this.onWorkoutSelected,
  });

  final GoalPlanWeekDisplaySnapshot display;
  final bool isExpanded;
  final VoidCallback onSelected;
  final ValueChanged<WeeklyWorkoutDetailSnapshot>? onWorkoutSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('goal_plan_detail_week_${display.weekLabel}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('goal_plan_detail_week_toggle_${display.weekLabel}'),
            borderRadius: BorderRadius.circular(16),
            onTap: onSelected,
            child: Container(
              key: display.status == GoalPlanWeekStatus.current
                  ? const ValueKey('goal_plan_detail_current_week_highlight')
                  : null,
              constraints: const BoxConstraints(minHeight: 58),
              decoration: BoxDecoration(
                color: display.status == GoalPlanWeekStatus.current
                    ? const Color(0xFFF7FAFF)
                    : null,
                borderRadius: display.status == GoalPlanWeekStatus.current
                    ? BorderRadius.circular(16)
                    : null,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 30,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _TimelineMarker(
                            key: ValueKey(
                              'goal_plan_detail_marker_${display.weekLabel}',
                            ),
                            status: display.status,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Text(
                                display.weekLabel,
                                style: _smallBodyStyle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                display.title,
                                style:
                                    display.status == GoalPlanWeekStatus.current
                                    ? _bodyStrongStyle
                                    : _bodyStyle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              key: ValueKey(
                                'goal_plan_detail_chevron_${display.weekLabel}_${isExpanded ? 'expanded' : 'collapsed'}',
                              ),
                              color: RuniacColors.textSecondary,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isExpanded)
          _WeeklyDailyPlanRows(
            weekLabel: display.weekLabel,
            dailyPlan: display.dailyPlan,
            onWorkoutSelected: onWorkoutSelected,
          ),
      ],
    );
  }
}

class _WeeklyDailyPlanRows extends StatelessWidget {
  const _WeeklyDailyPlanRows({
    required this.weekLabel,
    required this.dailyPlan,
    this.onWorkoutSelected,
  });

  final String weekLabel;
  final List<GoalPlanDayDisplaySnapshot> dailyPlan;
  final ValueChanged<WeeklyWorkoutDetailSnapshot>? onWorkoutSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('goal_plan_detail_daily_plan_$weekLabel'),
      padding: const EdgeInsets.fromLTRB(40, 0, 0, 12),
      child: Column(
        children: [
          for (final day in dailyPlan)
            _GoalPlanDailyRow(
              key: ValueKey('goal_plan_detail_day_${weekLabel}_${day.weekday}'),
              day: day,
              onWorkoutSelected: onWorkoutSelected,
            ),
        ],
      ),
    );
  }
}

class _GoalPlanDailyRow extends StatelessWidget {
  const _GoalPlanDailyRow({
    required this.day,
    required this.onWorkoutSelected,
    super.key,
  });

  final GoalPlanDayDisplaySnapshot day;
  final ValueChanged<WeeklyWorkoutDetailSnapshot>? onWorkoutSelected;

  @override
  Widget build(BuildContext context) {
    final workoutDetail = day.workoutDetail;
    final canOpenWorkout = workoutDetail != null && onWorkoutSelected != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(day.weekday, style: _smallBodyStyle)),
          Expanded(
            child: Text(
              day.workoutType,
              style: canOpenWorkout ? _bodyStrongStyle : _bodyStyle,
            ),
          ),
          const SizedBox(width: 8),
          Text(day.distanceOrTime, style: _smallBodyStyle),
          const SizedBox(width: 6),
          SizedBox(
            width: _dailyRowChevronSlotWidth,
            child: canOpenWorkout
                ? const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: RuniacColors.textSecondary,
                  )
                : null,
          ),
        ],
      ),
    );

    if (!canOpenWorkout) {
      return row;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onWorkoutSelected!(workoutDetail),
        child: row,
      ),
    );
  }
}

class _TimelineMarker extends StatelessWidget {
  const _TimelineMarker({super.key, required this.status});

  final GoalPlanWeekStatus status;

  @override
  Widget build(BuildContext context) {
    final markerColor = switch (status) {
      GoalPlanWeekStatus.completed => RuniacColors.primaryBlue,
      GoalPlanWeekStatus.current => RuniacColors.accentOrange,
      GoalPlanWeekStatus.upcoming => RuniacColors.white,
      GoalPlanWeekStatus.goalWeek => RuniacColors.white,
    };
    final borderColor =
        status == GoalPlanWeekStatus.upcoming ||
            status == GoalPlanWeekStatus.goalWeek
        ? RuniacColors.primaryBlue
        : markerColor;

    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: markerColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor),
      ),
      child: _markerChild(status),
    );
  }
}

Widget _markerChild(GoalPlanWeekStatus status) {
  return switch (status) {
    GoalPlanWeekStatus.completed => const Icon(
      Icons.check,
      size: 16,
      color: RuniacColors.white,
    ),
    GoalPlanWeekStatus.current => const Icon(
      Icons.directions_run,
      size: 16,
      color: RuniacColors.white,
    ),
    GoalPlanWeekStatus.upcoming => const SizedBox.shrink(),
    GoalPlanWeekStatus.goalWeek => const Icon(
      Icons.flag,
      size: 15,
      color: RuniacColors.primaryBlue,
    ),
  };
}

/// Reserved even on rest days so every daily row shares the same trailing edge.
const _dailyRowChevronSlotWidth = 20.0;

const _cardTitleStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 16,
  fontWeight: FontWeight.w800,
);

const _bodyStrongStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 13,
  fontWeight: FontWeight.w800,
);

const _bodyStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

const _smallBodyStyle = TextStyle(
  color: RuniacColors.textSecondary,
  fontSize: 11,
  fontWeight: FontWeight.w700,
);

const _progressInsideStyle = TextStyle(
  color: RuniacColors.white,
  fontSize: 10,
  fontWeight: FontWeight.w800,
);

final _softIconDecoration = BoxDecoration(
  color: const Color(0xFFF7FAFF),
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: RuniacColors.border),
);
