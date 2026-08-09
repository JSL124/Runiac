import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';

void main() {
  const generator = BeginnerAdaptivePlanGenerator();

  group('BeginnerAdaptivePlanGenerator policy', () {
    test('maps safety, experience, and caution into templates', () {
      final cases = [
        (
          draft: _draft(experience: OnboardingExperience.newRunner),
          template: BeginnerPlanTemplateKind.veryGentleStart,
          safety: BeginnerPlanSafetyBand.clear,
        ),
        (
          draft: _draft(experience: OnboardingExperience.walk),
          template: BeginnerPlanTemplateKind.veryGentleStart,
          safety: BeginnerPlanSafetyBand.clear,
        ),
        (
          draft: _draft(experience: OnboardingExperience.intervals),
          template: BeginnerPlanTemplateKind.standardBeginnerStart,
          safety: BeginnerPlanSafetyBand.clear,
        ),
        (
          draft: _draft(experience: OnboardingExperience.run10),
          template: BeginnerPlanTemplateKind.standardBeginnerStart,
          safety: BeginnerPlanSafetyBand.clear,
        ),
        (
          draft: _draft(
            experience: OnboardingExperience.run30,
            cautiousness: OnboardingPlanCautiousness.standard,
          ),
          template: BeginnerPlanTemplateKind.returningBeginnerStart,
          safety: BeginnerPlanSafetyBand.clear,
        ),
        (
          draft: _draft(
            experience: OnboardingExperience.run30,
            cautiousness: OnboardingPlanCautiousness.veryGentle,
          ),
          template: BeginnerPlanTemplateKind.veryGentleStart,
          safety: BeginnerPlanSafetyBand.clear,
        ),
        (
          draft: _draft(
            health: OnboardingHealthComfort.injury,
            symptoms: [OnboardingActivitySymptom.none],
          ),
          template: BeginnerPlanTemplateKind.veryGentleStart,
          safety: BeginnerPlanSafetyBand.highCaution,
        ),
        (
          draft: _draft(
            experience: OnboardingExperience.run30,
            health: OnboardingHealthComfort.heart,
            symptoms: [OnboardingActivitySymptom.chest],
            cautiousness: OnboardingPlanCautiousness.standard,
          ),
          template: BeginnerPlanTemplateKind.safetyFirstMovementStart,
          safety: BeginnerPlanSafetyBand.safetyFirst,
        ),
      ];

      for (final item in cases) {
        final plan = generator.generate(item.draft);

        expect(plan.templateKind, item.template);
        expect(plan.safetyBand, item.safety);
      }
    });

    test('applies weekly session caps from safety and caution policy', () {
      expect(
        generator
            .generate(
              _draft(
                availability: OnboardingAvailability.two,
                days: [OnboardingPreferredDay.mon, OnboardingPreferredDay.wed],
              ),
            )
            .weeks
            .first
            .workouts,
        hasLength(2),
      );
      expect(
        generator
            .generate(
              _draft(
                availability: OnboardingAvailability.three,
                days: [
                  OnboardingPreferredDay.mon,
                  OnboardingPreferredDay.wed,
                  OnboardingPreferredDay.fri,
                ],
              ),
            )
            .weeks
            .first
            .workouts,
        hasLength(3),
      );
      expect(
        generator
            .generate(
              _draft(
                goal: OnboardingGoal.first5k,
                experience: OnboardingExperience.run30,
                availability: OnboardingAvailability.four,
                days: [
                  OnboardingPreferredDay.mon,
                  OnboardingPreferredDay.tue,
                  OnboardingPreferredDay.thu,
                  OnboardingPreferredDay.sat,
                ],
                cautiousness: OnboardingPlanCautiousness.standard,
                consistency: RecentRunningConsistency.threeToSixMonths,
                frequency: CurrentWeeklyRunFrequency.four,
                capacity: ContinuousRunCapacity.fortyFivePlusMinutes,
              ),
            )
            .weeks
            .first
            .workouts,
        hasLength(4),
      );
      expect(
        generator
            .generate(
              _draft(
                availability: OnboardingAvailability.four,
                days: [
                  OnboardingPreferredDay.mon,
                  OnboardingPreferredDay.tue,
                  OnboardingPreferredDay.thu,
                  OnboardingPreferredDay.sat,
                ],
                cautiousness: OnboardingPlanCautiousness.veryGentle,
              ),
            )
            .weeks
            .first
            .workouts,
        hasLength(3),
      );
      expect(
        generator
            .generate(
              _draft(
                availability: OnboardingAvailability.four,
                days: [
                  OnboardingPreferredDay.mon,
                  OnboardingPreferredDay.tue,
                  OnboardingPreferredDay.thu,
                  OnboardingPreferredDay.sat,
                ],
                health: OnboardingHealthComfort.joint,
                symptoms: [OnboardingActivitySymptom.legpain],
              ),
            )
            .weeks
            .first
            .workouts,
        hasLength(3),
      );

      final blocked = generator.generate(
        _draft(
          availability: OnboardingAvailability.four,
          days: [
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.thu,
            OnboardingPreferredDay.sat,
          ],
          health: OnboardingHealthComfort.heart,
          symptoms: [OnboardingActivitySymptom.heartbeat],
        ),
      );
      expect(blocked.isBlocked, isTrue);
      expect(blocked.weeks, isEmpty);
      expect(blocked.weeklyFrequencyLabel, 'No running workouts');
    });

    test('needsClearance produces Safety Readiness Plan', () {
      final cases = [
        _draft(health: OnboardingHealthComfort.heart),
        _draft(health: OnboardingHealthComfort.advised),
        _draft(symptoms: [OnboardingActivitySymptom.chest]),
        _draft(symptoms: [OnboardingActivitySymptom.dizzy]),
        _draft(symptoms: [OnboardingActivitySymptom.breath]),
        _draft(symptoms: [OnboardingActivitySymptom.heartbeat]),
        _draft(
          health: OnboardingHealthComfort.ready,
          symptoms: [OnboardingActivitySymptom.chest],
        ),
        _draft(
          health: OnboardingHealthComfort.injury,
          symptoms: [OnboardingActivitySymptom.dizzy],
        ),
      ];

      for (final draft in cases) {
        final plan = generator.generate(draft);

        expect(
          plan.clientDisplayStatus,
          BeginnerAdaptivePlanClientDisplayStatus.safetyReadiness,
        );
        expect(plan.isSafetyReadinessDisplay, isTrue);
        expect(plan.canStartPlannedRun, isFalse);
        expect(plan.isBlocked, isTrue);
        expect(plan.family, isNull);
        expect(plan.familyCategory, isNull);
        expect(plan.durationWeeks, 0);
        expect(plan.weeks, isEmpty);
        expect(plan.weeklyFrequencyLabel, 'No running workouts');
        expect(plan.preferredScheduleLabel, 'No workout schedule');
        expect(plan.sessionDurationLabel, 'No duration target');
        expect(plan.title, 'Safety Readiness Plan');
        expect(
          [plan.subtitle, plan.safetyNote].join(' '),
          contains('qualified professional guidance'),
        );
        expect(
          [plan.title, plan.subtitle, plan.safetyNote].join(' '),
          isNot(
            contains(
              RegExp(
                'safe to run|cleared|diagnosis|treatment|medical advice|'
                'push through|continue anyway|at your own risk|pace|'
                'distance|planned session',
                caseSensitive: false,
              ),
            ),
          ),
        );
      }
    });

    test('uses only selected preferred days and best-spaced subset', () {
      final plan = generator.generate(
        _draft(
          experience: OnboardingExperience.intervals,
          availability: OnboardingAvailability.three,
          days: [
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.fri,
            OnboardingPreferredDay.sun,
          ],
          cautiousness: OnboardingPlanCautiousness.standard,
        ),
      );

      expect(plan.preferredScheduleLabel, 'Tue · Fri · Sun');
      expect(plan.weeks.first.workouts.map((workout) => workout.dayLabel), [
        'Tue',
        'Fri',
        'Sun',
      ]);
    });
  });
}

