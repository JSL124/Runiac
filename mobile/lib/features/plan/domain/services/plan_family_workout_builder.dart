import '../../../onboarding/domain/models/local_onboarding_draft.dart';
import '../models/beginner_adaptive_plan_snapshot.dart';
import '../models/plan_family.dart';
import 'beginner_adaptive_plan_copy.dart';

/// Builds the individual sessions of a plan once its shape has been decided.
///
/// [BeginnerPlanPolicyResolver] settles how many sessions and on which days;
/// this fills them in — what each session actually asks the runner to do, and
/// how that progresses week to week.
///
/// Session counts are capped per plan family rather than taken from the user's
/// answer alone: a starter plan stays a starter plan even if the runner claims
/// they can train every day.
class PlanFamilyWorkoutBuilder {
  const PlanFamilyWorkoutBuilder();

  int requiredSessionsFor(PlanFamily family, BeginnerPlanPolicy policy) {
    final capped = switch (family.category) {
      PlanFamilyCategory.starter =>
        policy.requiredSessions > 3 ? 3 : policy.requiredSessions,
      PlanFamilyCategory.developing =>
        policy.requiredSessions > 4 ? 4 : policy.requiredSessions,
      PlanFamilyCategory.performance =>
        policy.requiredSessions < 4 ? 4 : policy.requiredSessions,
    };

    if (family == PlanFamily.returnToMovement && capped > 3) {
      return 3;
    }

    return capped;
  }

  BeginnerAdaptiveWorkout workoutFor({
    required LocalOnboardingDraft draft,
    required BeginnerPlanPolicy policy,
    required PlanFamily family,
    required String dayLabel,
    required int sessionIndex,
    required int requiredSessions,
    required int weekNumber,
  }) {
    final isLastSession = sessionIndex == requiredSessions - 1;
    final intendedKind = _workoutKindFor(family, sessionIndex, isLastSession);
    final intensity = _intensityFor(family, policy);
    final kind = _resolvedKindFor(
      policy: policy,
      intendedKind: intendedKind,
      weekNumber: weekNumber,
    );
    final durationMinutes = _durationForKind(policy, weekNumber, kind);
    final runMinutes = _mainEffortMinutes(durationMinutes, kind);

    final description = BeginnerAdaptivePlanCopy.descriptionFor(draft, kind);
    final supportiveNote = BeginnerAdaptivePlanCopy.supportiveNoteFor(
      draft,
      intensity,
    );
    final steps = _stepsFor(kind, durationMinutes, runMinutes);

    return BeginnerAdaptiveWorkout(
      dayLabel: dayLabel,
      title: BeginnerAdaptivePlanCopy.workoutTitleFor(
        family,
        kind,
        sessionIndex,
        isLastSession,
      ),
      durationMinutes: durationMinutes,
      kind: kind,
      intensity: intensity,
      description: description,
      steps: steps,
      supportiveNote: supportiveNote,
      detail: BeginnerAdaptiveWorkoutDetail(
        metrics: [
          BeginnerAdaptiveWorkoutMetric(
            label: 'Duration',
            value: '$durationMinutes min',
          ),
          BeginnerAdaptiveWorkoutMetric(label: 'Type', value: _kindLabel(kind)),
          BeginnerAdaptiveWorkoutMetric(
            label: 'Effort',
            value: _intensityLabel(intensity),
          ),
        ],
        breakdown: [for (final step in steps) _detailStepFor(step, kind)],
        effortGuide: description,
        coachNotes: [
          supportiveNote,
          _purposeNoteFor(
            kind: kind,
            sessionIndex: sessionIndex,
            requiredSessions: requiredSessions,
            mainEffortMinutes: runMinutes,
          ),
          _adjustmentNoteFor(draft, intensity),
        ],
      ),
    );
  }

