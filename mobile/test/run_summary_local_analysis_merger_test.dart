import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/services/pace_graph_data_builder.dart';
import 'package:runiac_app/features/run/domain/services/run_summary_local_analysis_merger.dart';

// Partial-data merge behavior for RunSummaryLocalAnalysisMerger.
//
// The happy-path merge (full route + pace + cadence + elevation) and the
// session-id mismatch guard are covered in run_tracking_flow_test.dart; these
// unit tests pin the degraded inputs a real run can produce — an empty
// accepted route, and absent cadence/elevation series — with fixtures
// distinct from the flow test's.

const _sessionId = 'partial-merge-session';

RunSummarySnapshot _sufficientBackendSummary() {
  return const RunSummarySnapshot(
    title: 'Backend Partial Merge Run',
    dateLabel: 'Today',
    timeLabel: '6:40 AM',
    distanceKm: '0.70',
    avgPace: '7’09”',
    duration: '05:00',
    avgHeartRate: '--',
    calories: '--',
    routeName: 'Backend Partial Merge Route',
  );
}

RunSummarySnapshot _lowDataBackendSummary() {
  return const RunSummarySnapshot(
    title: 'Backend Partial Low Data Run',
    dateLabel: 'Today',
    timeLabel: '6:40 AM',
    distanceKm: '0.03',
    avgPace: '--',
    duration: '00:31',
    avgHeartRate: '--',
    calories: '--',
    routeName: 'Backend Partial Low Data Route',
    hasSufficientData: false,
  );
}

/// Sufficient-data local payload with a valid pace series but no cadence and
/// no elevation series (e.g. no pedometer permission and no barometer).
LocalRunCompletionPayload _paceOnlyPayload() {
  return LocalRunCompletionPayload(
    clientRunSessionId: _sessionId,
    startedAt: DateTime.utc(2026, 7, 20, 6, 30),
    completedAt: DateTime.utc(2026, 7, 20, 6, 35),
    durationSeconds: 300,
    distanceMeters: 700,
    avgPaceSecondsPerKm: 429,
    source: 'local_gps',
    routePrivacy: 'private',
    paceGraphSamples: const <PaceGraphSample>[
      PaceGraphSample(
        elapsedSeconds: 45,
        paceSecondsPerKm: 425,
        cumulativeDistanceMeters: 105,
      ),
      PaceGraphSample(
        elapsedSeconds: 105,
        paceSecondsPerKm: 431,
        cumulativeDistanceMeters: 245,
      ),
      PaceGraphSample(
        elapsedSeconds: 165,
        paceSecondsPerKm: 434,
        cumulativeDistanceMeters: 385,
      ),
      PaceGraphSample(
        elapsedSeconds: 225,
        paceSecondsPerKm: 427,
        cumulativeDistanceMeters: 525,
      ),
      PaceGraphSample(
        elapsedSeconds: 285,
        paceSecondsPerKm: 428,
        cumulativeDistanceMeters: 665,
      ),
    ],
    // Deliberately absent partial-data inputs.
    cadenceAnalysisSeries: null,
    elevationAnalysisSeries: null,
  );
}

RunRouteSnapshot _recordedRoute() {
  return RunRouteSnapshot(
    segments: [
      [
        RunLocationSample(
          recordedAt: DateTime.utc(2026, 7, 20, 6, 30),
          latitude: 1.29,
          longitude: 103.85,
        ),
        RunLocationSample(
          recordedAt: DateTime.utc(2026, 7, 20, 6, 32),
          latitude: 1.2906,
          longitude: 103.85,
        ),
        RunLocationSample(
          recordedAt: DateTime.utc(2026, 7, 20, 6, 35),
          latitude: 1.2912,
          longitude: 103.8504,
        ),
      ],
    ],
  );
}

void main() {
  group('RunSummaryLocalAnalysisMerger partial data', () {
    test(
      'empty local route with a valid pace series merges without a route',
      () {
        const merger = RunSummaryLocalAnalysisMerger();
        final payload = _paceOnlyPayload();

        late RunSummarySnapshot merged;
        expect(() {
          merged = merger.merge(
            backendSummary: _sufficientBackendSummary(),
            localPayload: payload,
            localRoute: RunRouteSnapshot.empty,
            resultClientRunSessionId: _sessionId,
          );
        }, returnsNormally);

        // The empty route is carried as-is — no crash and no phantom route.
        expect(merged.route.hasRoute, isFalse);
        expect(merged.route.segments, isEmpty);
        // The local pace analysis still comes through.
        expect(merged.paceAnalysisSeries, isNotNull);
        expect(merged.paceAnalysisSeries?.isLocalAcceptedSource, isTrue);
        expect(merged.paceGraph.isAvailable, isTrue);
      },
    );

    test(
      'absent cadence and elevation series keep route and pace, stay absent',
      () {
        const merger = RunSummaryLocalAnalysisMerger();
        final payload = _paceOnlyPayload();

        late RunSummarySnapshot merged;
        expect(() {
          merged = merger.merge(
            backendSummary: _sufficientBackendSummary(),
            localPayload: payload,
            localRoute: _recordedRoute(),
            resultClientRunSessionId: _sessionId,
          );
        }, returnsNormally);

        expect(merged.route.hasRoute, isTrue);
        expect(merged.paceAnalysisSeries, isNotNull);
        expect(merged.paceGraph.isAvailable, isTrue);
        // No cadence series is invented, and elevation stays unavailable
        // (the backend summary's default series is preserved by copyWith).
        expect(merged.cadenceAnalysisSeries, isNull);
        expect(merged.elevationSeries.isUnavailable, isTrue);
      },
    );

    test(
      'low-data summary with an empty local route stays route- and series-free',
      () {
        // The route-preserving low-data case is covered in
        // run_tracking_flow_test.dart ('low-data local analysis merge
        // preserves route only'); this pins the further-degraded variant
        // where even the local route is empty.
        const merger = RunSummaryLocalAnalysisMerger();
        final payload = _paceOnlyPayload();

        final merged = merger.merge(
          backendSummary: _lowDataBackendSummary(),
          localPayload: payload,
          localRoute: RunRouteSnapshot.empty,
          resultClientRunSessionId: _sessionId,
        );

        expect(merged.hasSufficientData, isFalse);
        expect(merged.route.hasRoute, isFalse);
        expect(merged.paceAnalysisSeries, isNull);
        expect(merged.paceGraph.isAvailable, isFalse);
        expect(merged.cadenceAnalysisSeries, isNull);
        expect(merged.elevationSeries.isUnavailable, isTrue);
        expect(
          merged.elevationSeries.unavailableReason,
          ElevationUnavailableReason.lowDataSummary,
        );
      },
    );
  });
}
