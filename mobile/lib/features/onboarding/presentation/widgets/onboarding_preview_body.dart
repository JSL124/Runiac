import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../domain/services/onboarding_plan_style_resolver.dart';
import '../../domain/services/runner_level_resolver.dart';
import '../../domain/services/safety_gate_resolver.dart';
import '../../domain/services/training_profile_summary_builder.dart';
import '../../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import '../../../plan/domain/services/beginner_adaptive_plan_generator.dart';
import '../../domain/models/local_onboarding_draft.dart';
import 'first_week_preview.dart';
import 'onboarding_visuals.dart';

/// The last onboarding step: what we concluded about the runner, and the plan
/// that follows from it.
///
/// Shown before anything is committed so the runner can go back and change an
/// answer. The plan here is produced by the real
/// [BeginnerAdaptivePlanGenerator] — generation is deterministic, so the
/// previewed plan is exactly the plan they will get, not an approximation.
///
/// [_SafetyReadinessPreview] surfaces the safety gate when the health answers
/// triggered an easier start, so an adjusted plan is never a silent one.
class OnboardingPreviewBody extends StatelessWidget {
  const OnboardingPreviewBody({required this.answers, super.key});

  final Map<String, Object> answers;

  @override
  Widget build(BuildContext context) {
    final draft = LocalOnboardingDraft.fromAnswers(answers);
    final safetyGate = draft == null
        ? SafetyGateState.clear
        : const SafetyGateResolver().resolve(draft);
    final plan = const BeginnerAdaptivePlanGenerator().generate(
      draft ?? _previewFallbackDraft,
    );
    if (plan.isSafetyReadinessDisplay) {
      return _SafetyReadinessPreview(plan: plan);
    }

    final runnerLevel = draft == null
        ? RunnerLevel.starter
        : const RunnerLevelResolver().resolve(draft);
    final resolvedStyle = draft == null
        ? ResolvedPlanStyle.balanced
        : const PlanStyleResolver().resolve(
            draft: draft,
            safetyGate: safetyGate,
            runnerLevel: runnerLevel,
          );
    if (plan.isBlocked) {
      return _SafetyReadinessPreview(plan: plan);
    }

    final length = plan.sessionDurationLabel;
    final weekly = plan.weeklyFrequencyLabel;
    final preferredDays = draft == null || draft.preferredDays.isEmpty
        ? plan.preferredScheduleLabel
        : draft.preferredDays.map((day) => day.value).join(' · ');
    final summary = [
      ('Plan length', '${plan.durationWeeks} weeks'),
      ('Starting point', runnerLevelLabel(runnerLevel)),
      ('Schedule', weekly),
      ('Session length', length),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Here's a preview based on your answers. Nothing is locked in. You can adjust it anytime.",
          style: onboardingTextStyle(
            size: 14,
            weight: FontWeight.w500,
            color: onboardingBlueWithOpacity(.75),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.42,
          children: [
            for (final item in summary)
              _SummaryTile(label: item.$1, value: item.$2),
          ],
        ),
        const SizedBox(height: 10),
        _SummaryTile(label: 'Preferred days', value: preferredDays),
        const SizedBox(height: 10),
        _SummaryTile(
          label: 'Plan style',
          value: resolvedPlanStyleLabel(resolvedStyle),
        ),
        const SizedBox(height: 16),
        _SuggestedPlanCard(title: plan.title, subtitle: plan.subtitle),
        const SizedBox(height: 10),
        OnboardingInfoBanner(
          icon: Icons.route_outlined,
          text: plan.familyReason,
        ),
        const SizedBox(height: 14),
        FirstWeekPreview(workouts: plan.weeks.first.workouts),
        const SizedBox(height: 14),
        const OnboardingInfoBanner(
          icon: Icons.info_outline_rounded,
          text:
              'This is a preview plan. Nothing is locked in, and you can adjust these answers later.',
        ),
      ],
    );
  }
}

final _previewFallbackDraft = LocalOnboardingDraft(
  goal: OnboardingGoal.habit,
  experience: OnboardingExperience.newRunner,
  availability: OnboardingAvailability.two,
  preferredDays: const [],
  preferredTime: OnboardingPreferredTime.flexible,
  sessionLength: OnboardingSessionLength.unsure,
  runningPlace: OnboardingRunningPlace.mixed,
  motivationStyle: OnboardingMotivationStyle.plan,
  healthComfort: OnboardingHealthComfort.ready,
  activitySymptoms: const [OnboardingActivitySymptom.none],
  planStyle: OnboardingPlanStyle.balanced,
);

class _SafetyReadinessPreview extends StatelessWidget {
  const _SafetyReadinessPreview({required this.plan});

  final BeginnerAdaptivePlanSnapshot plan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Safety-first setup',
          style: onboardingTextStyle(
            size: 14,
            weight: FontWeight.w800,
            color: RuniacColors.accentOrange,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Runiac will keep this as a read-only readiness checkpoint. It does not create running workouts or a workout schedule.',
          style: onboardingTextStyle(
            size: 14,
            weight: FontWeight.w500,
            color: onboardingBlueWithOpacity(.75),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _SafetyReadinessCard(title: plan.title, subtitle: plan.subtitle),
        const SizedBox(height: 10),
        _SummaryTile(label: 'Running workouts', value: 'None generated'),
        const SizedBox(height: 10),
        _SummaryTile(label: 'Workout schedule', value: 'None created'),
        const SizedBox(height: 10),
        OnboardingInfoBanner(
          icon: Icons.health_and_safety_outlined,
          text: plan.safetyNote,
        ),
      ],
    );
  }
}

class _SafetyReadinessCard extends StatelessWidget {
  const _SafetyReadinessCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: onboardingBlueWithOpacity(.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: RuniacColors.accentOrange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Read-only display',
                style: onboardingTextStyle(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: RuniacColors.accentOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: onboardingTextStyle(
              size: 19,
              weight: FontWeight.w800,
              color: RuniacColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: onboardingTextStyle(
              size: 13.5,
              weight: FontWeight.w500,
              color: onboardingBlueWithOpacity(.75),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onboardingBlueWithOpacity(.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: onboardingTextStyle(
              size: 11,
              weight: FontWeight.w600,
              color: onboardingBlueWithOpacity(.60),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: onboardingTextStyle(
              size: 14.5,
              weight: FontWeight.w700,
              color: RuniacColors.primaryBlue,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedPlanCard extends StatelessWidget {
  const _SuggestedPlanCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.primaryBlue, width: 2),
        boxShadow: [
          BoxShadow(
            color: onboardingBlueWithOpacity(.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                color: RuniacColors.accentOrange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Suggested starting plan',
                style: onboardingTextStyle(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: RuniacColors.accentOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: onboardingTextStyle(
              size: 19,
              weight: FontWeight.w800,
              color: RuniacColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: onboardingTextStyle(
              size: 13.5,
              weight: FontWeight.w500,
              color: onboardingBlueWithOpacity(.75),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
