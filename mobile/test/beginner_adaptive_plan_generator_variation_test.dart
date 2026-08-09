import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/models/plan_family.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';

void main() {
  const generator = BeginnerAdaptivePlanGenerator();

  group('BeginnerAdaptivePlanGenerator variation matrix', () {
    test('safe returning runner visibly differs from restricted restart', () {
      final restrictedRestart = generator.generate(
        _draft(
          goal: OnboardingGoal.tenK,
          experience: OnboardingExperience.run30,
          availability: OnboardingAvailability.four,
          days: const [
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.wed,
            OnboardingPreferredDay.thu,
          ],
          length: OnboardingSessionLength.thirty,
          health: OnboardingHealthComfort.injury,
          symptoms: const [OnboardingActivitySymptom.legpain],
          cautiousness: OnboardingPlanCautiousness.standard,
        ),
      );
      final safeReturning = generator.generate(
        _draft(
          goal: OnboardingGoal.tenK,
          experience: OnboardingExperience.run30,
          availability: OnboardingAvailability.four,
          days: const [
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.wed,
            OnboardingPreferredDay.thu,
          ],
          length: OnboardingSessionLength.thirty,
          cautiousness: OnboardingPlanCautiousness.standard,
          consistency: RecentRunningConsistency.threeToSixMonths,
          frequency: CurrentWeeklyRunFrequency.four,
          capacity: ContinuousRunCapacity.fortyFivePlusMinutes,
          style: OnboardingPlanStyle.performanceFocused,
        ),
      );

      expect(
        restrictedRestart.templateKind,
        BeginnerPlanTemplateKind.veryGentleStart,
      );
      expect(
        safeReturning.templateKind,
        BeginnerPlanTemplateKind.returningBeginnerStart,
      );
      expect(_firstWeekTitles(restrictedRestart), everyElement('Easy Walk'));
      expect(
        _firstWeekTitles(safeReturning),
        contains('Controlled Steady Run'),
      );
      expect(_firstWeekTitles(safeReturning), contains('Longer Easy Run'));
      expect(
        _firstWeekSignature(safeReturning),
        isNot(_firstWeekSignature(restrictedRestart)),
      );
    });

    test(
      'fifteen-minute performance plan does not label equal work as longer',
      () {
        final plan = generator.generate(
          _performanceReturningDraft(length: OnboardingSessionLength.fifteen),
        );

        expect(plan.family, PlanFamily.tenKPerformanceBuild);
        expect(
          plan.templateKind,
          BeginnerPlanTemplateKind.returningBeginnerStart,
        );
        expect(plan.sessionDurationLabel, '15 min');

        final comparableEasy = _requiredFirstWeekWorkout(
          plan,
          BeginnerWorkoutKind.easyRun,
        );
        expect(
          _firstWeekKinds(plan),
          isNot(contains(BeginnerWorkoutKind.longerEasyRun)),
        );
        expect(_firstWeekTitles(plan), isNot(contains('Longer Easy Run')));

        expect(comparableEasy.title, 'Comfortable Run');
        expect(comparableEasy.durationMinutes, 15);
        expect(_mainEffortMinutes(comparableEasy), lessThanOrEqualTo(15));
      },
    );

    test(
      'thirty-minute same-family plan keeps a genuinely longer easy run',
      () {
        final plan = generator.generate(
          _performanceReturningDraft(length: OnboardingSessionLength.thirty),
        );

        expect(plan.family, PlanFamily.tenKPerformanceBuild);
        expect(
          plan.templateKind,
          BeginnerPlanTemplateKind.returningBeginnerStart,
        );

        final comparableEasy = _requiredFirstWeekWorkout(
          plan,
          BeginnerWorkoutKind.easyRun,
        );
        final longerEasy = _requiredFirstWeekWorkout(
          plan,
          BeginnerWorkoutKind.longerEasyRun,
        );

        expect(longerEasy.title, 'Longer Easy Run');
        expect(
          longerEasy.durationMinutes,
          greaterThan(comparableEasy.durationMinutes),
        );
        expect(
          _mainEffortMinutes(longerEasy),
          greaterThan(_mainEffortMinutes(comparableEasy)),
        );
      },
    );

    test('first-week detail signatures vary by purpose and intensity', () {
      final performancePlan = generator.generate(
        _performanceReturningDraft(length: OnboardingSessionLength.thirty),
      );
      final titlelessPurposeSignatures = performancePlan.weeks.first.workouts
          .map(_workoutDetailSignature)
          .toSet();

      expect(
        titlelessPurposeSignatures,
        hasLength(performancePlan.weeks.first.workouts.length),
        reason:
            'Workout details should differ by kind, purpose, breakdown, and '
            'intensity instead of relying on titles alone.',
      );

      final balancedRecovery = _requiredFirstWeekWorkout(
        generator.generate(
          _draft(
            experience: OnboardingExperience.intervals,
            length: OnboardingSessionLength.fifteen,
            cautiousness: OnboardingPlanCautiousness.standard,
          ),
        ),
        BeginnerWorkoutKind.recoveryWalk,
      );
      final veryGentleRecovery = _requiredFirstWeekWorkout(
        generator.generate(
          _draft(
            experience: OnboardingExperience.newRunner,
            length: OnboardingSessionLength.fifteen,
            cautiousness: OnboardingPlanCautiousness.veryGentle,
          ),
        ),
        BeginnerWorkoutKind.recoveryWalk,
      );

      expect(balancedRecovery.title, veryGentleRecovery.title);
      expect(
        balancedRecovery.durationMinutes,
        veryGentleRecovery.durationMinutes,
      );
      expect(balancedRecovery.kind, veryGentleRecovery.kind);
      expect(balancedRecovery.intensity, isNot(veryGentleRecovery.intensity));
      expect(
        _workoutDetailSignature(balancedRecovery),
        isNot(_workoutDetailSignature(veryGentleRecovery)),
        reason:
            'Onboarding-derived intensity must change generated workout '
            'details even when title, kind, and total duration match.',
      );
    });

    test(
      'restricted answers override aggressive answers with conservative rows',
      () {
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
            health: OnboardingHealthComfort.injury,
            symptoms: const [OnboardingActivitySymptom.legpain],
            cautiousness: OnboardingPlanCautiousness.standard,
          ),
        );

        expect(plan.templateKind, BeginnerPlanTemplateKind.veryGentleStart);
        expect(plan.weeklyFrequencyLabel, '3 sessions / week');
        expect(plan.sessionDurationLabel, '20 min');
        expect(
          _firstWeekKinds(plan),
          everyElement(BeginnerWorkoutKind.recoveryWalk),
        );
        expect(
          _firstWeekIntensities(plan),
          everyElement(BeginnerPlanIntensity.veryGentle),
        );
        expect(_firstWeekTitles(plan), everyElement('Easy Walk'));
      },
    );

    test('standard beginner differs from very gentle first-week rows', () {
      final standard = generator.generate(
        _draft(
          experience: OnboardingExperience.intervals,
          cautiousness: OnboardingPlanCautiousness.standard,
        ),
      );
      final veryGentle = generator.generate(
        _draft(
          experience: OnboardingExperience.newRunner,
          cautiousness: OnboardingPlanCautiousness.veryGentle,
        ),
      );

      expect(
        standard.templateKind,
        BeginnerPlanTemplateKind.standardBeginnerStart,
      );
      expect(veryGentle.templateKind, BeginnerPlanTemplateKind.veryGentleStart);
      expect(_firstWeekKinds(standard), [
        BeginnerWorkoutKind.runWalk,
        BeginnerWorkoutKind.recoveryWalk,
        BeginnerWorkoutKind.runWalk,
      ]);
      expect(
        _firstWeekKinds(veryGentle),
        everyElement(BeginnerWorkoutKind.recoveryWalk),
      );
      expect(_firstWeekTitles(standard), [
        'Easy Run-Walk',
        'Easy Walk',
        'Confidence Run-Walk',
      ]);
      expect(_firstWeekTitles(veryGentle), [
        'Easy Walk',
        'Easy Walk',
        'Easy Walk',
      ]);
      expect(_firstWeekTitles(standard).toSet(), hasLength(greaterThan(1)));
      expect(
        _firstWeekSignature(standard),
        isNot(_firstWeekSignature(veryGentle)),
      );
    });

    test('preferred day changes affect rows without inventing days', () {
      final weekdayPlan = generator.generate(
        _draft(
          days: const [
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.wed,
            OnboardingPreferredDay.fri,
          ],
        ),
      );
      final weekendPlan = generator.generate(
        _draft(
          days: const [
            OnboardingPreferredDay.tue,
            OnboardingPreferredDay.thu,
            OnboardingPreferredDay.sun,
          ],
        ),
      );

      expect(_firstWeekDays(weekdayPlan), ['Mon', 'Wed', 'Fri']);
      expect(_firstWeekDays(weekendPlan), ['Tue', 'Thu', 'Sun']);
      expect(_firstWeekDays(weekdayPlan), isNot(_firstWeekDays(weekendPlan)));
      expect({
        ..._firstWeekDays(weekdayPlan),
        ..._firstWeekDays(weekendPlan),
      }, isNot(contains('Sat')));
    });
  });
}

