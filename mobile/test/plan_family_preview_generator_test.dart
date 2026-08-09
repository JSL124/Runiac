import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/models/plan_family.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';

import 'support/plan_family_test_drafts.dart';

void main() {
  const generator = BeginnerAdaptivePlanGenerator();

  group('multi-level family preview generation', () {
    test(
      'each initial family exposes distinct safe title and subtitle copy',
      () {
        final cases = <PlanFamily, LocalOnboardingDraft>{
          PlanFamily.returnToMovement: planFamilyStarterDraft(),
          PlanFamily.runWalkFoundation: planFamilyStarterDraft(
            goal: OnboardingGoal.gentle,
            availability: OnboardingAvailability.three,
            capacity: ContinuousRunCapacity.runWalk,
          ),
          PlanFamily.firstContinuousRunningStart: planFamilyStarterDraft(
            goal: OnboardingGoal.first5k,
            availability: OnboardingAvailability.three,
            consistency: RecentRunningConsistency.underFourWeeks,
            frequency: CurrentWeeklyRunFrequency.three,
            capacity: ContinuousRunCapacity.twentyToThirtyMinutes,
          ),
          PlanFamily.consistencyBase: planFamilyDevelopingDraft(
            goal: OnboardingGoal.habit,
          ),
          PlanFamily.fiveKBaseBuilder: planFamilyDevelopingDraft(
            goal: OnboardingGoal.first5k,
          ),
          PlanFamily.tenKFoundation: planFamilyDevelopingDraft(
            goal: OnboardingGoal.tenK,
          ),
          PlanFamily.fiveKPerformanceBuild: planFamilyPerformanceDraft(
            goal: OnboardingGoal.first5k,
            style: OnboardingPlanStyle.performanceFocused,
          ),
          PlanFamily.tenKPerformanceBuild: planFamilyPerformanceDraft(
            goal: OnboardingGoal.tenK,
            style: OnboardingPlanStyle.performanceFocused,
          ),
        };

        final plans = {
          for (final item in cases.entries)
            item.key: generator.generate(item.value),
        };

        expect(plans[PlanFamily.returnToMovement]!.title, 'Return to Movement');
        expect(
          plans[PlanFamily.runWalkFoundation]!.title,
          'Run-Walk Foundation',
        );
        expect(
          plans[PlanFamily.firstContinuousRunningStart]!.title,
          'First Continuous Running Start',
        );
        expect(plans[PlanFamily.consistencyBase]!.title, 'Consistency Base');
        expect(plans[PlanFamily.fiveKBaseBuilder]!.title, '5K Base Builder');
        expect(plans[PlanFamily.tenKFoundation]!.title, '10K Foundation');
        expect(
          plans[PlanFamily.fiveKPerformanceBuild]!.title,
          '5K Performance Build',
        );
        expect(
          plans[PlanFamily.tenKPerformanceBuild]!.title,
          '10K Performance Build',
        );

        expect(
          plans.values.map((plan) => plan.subtitle).toSet(),
          hasLength(plans.length),
        );
        expect(
          plans.values.map((plan) => plan.family).toSet(),
          containsAll(PlanFamily.values),
        );
      },
    );

    test(
      'developing and performance previews are distinct from starter rows',
      () {
        final starter = generator.generate(planFamilyStarterDraft());
        final developing = generator.generate(
          planFamilyDevelopingDraft(goal: OnboardingGoal.first5k),
        );
        final performance = generator.generate(
          planFamilyPerformanceDraft(
            goal: OnboardingGoal.first5k,
            style: OnboardingPlanStyle.performanceFocused,
          ),
        );

        final starterTitles = _weekOneTitles(starter);
        final developingTitles = _weekOneTitles(developing);
        final performanceTitles = _weekOneTitles(performance);

        expect(developingTitles, isNot(starterTitles));
        expect(performanceTitles, isNot(developingTitles));
        expect(developingTitles, contains('Steady Builder'));
        expect(performanceTitles, contains('Controlled Steady Run'));
        expect(performance.weeklyFrequencyLabel, '4 sessions / week');
        expect(performance.weeks.first.workouts, hasLength(4));
      },
    );

    test(
      'generated copy avoids forbidden pace, HR, calorie, and medical claims',
      () {
        final copy = [
          for (final draft in [
            planFamilyStarterDraft(health: OnboardingHealthComfort.joint),
            planFamilyDevelopingDraft(goal: OnboardingGoal.tenK),
            planFamilyPerformanceDraft(
              goal: OnboardingGoal.tenK,
              style: OnboardingPlanStyle.performanceFocused,
            ),
          ])
            ..._copyFor(generator.generate(draft)),
        ].join(' ');

        expect(
          copy,
          isNot(
            contains(
              RegExp(
                r'pace|heart rate|HR zone|calorie|VO2|diagnos|injury-proof|'
                r'injury-safe|rehab|treatment|cleared|risk-free|'
                r'medically cleared|guarantee|leaderboard|\bXP\b|rank',
                caseSensitive: false,
              ),
            ),
          ),
        );
      },
    );

    test(
      'preferred days are respected and session count matches generated rows',
      () {
        final plan = generator.generate(
          planFamilyPerformanceDraft(
            goal: OnboardingGoal.tenK,
            style: OnboardingPlanStyle.performanceFocused,
            days: const [
              OnboardingPreferredDay.tue,
              OnboardingPreferredDay.thu,
              OnboardingPreferredDay.sat,
              OnboardingPreferredDay.sun,
            ],
          ),
        );

        expect(plan.preferredScheduleLabel, 'Tue · Thu · Sat · Sun');
        expect(plan.weeklyFrequencyLabel, '4 sessions / week');
        expect(
          plan.weeks.first.workouts.map((workout) => workout.dayLabel).toList(),
          ['Tue', 'Thu', 'Sat', 'Sun'],
        );
        expect(plan.weeks.first.workouts, hasLength(4));
      },
    );

    test('restricted answers receive recovery-style movement-only preview', () {
      final plan = generator.generate(
        planFamilyPerformanceDraft(
          goal: OnboardingGoal.tenK,
          health: OnboardingHealthComfort.joint,
          style: OnboardingPlanStyle.performanceFocused,
        ),
      );

      expect(plan.family, PlanFamily.returnToMovement);
      expect(plan.familyCategory, PlanFamilyCategory.starter);
      expect(
        plan.subtitle,
        'A gentle restart plan focused on comfort and consistency.',
      );
      expect(
        _weekOneTitles(plan),
        isNot(
          anyOf(contains('Controlled Steady Run'), contains('Steady Builder')),
        ),
      );
      expect(
        plan.weeks.first.workouts.map((workout) => workout.intensity),
        everyElement(BeginnerPlanIntensity.veryGentle),
      );
    });

    test('needs-clearance answers do not fallback to movement rows', () {
      final plan = generator.generate(
        planFamilyStarterDraft(health: OnboardingHealthComfort.heart),
      );

      expect(plan.isBlocked, isTrue);
      expect(plan.family, isNull);
      expect(plan.familyCategory, isNull);
      expect(plan.title, isNot('Return to Movement'));
      expect(plan.weeks, isEmpty);
      expect(plan.weeklyFrequencyLabel, 'No running workouts');
      expect(plan.preferredScheduleLabel, 'No workout schedule');
      expect(plan.sessionDurationLabel, 'No duration target');
      expect(plan.isSafetyReadinessDisplay, isTrue);
      expect(plan.canStartPlannedRun, isFalse);
      expect(
        _copyFor(plan),
        isNot(containsAll(['Return to Movement', 'Easy Walk'])),
      );
    });
  });
}

List<String> _weekOneTitles(BeginnerAdaptivePlanSnapshot plan) {
  return plan.weeks.first.workouts.map((workout) => workout.title).toList();
}

List<String> _copyFor(BeginnerAdaptivePlanSnapshot plan) {
  return [
    plan.title,
    plan.subtitle,
    plan.familyReason,
    plan.supportStyleLabel,
    plan.safetyNote,
    for (final week in plan.weeks) ...[
      week.title,
      week.focus,
      for (final workout in week.workouts) ...[
        workout.title,
        workout.description,
        workout.supportiveNote,
        ...workout.steps,
      ],
    ],
  ];
}