  BeginnerPlanIntensity _intensityFor(
    PlanFamily family,
    BeginnerPlanPolicy policy,
  ) {
    if (family == PlanFamily.returnToMovement) {
      return BeginnerPlanIntensity.veryGentle;
    }

    if (family.category == PlanFamilyCategory.performance) {
      return BeginnerPlanIntensity.balanced;
    }

    return switch (policy.profile.templateKind) {
      BeginnerPlanTemplateKind.safetyFirstMovementStart ||
      BeginnerPlanTemplateKind.veryGentleStart =>
        BeginnerPlanIntensity.veryGentle,
      BeginnerPlanTemplateKind.standardBeginnerStart ||
      BeginnerPlanTemplateKind.returningBeginnerStart =>
        BeginnerPlanIntensity.balanced,
    };
  }

  BeginnerWorkoutKind _workoutKindFor(
    PlanFamily family,
    int sessionIndex,
    bool isLastSession,
  ) {
    return switch (family) {
      PlanFamily.returnToMovement => BeginnerWorkoutKind.recoveryWalk,
      PlanFamily.runWalkFoundation =>
        sessionIndex == 1
            ? BeginnerWorkoutKind.recoveryWalk
            : BeginnerWorkoutKind.runWalk,
      PlanFamily.firstContinuousRunningStart ||
      PlanFamily.consistencyBase ||
      PlanFamily.tenKFoundation =>
        isLastSession
            ? BeginnerWorkoutKind.longerEasyRun
            : BeginnerWorkoutKind.easyRun,
      PlanFamily.fiveKBaseBuilder =>
        sessionIndex == 1
            ? BeginnerWorkoutKind.steadyRun
            : isLastSession
            ? BeginnerWorkoutKind.longerEasyRun
            : BeginnerWorkoutKind.easyRun,
      PlanFamily.fiveKPerformanceBuild ||
      PlanFamily.tenKPerformanceBuild => switch (sessionIndex) {
        1 => BeginnerWorkoutKind.controlledSteadyRun,
        2 => BeginnerWorkoutKind.longerEasyRun,
        3 => BeginnerWorkoutKind.recoveryRun,
        _ => BeginnerWorkoutKind.easyRun,
      },
    };
  }

  BeginnerWorkoutKind _resolvedKindFor({
    required BeginnerPlanPolicy policy,
    required BeginnerWorkoutKind intendedKind,
    required int weekNumber,
  }) {
    if (intendedKind != BeginnerWorkoutKind.longerEasyRun) {
      return intendedKind;
    }

    final easyDuration = _durationForKind(
      policy,
      weekNumber,
      BeginnerWorkoutKind.easyRun,
    );
    final longerDuration = _durationForKind(policy, weekNumber, intendedKind);
    final easyMainEffort = _mainEffortMinutes(
      easyDuration,
      BeginnerWorkoutKind.easyRun,
    );
    final longerMainEffort = _mainEffortMinutes(longerDuration, intendedKind);

    if (longerDuration <= easyDuration || longerMainEffort <= easyMainEffort) {
      return BeginnerWorkoutKind.easyRun;
    }

    return intendedKind;
  }

  int _durationForKind(
    BeginnerPlanPolicy policy,
    int weekNumber,
    BeginnerWorkoutKind kind,
  ) {
    final standardDuration = policy.durationFor(
      weekNumber: weekNumber,
      isLastSession: false,
    );

    return switch (kind) {
      BeginnerWorkoutKind.longerEasyRun => policy.durationFor(
        weekNumber: weekNumber,
        isLastSession: true,
      ),
      BeginnerWorkoutKind.recoveryRun => _recoveryRunDuration(standardDuration),
      _ => standardDuration,
    };
  }

  int _recoveryRunDuration(int standardDuration) {
    final reduced = standardDuration - 5;
    return reduced < 15 ? 15 : reduced;
  }

