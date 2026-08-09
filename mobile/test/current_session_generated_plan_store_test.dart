import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';

import 'support/plan_family_test_drafts.dart';

void main() {
  group('CurrentSessionGeneratedPlanStore', () {
    test('starts empty and accepts eligible generated running plans', () {
      final store = CurrentSessionGeneratedPlanStore();
      final snapshot = const BeginnerAdaptivePlanGenerator().generate(
        planFamilyPerformanceDraft(
          goal: OnboardingGoal.tenK,
          style: OnboardingPlanStyle.performanceFocused,
        ),
      );
      var notifications = 0;
      store.addListener(() => notifications += 1);

      final accepted = store.setActivePlan(snapshot);

      expect(accepted, isTrue);
      expect(store.activePlan, same(snapshot));
      expect(store.hasActivePlan, isTrue);
      expect(store.currentWeekRunningSessionCount, 4);
      expect(notifications, 1);
    });

    test(
      'stores safety readiness plan for display only and replaces stale plan',
      () {
        final store = CurrentSessionGeneratedPlanStore();
        final acceptedSnapshot = const BeginnerAdaptivePlanGenerator().generate(
          planFamilyPerformanceDraft(
            goal: OnboardingGoal.tenK,
            style: OnboardingPlanStyle.performanceFocused,
          ),
        );
        final blockedSnapshot = const BeginnerAdaptivePlanGenerator().generate(
          planFamilyStarterDraft(health: OnboardingHealthComfort.heart),
        );

        expect(store.setActivePlan(acceptedSnapshot), isTrue);
        var notifications = 0;
        store.addListener(() => notifications += 1);

        final accepted = store.setActivePlan(blockedSnapshot);

        expect(accepted, isTrue);
        expect(store.activePlan, same(blockedSnapshot));
        expect(store.hasActivePlan, isTrue);
        expect(store.activePlan!.isSafetyReadinessDisplay, isTrue);
        expect(store.activePlan!.canStartPlannedRun, isFalse);
        expect(isEligibleCurrentSessionGeneratedPlan(blockedSnapshot), isFalse);
        expect(store.currentWeekRunningSessionCount, 0);
        expect(notifications, 1);
      },
    );

    test('accepts generated starter movement plans', () {
      final store = CurrentSessionGeneratedPlanStore();
      final starterSnapshot = const BeginnerAdaptivePlanGenerator().generate(
        planFamilyStarterDraft(availability: OnboardingAvailability.three),
      );

      expect(store.setActivePlan(starterSnapshot), isTrue);
      expect(store.activePlan, same(starterSnapshot));
      expect(store.hasActivePlan, isTrue);
      expect(store.currentWeekRunningSessionCount, 3);
    });

    test('clears accepted session-local state', () {
      final store = CurrentSessionGeneratedPlanStore();
      final snapshot = const BeginnerAdaptivePlanGenerator().generate(
        planFamilyPerformanceDraft(
          goal: OnboardingGoal.tenK,
          style: OnboardingPlanStyle.performanceFocused,
        ),
      );
      expect(store.setActivePlan(snapshot), isTrue);

      store.clear();

      expect(store.activePlan, isNull);
      expect(store.hasActivePlan, isFalse);
      expect(store.currentWeekRunningSessionCount, 0);
    });
  });
}
