import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> completeOnboardingToPreview(WidgetTester tester) async {
  await tapText(tester, 'Start setup');
  await answerSingle(tester, 'Build a running habit');
  await answerSingle(tester, 'I am not running yet');
  await answerSingle(tester, '0 runs per week');
  await answerSingle(tester, 'Mostly walking right now');
  await answerSingle(tester, 'Completely new to running');
  await answerSingle(tester, '3 days per week');
  for (final day in ['Mon', 'Wed', 'Fri']) {
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
}

Future<void> completeOnboardingToFourSessionPreview(WidgetTester tester) async {
  await tapText(tester, 'Start setup');
  await answerSingle(tester, 'Work toward a 10K');
  await answerSingle(tester, '3 to 6 months');
  await answerSingle(tester, '4 runs per week');
  await answerSingle(tester, '45 minutes or more');
  await answerSingle(tester, 'I can run 20-30 minutes');
  await answerSingle(tester, '4 days per week');
  for (final day in ['Mon', 'Tue', 'Wed', 'Thu']) {
    await tapText(tester, day);
  }
  await tapText(tester, 'Continue');
  await answerSingle(tester, 'Morning');
  await answerSingle(tester, '30 minutes');
  await answerSingle(tester, 'Outdoor park');
  await answerSingle(tester, 'Gentle reminders');
  await answerSingle(tester, "No, I'm ready to start");
  await tapText(tester, 'None of these');
  await tapText(tester, 'Continue');
  await answerSingle(tester, 'Build steadily');
}

Future<void> completeOnboardingToBodyConcernPreview(WidgetTester tester) async {
  await tapText(tester, 'Start setup');
  await answerSingle(tester, 'Work toward a 10K');
  await answerSingle(tester, '3 to 6 months');
  await answerSingle(tester, '4 runs per week');
  await answerSingle(tester, '45 minutes or more');
  await answerSingle(tester, 'I can run 20-30 minutes');
  await answerSingle(tester, '4 days per week');
  for (final day in ['Mon', 'Tue', 'Wed', 'Thu']) {
    await tapText(tester, day);
  }
  await tapText(tester, 'Continue');
  await answerSingle(tester, 'Morning');
  await answerSingle(tester, '30 minutes');
  await answerSingle(tester, 'Outdoor park');
  await answerSingle(tester, 'Gentle reminders');
  await answerSingle(tester, 'Currently managing an injury or pain');
  await tapText(tester, 'None of these');
  await tapText(tester, 'Continue');
  await answerSingle(tester, 'Build steadily');
}

Future<void> confirmOnboardingRetake(WidgetTester tester) async {
  await tapText(tester, 'Reset streak & continue');
}

Future<void> advanceToPreferredDays(
  WidgetTester tester,
  String availabilityLabel,
) async {
  await tapText(tester, 'Start setup');
  await answerSingle(tester, 'Build a running habit');
  await answerSingle(tester, 'I am not running yet');
  await answerSingle(tester, '0 runs per week');
  await answerSingle(tester, 'Mostly walking right now');
  await answerSingle(tester, 'Completely new to running');
  await answerSingle(tester, availabilityLabel);
}

Future<void> advanceToSymptoms(WidgetTester tester) async {
  await tapText(tester, 'Start setup');
  await answerSingle(tester, 'Build a running habit');
  await answerSingle(tester, 'I am not running yet');
  await answerSingle(tester, '0 runs per week');
  await answerSingle(tester, 'Mostly walking right now');
  await answerSingle(tester, 'Completely new to running');
  await answerSingle(tester, '3 days per week');
  for (final day in ['Mon', 'Wed', 'Fri']) {
    await tapText(tester, day);
  }
  await tapText(tester, 'Continue');
  await answerSingle(tester, 'Morning');
  await answerSingle(tester, '20 minutes');
  await answerSingle(tester, 'Outdoor park');
  await answerSingle(tester, 'Gentle reminders');
  await answerSingle(tester, "No, I'm ready to start");
  expect(find.text('Step 14 of 16'), findsOneWidget);
}

Future<void> completeOnboardingToNeedsClearancePreview(
  WidgetTester tester,
) async {
  await tapText(tester, 'Start setup');
  await answerSingle(tester, 'Build a running habit');
  await answerSingle(tester, 'I am not running yet');
  await answerSingle(tester, '0 runs per week');
  await answerSingle(tester, 'Mostly walking right now');
  await answerSingle(tester, 'Completely new to running');
  await answerSingle(tester, '3 days per week');
  for (final day in ['Mon', 'Wed', 'Fri']) {
    await tapText(tester, day);
  }
  await tapText(tester, 'Continue');
  await answerSingle(tester, 'Morning');
  await answerSingle(tester, '20 minutes');
  await answerSingle(tester, 'Outdoor park');
  await answerSingle(tester, 'Gentle reminders');
  await answerSingle(tester, 'Heart or blood pressure condition');
  await tapText(tester, 'None of these');
  await tapText(tester, 'Continue');
  await answerSingle(tester, 'Balanced progression');
}

Future<void> answerSingle(WidgetTester tester, String option) async {
  await tapText(tester, option);
  await tapText(tester, 'Continue');
}

Future<void> tapText(WidgetTester tester, String text) async {
  final matches = find.text(text);
  expect(matches, findsWidgets, reason: 'Expected to find text "$text".');
  final finder = matches.first;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  final finder = find.byTooltip(tooltip).first;
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

FilledButton primaryContinueButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Continue').last,
  );
}
