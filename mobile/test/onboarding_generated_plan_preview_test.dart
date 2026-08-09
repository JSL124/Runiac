import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/onboarding/presentation/widgets/onboarding_preview_body.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';

void main() {
  testWidgets(
    'final preview renders summary and rows from one generated plan',
    (tester) async {
      final draft = LocalOnboardingDraft(
        goal: OnboardingGoal.first5k,
        experience: OnboardingExperience.intervals,
        availability: OnboardingAvailability.three,
        preferredDays: const [
          OnboardingPreferredDay.mon,
          OnboardingPreferredDay.wed,
          OnboardingPreferredDay.fri,
        ],
        preferredTime: OnboardingPreferredTime.morning,
        sessionLength: OnboardingSessionLength.twenty,
        runningPlace: OnboardingRunningPlace.park,
        motivationStyle: OnboardingMotivationStyle.plan,
        healthComfort: OnboardingHealthComfort.ready,
        activitySymptoms: const [OnboardingActivitySymptom.none],
        planCautiousness: OnboardingPlanCautiousness.standard,
      );
      final plan = const BeginnerAdaptivePlanGenerator().generate(draft);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnboardingPreviewBody(answers: _answersFor(draft)),
            ),
          ),
        ),
      );

      expect(find.text(plan.title), findsOneWidget);
      expect(find.text(plan.subtitle), findsOneWidget);
      expect(find.text('${plan.durationWeeks} weeks'), findsOneWidget);
      expect(find.text(plan.weeklyFrequencyLabel), findsOneWidget);
      expect(find.text(plan.sessionDurationLabel), findsOneWidget);
      expect(find.text(plan.preferredScheduleLabel), findsWidgets);

      for (final workout in plan.weeks.first.workouts) {
        expect(
          find.text(
            '${workout.dayLabel} · ${workout.title} · '
            '${workout.durationMinutes} min',
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('needsClearance preview shows Safety Readiness Plan', (
    tester,
  ) async {
    final redFlagDrafts = <LocalOnboardingDraft>[
      _needsClearanceDraft(health: OnboardingHealthComfort.heart),
      _needsClearanceDraft(health: OnboardingHealthComfort.advised),
      _needsClearanceDraft(symptoms: const [OnboardingActivitySymptom.chest]),
      _needsClearanceDraft(symptoms: const [OnboardingActivitySymptom.dizzy]),
      _needsClearanceDraft(symptoms: const [OnboardingActivitySymptom.breath]),
      _needsClearanceDraft(
        symptoms: const [OnboardingActivitySymptom.heartbeat],
      ),
      _needsClearanceDraft(
        health: OnboardingHealthComfort.ready,
        symptoms: const [OnboardingActivitySymptom.chest],
      ),
      _needsClearanceDraft(
        health: OnboardingHealthComfort.injury,
        symptoms: const [OnboardingActivitySymptom.dizzy],
      ),
    ];

    for (final draft in redFlagDrafts) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnboardingPreviewBody(answers: _answersFor(draft)),
            ),
          ),
        ),
      );

      expect(find.text('Safety-first setup'), findsOneWidget);
      expect(find.text('Safety Readiness Plan'), findsOneWidget);
      expect(
        find.textContaining('qualified professional guidance'),
        findsWidgets,
      );
      expect(
        find.textContaining("Runiac can't create a running plan"),
        findsNothing,
      );
      expect(find.text('Suggested starting plan'), findsNothing);
      expect(find.text('First week preview'), findsNothing);
      expect(find.text('Return to Movement'), findsNothing);
      expect(find.textContaining('Easy Walk'), findsNothing);
      expect(find.textContaining(' min'), findsNothing);
      expect(find.textContaining('km'), findsNothing);
      expect(find.textContaining('pace'), findsNothing);
      expect(find.textContaining('Start Run'), findsNothing);
      expect(find.textContaining('continue anyway'), findsNothing);
    }
  });

  testWidgets('body concern preview renders recovery plan rows', (
    tester,
  ) async {
    final draft = LocalOnboardingDraft(
      goal: OnboardingGoal.first5k,
      experience: OnboardingExperience.run30,
      availability: OnboardingAvailability.three,
      preferredDays: const [
        OnboardingPreferredDay.mon,
        OnboardingPreferredDay.wed,
        OnboardingPreferredDay.fri,
      ],
      preferredTime: OnboardingPreferredTime.morning,
      sessionLength: OnboardingSessionLength.twenty,
      runningPlace: OnboardingRunningPlace.park,
      motivationStyle: OnboardingMotivationStyle.plan,
      healthComfort: OnboardingHealthComfort.injury,
      activitySymptoms: const [OnboardingActivitySymptom.none],
      planCautiousness: OnboardingPlanCautiousness.standard,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OnboardingPreviewBody(answers: _answersFor(draft)),
          ),
        ),
      ),
    );

    expect(
      find.textContaining("Runiac can't create a running plan"),
      findsNothing,
    );
    expect(find.text('Suggested starting plan'), findsOneWidget);
    expect(find.text('Return to Movement'), findsOneWidget);
    expect(
      find.text('A gentle restart plan focused on comfort and consistency.'),
      findsOneWidget,
    );
    expect(find.text('First week preview'), findsOneWidget);
    expect(find.text('Mon · Easy Walk · 20 min'), findsOneWidget);
    expect(find.text('Wed · Easy Walk · 20 min'), findsOneWidget);
    expect(find.text('Fri · Easy Walk · 20 min'), findsOneWidget);
  });
}

Map<String, Object> _answersFor(LocalOnboardingDraft draft) {
  return {
    'goal': draft.goal.value,
    'experience': draft.experience.value,
    'availability': draft.availability.value,
    'days': draft.preferredDays.map((day) => day.value).toSet(),
    'time': draft.preferredTime.value,
    'length': draft.sessionLength.value,
    'place': draft.runningPlace.value,
    'motivation': draft.motivationStyle.value,
    'health': draft.healthComfort.value,
    'symptoms': draft.activitySymptoms.map((symptom) => symptom.value).toSet(),
    'cautious': draft.planCautiousness.value,
  };
}

LocalOnboardingDraft _needsClearanceDraft({
  OnboardingHealthComfort health = OnboardingHealthComfort.ready,
  List<OnboardingActivitySymptom> symptoms = const [
    OnboardingActivitySymptom.none,
  ],
}) {
  return LocalOnboardingDraft(
    goal: OnboardingGoal.first5k,
    experience: OnboardingExperience.intervals,
    availability: OnboardingAvailability.three,
    preferredDays: const [
      OnboardingPreferredDay.mon,
      OnboardingPreferredDay.wed,
      OnboardingPreferredDay.fri,
    ],
    preferredTime: OnboardingPreferredTime.morning,
    sessionLength: OnboardingSessionLength.twenty,
    runningPlace: OnboardingRunningPlace.park,
    motivationStyle: OnboardingMotivationStyle.plan,
    healthComfort: health,
    activitySymptoms: symptoms,
    planCautiousness: OnboardingPlanCautiousness.standard,
  );
}
