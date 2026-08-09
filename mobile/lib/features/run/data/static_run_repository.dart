import '../domain/models/complete_run_result.dart';
import '../domain/models/elevation_analysis_series.dart';
import '../domain/models/local_run_completion_payload.dart';
import '../domain/models/pace_analysis_series.dart';
import '../domain/models/pace_graph_snapshot.dart';
import '../domain/models/progression_display_model.dart';
import '../domain/models/run_completion_error.dart';
import '../domain/models/run_completion_request_adapter.dart';
import '../domain/models/run_activity_read_model.dart';
import '../domain/models/run_summary_read_model.dart';
import '../domain/models/run_summary_snapshot.dart';
import '../domain/models/xp_update_display_model.dart';
import '../domain/repositories/run_repository.dart';
import '../domain/services/pace_graph_data_builder.dart';
import '../domain/services/rule_based_coaching_summary_engine.dart';
import '../domain/services/run_summary_scalar_mapper.dart';
import '../presentation/data/run_completion_demo_snapshots.dart';

class StaticRunRepository implements RunRepository {
  const StaticRunRepository();

  @override
  Future<RunSummaryReadModel> loadLatestRunSummary() async {
    const snapshot = defaultRunSummarySnapshot;

    return RunSummaryReadModel(
      summaryId: 'static-latest-run-summary',
      title: snapshot.title,
      dateLabel: snapshot.dateLabel,
      timeLabel: snapshot.timeLabel,
      distanceLabel: '${snapshot.distanceKm} km',
      avgPaceLabel: snapshot.avgPace,
      durationLabel: snapshot.duration,
      avgHeartRateLabel: snapshot.avgHeartRate,
      caloriesLabel: snapshot.calories,
      routeName: snapshot.routeName,
    );
  }

  @override
  Future<CompleteRunResult> loadLatestCompletionResult() async {
    return const CompleteRunResult(
      summary: defaultRunSummarySnapshot,
      xpUpdate: defaultXpUpdateDisplayModel,
    );
  }

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    RunCompletionRequestAdapter.toBackendRequest(payload);

    final sessionId = payload.clientRunSessionId;
    final scalar = const RunSummaryScalarMapper().map(
      completedAt: payload.completedAt,
      distanceMeters: payload.distanceMeters,
      durationSeconds: payload.durationSeconds,
      averagePaceSecondsPerKm: payload.avgPaceSecondsPerKm,
      routeLabel: payload.routeLabel,
    );
    final baseSummary = RunSummarySnapshot(
      title: scalar.title,
      dateLabel: scalar.dateLabel,
      timeLabel: scalar.timeLabel,
      distanceKm: scalar.distanceKm,
      avgPace: scalar.avgPace,
      duration: scalar.duration,
      avgHeartRate: '--',
      calories: scalar.calories,
      routeName: scalar.routeName,
      hasSufficientData: scalar.hasSufficientData,
      paceAnalysisSeries: scalar.hasSufficientData
          ? _paceAnalysisSeries(payload.paceGraphSamples)
          : null,
      cadenceAnalysisSeries: scalar.hasSufficientData
          ? payload.cadenceAnalysisSeries
          : null,
      elevationSeries: scalar.hasSufficientData
          ? payload.elevationAnalysisSeries ??
                ElevationAnalysisSeries.unavailable(
                  reason: payload.elevationUnavailableReason,
                )
          : const ElevationAnalysisSeries.unavailable(
              reason: ElevationUnavailableReason.lowDataSummary,
            ),
      paceGraph: scalar.hasSufficientData
          ? const PaceGraphDataBuilder().build(
              samples: payload.paceGraphSamples,
              durationSeconds: payload.durationSeconds,
              distanceMeters: payload.distanceMeters,
              averagePaceSecondsPerKm: payload.avgPaceSecondsPerKm,
            )
          : const PaceGraphSnapshot.unavailable(),
    );
    final summary = baseSummary.copyWith(
      coachingSummary: const RuleBasedCoachingSummaryEngine().build(
        baseSummary,
      ),
    );

    return CompleteRunResult(
      clientRunSessionId: sessionId,
      activityId: 'static-$sessionId',
      summaryId: 'static-summary-$sessionId',
      progressionEventId: 'static-progression-$sessionId',
      validationStatus: 'validated',
      summary: summary,
      progressionDisplay: const ProgressionDisplayModel(
        xpDelta: 0,
        countsTowardLeaderboard: false,
        status: 'deferred',
        reason: 'progression_formula_deferred',
      ),
      xpUpdate: const XpUpdateDisplayModel(
        runnerName: 'Runiac Runner',
        earnedXpLabel: '+0 XP',
        totalXpLabel: 'Saved on this device',
        levelLabel: '--',
        nextLevelLabel: '--',
        progressTargetLabel: 'Sync pending',
        xpRemainingLabel: 'XP updates after sync',
        previousProgressFraction: 0,
        currentProgressFraction: 0,
        streakChangeLabel: 'Not updated yet',
        streakNote: 'We’ll retry when the service is available.',
        didLevelUp: false,
        xpAwardState: XpAwardState.syncPending,
        heroMessage: 'This run is saved locally. XP updates after sync.',
      ),
      message: 'Static repository completion accepted.',
    );
  }

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) async {
    // Demo/offline mode must not fabricate a cool-down XP bonus; the guide
    // screen falls back silently and keeps the original completion result.
    throw const RunCompletionException(
      code: 'unimplemented',
      message: 'Cool-down bonus is unavailable in demo mode.',
      isRetryable: false,
    );
  }

  @override
  Future<RunActivityReadModel> loadLatestRunActivity() async {
    const snapshot = defaultRunSummarySnapshot;

    return RunActivityReadModel(
      activityId: 'static-latest-run-activity',
      title: snapshot.title,
      completedAtLabel: snapshot.dateLabel,
      distanceLabel: '${snapshot.distanceKm} km',
      durationLabel: snapshot.duration,
      avgPaceLabel: snapshot.avgPace,
      routeLabel: snapshot.routeName,
    );
  }

  PaceAnalysisSeries? _paceAnalysisSeries(List<PaceGraphSample> samples) {
    final acceptedSamples = <PaceAnalysisSample>[];
    for (final sample in samples) {
      final cumulativeDistanceMeters = sample.cumulativeDistanceMeters;
      if (cumulativeDistanceMeters == null) {
        continue;
      }
      acceptedSamples.add(
        PaceAnalysisSample.accepted(
          elapsedSeconds: sample.elapsedSeconds,
          cumulativeDistanceMeters: cumulativeDistanceMeters.toDouble(),
          paceSecondsPerKm: sample.paceSecondsPerKm,
        ),
      );
    }

    if (acceptedSamples.isEmpty) {
      return null;
    }
    return PaceAnalysisSeries.localAccepted(samples: acceptedSamples);
  }
}
