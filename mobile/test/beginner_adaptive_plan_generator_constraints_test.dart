import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';

void main() {
  const generator = BeginnerAdaptivePlanGenerator();

  group('BeginnerAdaptivePlanGenerator constraints', () {
    test('keeps durations under user cap and B0.2 hard cap', () {
      final returning = generator.generate(
        _draft(
          experience: OnboardingExperience.run30,
          availability: OnboardingAvailability.four,
          days: [
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.thu,
            OnboardingPreferredDay.sat,
          ],
          length: OnboardingSessionLength.fortyFive,
          cautiousness: OnboardingPlanCautiousness.standard,
        ),
      );
      final veryGentle = generator.generate(
        _draft(
          experience: OnboardingExperience.run30,
          length: OnboardingSessionLength.thirty,
          cautiousness: OnboardingPlanCautiousness.veryGentle,
        ),
      );

      expect(
        returning.weeks.expand((week) => week.workouts),
        everyElement(
          isA<BeginnerAdaptiveWorkout>().having(
            (workout) => workout.durationMinutes,
            'durationMinutes',
            lessThanOrEqualTo(35),
          ),
        ),
      );
      expect(
        veryGentle.weeks.first.workouts.map(
          (workout) => workout.durationMinutes,
        ),
        everyElement(15),
      );
    });

    test('keeps generated copy inside preview-safe training claims', () {
      final plan = generator.generate(
        _draft(
          goal: OnboardingGoal.tenK,
          experience: OnboardingExperience.run30,
          availability: OnboardingAvailability.four,
          days: [
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.thu,
            OnboardingPreferredDay.sat,
          ],
          length: OnboardingSessionLength.fortyFive,
          cautiousness: OnboardingPlanCautiousness.standard,
          consistency: RecentRunningConsistency.oneToThreeMonths,
          frequency: CurrentWeeklyRunFrequency.three,
          capacity: ContinuousRunCapacity.twentyToThirtyMinutes,
        ),
      );

      expect(plan.title, '10K Foundation');
      expect(_copyFor(plan), isNot(contains(_forbiddenPlanClaims)));
    });
  });
}

final _forbiddenPlanClaims = RegExp(
  'fully personalized|optimized for your body|injury-safe|'
  'medical recommendation|heart-rate|HR zone|pace target|'
  'calorie|tempo|threshold|VO2|max|guaranteed|10K plan',
  caseSensitive: false,
);

String _copyFor(BeginnerAdaptivePlanSnapshot plan) {
  return [
    plan.title,
    plan.subtitle,
    plan.supportStyleLabel,
    plan.weeklyFrequencyLabel,
    plan.preferredScheduleLabel,
    plan.sessionDurationLabel,
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
  ].join(' ');
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
