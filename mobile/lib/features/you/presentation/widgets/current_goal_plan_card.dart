import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../data/you_overview_demo_snapshots.dart';
import 'you_surface_primitives.dart';

class CurrentGoalPlanCard extends StatelessWidget {
  const CurrentGoalPlanCard({required this.onViewGoalPlan, super.key});

  final VoidCallback onViewGoalPlan;

  @override
  Widget build(BuildContext context) {
    return YouDividerSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YouCardHeader(
                      Icons.flag_outlined,
                      youPlansSnapshot.goalLabel,
                      iconSize: 20,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      youPlansSnapshot.goalTitle,
                      style: YouTextStyles.largeValue,
                    ),
                  ],
                ),
              ),
              planBadge(youPlansSnapshot.goalBadge),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                youPlansSnapshot.completionLabel,
                style: YouTextStyles.planAccentLabel,
              ),
              const Spacer(),
              Text(
                youPlansSnapshot.completionPercentLabel,
                style: YouTextStyles.planPercent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            child: LinearProgressIndicator(
              value: youPlansSnapshot.completionProgress,
              minHeight: 7,
              backgroundColor: const Color(0xFFE8EEF8),
              valueColor: const AlwaysStoppedAnimation(
                RuniacColors.primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _PlanMilestoneRow(),
          const SizedBox(height: 14),
          StaticPlanAction(
            youPlansSnapshot.goalActionLabel,
            onTap: onViewGoalPlan,
          ),
        ],
      ),
    );
  }
}

class _PlanMilestoneRow extends StatelessWidget {
  const _PlanMilestoneRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: youSoftIconDecoration,
          child: const Icon(
            Icons.flag_outlined,
            color: RuniacColors.primaryBlue,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                youPlansSnapshot.milestoneLabel,
                style: YouTextStyles.smallStrong,
              ),
              const SizedBox(height: 2),
              Text(
                youPlansSnapshot.milestoneTitle,
                style: YouTextStyles.bodyStrong,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
