import '../../../onboarding/domain/models/local_onboarding_draft.dart';
import '../../../onboarding/domain/services/onboarding_plan_style_resolver.dart';
import '../../../onboarding/domain/services/runner_level_resolver.dart';
import '../../../onboarding/domain/services/safety_gate_resolver.dart';
import '../models/beginner_adaptive_plan_snapshot.dart';
import '../models/plan_family.dart';
import 'beginner_adaptive_plan_copy.dart';
import 'beginner_plan_policy_resolver.dart';
import 'plan_family_resolver.dart';
import 'plan_family_workout_builder.dart';

/// Turns the onboarding answers into the runner's first training plan.
///
/// This is the entry point of plan generation and it only orchestrates. The
/// judgements are made by the resolvers it calls, each of which answers one
/// question and can be tested alone:
///
/// * `RunnerLevelResolver` — how experienced is this runner?
/// * `SafetyGateResolver` — did the health answers require an easier start?
/// * `OnboardingPlanStyleResolver` / `PlanFamilyResolver` — which plan shape fits?
/// * [BeginnerPlanPolicyResolver] — how many sessions a week, on which days?
/// * [PlanFamilyWorkoutBuilder] — the actual sessions.
///
/// Generation is deterministic: the same answers always produce the same plan,
/// which is what makes the onboarding preview trustworthy and the tests exact.
class BeginnerAdaptivePlanGenerator {
  const BeginnerAdaptivePlanGenerator([
    this._policyResolver = const BeginnerPlanPolicyResolver(),
    this._safetyGateResolver = const SafetyGateResolver(),
    this._runnerLevelResolver = const RunnerLevelResolver(),
    this._styleResolver = const PlanStyleResolver(),
    this._familyResolver = const PlanFamilyResolver(),
    this._workoutBuilder = const PlanFamilyWorkoutBuilder(),
  ]);

  final BeginnerPlanPolicyResolver _policyResolver;
  final SafetyGateResolver _safetyGateResolver;
  final RunnerLevelResolver _runnerLevelResolver;
  final PlanStyleResolver _styleResolver;
  final PlanFamilyResolver _familyResolver;
  final PlanFamilyWorkoutBuilder _workoutBuilder;