LocalOnboardingDraft _performanceReturningDraft({
  required OnboardingSessionLength length,
}) {
  return _draft(
    goal: OnboardingGoal.tenK,
    experience: OnboardingExperience.run30,
    availability: OnboardingAvailability.four,
    days: const [
      OnboardingPreferredDay.mon,
      OnboardingPreferredDay.tue,
      OnboardingPreferredDay.wed,
      OnboardingPreferredDay.thu,
    ],
    length: length,
    cautiousness: OnboardingPlanCautiousness.standard,
    consistency: RecentRunningConsistency.threeToSixMonths,
    frequency: CurrentWeeklyRunFrequency.four,
    capacity: ContinuousRunCapacity.fortyFivePlusMinutes,
    style: OnboardingPlanStyle.performanceFocused,
  );
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
  OnboardingPlanStyle? style,
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
    planStyle: style,
  );
}

List<String> _firstWeekDays(BeginnerAdaptivePlanSnapshot plan) {
  return plan.weeks.first.workouts.map((workout) => workout.dayLabel).toList();
}

List<BeginnerPlanIntensity> _firstWeekIntensities(
  BeginnerAdaptivePlanSnapshot plan,
) {
  return plan.weeks.first.workouts.map((workout) => workout.intensity).toList();
}

List<BeginnerWorkoutKind> _firstWeekKinds(BeginnerAdaptivePlanSnapshot plan) {
  return plan.weeks.first.workouts.map((workout) => workout.kind).toList();
}

