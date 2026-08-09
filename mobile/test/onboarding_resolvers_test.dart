import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/onboarding/domain/services/onboarding_plan_style_resolver.dart';
import 'package:runiac_app/features/onboarding/domain/services/runner_level_resolver.dart';
import 'package:runiac_app/features/onboarding/domain/services/safety_gate_resolver.dart';

void main() {
  group('SafetyGateResolver', () {
    const resolver = SafetyGateResolver();

    test('resolves ready answers without symptoms as clear', () {
      expect(resolver.resolve(_draft()), SafetyGateState.clear);
    });

    test('keeps red-flag symptoms and unsafe advice at needsClearance', () {
      for (final symptom in [
        OnboardingActivitySymptom.chest,
        OnboardingActivitySymptom.dizzy,
        OnboardingActivitySymptom.breath,
        OnboardingActivitySymptom.heartbeat,
      ]) {
        expect(
          resolver.resolve(_draft(symptoms: [symptom])),
          SafetyGateState.needsClearance,
        );
      }

      for (final health in [
        OnboardingHealthComfort.advised,
        OnboardingHealthComfort.heart,
      ]) {
        expect(
          resolver.resolve(_draft(health: health)),
          SafetyGateState.needsClearance,
        );
      }
    });

    test('maps body concerns to restricted recovery instead of clearance', () {
      for (final health in [
        OnboardingHealthComfort.injury,
        OnboardingHealthComfort.joint,
      ]) {
        expect(
          resolver.resolve(_draft(health: health)),
          SafetyGateState.restricted,
        );
      }

      expect(
        resolver.resolve(_draft(symptoms: [OnboardingActivitySymptom.legpain])),
        SafetyGateState.restricted,
      );
    });

    test('maps softer conservative concerns to caution', () {
      for (final health in [
        OnboardingHealthComfort.breakAfterTimeAway,
        OnboardingHealthComfort.asthma,
        OnboardingHealthComfort.unsure,
      ]) {
        expect(
          resolver.resolve(_draft(health: health)),
          SafetyGateState.caution,
        );
      }

      expect(
        resolver.resolve(_draft(symptoms: const [])),
        SafetyGateState.caution,
      );
    });
  });

  group('RunnerLevelResolver', () {
    const safetyResolver = SafetyGateResolver();
    const resolver = RunnerLevelResolver();

    test(
      'resolves levels from objective history without goal/style promotion',
      () {
        expect(resolver.resolve(_draft()), RunnerLevel.starter);
        expect(
          resolver.resolve(
            _draft(
              consistency: RecentRunningConsistency.oneToThreeMonths,
              frequency: CurrentWeeklyRunFrequency.three,
              capacity: ContinuousRunCapacity.twentyToThirtyMinutes,
              goal: OnboardingGoal.tenK,
              style: OnboardingPlanStyle.performanceFocused,
            ),
          ),
          RunnerLevel.developing,
        );
        expect(
          resolver.resolve(
            _draft(
              consistency: RecentRunningConsistency.threeToSixMonths,
              frequency: CurrentWeeklyRunFrequency.four,
              capacity: ContinuousRunCapacity.fortyFivePlusMinutes,
            ),
          ),
          RunnerLevel.performance,
        );
        expect(
          resolver.resolve(
            _draft(
              consistency: RecentRunningConsistency.sixMonthsPlus,
              frequency: CurrentWeeklyRunFrequency.fivePlus,
              capacity: ContinuousRunCapacity.sixtyPlusMinutes,
            ),
          ),
          RunnerLevel.advanced,
        );
      },
    );

    test('caps or downgrades incomplete and safety-limited answers', () {
      expect(
        resolver.resolve(
          _draft(
            consistency: RecentRunningConsistency.sixMonthsPlus,
            frequency: CurrentWeeklyRunFrequency.fivePlus,
            capacity: ContinuousRunCapacity.tenMinutes,
          ),
        ),
        RunnerLevel.starter,
      );

      final restrictedDraft = _draft(
        consistency: RecentRunningConsistency.sixMonthsPlus,
        frequency: CurrentWeeklyRunFrequency.fivePlus,
        capacity: ContinuousRunCapacity.sixtyPlusMinutes,
        health: OnboardingHealthComfort.joint,
      );

      expect(
        safetyResolver.resolve(restrictedDraft),
        SafetyGateState.restricted,
      );
      expect(resolver.resolve(restrictedDraft), RunnerLevel.starter);
    });
  });

  group('PlanStyleResolver', () {
    const styleResolver = PlanStyleResolver();
    const levelResolver = RunnerLevelResolver();
    const safetyResolver = SafetyGateResolver();

    test('auto and performance-focused style stay inside eligibility', () {
      final starter = _draft(style: OnboardingPlanStyle.auto);
      expect(
        styleResolver.resolve(
          draft: starter,
          safetyGate: safetyResolver.resolve(starter),
          runnerLevel: levelResolver.resolve(starter),
        ),
        ResolvedPlanStyle.conservativeBase,
      );

      final ambitiousStarter = _draft(
        goal: OnboardingGoal.tenK,
        style: OnboardingPlanStyle.performanceFocused,
      );
      expect(levelResolver.resolve(ambitiousStarter), RunnerLevel.starter);
      expect(
        styleResolver.resolve(
          draft: ambitiousStarter,
          safetyGate: safetyResolver.resolve(ambitiousStarter),
          runnerLevel: levelResolver.resolve(ambitiousStarter),
        ),
        ResolvedPlanStyle.balanced,
      );
    });

    test('needsClearance blocks style effect', () {
      final draft = _draft(
        health: OnboardingHealthComfort.heart,
        style: OnboardingPlanStyle.performanceFocused,
      );

      expect(
        styleResolver.resolve(
          draft: draft,
          safetyGate: safetyResolver.resolve(draft),
          runnerLevel: levelResolver.resolve(draft),
        ),
        ResolvedPlanStyle.blocked,
      );
    });
  });
}

LocalOnboardingDraft _draft({
  OnboardingGoal goal = OnboardingGoal.habit,
  OnboardingExperience experience = OnboardingExperience.newRunner,
  OnboardingAvailability availability = OnboardingAvailability.three,
  List<OnboardingPreferredDay> days = const [
    OnboardingPreferredDay.mon,
    OnboardingPreferredDay.wed,
    OnboardingPreferredDay.fri,
  ],
  OnboardingPreferredTime time = OnboardingPreferredTime.morning,
  OnboardingSessionLength length = OnboardingSessionLength.twenty,
  OnboardingRunningPlace place = OnboardingRunningPlace.park,
  OnboardingMotivationStyle motivation = OnboardingMotivationStyle.plan,
  OnboardingHealthComfort health = OnboardingHealthComfort.ready,
  List<OnboardingActivitySymptom> symptoms = const [
    OnboardingActivitySymptom.none,
  ],
  RecentRunningConsistency consistency = RecentRunningConsistency.none,
  CurrentWeeklyRunFrequency frequency = CurrentWeeklyRunFrequency.zero,
  ContinuousRunCapacity capacity = ContinuousRunCapacity.walkOnly,
  OnboardingPlanStyle style = OnboardingPlanStyle.balanced,
}) {
  return LocalOnboardingDraft(
    goal: goal,
    experience: experience,
    availability: availability,
    preferredDays: days,
    preferredTime: time,
    sessionLength: length,
    runningPlace: place,
    motivationStyle: motivation,
    healthComfort: health,
    activitySymptoms: symptoms,
    recentRunningConsistency: consistency,
    currentWeeklyRunFrequency: frequency,
    continuousRunCapacity: capacity,
    planStyle: style,
  );
}
