import '../services/xp_update_display_model_mapper.dart';
import 'progression_display_model.dart';
import 'run_summary_snapshot.dart';
import 'xp_update_display_model.dart';

class PlanCompletionResult {
  const PlanCompletionResult({
    this.completed = false,
    this.planEnrollmentId,
    this.scheduledWorkoutId,
  });

  final bool completed;
  final String? planEnrollmentId;
  final String? scheduledWorkoutId;
}

/// Future backend-produced display result for a completed run.
///
/// This presentation-only shape must not calculate rewards, decide progression
/// eligibility, or perform backend, network, or storage actions.
class CompleteRunResult {
  const CompleteRunResult({
    this.clientRunSessionId,
    this.activityId = 'static-latest-run-activity',
    this.summaryId = 'static-latest-run-summary',
    this.progressionEventId = 'static-latest-progression-event',
    this.validationStatus = 'validated',
    required this.summary,
    this.progressionDisplay = const ProgressionDisplayModel(
      xpDelta: 0,
      countsTowardLeaderboard: false,
      status: 'deferred',
      reason: 'progression_formula_deferred',
    ),
    this.planCompletion = const PlanCompletionResult(),
    required this.xpUpdate,
    this.message = 'Static completion result.',
  });

  final String? clientRunSessionId;
  final String activityId;
  final String summaryId;
  final String progressionEventId;
  final String validationStatus;
  final RunSummarySnapshot summary;
  final ProgressionDisplayModel progressionDisplay;
  final PlanCompletionResult planCompletion;
  final XpUpdateDisplayModel xpUpdate;
  final String message;

  CompleteRunResult copyWith({
    String? clientRunSessionId,
    String? activityId,
    String? summaryId,
    String? progressionEventId,
    String? validationStatus,
    RunSummarySnapshot? summary,
    ProgressionDisplayModel? progressionDisplay,
    PlanCompletionResult? planCompletion,
    XpUpdateDisplayModel? xpUpdate,
    String? message,
  }) {
    return CompleteRunResult(
      clientRunSessionId: clientRunSessionId ?? this.clientRunSessionId,
      activityId: activityId ?? this.activityId,
      summaryId: summaryId ?? this.summaryId,
      progressionEventId: progressionEventId ?? this.progressionEventId,
      validationStatus: validationStatus ?? this.validationStatus,
      summary: summary ?? this.summary,
      progressionDisplay: progressionDisplay ?? this.progressionDisplay,
      planCompletion: planCompletion ?? this.planCompletion,
      xpUpdate: xpUpdate ?? this.xpUpdate,
      message: message ?? this.message,
    );
  }

  /// Folds a server-computed cool-down XP bonus into this run's progression
  /// display for rendering.
  ///
  /// This is a display-only merge: it never derives new progression numbers.
  /// It only (a) sums the two server-returned XP deltas so the celebration
  /// screen shows the combined amount earned this session, and (b) copies the
  /// bonus response's server-returned totals (totalXp, level, progress
  /// percents, etc.) as the new truth, since those already account for the
  /// bonus having been applied server-side. The "previous" fields are taken
  /// from this run's own progression display so the XP screen still animates
  /// from the pre-run baseline; streak fields are untouched because
  /// cool-down never changes streak.
  ///
  /// Returns this result unchanged if the cool-down bonus was not awarded.
  CompleteRunResult mergeCoolDownBonus(ProgressionDisplayModel coolDownDisplay) {
    if (coolDownDisplay.status != 'awarded' ||
        coolDownDisplay.xpDelta <= 0 ||
        coolDownDisplay.totalXp == null) {
      return this;
    }

    final merged = ProgressionDisplayModel(
      xpDelta: progressionDisplay.xpDelta + coolDownDisplay.xpDelta,
      countsTowardLeaderboard:
          progressionDisplay.countsTowardLeaderboard ||
          coolDownDisplay.countsTowardLeaderboard,
      status: 'awarded',
      reason: progressionDisplay.reason,
      totalXp: coolDownDisplay.totalXp,
      level: coolDownDisplay.level,
      divisionKey: coolDownDisplay.divisionKey,
      previousTotalXp:
          progressionDisplay.previousTotalXp ?? coolDownDisplay.previousTotalXp,
      previousLevel:
          progressionDisplay.previousLevel ?? coolDownDisplay.previousLevel,
      previousLevelProgressPercent:
          progressionDisplay.previousLevelProgressPercent ??
          coolDownDisplay.previousLevelProgressPercent,
      levelProgressPercent: coolDownDisplay.levelProgressPercent,
      xpToNextLevel: coolDownDisplay.xpToNextLevel,
      nextLevelXp: coolDownDisplay.nextLevelXp,
      streak: progressionDisplay.streak,
      previousStreak: progressionDisplay.previousStreak,
    );

    return copyWith(
      progressionDisplay: merged,
      xpUpdate: XpUpdateDisplayModelMapper.fromProgression(merged),
    );
  }
}