List<String> _firstWeekTitles(BeginnerAdaptivePlanSnapshot plan) {
  return plan.weeks.first.workouts.map((workout) => workout.title).toList();
}

String _firstWeekSignature(BeginnerAdaptivePlanSnapshot plan) {
  return plan.weeks.first.workouts
      .map(
        (workout) =>
            '${workout.dayLabel}|${workout.title}|${workout.durationMinutes}|'
            '${workout.kind.name}|${workout.intensity.name}',
      )
      .join('\n');
}

BeginnerAdaptiveWorkout _requiredFirstWeekWorkout(
  BeginnerAdaptivePlanSnapshot plan,
  BeginnerWorkoutKind kind,
) {
  final workout = _firstWeekWorkoutOrNull(plan, kind);
  expect(workout, isNotNull);
  return workout!;
}

BeginnerAdaptiveWorkout? _firstWeekWorkoutOrNull(
  BeginnerAdaptivePlanSnapshot plan,
  BeginnerWorkoutKind kind,
) {
  for (final workout in plan.weeks.first.workouts) {
    if (workout.kind == kind) {
      return workout;
    }
  }
  return null;
}

int _mainEffortMinutes(BeginnerAdaptiveWorkout workout) {
  final mainEffortSteps = workout.detail.breakdown.where((step) {
    final title = step.title.toLowerCase();
    return !title.contains('warm') &&
        !title.contains('cool') &&
        !title.contains('finish') &&
        !title.contains('rest');
  });
  if (mainEffortSteps.isNotEmpty) {
    return mainEffortSteps
        .map((step) => _minutesFromBreakdownDetail(step.detail))
        .reduce((total, minutes) => total + minutes);
  }

  return workout.detail.breakdown
      .map((step) => _minutesFromBreakdownDetail(step.detail))
      .reduce((total, minutes) => total + minutes);
}

int _minutesFromBreakdownDetail(String detail) {
  final match = RegExp(r'(\d+)\s*min').firstMatch(detail);
  expect(match, isNotNull, reason: 'Expected a minute value in "$detail".');
  return int.parse(match!.group(1)!);
}

String _workoutDetailSignature(BeginnerAdaptiveWorkout workout) {
  final metrics = workout.detail.metrics
      .map((metric) => '${metric.label}:${metric.value}')
      .join('|');
  final breakdown = workout.detail.breakdown
      .map((step) => '${step.kind.name}:${step.title}:${step.detail}')
      .join('|');
  final notes = workout.detail.coachNotes.join('|');

  return [
    workout.kind.name,
    workout.intensity.name,
    workout.description,
    metrics,
    breakdown,
    workout.detail.effortGuide,
    notes,
  ].join('\n');
}
