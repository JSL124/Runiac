import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';

void main() {
  const generator = BeginnerAdaptivePlanGenerator();

  group('BeginnerAdaptivePlanGenerator snapshot labels', () {
    test('goal variation changes plan emphasis without aggressive rows', () {
      final habit = generator.generate(_draft(goal: OnboardingGoal.habit));
      final first5k = generator.generate(
        _draft(
          goal: OnboardingGoal.first5k,
          consistency: RecentRunningConsistency.underFourWeeks,
          frequency: CurrentWeeklyRunFrequency.three,
          capacity: ContinuousRunCapacity.twentyToThirtyMinutes,
        ),
      );

      expect(habit.title, 'Run-Walk Foundation');
      expect(first5k.title, 'First Continuous Running Start');
      expect(habit.subtitle, contains('repeatable short sessions'));
      expect(first5k.subtitle, contains('gradual running confidence'));
      expect(_firstWeekKinds(first5k), contains(BeginnerWorkoutKind.easyRun));
      expect(
        _firstWeekCopy(first5k),
        isNot(contains(RegExp('pace|heart rate|calorie|VO2|max'))),
      );
    });

    test('session length changes first-week duration labels within caps', () {
      final fifteen = generator.generate(
        _draft(
          experience: OnboardingExperience.run30,
          length: OnboardingSessionLength.fifteen,
        ),
      );
      final twenty = generator.generate(
        _draft(
          experience: OnboardingExperience.run30,
          length: OnboardingSessionLength.twenty,
        ),
      );
      final thirty = generator.generate(
        _draft(
          experience: OnboardingExperience.run30,
          availability: OnboardingAvailability.four,
          days: const [
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.thu,
            OnboardingPreferredDay.sun,
          ],
          length: OnboardingSessionLength.thirty,
          cautiousness: OnboardingPlanCautiousness.standard,
          consistency: RecentRunningConsistency.threeToSixMonths,
          frequency: CurrentWeeklyRunFrequency.four,
          capacity: ContinuousRunCapacity.fortyFivePlusMinutes,
        ),
      );

      expect(fifteen.sessionDurationLabel, '15 min');
      expect(_firstWeekDurations(fifteen), everyElement(15));
      expect(twenty.sessionDurationLabel, '20 min');
      expect(_firstWeekDurations(twenty), everyElement(20));
      expect(thirty.sessionDurationLabel, '25-30 min');
      expect(_firstWeekDurations(thirty), [25, 25, 25, 30]);
    });

    test('summary labels match the generated first-week snapshot', () {
      final plan = generator.generate(
        _draft(
          experience: OnboardingExperience.run30,
          availability: OnboardingAvailability.four,
          days: const [
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.wed,
            OnboardingPreferredDay.thu,
          ],
          length: OnboardingSessionLength.thirty,
        ),
      );
      final durations = _firstWeekDurations(plan);

      expect(plan.weeks.first.workouts, hasLength(_weeklyCount(plan)));
      expect(_weeklyCount(plan), durations.length);
      expect(plan.sessionDurationLabel, _durationLabelFor(durations));
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

List<int> _firstWeekDurations(BeginnerAdaptivePlanSnapshot plan) {
  return plan.weeks.first.workouts
      .map((workout) => workout.durationMinutes)
      .toList();
}

List<BeginnerWorkoutKind> _firstWeekKinds(BeginnerAdaptivePlanSnapshot plan) {
  return plan.weeks.first.workouts.map((workout) => workout.kind).toList();
}

String _firstWeekCopy(BeginnerAdaptivePlanSnapshot plan) {
  return [
    plan.title,
    plan.subtitle,
    plan.safetyNote,
    for (final workout in plan.weeks.first.workouts) ...[
      workout.title,
      workout.description,
      workout.supportiveNote,
      ...workout.steps,
    ],
  ].join(' ');
}

String _durationLabelFor(List<int> durations) {
  final ordered = durations.toSet().toList()..sort();
  if (ordered.length == 1) {
    return '${ordered.single} min';
  }

  return '${ordered.first}-${ordered.last} min';
}

int _weeklyCount(BeginnerAdaptivePlanSnapshot plan) {
  return int.parse(plan.weeklyFrequencyLabel.split(' ').first);
}