  int _mainEffortMinutes(int durationMinutes, BeginnerWorkoutKind kind) {
    final minutes = switch (kind) {
      BeginnerWorkoutKind.recoveryWalk => durationMinutes - 5,
      BeginnerWorkoutKind.walkRun ||
      BeginnerWorkoutKind.controlledSteadyRun => durationMinutes - 10,
      BeginnerWorkoutKind.restOrMobility => 0,
      _ => durationMinutes - 8,
    };

    return minutes < 1 ? 1 : minutes;
  }

  List<String> _stepsFor(
    BeginnerWorkoutKind kind,
    int durationMinutes,
    int mainEffortMinutes,
  ) {
    return switch (kind) {
      BeginnerWorkoutKind.recoveryWalk => [
        'Easy walk · $mainEffortMinutes min',
        'Slow finish · 5 min',
      ],
      BeginnerWorkoutKind.walkRun => [
        'Warm-up walk · 5 min',
        'Short walk-run repeats · $mainEffortMinutes min',
        'Cool-down walk · ${durationMinutes - mainEffortMinutes - 5} min',
      ],
      BeginnerWorkoutKind.runWalk => [
        'Warm-up walk · 4 min',
        'Easy run-walk repeats · $mainEffortMinutes min',
        'Cool-down walk · ${durationMinutes - mainEffortMinutes - 4} min',
      ],
      BeginnerWorkoutKind.easyRun => [
        'Warm-up walk · 4 min',
        'Easy run · $mainEffortMinutes min',
        'Cool-down walk · ${durationMinutes - mainEffortMinutes - 4} min',
      ],
      BeginnerWorkoutKind.steadyRun => [
        'Warm-up walk · 4 min',
        'Steady comfortable run · $mainEffortMinutes min',
        'Cool-down walk · ${durationMinutes - mainEffortMinutes - 4} min',
      ],
      BeginnerWorkoutKind.controlledSteadyRun => [
        'Warm-up walk · 5 min',
        'Controlled steady effort · $mainEffortMinutes min',
        'Cool-down walk · ${durationMinutes - mainEffortMinutes - 5} min',
      ],
      BeginnerWorkoutKind.longerEasyRun => [
        'Warm-up walk · 4 min',
        'Longer easy run · $mainEffortMinutes min',
        'Cool-down walk · ${durationMinutes - mainEffortMinutes - 4} min',
      ],
      BeginnerWorkoutKind.recoveryRun => [
        'Warm-up walk · 4 min',
        'Short easy run · $mainEffortMinutes min',
        'Cool-down walk · ${durationMinutes - mainEffortMinutes - 4} min',
      ],
      BeginnerWorkoutKind.restOrMobility => const ['Rest or light mobility'],
    };
  }

  BeginnerAdaptiveWorkoutBreakdownStep _detailStepFor(
    String step,
    BeginnerWorkoutKind kind,
  ) {
    final parts = step.split(' · ');
    final title = parts.first;
    return BeginnerAdaptiveWorkoutBreakdownStep(
      kind: _stepKindFor(title, kind),
      title: title,
      detail: parts.length > 1 ? parts.sublist(1).join(' · ') : step,
    );
  }

  BeginnerAdaptiveWorkoutBreakdownStepKind _stepKindFor(
    String title,
    BeginnerWorkoutKind kind,
  ) {
    final normalized = title.toLowerCase();
    if (normalized.contains('mobility') || normalized.contains('cool')) {
      return BeginnerAdaptiveWorkoutBreakdownStepKind.mobility;
    }
    if (normalized.contains('run') ||
        kind == BeginnerWorkoutKind.steadyRun ||
        kind == BeginnerWorkoutKind.controlledSteadyRun ||
        kind == BeginnerWorkoutKind.longerEasyRun ||
        kind == BeginnerWorkoutKind.recoveryRun ||
        kind == BeginnerWorkoutKind.easyRun) {
      return BeginnerAdaptiveWorkoutBreakdownStepKind.run;
    }
    return BeginnerAdaptiveWorkoutBreakdownStepKind.walk;
  }

