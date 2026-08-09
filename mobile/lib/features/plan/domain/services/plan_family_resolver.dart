import '../../../onboarding/domain/models/local_onboarding_draft.dart';
import '../../../onboarding/domain/services/onboarding_plan_style_resolver.dart';
import '../../../onboarding/domain/services/runner_level_resolver.dart';
import '../../../onboarding/domain/services/safety_gate_resolver.dart';
import '../models/plan_family.dart';

class PlanFamilyResolver {
  const PlanFamilyResolver();

  ResolvedPlanFamily resolve({
    required LocalOnboardingDraft draft,
    required SafetyGateState safetyGate,
    required RunnerLevel runnerLevel,
    required ResolvedPlanStyle resolvedStyle,
  }) {
    if (safetyGate == SafetyGateState.needsClearance) {
      return const ResolvedPlanFamily.blocked();
    }

    if (safetyGate == SafetyGateState.restricted) {
      return _resolved(
        PlanFamily.returnToMovement,
        'Chosen because your answers point to a gentle restart before adding more running.',
      );
    }

    return switch (runnerLevel) {
      RunnerLevel.starter => _starterFamily(draft, safetyGate, resolvedStyle),
      RunnerLevel.developing => _developingFamily(
        draft,
        safetyGate,
        resolvedStyle,
      ),
      RunnerLevel.performance || RunnerLevel.advanced => _performanceFamily(
        draft,
        safetyGate,
        resolvedStyle,
      ),
    };
  }

  ResolvedPlanFamily _starterFamily(
    LocalOnboardingDraft draft,
    SafetyGateState safetyGate,
    ResolvedPlanStyle resolvedStyle,
  ) {
    if (safetyGate == SafetyGateState.caution ||
        resolvedStyle == ResolvedPlanStyle.conservativeBase ||
        draft.requestedWeeklySessionCount <= 2 ||
        draft.continuousRunCapacity == ContinuousRunCapacity.walkOnly) {
      return _resolved(
        PlanFamily.returnToMovement,
        'Chosen because your answers point to a gentle restart before adding more running.',
      );
    }

    if ((draft.goal == OnboardingGoal.gentle ||
            draft.goal == OnboardingGoal.habit ||
            draft.goal == OnboardingGoal.stamina) &&
        (draft.continuousRunCapacity == ContinuousRunCapacity.runWalk ||
            draft.continuousRunCapacity == ContinuousRunCapacity.tenMinutes)) {
      return _resolved(
        PlanFamily.runWalkFoundation,
        'Chosen because run-walk sessions match your current base and weekly rhythm.',
      );
    }

    if ((draft.goal == OnboardingGoal.first5k ||
            draft.goal == OnboardingGoal.stamina) &&
        (draft.continuousRunCapacity ==
                ContinuousRunCapacity.twentyToThirtyMinutes ||
            draft.continuousRunCapacity == ContinuousRunCapacity.tenMinutes ||
            draft.continuousRunCapacity ==
                ContinuousRunCapacity.fortyFivePlusMinutes ||
            draft.continuousRunCapacity ==
                ContinuousRunCapacity.sixtyPlusMinutes)) {
      return _resolved(
        PlanFamily.firstContinuousRunningStart,
        'Chosen because your answers show a starter base for building continuous easy running.',
      );
    }

    return _resolved(
      PlanFamily.returnToMovement,
      'Chosen because a movement-first plan is the safest fit for the current answers.',
    );
  }

  ResolvedPlanFamily _developingFamily(
    LocalOnboardingDraft draft,
    SafetyGateState safetyGate,
    ResolvedPlanStyle resolvedStyle,
  ) {
    if (safetyGate == SafetyGateState.caution ||
        resolvedStyle == ResolvedPlanStyle.conservativeBase ||
        draft.requestedWeeklySessionCount <= 2 ||
        draft.goal == OnboardingGoal.habit ||
        draft.goal == OnboardingGoal.gentle ||
        draft.goal == OnboardingGoal.stamina) {
      return _resolved(
        PlanFamily.consistencyBase,
        'Chosen because consistency matters before adding a larger target.',
      );
    }

    if (draft.goal == OnboardingGoal.tenK &&
        _hasTwentyMinuteCapacity(draft.continuousRunCapacity)) {
      return _resolved(
        PlanFamily.tenKFoundation,
        'Chosen because your recent base can support gradual endurance building.',
      );
    }

    if (draft.goal == OnboardingGoal.first5k) {
      return _resolved(
        PlanFamily.fiveKBaseBuilder,
        'Chosen because your recent running supports a controlled 5K base.',
      );
    }

    return _resolved(
      PlanFamily.consistencyBase,
      'Chosen because a stable routine is the best next step from these answers.',
    );
  }

  ResolvedPlanFamily _performanceFamily(
    LocalOnboardingDraft draft,
    SafetyGateState safetyGate,
    ResolvedPlanStyle resolvedStyle,
  ) {
    if (safetyGate != SafetyGateState.clear ||
        resolvedStyle != ResolvedPlanStyle.performanceFocused ||
        draft.requestedWeeklySessionCount < 4) {
      return _developingFamily(
        draft,
        safetyGate,
        ResolvedPlanStyle.conservativeBase,
      );
    }

    if (draft.goal == OnboardingGoal.tenK ||
        draft.goal == OnboardingGoal.stamina) {
      return _resolved(
        PlanFamily.tenKPerformanceBuild,
        'Chosen because your consistent base can support structured endurance work.',
      );
    }

    if (draft.goal == OnboardingGoal.first5k) {
      return _resolved(
        PlanFamily.fiveKPerformanceBuild,
        'Chosen because your consistent base can support structured 5K work.',
      );
    }

    return _resolved(
      PlanFamily.consistencyBase,
      'Chosen because the selected goal is best served by a stable base first.',
    );
  }

  bool _hasTwentyMinuteCapacity(ContinuousRunCapacity capacity) {
    return switch (capacity) {
      ContinuousRunCapacity.walkOnly ||
      ContinuousRunCapacity.runWalk ||
      ContinuousRunCapacity.tenMinutes => false,
      ContinuousRunCapacity.twentyToThirtyMinutes ||
      ContinuousRunCapacity.fortyFivePlusMinutes ||
      ContinuousRunCapacity.sixtyPlusMinutes => true,
    };
  }

  ResolvedPlanFamily _resolved(PlanFamily family, String reason) {
    return ResolvedPlanFamily(
      family: family,
      category: family.category,
      reason: reason,
    );
  }
}
