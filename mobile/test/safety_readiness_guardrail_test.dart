import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/onboarding/presentation/widgets/onboarding_preview_body.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/you/presentation/adapters/generated_plan_you_display_adapter.dart';

void main() {
  testWidgets('safety readiness copy avoids medical claims', (tester) async {
    final productionCopy = await _productionSafetyReadinessCopy(tester);
    final badCopyFixture = [
      'You are cleared and safe to run. Start Run for 20 min at 5 km pace.',
    ];

    expect(_safetyReadinessCopyViolations(badCopyFixture), isNotEmpty);
    expect(_safetyReadinessCopyViolations(productionCopy), isEmpty);
  });

  test('duration guardrail allows only non-prescriptive exceptions', () {
    final allowedCopyFixture = [
      'No duration target',
      'No session duration target',
      'No duration prescription',
    ];
    final badCopyFixture = [
      'Duration target: 20 min',
      'Start with a 20-minute session',
      'Run for 20 minutes',
      'No duration target today, then run for 20 minutes',
    ];

    expect(_safetyReadinessCopyViolations(allowedCopyFixture), isEmpty);
    for (final item in badCopyFixture) {
      expect(_safetyReadinessCopyViolations([item]), isNotEmpty);
    }
  });

  test('safety readiness surfaces avoid backend and progression imports', () {
    final violations = <String>[];
    for (final path in _safetyReadinessSurfacePaths) {
      final importLines = File(path)
          .readAsLinesSync()
          .where((line) => line.trimLeft().startsWith('import '))
          .join('\n');
      for (final pattern in _forbiddenBackendImportPatterns) {
        if (pattern.hasMatch(importLines)) {
          violations.add('$path imports ${pattern.pattern}');
        }
      }
    }

    expect(violations, isEmpty);
  });
}

Future<List<String>> _productionSafetyReadinessCopy(WidgetTester tester) async {
  final draft = _needsClearanceDraft();
  final plan = const BeginnerAdaptivePlanGenerator().generate(draft);
  final safetyDisplay = safetyReadinessYouPlanDisplayFromSnapshot(plan);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OnboardingPreviewBody(answers: _answersFor(draft)),
        ),
      ),
    ),
  );

  final onboardingCopy = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .nonNulls;

  return [
    ...onboardingCopy,
    plan.title,
    plan.subtitle,
    plan.weeklyFrequencyLabel,
    plan.preferredScheduleLabel,
    plan.sessionDurationLabel,
    plan.safetyNote,
    if (safetyDisplay != null) ...[
      safetyDisplay.title,
      safetyDisplay.subtitle,
      safetyDisplay.statusLabel,
      for (final row in safetyDisplay.readinessRows) ...[
        row.title,
        row.subtitle,
      ],
    ],
  ];
}

List<String> _safetyReadinessCopyViolations(Iterable<String> copyItems) {
  return [for (final item in copyItems) ..._copyViolationsFor(item)];
}

List<String> _copyViolationsFor(String item) {
  return [
    for (final pattern in _forbiddenSafetyReadinessCopyPatterns)
      if (pattern.hasMatch(item)) '"$item" matched ${pattern.pattern}',
    ..._positiveDurationPrescriptionViolations(item),
  ];
}

List<String> _positiveDurationPrescriptionViolations(String item) {
  var searchable = item;
  for (final pattern in _allowedNonPrescriptiveDurationPatterns) {
    searchable = searchable.replaceAll(pattern, '');
  }

  return [
    for (final pattern in _forbiddenPositiveDurationPrescriptionPatterns)
      if (pattern.hasMatch(searchable)) '"$item" matched ${pattern.pattern}',
  ];
}

const _safetyReadinessSurfacePaths = [
  'lib/features/onboarding/presentation/widgets/onboarding_preview_body.dart',
  'lib/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart',
  'lib/features/plan/domain/services/beginner_adaptive_plan_generator.dart',
  'lib/features/you/presentation/adapters/generated_plan_you_display_adapter.dart',
  'lib/features/you/presentation/widgets/safety_readiness_plan_card.dart',
];

final _forbiddenSafetyReadinessCopyPatterns = [
  RegExp(r'\bsafe to run\b', caseSensitive: false),
  RegExp(r'\bcleared\b', caseSensitive: false),
  RegExp(r'\bcontinue anyway\b', caseSensitive: false),
  RegExp(r'\bStart Run\b', caseSensitive: false),
  RegExp(r'\bStart this run\b', caseSensitive: false),
  RegExp(r'\bFirestore\b', caseSensitive: false),
  RegExp(r'\bbackend\b', caseSensitive: false),
  RegExp(r'\bCloud Functions?\b', caseSensitive: false),
  RegExp(r'\bXP\b', caseSensitive: false),
  RegExp(r'\bleaderboard\b', caseSensitive: false),
  RegExp(r'\bsubscription\b', caseSensitive: false),
  RegExp(r'\bexpert publication\b', caseSensitive: false),
  RegExp(r'\bofficial training plan\b', caseSensitive: false),
  RegExp(r'\bdiagnosis\b', caseSensitive: false),
  RegExp(r'\btreatment\b', caseSensitive: false),
  RegExp(r'\bmedical advice\b', caseSensitive: false),
  RegExp(r'\bpush through\b', caseSensitive: false),
  RegExp(r'\bat your own risk\b', caseSensitive: false),
  RegExp(r'\bplanned sessions?\b', caseSensitive: false),
  RegExp(r'\brun/walk\b', caseSensitive: false),
  RegExp(r'\bwalk/run\b', caseSensitive: false),
  RegExp(r'\bpace\b', caseSensitive: false),
  RegExp(r'\bdistance\b', caseSensitive: false),
  RegExp(
    r'\b\d+\s*(km|kilometer|kilometers|mi|mile|miles)\b',
    caseSensitive: false,
  ),
];

final _allowedNonPrescriptiveDurationPatterns = [
  RegExp(r'\bno\s+(session\s+)?duration\s+target\b', caseSensitive: false),
  RegExp(r'\bno\s+duration\s+prescription\b', caseSensitive: false),
];

final _forbiddenPositiveDurationPrescriptionPatterns = [
  RegExp(r'\b\d+\s*(-|\s)*(min|mins|minute|minutes)\b', caseSensitive: false),
  RegExp(r'\bduration\s+(target|goal|prescription)\b', caseSensitive: false),
  RegExp(r'\b(target|goal)\s+duration\b', caseSensitive: false),
  RegExp(r'\b(run|walk|workout|session)\s+for\s+\d+\b', caseSensitive: false),
];

final _forbiddenBackendImportPatterns = [
  RegExp(r'firebase|firestore|cloud_functions', caseSensitive: false),
  RegExp(r'xp|leaderboard|subscription', caseSensitive: false),
  RegExp(r'expert.*publish|publish.*expert', caseSensitive: false),
];

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

LocalOnboardingDraft _needsClearanceDraft() {
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
    healthComfort: OnboardingHealthComfort.ready,
    activitySymptoms: const [OnboardingActivitySymptom.chest],
    planCautiousness: OnboardingPlanCautiousness.standard,
  );
}