  String _adjustmentNoteFor(
    LocalOnboardingDraft draft,
    BeginnerPlanIntensity intensity,
  ) {
    final place = _placeLabelFor(draft.runningPlace);
    return switch (intensity) {
      BeginnerPlanIntensity.veryGentle =>
        'Use a comfortable $place and keep this session easy enough to finish feeling steady.',
      BeginnerPlanIntensity.gentle =>
        'Choose a familiar $place and keep the effort conversational from start to finish.',
      BeginnerPlanIntensity.balanced =>
        'Stay controlled on your $place and reduce the run portions if the effort stops feeling comfortable.',
    };
  }

  String _purposeNoteFor({
    required BeginnerWorkoutKind kind,
    required int sessionIndex,
    required int requiredSessions,
    required int mainEffortMinutes,
  }) {
    final position = _sessionPositionLabel(sessionIndex, requiredSessions);
    return switch (kind) {
      BeginnerWorkoutKind.easyRun =>
        'Use this as the $position easy run: $mainEffortMinutes minutes of relaxed running after the warm-up.',
      BeginnerWorkoutKind.runWalk =>
        'Use this as the $position run-walk session: keep the run blocks short and repeatable.',
      BeginnerWorkoutKind.walkRun =>
        'Use this as the $position walk-run session: walking stays in control and the running stays brief.',
      BeginnerWorkoutKind.recoveryWalk =>
        'Use this as the $position recovery walk: keep the pace light enough to feel better afterward.',
      BeginnerWorkoutKind.steadyRun =>
        'Use this as the $position steady builder: hold one calm rhythm without pushing the pace.',
      BeginnerWorkoutKind.controlledSteadyRun =>
        'Use this as the $position controlled session: the middle block should feel structured, not hard.',
      BeginnerWorkoutKind.longerEasyRun =>
        'Use this as the $position longer run: $mainEffortMinutes minutes of easy running, easier than a steady day.',
      BeginnerWorkoutKind.recoveryRun =>
        'Use this as the $position recovery run: short running only, with enough energy left for the next session.',
      BeginnerWorkoutKind.restOrMobility =>
        'Use this as the $position reset day: skip running and keep any movement light.',
    };
  }

  String _sessionPositionLabel(int sessionIndex, int requiredSessions) {
    if (sessionIndex == 0) {
      return 'opening';
    }
    if (sessionIndex == requiredSessions - 1) {
      return 'closing';
    }
    if (sessionIndex == 1) {
      return 'middle';
    }
    return 'bridge';
  }

  String _kindLabel(BeginnerWorkoutKind kind) {
    return switch (kind) {
      BeginnerWorkoutKind.easyRun => 'Easy run',
      BeginnerWorkoutKind.runWalk => 'Run-walk',
      BeginnerWorkoutKind.walkRun => 'Walk-run',
      BeginnerWorkoutKind.recoveryWalk => 'Recovery walk',
      BeginnerWorkoutKind.steadyRun => 'Steady run',
      BeginnerWorkoutKind.controlledSteadyRun => 'Controlled steady run',
      BeginnerWorkoutKind.longerEasyRun => 'Longer easy run',
      BeginnerWorkoutKind.recoveryRun => 'Recovery run',
      BeginnerWorkoutKind.restOrMobility => 'Rest or mobility',
    };
  }

  String _intensityLabel(BeginnerPlanIntensity intensity) {
    return switch (intensity) {
      BeginnerPlanIntensity.veryGentle => 'Very gentle',
      BeginnerPlanIntensity.gentle => 'Gentle',
      BeginnerPlanIntensity.balanced => 'Balanced',
    };
  }

  String _placeLabelFor(OnboardingRunningPlace place) {
    return switch (place) {
      OnboardingRunningPlace.park => 'park loop',
      OnboardingRunningPlace.road => 'neighbourhood route',
      OnboardingRunningPlace.track => 'track lane',
      OnboardingRunningPlace.treadmill => 'treadmill setup',
      OnboardingRunningPlace.mixed => 'route',
    };
  }
}
