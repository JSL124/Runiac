import '../models/local_onboarding_draft.dart';
import 'onboarding_plan_style_resolver.dart';
import 'runner_level_resolver.dart';
import 'safety_gate_resolver.dart';

/// Identifies a training-profile row so presentation can pick an icon without
/// matching on display copy.
enum TrainingProfileRowKind {
  goal,
  startingPoint,
  planStyle,
  schedule,
  sessionLength,
  safety,
}

class TrainingProfileRow {
  const TrainingProfileRow({
    required this.kind,
    required this.label,
    required this.value,
  });

  final TrainingProfileRowKind kind;
  final String label;
  final String value;
}

class TrainingProfileSummary {
  TrainingProfileSummary({
    required List<TrainingProfileRow> rows,
    required this.note,
  }) : rows = List.unmodifiable(rows);

  final List<TrainingProfileRow> rows;

  /// One-line reason for the resolved plan style. It never names a health
  /// condition or symptom, so the card stays safe to show next to the rest of
  /// the profile.
  final String note;
}

/// Turns stored onboarding answers into the outcome Runiac derived from them.
///
/// The profile card and the onboarding preview run the same resolvers, so a
/// runner never sees two different verdicts for one set of answers.
class TrainingProfileSummaryBuilder {
  const TrainingProfileSummaryBuilder();

  TrainingProfileSummary build(LocalOnboardingDraft draft) {
    const safetyGateResolver = SafetyGateResolver();
    const runnerLevelResolver = RunnerLevelResolver();
    const planStyleResolver = PlanStyleResolver();

    final safetyGate = safetyGateResolver.resolve(draft);
    final runnerLevel = runnerLevelResolver.resolve(draft);
    final planStyle = planStyleResolver.resolve(
      draft: draft,
      safetyGate: safetyGate,
      runnerLevel: runnerLevel,
    );
    final isPaused = planStyle == ResolvedPlanStyle.blocked;

    return TrainingProfileSummary(
      rows: <TrainingProfileRow>[
        TrainingProfileRow(
          kind: TrainingProfileRowKind.goal,
          // 'Goal' alone collides with the Home plan card copy.
          label: 'Current goal',
          value: onboardingGoalLabel(draft.goal),
        ),
        TrainingProfileRow(
          kind: TrainingProfileRowKind.startingPoint,
          label: 'Starting point',
          value: runnerLevelLabel(runnerLevel),
        ),
        TrainingProfileRow(
          kind: TrainingProfileRowKind.planStyle,
          label: 'Plan style',
          value: resolvedPlanStyleLabel(planStyle),
        ),
        TrainingProfileRow(
          kind: TrainingProfileRowKind.schedule,
          label: 'Schedule',
          // A paused plan has no workouts, so promising a weekly rhythm here
          // would contradict the plan the runner actually has.
          value: isPaused ? 'No workouts scheduled' : _scheduleLabel(draft),
        ),
        TrainingProfileRow(
          kind: TrainingProfileRowKind.sessionLength,
          label: 'Session length',
          value: isPaused
              ? 'Not set while paused'
              : sessionLengthLabel(draft.sessionLength),
        ),
        TrainingProfileRow(
          kind: TrainingProfileRowKind.safety,
          label: 'Safety',
          value: safetyGateLabel(safetyGate),
        ),
      ],
      note: _noteFor(safetyGate: safetyGate, planStyle: planStyle),
    );
  }

  String _scheduleLabel(LocalOnboardingDraft draft) {
    final sessions = draft.requestedWeeklySessionCount;
    // 'Not sure yet' still resolves to a real session count, so say that the
    // number is Runiac's suggestion rather than the runner's own answer.
    final sessionsLabel = draft.availability == OnboardingAvailability.unsure
        ? '$sessions sessions / week (suggested)'
        : '$sessions sessions / week';
    return '$sessionsLabel · ${_preferredDaysLabel(draft.preferredDays)}';
  }

  String _preferredDaysLabel(List<OnboardingPreferredDay> preferredDays) {
    if (preferredDays.isEmpty) {
      return 'Flexible days';
    }
    final ordered = [...preferredDays]
      ..sort((first, second) => first.index.compareTo(second.index));
    return ordered.map((day) => day.value).join(' · ');
  }

  String _noteFor({
    required SafetyGateState safetyGate,
    required ResolvedPlanStyle planStyle,
  }) {
    if (planStyle == ResolvedPlanStyle.blocked) {
      return 'Runiac is holding off on running workouts until a qualified '
          'professional says you are ready.';
    }
    if (safetyGate != SafetyGateState.clear) {
      return 'Runiac is easing you in based on your health check answers.';
    }
    return switch (planStyle) {
      ResolvedPlanStyle.conservativeBase =>
        'You asked for a gentle build-up, so the first weeks stay easy.',
      ResolvedPlanStyle.balanced =>
        'Based on how often you run now and the days you can commit to.',
      ResolvedPlanStyle.performanceFocused =>
        'Your recent consistency supports a steadier build.',
      ResolvedPlanStyle.blocked => '',
    };
  }
}

String onboardingGoalLabel(OnboardingGoal goal) {
  return switch (goal) {
    OnboardingGoal.habit => 'Build a running habit',
    OnboardingGoal.gentle => 'Start running gently',
    OnboardingGoal.first5k => 'Complete my first 5K',
    OnboardingGoal.tenK => 'Work toward a 10K',
    OnboardingGoal.stamina => 'Improve my stamina',
  };
}

String onboardingExperienceLabel(OnboardingExperience experience) {
  return switch (experience) {
    OnboardingExperience.newRunner => 'Completely new to running',
    OnboardingExperience.walk => 'Can walk 20-30 minutes',
    OnboardingExperience.intervals => 'Doing run / walk intervals',
    OnboardingExperience.run10 => 'Can run about 10 minutes',
    OnboardingExperience.run30 => 'Can run 20-30 minutes',
  };
}

String sessionLengthLabel(OnboardingSessionLength sessionLength) {
  return switch (sessionLength) {
    OnboardingSessionLength.fifteen => '15 min',
    OnboardingSessionLength.twenty => '20 min',
    OnboardingSessionLength.thirty => '30 min',
    OnboardingSessionLength.fortyFive => '45 min',
    OnboardingSessionLength.unsure => '15 min (suggested)',
  };
}

String runnerLevelLabel(RunnerLevel level) {
  return switch (level) {
    RunnerLevel.starter => 'Getting started',
    RunnerLevel.developing => 'Building consistency',
    RunnerLevel.performance => 'Training for performance',
    RunnerLevel.advanced => 'Advanced structured training',
  };
}

String resolvedPlanStyleLabel(ResolvedPlanStyle style) {
  return switch (style) {
    ResolvedPlanStyle.conservativeBase => 'Keep it gentle',
    ResolvedPlanStyle.balanced => 'Balanced progression',
    ResolvedPlanStyle.performanceFocused => 'Build steadily',
    ResolvedPlanStyle.blocked => 'Paused for safety',
  };
}

/// Neutral readiness wording. The specific condition or symptom a runner
/// reported stays out of the profile surface on purpose.
String safetyGateLabel(SafetyGateState safetyGate) {
  return switch (safetyGate) {
    SafetyGateState.clear => 'Cleared to start',
    SafetyGateState.caution => 'Gentle start advised',
    SafetyGateState.restricted => 'Extra care advised',
    SafetyGateState.needsClearance => 'Professional clearance needed',
  };
}
