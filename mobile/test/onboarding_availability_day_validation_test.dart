import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';

import 'support/onboarding_flow_test_helpers.dart';

void main() {
  testWidgets('preferred days require the selected availability minimum', (
    tester,
  ) async {
    final scenarios = [
      ('2 days per week', 2),
      ('3 days per week', 3),
      ('4 days per week', 4),
      ('Not sure yet', 2),
    ];

    for (final scenario in scenarios) {
      await tester.pumpWidget(
        const RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
        ),
      );

      await advanceToPreferredDays(tester, scenario.$1);

      expect(find.text('Step 8 of 16'), findsOneWidget);
      expect(
        find.text(
          'Choose at least ${scenario.$2} days that usually work for you.',
        ),
        findsOneWidget,
      );
      expect(primaryContinueButton(tester).onPressed, isNull);

      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
      for (var index = 0; index < scenario.$2 - 1; index++) {
        await tapText(tester, days[index]);
      }

      expect(primaryContinueButton(tester).onPressed, isNull);

      await tapText(tester, days[scenario.$2 - 1]);
      expect(primaryContinueButton(tester).onPressed, isNotNull);

      await tapText(tester, days[scenario.$2]);
      expect(primaryContinueButton(tester).onPressed, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('completed onboarding shows generated plan on Plans tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
        youProgressToday: DateTime(2026, 7, 6),
      ),
    );

    await completeOnboardingToPreview(tester);
    await tapText(tester, 'Continue with this plan');
    await tapTooltip(tester, 'You');
    await tapText(tester, 'Plans');

    expect(find.text('Current Goal'), findsNothing);
    expect(find.text('Return to Movement'), findsOneWidget);
    expect(find.textContaining('Week 1 of'), findsOneWidget);
    expect(find.text('20 min Easy Walk'), findsNWidgets(3));
    expect(find.text('Upcoming · 7:30 AM'), findsNWidgets(3));
    expect(find.text('Rest Day'), findsNWidgets(4));
    expect(find.text('10K Preparation'), findsNothing);
  });

  testWidgets('preview preferred days shows every selected candidate day', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
      ),
    );

    await advanceToPreferredDays(tester, '3 days per week');
    for (final day in ['Mon', 'Tue', 'Fri', 'Sun']) {
      await tapText(tester, day);
    }
    await tapText(tester, 'Continue');
    await answerSingle(tester, 'Morning');
    await answerSingle(tester, '20 minutes');
    await answerSingle(tester, 'Outdoor park');
    await answerSingle(tester, 'Gentle reminders');
    await answerSingle(tester, "No, I'm ready to start");
    await tapText(tester, 'None of these');
    await tapText(tester, 'Continue');
    await answerSingle(tester, 'Balanced progression');

    expect(find.text('Step 16 of 16'), findsOneWidget);
    expect(find.text('Mon · Tue · Fri · Sun'), findsOneWidget);
    expect(find.text('3 sessions / week'), findsOneWidget);
  });
}
