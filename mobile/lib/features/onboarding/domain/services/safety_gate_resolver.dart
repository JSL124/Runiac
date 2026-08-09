import '../models/local_onboarding_draft.dart';

enum SafetyGateState { clear, caution, restricted, needsClearance }

class SafetyGateResolver {
  const SafetyGateResolver();

  SafetyGateState resolve(LocalOnboardingDraft draft) {
    if (draft.healthComfort == OnboardingHealthComfort.heart ||
        draft.healthComfort == OnboardingHealthComfort.advised ||
        draft.activitySymptoms.any(_requiresClearance)) {
      return SafetyGateState.needsClearance;
    }

    if (draft.healthComfort == OnboardingHealthComfort.injury ||
        draft.healthComfort == OnboardingHealthComfort.joint ||
        draft.activitySymptoms.contains(OnboardingActivitySymptom.legpain)) {
      return SafetyGateState.restricted;
    }

    if (draft.healthComfort == OnboardingHealthComfort.breakAfterTimeAway ||
        draft.healthComfort == OnboardingHealthComfort.asthma ||
        draft.healthComfort == OnboardingHealthComfort.unsure ||
        draft.activitySymptoms.isEmpty) {
      return SafetyGateState.caution;
    }

    return SafetyGateState.clear;
  }

  bool _requiresClearance(OnboardingActivitySymptom symptom) {
    return switch (symptom) {
      OnboardingActivitySymptom.chest ||
      OnboardingActivitySymptom.dizzy ||
      OnboardingActivitySymptom.breath ||
      OnboardingActivitySymptom.heartbeat => true,
      OnboardingActivitySymptom.legpain ||
      OnboardingActivitySymptom.none => false,
    };
  }
}
