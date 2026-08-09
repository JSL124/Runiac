import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/onboarding/domain/services/safety_gate_resolver.dart';
import 'package:runiac_app/features/onboarding/presentation/widgets/onboarding_preview_body.dart';

import 'support/onboarding_flow_test_helpers.dart';

void main() {
  testWidgets('onboarding renders before Home when enabled', (tester) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
      ),
    );

    expect(find.text('Welcome to Runiac'), findsOneWidget);
    expect(find.text('Step 1 of 16'), findsOneWidget);
    expect(find.text('Start setup'), findsOneWidget);
    expect(find.text('Set up later'), findsNothing);
    expect(find.text('Good to see you'), findsNothing);
  });

  testWidgets('onboarding advances, backs up, and keeps local selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
      ),
    );

    await tapText(tester, 'Start setup');
    expect(find.text('Step 2 of 16'), findsOneWidget);
    expect(find.text('What would you like to work toward?'), findsOneWidget);

    await tapText(tester, 'Build a running habit');
    await tapText(tester, 'Continue');
    expect(find.text('Step 3 of 16'), findsOneWidget);
    expect(
      find.text('How consistently have you been running lately?'),
      findsOneWidget,
    );

    await tapTooltip(tester, 'Back');
    expect(find.text('Step 2 of 16'), findsOneWidget);
    expect(find.text('Build a running habit'), findsOneWidget);

    await tapText(tester, 'Continue');
    expect(find.text('Step 3 of 16'), findsOneWidget);
  });

  testWidgets('onboarding remains mandatory before the preview is created', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
      ),
    );

    await tapText(tester, 'Start setup');

    expect(find.text('Step 2 of 16'), findsOneWidget);
    expect(find.text('What would you like to work toward?'), findsOneWidget);
    expect(find.text('Set up later'), findsNothing);
    expect(find.text('Setup paused'), findsNothing);
    expect(find.text('Go to Home'), findsNothing);
    expect(find.text('Good to see you'), findsNothing);
  });

  testWidgets('final preview completes into the Home dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
      ),
    );

    await completeOnboardingToPreview(tester);

    expect(find.text('Step 16 of 16'), findsOneWidget);
    expect(find.text('Your plan preview is ready'), findsOneWidget);
    expect(find.text('Suggested starting plan'), findsOneWidget);
    expect(find.text('Getting started'), findsOneWidget);
    expect(find.text('Balanced progression'), findsOneWidget);
    expect(find.text('First week preview'), findsOneWidget);
    expect(find.text('4 weeks'), findsOneWidget);
    expect(find.text('3 sessions / week'), findsOneWidget);
    expect(find.text('Return to Movement'), findsOneWidget);
    expect(find.text('Mon · Easy Walk · 20 min'), findsOneWidget);
    expect(find.text('Wed · Easy Walk · 20 min'), findsOneWidget);
    expect(find.text('Fri · Easy Walk · 20 min'), findsOneWidget);
    expect(find.text('Continue with this plan'), findsOneWidget);
    expect(find.text('Create my preview plan'), findsNothing);
    expect(find.text('Edit answers'), findsOneWidget);

    await tapText(tester, 'Continue with this plan');
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Home'), findsOneWidget);
  });

  testWidgets('final preview rows follow the generated local plan', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
      ),
    );

    await completeOnboardingToFourSessionPreview(tester);

    expect(find.text('8 weeks'), findsOneWidget);
    expect(find.text('4 sessions / week'), findsOneWidget);
    expect(find.text('20-30 min'), findsOneWidget);
    expect(find.text('10K Performance Build'), findsOneWidget);
    expect(find.text('Mon · Comfortable Run · 25 min'), findsOneWidget);
    expect(find.text('Tue · Controlled Steady Run · 25 min'), findsOneWidget);
    expect(find.text('Wed · Longer Easy Run · 30 min'), findsOneWidget);
    expect(find.text('Thu · Recovery Run · 20 min'), findsOneWidget);
  });

  testWidgets('final preview emits a typed local onboarding draft', (
    tester,
  ) async {
    LocalOnboardingDraft? completedDraft;

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
        onOnboardingCompleted: (draft) {
          completedDraft = draft;
        },
      ),
    );

    await completeOnboardingToPreview(tester);
    await tapText(tester, 'Continue with this plan');

    expect(completedDraft, isNotNull);
    expect(completedDraft!.goal, OnboardingGoal.habit);
    expect(completedDraft!.experience, OnboardingExperience.newRunner);
    expect(completedDraft!.availability, OnboardingAvailability.three);
    expect(completedDraft!.activitySymptoms, [OnboardingActivitySymptom.none]);
    expect(find.byTooltip('Home'), findsOneWidget);
  });

  testWidgets('symptom none option clears other local selections', (
    tester,
  ) async {
    LocalOnboardingDraft? completedDraft;

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
        onOnboardingCompleted: (draft) {
          completedDraft = draft;
        },
      ),
    );

    await advanceToSymptoms(tester);

    await tapText(tester, 'Chest pain or discomfort');
    await tapText(tester, 'None of these');
    await tapText(tester, 'Continue');

    expect(find.text('Step 15 of 16'), findsOneWidget);
    expect(
      find.text('How would you like your training plan to feel?'),
      findsOneWidget,
    );
    expect(find.text('How gentle should your first plan be?'), findsNothing);
    await answerSingle(tester, 'Balanced progression');
    await tapTooltip(tester, 'Back');
    expect(find.text('Step 15 of 16'), findsOneWidget);
    await tapTooltip(tester, 'Back');
    expect(find.text('Step 14 of 16'), findsOneWidget);

    await tapText(tester, 'Continue');
    expect(find.text('Step 15 of 16'), findsOneWidget);

    await answerSingle(tester, 'Balanced progression');
    await tapText(tester, 'Continue with this plan');

    expect(completedDraft, isNotNull);
    expect(completedDraft!.activitySymptoms, [OnboardingActivitySymptom.none]);
  });

  testWidgets(
    'symptoms step disables Continue until an option is selected',
    (tester) async {
      await tester.pumpWidget(
        const RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
        ),
      );

      await advanceToSymptoms(tester);

      expect(primaryContinueButton(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'symptoms step enables Continue after selecting None of these',
    (tester) async {
      await tester.pumpWidget(
        const RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
        ),
      );

      await advanceToSymptoms(tester);
      expect(primaryContinueButton(tester).onPressed, isNull);

      await tapText(tester, 'None of these');
      expect(primaryContinueButton(tester).onPressed, isNotNull);

      await tapText(tester, 'Continue');
      expect(
        find.text('How would you like your training plan to feel?'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'symptoms step enables Continue after selecting a real symptom and '
    'still resolves to needsClearance',
    (tester) async {
      LocalOnboardingDraft? completedDraft;

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
          onOnboardingCompleted: (draft) {
            completedDraft = draft;
          },
        ),
      );

      await advanceToSymptoms(tester);
      expect(primaryContinueButton(tester).onPressed, isNull);

      await tapText(tester, 'Chest pain or discomfort');
      expect(primaryContinueButton(tester).onPressed, isNotNull);

      await tapText(tester, 'Continue');
      await answerSingle(tester, 'Balanced progression');
      await tapText(tester, 'Finish for now');

      expect(completedDraft, isNotNull);
      expect(
        const SafetyGateResolver().resolve(completedDraft!),
        SafetyGateState.needsClearance,
      );
    },
  );

  testWidgets('needs clearance preview does not show normal plan rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
      ),
    );

    await completeOnboardingToNeedsClearancePreview(tester);

    expect(find.text('Step 16 of 16'), findsOneWidget);
    expect(find.text('Safety-first setup'), findsOneWidget);
    expect(find.text('Safety Readiness Plan'), findsOneWidget);
    expect(
      find.textContaining('qualified professional guidance'),
      findsWidgets,
    );
    expect(find.text('First week preview'), findsNothing);
    expect(find.text('Suggested starting plan'), findsNothing);
    expect(find.text('Continue with this plan'), findsNothing);
    expect(find.text('Finish for now'), findsOneWidget);
    expect(find.text('Edit answers'), findsOneWidget);
  });

  testWidgets('onboarding avoids forbidden backend-owned and medical claims', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
      ),
    );

    for (final forbidden in [
      'safe to run',
      'medically cleared',
      'diagnosed',
      'risk score',
      'approved',
      'published',
      'official plan',
      'Level',
      'XP',
      'rank',
      'leaderboard',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  });

  testWidgets('incomplete preview uses the generator fallback path', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OnboardingPreviewBody(
              answers: <String, Object>{'availability': 'unsure'},
            ),
          ),
        ),
      ),
    );

    expect(find.text('2 sessions / week'), findsOneWidget);
    expect(find.text('4 weeks'), findsOneWidget);
    expect(find.text('3 runs / week'), findsNothing);
    expect(find.text('Day 1 · Easy Walk · 20 min'), findsOneWidget);
    expect(find.text('Day 2 · Easy Walk · 20 min'), findsOneWidget);
    expect(find.text('First week preview'), findsOneWidget);
  });
}
