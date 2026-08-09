import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/card_title.dart';
import '../../../../core/widgets/dashboard_card.dart';
import 'home_placeholders.dart';

const _softBlue = Color(0xFFF8FAFF);
const _blueBorder = RuniacColors.border;

const _weeklyPlanDisplaySnapshot = _WeeklyPlanDisplaySnapshot(
  title: 'This Week\'s Plan',
  message: 'Your weekly plan will appear after setup.',
);

class WeeklyPlanCard extends StatelessWidget {
  const WeeklyPlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    const snapshot = _weeklyPlanDisplaySnapshot;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardTitle(icon: Icons.view_week_outlined, title: snapshot.title),
          const SizedBox(height: 12),
          Text(
            snapshot.message,
            style: const TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          const _WeeklyPreviewRows(),
        ],
      ),
    );
  }
}

class _WeeklyPlanDisplaySnapshot {
  const _WeeklyPlanDisplaySnapshot({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;
}

class _WeeklyPreviewRows extends StatelessWidget {
  const _WeeklyPreviewRows();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _softBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blueBorder),
      ),
      child: const Column(
        children: [
          PlanSkeletonRow(),
          SizedBox(height: 8),
          PlanSkeletonRow(),
          SizedBox(height: 8),
          PlanSkeletonRow(),
        ],
      ),
    );
  }
}
