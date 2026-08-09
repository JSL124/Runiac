import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/data/static_run_repository.dart';
import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_provider.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';
import 'package:runiac_app/features/run/domain/services/completed_run_title_formatter.dart';
import 'package:runiac_app/features/run/domain/services/pace_graph_data_builder.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_state.dart';
import 'package:runiac_app/features/run/presentation/controllers/run_tracking_controller.dart';

void main() {
  group('RunTrackingController local engine integration', () {
    test(
      'uses replay location samples for distance and completion summary',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: Duration.zero,
              sample: RunLocationSample(
                recordedAt: startedAt,
                latitude: 1.300000,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 120),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 120)),
                latitude: 1.302698,
                longitude: 103.800000,
              ),
            ),
          ]),
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'local-session-replay',
          routeLabel: 'Replay local route',
        );
        controller.advanceBy(const Duration(seconds: 120));
        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 120)),
        );
        final payloadMap = payload.toRawClientMap();

        expect(controller.state.phase, RunTrackingPhase.active);
        expect(controller.state.elapsedSeconds, 120);
        expect(controller.state.distanceMeters, closeTo(300, 2));
        expect(controller.state.averagePaceSecondsPerKm, closeTo(400, 3));
        expect(payload.durationSeconds, 120);
        expect(
          payload.activityTitle,
          const CompletedRunTitleFormatter().format(
            completedAt: startedAt.add(const Duration(seconds: 120)),
          ),
        );
        expect(payload.distanceMeters, closeTo(300, 2));
        expect(payload.avgPaceSecondsPerKm, closeTo(400, 3));
        expect(payload.routeSnapshot.segments, hasLength(1));
        expect(payload.routeSnapshot.segments.single, hasLength(2));
        expect(payload.routeSnapshot.lastKnownLocation?.latitude, 1.302698);
        expect(payloadMap.keys, isNot(contains('latitude')));
        expect(payloadMap.keys, isNot(contains('longitude')));
        expect(payloadMap.keys, isNot(contains('samples')));
        expect(payloadMap.keys, isNot(contains('routeTrace')));
        expect(payloadMap.keys, isNot(contains('polyline')));
      },
    );

    test('completed local run builds payload-derived pace graph', () async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: Duration.zero,
            sample: RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.300000,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 60),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 60)),
              latitude: 1.301349,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 120),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 120)),
              latitude: 1.302698,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 180),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 180)),
              latitude: 1.304047,
              longitude: 103.800000,
            ),
          ),
        ]),
      );

      controller.start(
        startedAt: startedAt,
        clientRunSessionId: 'local-completion-graph-flow',
        routeLabel: 'Payload Derived Route',
      );
      controller.advanceBy(const Duration(seconds: 180));

      final payload = controller.completionPayload(
        completedAt: startedAt.add(const Duration(seconds: 180)),
      );
      final expectedGraph = const PaceGraphDataBuilder().build(
        samples: payload.paceGraphSamples,
        durationSeconds: payload.durationSeconds,
        distanceMeters: payload.distanceMeters,
        averagePaceSecondsPerKm: payload.avgPaceSecondsPerKm,
      );
      final completedRun = await const StaticRunRepository().completeRun(
        payload,
      );
      final graph = completedRun.summary.paceGraph;

      expect(payload.paceGraphSamples.length, greaterThanOrEqualTo(3));
      expect(completedRun.summary.hasSufficientData, isTrue);
      expect(completedRun.summary.distanceKm, '0.45');
      expect(completedRun.summary.duration, '3:00');
      expect(completedRun.summary.avgPace, '6’39”');
      expect(completedRun.summary.routeName, 'Payload Derived Route');
      expect(completedRun.summary.routeName, isNot('East Coast Park Loop'));
      expect(graph.isAvailable, isTrue);
      expect(graph.points, hasLength(expectedGraph.points.length));
      expect(
        graph.points.map((point) => point.elapsedSeconds),
        expectedGraph.points.map((point) => point.elapsedSeconds),
      );
      expect(
        graph.points.map((point) => point.paceSecondsPerKm),
        expectedGraph.points.map((point) => point.paceSecondsPerKm),
      );
      expect(graph.totalDurationSeconds, payload.durationSeconds);
      expect(graph.averagePaceSecondsPerKm, payload.avgPaceSecondsPerKm);
    });

    test(
      'completed low-data local run returns unavailable pace graph',
      () async {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: Duration.zero,
              sample: RunLocationSample(
                recordedAt: startedAt,
                latitude: 1.300000,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 120),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 120)),
                latitude: 1.302698,
                longitude: 103.800000,
              ),
            ),
          ]),
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'local-completion-low-data-graph-flow',
          routeLabel: 'Low data local route',
        );
        controller.advanceBy(const Duration(seconds: 120));

        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 120)),
        );
        final completedRun = await const StaticRunRepository().completeRun(
          payload,
        );

        expect(payload.paceGraphSamples.length, lessThan(3));
        expect(completedRun.summary.hasSufficientData, isTrue);
        expect(completedRun.summary.paceGraph.isAvailable, isFalse);
        expect(completedRun.summary.paceGraph.points, isEmpty);
      },
    );

    test(
      'completed local run derives elevation from accepted live altitude',
      () async {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: Duration.zero,
              sample: RunLocationSample(
                recordedAt: startedAt,
                latitude: 1.300000,
                longitude: 103.800000,
                altitudeMeters: 4,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 60),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 60)),
                latitude: 1.301349,
                longitude: 103.800000,
                altitudeMeters: 5.2,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 120),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 120)),
                latitude: 1.302698,
                longitude: 103.800000,
                altitudeMeters: 8.4,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 180),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 180)),
                latitude: 1.304047,
                longitude: 103.800000,
                altitudeMeters: 6.1,
              ),
            ),
          ]),
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'local-completion-elevation-flow',
        );
        controller.advanceBy(const Duration(seconds: 180));

        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 180)),
        );
        final completedRun = await const StaticRunRepository().completeRun(
          payload,
        );
        final elevation = const AdvancedAnalysisSnapshotBuilder()
            .fromRunSummary(completedRun.summary)
            .elevation;

        expect(payload.elevationAnalysisSeries?.validSamples, hasLength(4));
        expect(completedRun.summary.elevationSeries.isUnavailable, isFalse);
        expect(
          elevation.elevationGraph.source,
          AdvancedAnalysisMetricSource.localGpsDerived,
        );
        expect(elevation.totalGain.valueLabel, '+3 m');
        expect(elevation.highestPoint.valueLabel, '8 m');
        expect(elevation.lowestPoint.valueLabel, '4 m');
        expect(elevation.elevationGraph.isAvailable, isTrue);
      },
    );

    test(
      'completed local run keeps elevation unavailable without altitude',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: Duration.zero,
              sample: RunLocationSample(
                recordedAt: startedAt,
                latitude: 1.300000,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 60),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 60)),
                latitude: 1.301349,
                longitude: 103.800000,
              ),
            ),
          ]),
        );

        controller.start(startedAt: startedAt);
        controller.advanceBy(const Duration(seconds: 60));
        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 60)),
        );

        expect(payload.elevationAnalysisSeries, isNull);
        expect(
          payload.elevationUnavailableReason,
          ElevationUnavailableReason.noAcceptedAltitudeSamples,
        );
      },
    );

    test('completed local run explains too few accepted altitude samples', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: Duration.zero,
            sample: RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.300000,
              longitude: 103.800000,
              altitudeMeters: 4,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 60),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 60)),
              latitude: 1.301349,
              longitude: 103.800000,
            ),
          ),
        ]),
      );

      controller.start(startedAt: startedAt);
      controller.advanceBy(const Duration(seconds: 60));
      final payload = controller.completionPayload(
        completedAt: startedAt.add(const Duration(seconds: 60)),
      );

      expect(payload.elevationAnalysisSeries, isNull);
      expect(
        payload.elevationUnavailableReason,
        ElevationUnavailableReason.tooFewValidAltitudeSamples,
      );
    });

    test(
      'completion payload carries local-only graph samples from accepted route segments',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: Duration.zero,
              sample: RunLocationSample(
                recordedAt: startedAt,
                latitude: 1.300000,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 60),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 60)),
                latitude: 1.301349,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 120),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 120)),
                latitude: 1.302698,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 180),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 180)),
                latitude: 1.304047,
                longitude: 103.800000,
              ),
            ),
          ]),
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'local-graph-samples-run',
        );
        controller.advanceBy(const Duration(seconds: 180));

        final payload = controller.completionPayload(
          completedAt: startedAt.add(const Duration(seconds: 180)),
        );

        expect(payload.paceGraphSamples.length, greaterThanOrEqualTo(3));
        expect(
          payload.paceGraphSamples.map((sample) => sample.elapsedSeconds),
          [60, 120, 180],
        );
        expect(
          payload.paceGraphSamples.every(
            (sample) =>
                sample.paceSecondsPerKm >= minGraphPaceSecondsPerKm &&
                sample.paceSecondsPerKm <= maxGraphPaceSecondsPerKm,
          ),
          isTrue,
        );
      },
    );

    test(
      'paused local run pace graph uses active elapsed instead of wall-clock elapsed',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final resumedAt = startedAt.add(const Duration(minutes: 15));
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: Duration.zero,
              sample: RunLocationSample(
                recordedAt: startedAt,
                latitude: 1.300000,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 60),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 60)),
                latitude: 1.301349,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 120),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 120)),
                latitude: 1.302698,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 180),
              sample: RunLocationSample(
                recordedAt: resumedAt.add(const Duration(seconds: 60)),
                latitude: 1.400000,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 240),
              sample: RunLocationSample(
                recordedAt: resumedAt.add(const Duration(seconds: 120)),
                latitude: 1.401349,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 300),
              sample: RunLocationSample(
                recordedAt: resumedAt.add(const Duration(seconds: 180)),
                latitude: 1.402698,
                longitude: 103.800000,
              ),
            ),
          ]),
        );

        controller.start(
          startedAt: startedAt,
          clientRunSessionId: 'paused-local-active-graph-run',
        );
        controller.advanceBy(const Duration(seconds: 120));
        controller.pause(pausedAt: startedAt.add(const Duration(minutes: 5)));
        controller.resume(resumedAt: resumedAt);
        controller.advanceBy(const Duration(seconds: 180));

        final payload = controller.completionPayload(
          completedAt: resumedAt.add(const Duration(minutes: 5)),
        );
        final graph = const PaceGraphDataBuilder().build(
          samples: payload.paceGraphSamples,
          durationSeconds: payload.durationSeconds,
          distanceMeters: payload.distanceMeters,
          averagePaceSecondsPerKm: payload.avgPaceSecondsPerKm,
        );

        expect(payload.durationSeconds, 300);
        expect(
          payload.paceGraphSamples.map((sample) => sample.elapsedSeconds),
          [60, 120, 240, 300],
        );
        expect(
          payload.paceGraphSamples.every(
            (sample) => sample.elapsedSeconds <= payload.durationSeconds,
          ),
          isTrue,
        );
        expect(controller.mapViewState.routeSegments, hasLength(2));
        expect(
          controller.mapViewState.routeSegments.map(
            (segment) => segment.length,
          ),
          [3, 3],
        );
        expect(graph.isAvailable, isTrue);
        expect(
          graph.points.map((point) => point.progressFraction),
          everyElement(lessThanOrEqualTo(1)),
        );
        expect(graph.points.last.progressFraction, 1);
      },
    );

    test('completion payload raw map excludes local graph and route data', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-graph-raw-map-run',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 3),
        durationSeconds: 180,
        distanceMeters: 450,
        avgPaceSecondsPerKm: 400,
        source: 'local_simulation',
        routePrivacy: 'private',
        paceGraphSamples: const [
          PaceGraphSample(elapsedSeconds: 60, paceSecondsPerKm: 400),
          PaceGraphSample(elapsedSeconds: 120, paceSecondsPerKm: 402),
          PaceGraphSample(elapsedSeconds: 180, paceSecondsPerKm: 398),
        ],
      );

      final payloadMap = payload.toRawClientMap();
      const forbiddenKeys = [
        'paceGraphSamples',
        'graphSamples',
        'paceGraph',
        'samples',
        'latitude',
        'longitude',
        'routeTrace',
        'polyline',
        'positions',
        'gpsSamples',
        'rawLocationSamples',
        'displayRouteSegments',
        'acceptedRouteSegments',
        'motionEvidence',
      ];

      for (final key in forbiddenKeys) {
        expect(payloadMap.keys, isNot(contains(key)));
      }
    });

    test('exposes accepted samples as local-only map route state', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: Duration.zero,
            sample: RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.300000,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 60),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 60)),
              latitude: 1.300899,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 120),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 120)),
              latitude: 1.301798,
              longitude: 103.800000,
            ),
          ),
        ]),
      );

      controller.start(startedAt: startedAt);
      controller.advanceBy(const Duration(seconds: 120));

      expect(controller.mapViewState.currentPosition?.latitude, 1.301798);
      expect(controller.mapViewState.currentPosition?.longitude, 103.800000);
      expect(controller.mapViewState.routeSegments, hasLength(1));
      expect(controller.mapViewState.routeSegments.single, hasLength(3));
      expect(controller.mapViewState.routePointCount, 3);
      expect(controller.mapViewState.hasRoutePolyline, isTrue);
      expect(
        controller.mapViewState.displayRouteSegments.single,
        hasLength(
          greaterThan(controller.mapViewState.routeSegments.single.length),
        ),
      );
      expect(
        controller.mapViewState.displayRouteSegments.single.first,
        same(controller.mapViewState.routeSegments.single.first),
      );
      expect(
        controller.mapViewState.displayRouteSegments.single.last,
        same(controller.mapViewState.routeSegments.single.last),
      );

      final payloadMap = controller.completionPayload().toRawClientMap();
      expect(payloadMap.keys, isNot(contains('latitude')));
      expect(payloadMap.keys, isNot(contains('longitude')));
      expect(payloadMap.keys, isNot(contains('samples')));
      expect(payloadMap.keys, isNot(contains('routeTrace')));
      expect(payloadMap.keys, isNot(contains('polyline')));
      expect(payloadMap.keys, isNot(contains('positions')));
      expect(payloadMap.keys, isNot(contains('gpsSamples')));
      expect(payloadMap.keys, isNot(contains('rawLocationSamples')));
      expect(payloadMap.keys, isNot(contains('displayRouteSegments')));
      expect(payloadMap.keys, isNot(contains('acceptedRouteSegments')));
    });

    test('pause does not extend local map route polyline', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: Duration.zero,
            sample: RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.300000,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 10),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 10)),
              latitude: 1.300100,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 20),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 20)),
              latitude: 1.350000,
              longitude: 103.800000,
            ),
          ),
        ]),
      );

      controller.start(startedAt: startedAt);
      controller.advanceBy(const Duration(seconds: 10));
      controller.pause();
      controller.advanceBy(const Duration(seconds: 10));

      expect(controller.mapViewState.routeSegments, hasLength(1));
      expect(controller.mapViewState.routeSegments.single, hasLength(2));
      expect(controller.mapViewState.currentPosition?.latitude, 1.300100);
    });

    test('resume starts a new local route segment without bridge polyline', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: Duration.zero,
            sample: RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.300000,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 10),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 10)),
              latitude: 1.300100,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 20),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 20)),
              latitude: 1.400000,
              longitude: 103.800000,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 30),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 30)),
              latitude: 1.400100,
              longitude: 103.800000,
            ),
          ),
        ]),
      );

      controller.start(startedAt: startedAt);
      controller.advanceBy(const Duration(seconds: 10));
      controller.pause();
      controller.resume();
      controller.advanceBy(const Duration(seconds: 10));
      controller.advanceBy(const Duration(seconds: 10));

      expect(controller.mapViewState.routeSegments, hasLength(2));
      expect(
        controller.mapViewState.routeSegments.map((segment) => segment.length),
        [2, 2],
      );
      expect(
        controller.mapViewState.routeSegments.first.last.latitude,
        1.300100,
      );
      expect(
        controller.mapViewState.routeSegments.last.first.latitude,
        1.400000,
      );
    });

    test(
      'resume duplicate anchor makes first displaced sample a no-distance route anchor',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: Duration.zero,
              sample: RunLocationSample(
                recordedAt: startedAt,
                latitude: 1.300000,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 10),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 10)),
                latitude: 1.300100,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 20),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 20)),
                latitude: 1.300200,
                longitude: 103.800000,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 30),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 30)),
                latitude: 1.300300,
                longitude: 103.800000,
              ),
            ),
          ]),
        );

        controller.start(startedAt: startedAt);
        controller.advanceBy(const Duration(seconds: 10));
        final distanceBeforePause = controller.state.distanceMeters;
        controller.pause();
        controller.resume();
        controller.advanceBy(const Duration(seconds: 10));

        expect(controller.mapViewState.routeSegments, hasLength(2));
        expect(controller.state.distanceMeters, distanceBeforePause);
        expect(
          controller.mapViewState.routeSegments.map((segment) {
            return segment.map((sample) => sample.latitude).toList();
          }),
          [
            [1.300000, 1.300100],
            [1.300200],
          ],
        );
        expect(controller.mapViewState.currentPosition?.latitude, 1.300200);

        controller.advanceBy(const Duration(seconds: 10));

        expect(controller.mapViewState.routeSegments, hasLength(2));
        expect(
          controller.state.distanceMeters,
          greaterThan(distanceBeforePause),
        );
        expect(
          controller.mapViewState.routeSegments.map((segment) {
            return segment.map((sample) => sample.latitude).toList();
          }),
          [
            [1.300000, 1.300100],
            [1.300200, 1.300300],
          ],
        );
      },
    );

    test('auto pause updates marker without extending drift route', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: Duration.zero,
            sample: RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.300000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 60),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 60)),
              latitude: 1.300899,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 70),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 70)),
              latitude: 1.300908,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 80),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 80)),
              latitude: 1.300917,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 0.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 90),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 90)),
              latitude: 1.301000,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 1.2,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 100),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 100)),
              latitude: 1.301090,
              longitude: 103.800000,
              horizontalAccuracyMeters: 5,
              speedMetersPerSecond: 1.2,
            ),
          ),
        ]),
      );

      controller.start(startedAt: startedAt);
      controller.advanceBy(const Duration(seconds: 60));
      final distanceBeforeStop = controller.state.distanceMeters;
      final routePointCountBeforeStop = controller.mapViewState.routePointCount;

      controller.advanceBy(const Duration(seconds: 20));

      expect(controller.state.isAutoPaused, isTrue);
      expect(controller.state.distanceMeters, distanceBeforeStop);
      expect(
        controller.mapViewState.routePointCount,
        routePointCountBeforeStop,
      );
      expect(controller.mapViewState.currentPosition?.latitude, 1.300917);

      controller.advanceBy(const Duration(seconds: 10));

      expect(controller.state.isAutoPaused, isTrue);
      expect(controller.mapViewState.routeSegments, hasLength(1));
      expect(controller.state.distanceMeters, distanceBeforeStop);

      controller.advanceBy(const Duration(seconds: 10));

      expect(controller.state.isAutoPaused, isFalse);
      expect(controller.state.distanceMeters, greaterThan(distanceBeforeStop));
      expect(controller.mapViewState.routeSegments, hasLength(2));
      expect(controller.mapViewState.routeSegments.last, hasLength(2));
      expect(
        controller.mapViewState.routeSegments.first.last.latitude,
        1.300899,
      );
      expect(
        controller.mapViewState.routeSegments.last.first.latitude,
        1.301000,
      );
    });

    test(
      'start-stationary auto pause keeps marker alive without route drift',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final controller = RunTrackingController(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 1)),
                latitude: 1.300000,
                longitude: 103.800000,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 0.1,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 10),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 10)),
                latitude: 1.300009,
                longitude: 103.800000,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 0.1,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 20),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 20)),
                latitude: 1.300018,
                longitude: 103.800000,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 0.1,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 30),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 30)),
                latitude: 1.300100,
                longitude: 103.800000,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 1.2,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 40),
              sample: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 40)),
                latitude: 1.300190,
                longitude: 103.800000,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 1.2,
              ),
            ),
          ]),
        );

        controller.start(startedAt: startedAt);
        controller.advanceBy(const Duration(seconds: 21));

        expect(controller.state.isAutoPaused, isTrue);
        expect(controller.state.elapsedSeconds, 0);
        expect(controller.state.distanceMeters, 0);
        expect(controller.mapViewState.routeSegments, hasLength(1));
        expect(controller.mapViewState.routePointCount, 1);
        expect(controller.mapViewState.currentPosition?.latitude, 1.300018);

        controller.advanceBy(const Duration(seconds: 9));

        expect(controller.state.isAutoPaused, isTrue);
        expect(controller.state.elapsedSeconds, 0);
        expect(controller.state.distanceMeters, 0);
        expect(controller.mapViewState.routeSegments, hasLength(1));
        expect(controller.mapViewState.currentPosition?.latitude, 1.300100);

        controller.advanceBy(const Duration(seconds: 10));

        expect(controller.state.isAutoPaused, isFalse);
        expect(controller.state.elapsedSeconds, 0);
        expect(controller.state.distanceMeters, greaterThan(0));
        expect(controller.mapViewState.routeSegments, hasLength(2));
        expect(controller.mapViewState.routeSegments.last, hasLength(2));
      },
    );
  });
}
