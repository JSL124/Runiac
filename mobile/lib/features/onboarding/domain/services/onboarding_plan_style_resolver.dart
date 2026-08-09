import '../models/local_onboarding_draft.dart';
import 'runner_level_resolver.dart';
import 'safety_gate_resolver.dart';

enum ResolvedPlanStyle {
  conservativeBase,
  balanced,
  performanceFocused,
  blocked,
}

class PlanStyleResolver {
  const PlanStyleResolver();

  ResolvedPlanStyle resolve({
    required LocalOnboardingDraft draft,
    required SafetyGateState safetyGate,
    required RunnerLevel runnerLevel,
  }) {
    if (safetyGate == SafetyGateState.needsClearance) {
      return ResolvedPlanStyle.blocked;
    }

    if (safetyGate == SafetyGateState.caution ||
        safetyGate == SafetyGateState.restricted) {
      return ResolvedPlanStyle.conservativeBase;
    }

    return switch (draft.planStyle) {
      OnboardingPlanStyle.conservativeBase =>
        ResolvedPlanStyle.conservativeBase,
      OnboardingPlanStyle.balanced => ResolvedPlanStyle.balanced,
      OnboardingPlanStyle.auto => _autoFor(runnerLevel),
      OnboardingPlanStyle.performanceFocused => _performanceFor(runnerLevel),
    };
  }

  ResolvedPlanStyle _autoFor(RunnerLevel runnerLevel) {
    return switch (runnerLevel) {
      RunnerLevel.starter => ResolvedPlanStyle.conservativeBase,
      RunnerLevel.developing => ResolvedPlanStyle.balanced,
      RunnerLevel.performance ||
      RunnerLevel.advanced => ResolvedPlanStyle.performanceFocused,
    };
  }

  ResolvedPlanStyle _performanceFor(RunnerLevel runnerLevel) {
    return switch (runnerLevel) {
      RunnerLevel.starter ||
      RunnerLevel.developing => ResolvedPlanStyle.balanced,
      RunnerLevel.performance ||
      RunnerLevel.advanced => ResolvedPlanStyle.performanceFocused,
    };
  }
}