  BeginnerAdaptivePlanSnapshot generate(LocalOnboardingDraft draft) {
    final policy = _policyResolver.resolve(draft);
    final safetyGate = _safetyGateResolver.resolve(draft);
    final runnerLevel = _runnerLevelResolver.resolve(draft);
    final resolvedStyle = _styleResolver.resolve(
      draft: draft,
      safetyGate: safetyGate,
      runnerLevel: runnerLevel,
    );
    final resolvedFamily = _familyResolver.resolve(
      draft: draft,
      safetyGate: safetyGate,
      runnerLevel: runnerLevel,
      resolvedStyle: resolvedStyle,
    );
    final family = resolvedFamily.family;
    if (family == null) {
      return BeginnerAdaptivePlanSnapshot(
        id: _stablePlanId('safety-readiness', [
          policy.profile.safetyBand.name,
          policy.profile.templateKind.name,
          resolvedFamily.reason,
        ]),
        title: 'Safety Readiness Plan',
        subtitle:
            'These answers need qualified professional guidance before Runiac '
            'can suggest running workouts.',
        planKind: BeginnerAdaptivePlanKind.onboardingBased,
        sourceLabel: 'Onboarding based',
        durationWeeks: 0,
        safetyBand: policy.profile.safetyBand,
        templateKind: policy.profile.templateKind,
        family: null,
        familyCategory: null,
        familyReason: resolvedFamily.reason,
        supportStyleLabel: BeginnerAdaptivePlanCopy.supportStyleFor(draft),
        weeklyFrequencyLabel: 'No running workouts',
        preferredScheduleLabel: 'No workout schedule',
        sessionDurationLabel: 'No duration target',
        safetyNote:
            'Use this as a readiness checkpoint and get qualified '
            'professional guidance before choosing a running plan.',
        weeks: const [],
        clientDisplayStatus:
            BeginnerAdaptivePlanClientDisplayStatus.safetyReadiness,
      );
    }

    final category = resolvedFamily.category ?? family.category;
    final requiredSessions = _workoutBuilder.requiredSessionsFor(
      family,
      policy,
    );
    final durationWeeks = family.durationWeeks;
    final weeks = [
      for (var weekNumber = 1; weekNumber <= durationWeeks; weekNumber++)
        _weekFor(
          draft: draft,
          policy: policy,
          family: family,
          requiredSessions: requiredSessions,
          weekNumber: weekNumber,
        ),
    ];
    final weekOneDurations = [
      for (final workout in weeks.first.workouts) workout.durationMinutes,
    ];

    return BeginnerAdaptivePlanSnapshot(
      id: _stablePlanId('generated-onboarding', [
        family.name,
        category.name,
        policy.profile.safetyBand.name,
        policy.profile.templateKind.name,
        '$requiredSessions',
        '$durationWeeks',
        for (final week in weeks)
          for (final workout in week.workouts)
            [
              week.weekNumber,
              workout.dayLabel,
              workout.title,
              workout.durationMinutes,
              workout.kind.name,
              workout.intensity.name,
            ].join(':'),
      ]),
      title: family.title,
      subtitle: BeginnerAdaptivePlanCopy.subtitleFor(
        draft: draft,
        family: family,
        requiredSessions: requiredSessions,
        durationWeeks: durationWeeks,
      ),
      planKind: BeginnerAdaptivePlanKind.onboardingBased,
      sourceLabel: 'Onboarding based',
      durationWeeks: durationWeeks,
      safetyBand: policy.profile.safetyBand,
      templateKind: policy.profile.templateKind,
      family: family,
      familyCategory: category,
      familyReason: resolvedFamily.reason,
      supportStyleLabel: BeginnerAdaptivePlanCopy.supportStyleFor(draft),
      weeklyFrequencyLabel: '$requiredSessions sessions / week',
      preferredScheduleLabel: _dayLabelsFor(
        draft,
        policy,
        requiredSessions,
      ).join(' · '),
      sessionDurationLabel: BeginnerAdaptivePlanCopy.durationLabelFor(
        weekOneDurations,
      ),
      safetyNote: BeginnerAdaptivePlanCopy.safetyNoteFor(
        policy.profile.safetyBand,
      ),
      weeks: weeks,
    );
  }

  BeginnerAdaptivePlanWeek _weekFor({
    required LocalOnboardingDraft draft,
    required BeginnerPlanPolicy policy,
    required PlanFamily family,
    required int requiredSessions,
    required int weekNumber,
  }) {
    final dayLabels = _dayLabelsFor(draft, policy, requiredSessions);
    final workouts = <BeginnerAdaptiveWorkout>[
      for (var index = 0; index < requiredSessions; index++)
        _workoutBuilder.workoutFor(
          draft: draft,
          policy: policy,
          family: family,
          dayLabel: dayLabels[index],
          sessionIndex: index,
          requiredSessions: requiredSessions,
          weekNumber: weekNumber,
        ),
    ];

    return BeginnerAdaptivePlanWeek(
      weekNumber: weekNumber,
      title: 'Week $weekNumber',
      focus: BeginnerAdaptivePlanCopy.focusFor(family, weekNumber),
      workouts: workouts,
    );
  }

  List<String> _dayLabelsFor(
    LocalOnboardingDraft draft,
    BeginnerPlanPolicy policy,
    int requiredSessions,
  ) {
    final selectedDays = policy.selectedDays.length == requiredSessions
        ? policy.selectedDays
        : _policyResolver.selectPreferredDays(
            draft.preferredDays,
            requiredSessions,
          );
    if (selectedDays.isEmpty) {
      return [
        for (var index = 0; index < requiredSessions; index++)
          'Day ${index + 1}',
      ];
    }

    return [
      for (var index = 0; index < requiredSessions; index++)
        selectedDays[index % selectedDays.length].value,
    ];
  }

  String _stablePlanId(String prefix, Iterable<String> parts) {
    var hash = 0x811c9dc5;
    for (final unit in parts.join('|').codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '$prefix-${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
