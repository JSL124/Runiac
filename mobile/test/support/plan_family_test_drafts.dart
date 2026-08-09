import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';

export 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';

LocalOnboardingDraft planFamilyStarterDraft({
  OnboardingGoal goal = OnboardingGoal.habit,
  OnboardingAvailability availability = OnboardingAvailability.two,
  OnboardingHealthComfort health = OnboardingHealthComfort.ready,
  List<OnboardingActivitySymptom> symptoms = const [
    OnboardingActivitySymptom.none,
  ],
  RecentRunningConsistency consistency = RecentRunningConsistency.none,
  CurrentWeeklyRunFrequency frequency = CurrentWeeklyRunFrequency.zero,
  ContinuousRunCapacity capacity = ContinuousRunCapacity.walkOnly,
  OnboardingPlanStyle style = OnboardingPlanStyle.balanced,
  List<OnboardingPreferredDay> days = const [
    OnboardingPreferredDay.mon,
    OnboardingPreferredDay.wed,
    OnboardingPreferredDay.fri,
  ],
}) {
  return _draft(
    goal: goal,
    availability: availability,
    health: health,
    symptoms: symptoms,
    consistency: consistency,
    frequency: frequency,
    capacity: capacity,
    style: style,
    days: days,
  );
}

LocalOnboardingDraft planFamilyDevelopingDraft({
  OnboardingGoal goal = OnboardingGoal.habit,
  OnboardingAvailability availability = OnboardingAvailability.three,
  OnboardingPlanStyle style = OnboardingPlanStyle.balanced,
  List<OnboardingPreferredDay> days = const [
    OnboardingPreferredDay.mon,
    OnboardingPreferredDay.wed,
    OnboardingPreferredDay.fri,
  ],
}) {
  return _draft(
    goal: goal,
    availability: availability,
    consistency: RecentRunningConsistency.oneToThreeMonths,
    frequency: CurrentWeeklyRunFrequency.three,
    capacity: ContinuousRunCapacity.twentyToThirtyMinutes,
    style: style,
    days: days,
  );
}

LocalOnboardingDraft planFamilyPerformanceDraft({
  OnboardingGoal goal = OnboardingGoal.first5k,
  OnboardingAvailability availability = OnboardingAvailability.four,
  OnboardingHealthComfort health = OnboardingHealthComfort.ready,
  List<OnboardingActivitySymptom> symptoms = const [
    OnboardingActivitySymptom.none,
  ],
  OnboardingPlanStyle style = OnboardingPlanStyle.balanced,
  List<OnboardingPreferredDay> days = const [
    OnboardingPreferredDay.mon,
    OnboardingPreferredDay.tue,
    OnboardingPreferredDay.thu,
    OnboardingPreferredDay.sun,
  ],
}) {
  return _draft(
    goal: goal,
    availability: availability,
    health: health,
    symptoms: symptoms,
    consistency: RecentRunningConsistency.threeToSixMonths,
    frequency: CurrentWeeklyRunFrequency.four,
    capacity: ContinuousRunCapacity.fortyFivePlusMinutes,
    style: style,
    days: days,
  );
}

LocalOnboardingDraft planFamilyAdvancedDraft({
  OnboardingGoal goal = OnboardingGoal.first5k,
  OnboardingPlanStyle style = OnboardingPlanStyle.balanced,
}) {
  return _draft(
    goal: goal,
    availability: OnboardingAvailability.four,
    consistency: RecentRunningConsistency.sixMonthsPlus,
    frequency: CurrentWeeklyRunFrequency.fivePlus,
    capacity: ContinuousRunCapacity.sixtyPlusMinutes,
    style: style,
    days: const [
      OnboardingPreferredDay.mon,
      OnboardingPreferredDay.wed,
      OnboardingPreferredDay.fri,
      OnboardingPreferredDay.sun,
    ],
  );
}

LocalOnboardingDraft _draft({
  required OnboardingGoal goal,
  required OnboardingAvailability availability,
  required RecentRunningConsistency consistency,
  required CurrentWeeklyRunFrequency frequency,
  required ContinuousRunCapacity capacity,
  required OnboardingPlanStyle style,
  required List<OnboardingPreferredDay> days,
  OnboardingHealthComfort health = OnboardingHealthComfort.ready,
  List<OnboardingActivitySymptom> symptoms = const [
    OnboardingActivitySymptom.none,
  ],
}) {
  return LocalOnboardingDraft(
    goal: goal,
    experience: OnboardingExperience.run30,
    availability: availability,
    preferredDays: days,
    preferredTime: OnboardingPreferredTime.morning,
    sessionLength: OnboardingSessionLength.thirty,
    runningPlace: OnboardingRunningPlace.park,
    motivationStyle: OnboardingMotivationStyle.plan,
    healthComfort: health,
    activitySymptoms: symptoms,
    recentRunningConsistency: consistency,
    currentWeeklyRunFrequency: frequency,
    continuousRunCapacity: capacity,
    planStyle: style,
  );
}
