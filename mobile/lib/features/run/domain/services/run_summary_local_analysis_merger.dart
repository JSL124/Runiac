import '../models/local_run_completion_payload.dart';
import '../models/pace_analysis_series.dart';
import '../models/elevation_analysis_series.dart';
import '../models/run_route_snapshot.dart';
import '../models/run_summary_snapshot.dart';
import 'pace_graph_data_builder.dart';
import 'rule_based_coaching_summary_engine.dart';

class RunSummaryLocalAnalysisMerger {
  const RunSummaryLocalAnalysisMerger();

  RunSummarySnapshot merge({
    required RunSummarySnapshot backendSummary,
    required LocalRunCompletionPayload localPayload,
    required RunRouteSnapshot localRoute,
    required String? resultClientRunSessionId,
  }) {
    if (localPayload.clientRunSessionId != resultClientRunSessionId) {
      return backendSummary;
    }
    if (!backendSummary.hasSufficientData) {
      // Low-data runs may still show the recorded route, but local analysis
      // remains unavailable so the summary does not imply metric confidence.
      return backendSummary.copyWith(
        route: localRoute,
        elevationSeries: const ElevationAnalysisSeries.unavailable(
          reason: ElevationUnavailableReason.lowDataSummary,
        ),
      );
    }

    final localPaceGraph = const PaceGraphDataBuilder().build(
      samples: localPayload.paceGraphSamples,
      durationSeconds: localPayload.durationSeconds,
      distanceMeters: localPayload.distanceMeters,
      averagePaceSecondsPerKm: localPayload.avgPaceSecondsPerKm,
    );
    final mergedSummary = backendSummary.copyWith(
      route: localRoute,
      paceAnalysisSeries: _paceAnalysisSeries(localPayload.paceGraphSamples),
      cadenceAnalysisSeries: localPayload.cadenceAnalysisSeries,
      elevationSeries: localPayload.elevationAnalysisSeries,
      paceGraph: localPaceGraph.isAvailable
          ? localPaceGraph
          : backendSummary.paceGraph,
    );

    return mergedSummary.copyWith(
      coachingSummary: const RuleBasedCoachingSummaryEngine().build(
        mergedSummary,
      ),
    );
  }
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