LocalOnboardingDraft _draft({
  OnboardingGoal goal = OnboardingGoal.habit,
  OnboardingExperience experience = OnboardingExperience.newRunner,
  OnboardingAvailability availability = OnboardingAvailability.three,
  List<OnboardingPreferredDay> days = const [OnboardingPreferredDay.mon],
  OnboardingPreferredTime time = OnboardingPreferredTime.morning,
  OnboardingSessionLength length = OnboardingSessionLength.twenty,
  OnboardingRunningPlace place = OnboardingRunningPlace.mixed,
  OnboardingMotivationStyle motivation = OnboardingMotivationStyle.plan,
  OnboardingHealthComfort health = OnboardingHealthComfort.ready,
  List<OnboardingActivitySymptom> symptoms = const [
    OnboardingActivitySymptom.none,
  ],
  OnboardingPlanCautiousness cautiousness = OnboardingPlanCautiousness.balanced,
  RecentRunningConsistency consistency = RecentRunningConsistency.none,
  CurrentWeeklyRunFrequency frequency = CurrentWeeklyRunFrequency.zero,
  ContinuousRunCapacity capacity = ContinuousRunCapacity.runWalk,
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
    planCautiousness: cautiousness,
    recentRunningConsistency: consistency,
    currentWeeklyRunFrequency: frequency,
    continuousRunCapacity: capacity,
  );
}
