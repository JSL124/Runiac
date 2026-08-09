import 'package:flutter/material.dart';

import '../adapters/generated_plan_you_display_adapter.dart';
import '../data/weekly_workout_demo_snapshots.dart';
import 'current_goal_plan_card.dart';
import 'generated_weekly_plan_card.dart';
import 'premium_upsell_section.dart';
import 'safety_readiness_plan_card.dart';
import 'weekly_plan_card.dart';
import 'you_surface_primitives.dart';

class YouPlansSurface extends StatelessWidget {
  const YouPlansSurface({
    required this.onViewGoalPlan,
    required this.onViewWorkout,
    this.generatedPlan,
    this.safetyReadinessPlan,
    super.key,
  });

  final VoidCallback onViewGoalPlan;
  final ValueChanged<WeeklyWorkoutDetailSnapshot> onViewWorkout;
  final GeneratedYouPlanDisplay? generatedPlan;
  final SafetyReadinessYouPlanDisplay? safetyReadinessPlan;

  @override
  Widget build(BuildContext context) {
    final plan = generatedPlan;
    final safetyPlan = safetyReadinessPlan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RuniacAccentStrip(),
        const SizedBox(height: 12),
        if (safetyPlan != null) ...[
          SafetyReadinessPlanCard(plan: safetyPlan),
        ] else if (plan == null) ...[
          CurrentGoalPlanCard(onViewGoalPlan: onViewGoalPlan),
          const SizedBox(height: 12),
          WeeklyPlanCard(onViewWorkout: onViewWorkout),
          const SizedBox(height: 12),
          const PremiumUpsellSection(),
        ] else ...[
          GeneratedWeeklyPlanCard(
            plan: plan,
            onViewWorkout: onViewWorkout,
            onViewPlanDetail: onViewGoalPlan,
          ),
          const SizedBox(height: 12),
          const PremiumUpsellSection(),
        ],
      ],
    );
  }
}
