import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';

void main() {
  const generator = BeginnerAdaptivePlanGenerator();

  group('BeginnerAdaptivePlanGenerator', () {
    test(
      'creates a local onboarding-based beginner plan from typed answers',
      () {
        final plan = generator.generate(
          _draft(
            goal: OnboardingGoal.first5k,
            experience: OnboardingExperience.intervals,
            availability: OnboardingAvailability.three,
            days: [
              OnboardingPreferredDay.mon,
              OnboardingPreferredDay.wed,
              OnboardingPreferredDay.sat,
            ],
            length: OnboardingSessionLength.twenty,
            place: OnboardingRunningPlace.park,
            motivation: OnboardingMotivationStyle.encourage,
            cautiousness: OnboardingPlanCautiousness.balanced,
            consistency: RecentRunningConsistency.underFourWeeks,
            frequency: CurrentWeeklyRunFrequency.three,
            capacity: ContinuousRunCapacity.twentyToThirtyMinutes,
          ),
        );

        expect(plan.id, startsWith('generated-onboarding-'));
        expect(plan.planKind, BeginnerAdaptivePlanKind.onboardingBased);
        expect(plan.sourceLabel, 'Onboarding based');
        expect(plan.title, 'First Continuous Running Start');
        expect(
          plan.templateKind,
          BeginnerPlanTemplateKind.standardBeginnerStart,
        );
        expect(plan.safetyBand, BeginnerPlanSafetyBand.clear);
        expect(plan.durationWeeks, 4);
        expect(plan.weeklyFrequencyLabel, '3 sessions / week');
        expect(plan.preferredScheduleLabel, 'Mon · Wed · Sat');
        expect(plan.sessionDurationLabel, '20 min');
        expect(plan.weeks, hasLength(4));
        expect(plan.weeks.first.workouts, hasLength(3));
        expect(
          plan.weeks.first.workouts.first.kind,
          BeginnerWorkoutKind.easyRun,
        );
        expect(
          plan.weeks.first.workouts.first.description,
          contains('familiar park loop'),
        );
        expect(
          plan.weeks.first.workouts.first.detail.metrics.map(
            (metric) => metric.label,
          ),
          <String>['Duration', 'Type', 'Effort'],
        );
        expect(
          plan.weeks.first.workouts.first.detail.breakdown.first.title,
          isNotEmpty,
        );
        expect(
          plan.weeks.first.workouts.first.detail.effortGuide,
          contains('park'),
        );
        expect(plan.weeks.first.workouts.first.detail.coachNotes, isNotEmpty);
      },
    );

    test('uses stable generated plan ids that change with plan content', () {
      final mondayPlan = generator.generate(
        _draft(days: const [OnboardingPreferredDay.mon]),
      );
      final mondayPlanAgain = generator.generate(
        _draft(days: const [OnboardingPreferredDay.mon]),
      );
      final tuesdayPlan = generator.generate(
        _draft(days: const [OnboardingPreferredDay.tue]),
      );

      expect(mondayPlan.id, mondayPlanAgain.id);
      expect(mondayPlan.id, isNot(tuesdayPlan.id));
      expect(mondayPlan.id, startsWith('generated-onboarding-'));
      expect(tuesdayPlan.id, startsWith('generated-onboarding-'));
    });

    test(
      'defaults unsure availability and length to short gentle sessions',
      () {
        final plan = generator.generate(
          _draft(
            availability: OnboardingAvailability.unsure,
            days: const [],
            length: OnboardingSessionLength.unsure,
            time: OnboardingPreferredTime.flexible,
          ),
        );

        expect(plan.weeklyFrequencyLabel, '2 sessions / week');
        expect(plan.preferredScheduleLabel, 'Day 1 · Day 2');
        expect(plan.sessionDurationLabel, '20 min');
        expect(plan.weeks, hasLength(4));
        expect(plan.weeks.first.workouts, hasLength(2));
        expect(
          plan.weeks.first.workouts.map((workout) => workout.durationMinutes),
          everyElement(20),
        );
        expect(
          plan.weeks.first.workouts.map((workout) => workout.intensity),
          everyElement(BeginnerPlanIntensity.veryGentle),
        );
      },
    );

    test('keeps restricted health answers conservative and local-only', () {
      final plan = generator.generate(
        _draft(
          experience: OnboardingExperience.newRunner,
          availability: OnboardingAvailability.four,
          days: [
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.thu,
            OnboardingPreferredDay.sat,
            OnboardingPreferredDay.sun,
          ],
          length: OnboardingSessionLength.fortyFive,
          health: OnboardingHealthComfort.joint,
          symptoms: [OnboardingActivitySymptom.legpain],
          cautiousness: OnboardingPlanCautiousness.veryGentle,
        ),
      );

      expect(plan.title, 'Return to Movement');
      expect(plan.templateKind, BeginnerPlanTemplateKind.veryGentleStart);
      expect(plan.safetyBand, BeginnerPlanSafetyBand.highCaution);
      expect(plan.weeklyFrequencyLabel, '3 sessions / week');
      expect(plan.preferredScheduleLabel, 'Tue · Thu · Sat');
      expect(plan.sessionDurationLabel, '15 min');
      expect(plan.weeks.first.focus, 'Keep movement easy and comfortable');
      expect(
        plan.weeks.first.workouts.map((workout) => workout.intensity),
        everyElement(BeginnerPlanIntensity.veryGentle),
      );
      expect(
        plan.weeks.first.workouts.map((workout) => workout.kind),
        everyElement(BeginnerWorkoutKind.recoveryWalk),
      );
      expect(plan.safetyNote, contains('Start gently'));

      final copy = [
        plan.title,
        plan.subtitle,
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
      ].join(' ');

      expect(
        copy,
        isNot(
          contains(
            RegExp(
              'medically cleared|diagnosed|approved to run|risk score|'
              r'\bXP\b|leaderboard|subscription|rank',
              caseSensitive: false,
            ),
          ),
        ),
      );
    });

    test('blocks needs-clearance drafts without fallback workout rows', () {
      final plan = generator.generate(
        _draft(
          health: OnboardingHealthComfort.heart,
          symptoms: [OnboardingActivitySymptom.breath],
        ),
      );

      expect(plan.isBlocked, isTrue);
      expect(plan.family, isNull);
      expect(plan.familyCategory, isNull);
      expect(plan.title, isNot('Return to Movement'));
      expect(plan.durationWeeks, 0);
      expect(plan.weeks, isEmpty);
      expect(plan.weeklyFrequencyLabel, 'No running workouts');
      expect(plan.preferredScheduleLabel, 'No workout schedule');
      expect(plan.sessionDurationLabel, 'No duration target');
      expect(plan.isSafetyReadinessDisplay, isTrue);
      expect(plan.canStartPlannedRun, isFalse);
      expect(plan.familyReason, contains('paused'));
      expect([
        plan.title,
        plan.subtitle,
        for (final week in plan.weeks)
          for (final workout in week.workouts) workout.title,
      ], isNot(contains('Easy Walk')));
    });

    test('generated workout detail avoids forbidden backend-owned fields', () {
      final plan = generator.generate(_draft());
      final detailCopy = [
        for (final week in plan.weeks)
          for (final workout in week.workouts) ...[
            for (final metric in workout.detail.metrics) ...[
              metric.label,
              metric.value,
            ],
            for (final step in workout.detail.breakdown) ...[
              step.title,
              step.detail,
            ],
            workout.detail.effortGuide,
            ...workout.detail.coachNotes,
          ],
      ].join(' ');

      expect(
        detailCopy,
        isNot(
          contains(
            RegExp(
              r'\bXP\b|leaderboard|subscription|rank|streak|validated',
              caseSensitive: false,
            ),
          ),
        ),
      );
    });

    test('treats none symptom intent as a clear standard start', () {
      final plan = generator.generate(
        _draft(
          experience: OnboardingExperience.intervals,
          cautiousness: OnboardingPlanCautiousness.balanced,
        ),
      );

      expect(plan.title, 'Run-Walk Foundation');
      expect(plan.safetyBand, BeginnerPlanSafetyBand.clear);
      expect(plan.templateKind, BeginnerPlanTemplateKind.standardBeginnerStart);
      expect(
        plan.weeks.first.workouts.map((workout) => workout.intensity),
        everyElement(BeginnerPlanIntensity.balanced),
      );
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
