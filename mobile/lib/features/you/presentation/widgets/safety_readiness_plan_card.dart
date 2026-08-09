import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../adapters/generated_plan_you_display_adapter.dart';
import 'you_surface_primitives.dart';

class SafetyReadinessPlanCard extends StatelessWidget {
  const SafetyReadinessPlanCard({required this.plan, super.key});

  final SafetyReadinessYouPlanDisplay plan;

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
                child: YouCardHeader(
                  Icons.verified_user_outlined,
                  plan.title,
                  accent: true,
                  iconSize: 20,
                ),
              ),
              const SizedBox(width: 12),
              _SafetyReadinessBadge(plan.statusLabel),
            ],
          ),
          const SizedBox(height: 8),
          Text(plan.subtitle, style: YouTextStyles.body),
          const SizedBox(height: 14),
          for (var index = 0; index < plan.readinessRows.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _SafetyReadinessRow(plan.readinessRows[index]),
          ],
        ],
      ),
    );
  }
}

class _SafetyReadinessBadge extends StatelessWidget {
  const _SafetyReadinessBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: RuniacColors.accentOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: RuniacColors.accentOrange.withValues(alpha: 0.24),
        ),
      ),
      child: Text(
        label,
        style: YouTextStyles.smallStrong.copyWith(
          color: RuniacColors.accentOrange,
        ),
      ),
    );
  }
}

class _SafetyReadinessRow extends StatelessWidget {
  const _SafetyReadinessRow(this.row);

  final SafetyReadinessYouPlanRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: RuniacColors.sectionSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RuniacColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: RuniacColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: RuniacColors.border),
            ),
            child: Icon(row.icon, size: 18, color: RuniacColors.primaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: YouTextStyles.bodyStrong),
                const SizedBox(height: 3),
                Text(row.subtitle, style: YouTextStyles.smallBody),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
