import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_completion_request_adapter.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/services/pace_graph_data_builder.dart';

void main() {
  group('RunCompletionRequestAdapter', () {
    test('converts local completion payload to backend-shaped request', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-20260614-0700',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 25),
        durationSeconds: 1500,
        distanceMeters: 3200,
        avgPaceSecondsPerKm: 469,
        source: 'local_simulation',
        routePrivacy: 'private',
        activityTitle: 'Sunday Morning Run',
        routeLabel: 'Repository Result Route',
        clientAppVersion: 'm3-test',
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request['clientRunSessionId'], 'local-session-20260614-0700');
      expect(request['startedAt'], '2026-06-14T07:00:00.000Z');
      expect(request['completedAt'], '2026-06-14T07:25:00.000Z');
      expect(request['durationSeconds'], 1500);
      expect(request['activeDurationSeconds'], 1500);
      expect(request['elapsedWallSeconds'], 1500);
      expect(request['pausedDurationSeconds'], 0);
      expect(request['distanceMeters'], 3200);
      expect(request['avgPaceSecondsPerKm'], 469);
      expect(request['source'], 'mobile');
      expect(request['routePrivacy'], 'private');
      expect(request['activityTitle'], 'Sunday Morning Run');
      expect(request['routeLabel'], 'Repository Result Route');
      expect(request['clientAppVersion'], 'm3-test');
    });

    test('includes planned workout identifiers for generated plan runs', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-planned-generated',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 25),
        durationSeconds: 1500,
        distanceMeters: 3200,
        avgPaceSecondsPerKm: 469,
        source: 'local_simulation',
        routePrivacy: 'private',
        planEnrollmentId: 'generated-plan-10k-performance',
        scheduledWorkoutId: 'week-1-tue-controlled-steady-run',
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request['planEnrollmentId'], 'generated-plan-10k-performance');
      expect(request['scheduledWorkoutId'], 'week-1-tue-controlled-steady-run');
    });

    test('omits planned workout identifiers for free runs', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-free-run',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 25),
        durationSeconds: 1500,
        distanceMeters: 3200,
        avgPaceSecondsPerKm: 469,
        source: 'local_simulation',
        routePrivacy: 'private',
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request.keys, isNot(contains('planEnrollmentId')));
      expect(request.keys, isNot(contains('scheduledWorkoutId')));
    });

    test('excludes protected backend-owned and governance fields', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-protected-check',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 25),
        durationSeconds: 1500,
        distanceMeters: 3200,
        avgPaceSecondsPerKm: 469,
        source: 'local_simulation',
        routePrivacy: 'private',
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      const forbiddenFragments = <String>[
        'calorie',
        'xp',
        'streak',
        'level',
        'rank',
        'leaderboard',
        'validation',
        'subscription',
        'userRole',
      ];

      for (final key in request.keys) {
        for (final fragment in forbiddenFragments) {
          expect(
            key.toLowerCase(),
            isNot(contains(fragment.toLowerCase())),
            reason: 'request key $key contains protected fragment $fragment',
          );
        }
      }
    });

    test('formats real run timestamps with backend millisecond precision', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-microsecond-timestamps',
        startedAt: DateTime.utc(2026, 6, 14, 7, 0, 0, 123, 456),
        completedAt: DateTime.utc(2026, 6, 14, 7, 25, 0, 789, 123),
        durationSeconds: 1500,
        distanceMeters: 3200,
        avgPaceSecondsPerKm: 469,
        source: 'local_simulation',
        routePrivacy: 'private',
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request['startedAt'], '2026-06-14T07:00:00.123Z');
      expect(request['completedAt'], '2026-06-14T07:25:00.789Z');
    });

    test('sends explicit paused-run duration fields', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-paused-duration',
        startedAt: DateTime.utc(2026, 6, 14, 9),
        completedAt: DateTime.utc(2026, 6, 14, 10, 5),
        durationSeconds: 3207,
        distanceMeters: 8460,
        avgPaceSecondsPerKm: 379,
        source: 'local_simulation',
        routePrivacy: 'private',
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request['durationSeconds'], 3207);
      expect(request['activeDurationSeconds'], 3207);
      expect(request['elapsedWallSeconds'], 3900);
      expect(request['pausedDurationSeconds'], 693);
    });

    test('includes user confirmation for low-data save requests', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-confirmed-low-data',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 0, 2),
        durationSeconds: 2,
        distanceMeters: 0,
        avgPaceSecondsPerKm: 0,
        source: 'local_simulation',
        routePrivacy: 'private',
        userConfirmedLowDataSave: true,
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request['userConfirmedLowDataSave'], isTrue);
    });

    test('excludes low-data confirmation unless the user saved it', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-raw-low-data',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 0, 2),
        durationSeconds: 2,
        distanceMeters: 0,
        avgPaceSecondsPerKm: 0,
        source: 'local_simulation',
        routePrivacy: 'private',
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request.keys, isNot(contains('userConfirmedLowDataSave')));
    });

    test('excludes local-only pace graph samples from backend request', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-graph-request-boundary',
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

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      const forbiddenKeys = <String>[
        'paceGraphSamples',
        'graphSamples',
        'paceGraph',
        'paceGraphPoints',
        'samples',
      ];

      for (final key in forbiddenKeys) {
        expect(request.keys, isNot(contains(key)));
      }
      expect(request.values.join(' '), isNot(contains('paceGraphSamples')));
      expect(request.values.join(' '), isNot(contains('paceGraph')));
    });

    test('sanitizes pace timing before backend persistence', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-pace-timing-sanitized',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 3),
        durationSeconds: 180,
        distanceMeters: 450,
        avgPaceSecondsPerKm: 400,
        source: 'local_simulation',
        routePrivacy: 'private',
        paceGraphSamples: const [
          PaceGraphSample(
            elapsedSeconds: 60,
            paceSecondsPerKm: 400,
            cumulativeDistanceMeters: 150,
          ),
          PaceGraphSample(
            elapsedSeconds: 300,
            paceSecondsPerKm: 400,
            cumulativeDistanceMeters: 700,
          ),
          PaceGraphSample(
            elapsedSeconds: 120,
            paceSecondsPerKm: 400,
            cumulativeDistanceMeters: 300,
          ),
        ],
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final pace = request['paceAnalysisSeries']! as Map<String, Object?>;

      expect(pace['samples'], [
        {
          'elapsedSeconds': 60,
          'cumulativeDistanceMeters': 150,
          'paceSecondsPerKm': 400,
          'status': 'accepted',
        },
        {
          'elapsedSeconds': 120,
          'cumulativeDistanceMeters': 300,
          'paceSecondsPerKm': 400,
          'status': 'accepted',
        },
      ]);
    });

    test('omits pace analysis when no sample fits the run bounds', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-pace-timing-empty',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 3),
        durationSeconds: 180,
        distanceMeters: 450,
        avgPaceSecondsPerKm: 400,
        source: 'local_simulation',
        routePrivacy: 'private',
        paceGraphSamples: const [
          PaceGraphSample(
            elapsedSeconds: 300,
            paceSecondsPerKm: 400,
            cumulativeDistanceMeters: 700,
          ),
        ],
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request, isNot(contains('paceAnalysisSeries')));
    });

    test('includes cadence analysis samples for backend persistence', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-cadence-request',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 3),
        durationSeconds: 180,
        distanceMeters: 450,
        avgPaceSecondsPerKm: 400,
        source: 'local_simulation',
        routePrivacy: 'private',
        cadenceAnalysisSeries: CadenceAnalysisSeries.phoneMotionEstimated(
          samples: const [
            CadenceAnalysisSample.accepted(elapsedSeconds: 30, cadenceSpm: 95),
            CadenceAnalysisSample.accepted(elapsedSeconds: 90, cadenceSpm: 118),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cadenceSpm: 120,
            ),
          ],
        ),
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final cadence = request['cadenceAnalysisSeries'];

      expect(cadence, isA<Map<String, Object?>>());
      final cadenceMap = cadence! as Map<String, Object?>;
      expect(cadenceMap['source'], 'phoneSensorEstimated');
      expect(cadenceMap['confidence'], 'low');
      expect(cadenceMap['samples'], [
        {'elapsedSeconds': 30, 'cadenceSpm': 95, 'status': 'accepted'},
        {'elapsedSeconds': 90, 'cadenceSpm': 118, 'status': 'accepted'},
        {'elapsedSeconds': 120, 'cadenceSpm': 120, 'status': 'accepted'},
      ]);
    });

    test('sends only valid accepted cadence samples to the backend', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-cadence-accepted-only',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 3),
        durationSeconds: 180,
        distanceMeters: 450,
        avgPaceSecondsPerKm: 400,
        source: 'local_simulation',
        routePrivacy: 'private',
        cadenceAnalysisSeries: CadenceAnalysisSeries.phoneMotionEstimated(
          samples: [
            const CadenceAnalysisSample.accepted(
              elapsedSeconds: 30,
              cadenceSpm: 95,
            ),
            CadenceAnalysisSample.rejected(
              elapsedSeconds: 60,
              cadenceSpm: 80,
              rejectionReason:
                  CadenceAnalysisSampleRejectionReason.outOfRangeCadence,
            ),
            const CadenceAnalysisSample.accepted(
              elapsedSeconds: 90,
              cadenceSpm: 118,
            ),
          ],
        ),
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final cadence = request['cadenceAnalysisSeries']! as Map<String, Object?>;

      expect(cadence['samples'], [
        {'elapsedSeconds': 30, 'cadenceSpm': 95, 'status': 'accepted'},
        {'elapsedSeconds': 90, 'cadenceSpm': 118, 'status': 'accepted'},
      ]);
    });

    test('sanitizes cadence timing before backend persistence', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-cadence-timing-sanitized',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 3),
        durationSeconds: 180,
        distanceMeters: 450,
        avgPaceSecondsPerKm: 400,
        source: 'local_simulation',
        routePrivacy: 'private',
        cadenceAnalysisSeries: CadenceAnalysisSeries.phoneMotionEstimated(
          samples: const [
            CadenceAnalysisSample.accepted(elapsedSeconds: 30, cadenceSpm: 95),
            CadenceAnalysisSample.accepted(elapsedSeconds: 90, cadenceSpm: 118),
            CadenceAnalysisSample.accepted(elapsedSeconds: 90, cadenceSpm: 120),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 240,
              cadenceSpm: 121,
            ),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cadenceSpm: 122,
            ),
          ],
        ),
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final cadence = request['cadenceAnalysisSeries']! as Map<String, Object?>;

      expect(cadence['samples'], [
        {'elapsedSeconds': 30, 'cadenceSpm': 95, 'status': 'accepted'},
        {'elapsedSeconds': 90, 'cadenceSpm': 118, 'status': 'accepted'},
        {'elapsedSeconds': 120, 'cadenceSpm': 122, 'status': 'accepted'},
      ]);
    });

    test('omits cadence analysis when no sample fits the run duration', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-cadence-timing-empty',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 3),
        durationSeconds: 180,
        distanceMeters: 450,
        avgPaceSecondsPerKm: 400,
        source: 'local_simulation',
        routePrivacy: 'private',
        cadenceAnalysisSeries: CadenceAnalysisSeries.phoneMotionEstimated(
          samples: const [
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 181,
              cadenceSpm: 120,
            ),
          ],
        ),
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request, isNot(contains('cadenceAnalysisSeries')));
    });

    test('bounds cadence samples before backend request persistence', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-cadence-request-bounded',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 8),
        durationSeconds: 3600,
        distanceMeters: 6400,
        avgPaceSecondsPerKm: 562,
        source: 'local_simulation',
        routePrivacy: 'private',
        cadenceAnalysisSeries: CadenceAnalysisSeries.phoneMotionEstimated(
          samples: [
            for (var index = 0; index < 900; index += 1)
              CadenceAnalysisSample.accepted(
                elapsedSeconds: index,
                cadenceSpm: 95 + index % 10,
              ),
          ],
        ),
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final cadence = request['cadenceAnalysisSeries']! as Map<String, Object?>;
      final samples = cadence['samples']! as List<Object?>;
      final first = samples.first! as Map<String, Object?>;
      final last = samples.last! as Map<String, Object?>;

      expect(samples, hasLength(720));
      expect(first['elapsedSeconds'], 0);
      expect(last['elapsedSeconds'], 899);
    });

    test('serializes a bounded privacy-safe route preview', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final route = RunRouteSnapshot(
        segments: [
          [
            for (var index = 0; index < 180; index += 1)
              RunLocationSample(
                recordedAt: startedAt.add(Duration(seconds: index)),
                latitude: 1.300600 + index / 100000,
                longitude: 103.800600,
                altitudeMeters: index == 0 ? 12.5 : null,
                horizontalAccuracyMeters: index == 0 ? 4 : null,
                speedMetersPerSecond: index == 0 ? 2 : null,
              ),
          ],
          [
            for (var index = 0; index < 180; index += 1)
              RunLocationSample(
                recordedAt: startedAt.add(Duration(seconds: 180 + index)),
                latitude: 1.400600 + index / 100000,
                longitude: 103.800600,
              ),
          ],
        ],
        lastKnownLocation: RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 360)),
          latitude: 1.403600,
          longitude: 103.800600,
        ),
      );
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-route-request',
        startedAt: startedAt,
        completedAt: startedAt.add(const Duration(minutes: 6)),
        durationSeconds: 360,
        distanceMeters: 860,
        avgPaceSecondsPerKm: 419,
        source: 'local_simulation',
        routePrivacy: 'private',
        routeSnapshot: route,
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final routeMap = request['routePreview']! as Map<String, Object?>;
      final segments = routeMap['segments']! as List<Object?>;
      final pointCount = segments.fold<int>(
        0,
        (total, rawSegment) =>
            total +
            ((rawSegment! as Map<String, Object?>)['points']! as List<Object?>)
                .length,
      );

      expect(segments, hasLength(2));
      expect(pointCount, lessThanOrEqualTo(256));
      expect(request.keys, isNot(contains('routeSnapshot')));
      final firstPoints =
          (segments.first! as Map<String, Object?>)['points']! as List<Object?>;
      final lastPoints =
          (segments.last! as Map<String, Object?>)['points']! as List<Object?>;
      final first = firstPoints.first! as Map<String, Object?>;
      final last = lastPoints.last! as Map<String, Object?>;
      expect(first['latitude'], closeTo(1.3006, 0.0000001));
      expect(first['longitude'], closeTo(103.8006, 0.0000001));
      expect(last['latitude'], closeTo(1.40239, 0.0000001));
      expect(last['longitude'], closeTo(103.8006, 0.0000001));
      expect(first.keys, isNot(contains('recordedAt')));
      expect(first.keys, isNot(contains('altitudeMeters')));
      expect(first.keys, isNot(contains('horizontalAccuracyMeters')));
      expect(first.keys, isNot(contains('speedMetersPerSecond')));
      const forbiddenRouteKeys = <String>[
        'recordedAt',
        'altitudeMeters',
        'horizontalAccuracyMeters',
        'speedMetersPerSecond',
      ];
      for (final rawSegment in segments) {
        final points =
            (rawSegment! as Map<String, Object?>)['points']! as List<Object?>;
        for (final rawPoint in points) {
          final point = rawPoint! as Map<String, Object?>;
          for (final key in forbiddenRouteKeys) {
            expect(point.keys, isNot(contains(key)));
          }
        }
      }
    });

    test('keeps successive route preview points distinct at running scale', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      // ~3.3 m apart, which is closer than any two points a 256-point preview
      // of a real run holds. Rounding to three decimals (~111 m) collapsed runs
      // like this onto one grid cell and drew them as a staircase.
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-route-preview-precision',
        startedAt: startedAt,
        completedAt: startedAt.add(const Duration(seconds: 30)),
        durationSeconds: 30,
        distanceMeters: 100,
        avgPaceSecondsPerKm: 300,
        source: 'local_simulation',
        routePrivacy: 'private',
        routeSnapshot: RunRouteSnapshot(
          segments: [
            [
              for (var index = 0; index < 30; index += 1)
                RunLocationSample(
                  recordedAt: startedAt.add(Duration(seconds: index)),
                  latitude: 1.30060 + index * 0.00003,
                  longitude: 103.80060 + index * 0.00003,
                ),
            ],
          ],
        ),
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final preview = request['routePreview']! as Map<String, Object?>;
      final points =
          ((preview['segments']! as List<Object?>).single
                  as Map<String, Object?>)['points']!
              as List<Object?>;
      final latitudes = [
        for (final rawPoint in points)
          (rawPoint! as Map<String, Object?>)['latitude']! as double,
      ];

      expect(latitudes, hasLength(30));
      expect(latitudes.toSet(), hasLength(30));
      expect(latitudes.first, closeTo(1.3006, 0.0000001));
      expect(latitudes.last, closeTo(1.30147, 0.0000001));
      for (final latitude in latitudes) {
        expect((latitude * 100000).round() / 100000, latitude);
      }
    });

    test('bounds route preview segment count independently of point count', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-route-preview-segments',
        startedAt: startedAt,
        completedAt: startedAt.add(const Duration(minutes: 2)),
        durationSeconds: 120,
        distanceMeters: 240,
        avgPaceSecondsPerKm: 500,
        source: 'local_simulation',
        routePrivacy: 'private',
        routeSnapshot: RunRouteSnapshot(
          segments: [
            for (var index = 0; index < 65; index += 1)
              [
                RunLocationSample(
                  recordedAt: startedAt.add(Duration(seconds: index)),
                  latitude: 1.3001 + index / 1000,
                  longitude: 103.8001 + index / 1000,
                ),
              ],
          ],
        ),
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final preview = request['routePreview']! as Map<String, Object?>;
      final segments = preview['segments']! as List<Object?>;

      expect(segments, hasLength(64));
      expect(
        segments.fold<int>(
          0,
          (total, rawSegment) =>
              total +
              ((rawSegment! as Map<String, Object?>)['points']!
                      as List<Object?>)
                  .length,
        ),
        lessThanOrEqualTo(256),
      );
    });

    test('preserves endpoints for every uneven route segment', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-route-preview-endpoints',
        startedAt: startedAt,
        completedAt: startedAt.add(const Duration(minutes: 5)),
        durationSeconds: 300,
        distanceMeters: 600,
        avgPaceSecondsPerKm: 500,
        source: 'local_simulation',
        routePrivacy: 'private',
        routeSnapshot: RunRouteSnapshot(
          segments: [
            [
              for (var index = 0; index < 255; index += 1)
                RunLocationSample(
                  recordedAt: startedAt.add(Duration(seconds: index)),
                  latitude: 1.3001 + index / 1000,
                  longitude: 103.8001,
                ),
            ],
            [
              RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 255)),
                latitude: 2.0001,
                longitude: 103.8001,
              ),
              RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 256)),
                latitude: 2.0011,
                longitude: 103.8001,
              ),
            ],
          ],
        ),
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final preview = request['routePreview']! as Map<String, Object?>;
      final segments = preview['segments']! as List<Object?>;
      final firstPoints =
          (segments.first! as Map<String, Object?>)['points']! as List<Object?>;
      final secondPoints =
          (segments.last! as Map<String, Object?>)['points']! as List<Object?>;

      expect(firstPoints, hasLength(254));
      expect(secondPoints, hasLength(2));
      expect(
        (firstPoints.first! as Map<String, Object?>)['latitude'],
        closeTo(1.3001, 0.0000001),
      );
      expect(
        (firstPoints.last! as Map<String, Object?>)['latitude'],
        closeTo(1.5541, 0.0000001),
      );
      expect(
        (secondPoints.first! as Map<String, Object?>)['latitude'],
        closeTo(2.0001, 0.0000001),
      );
      expect(
        (secondPoints.last! as Map<String, Object?>)['latitude'],
        closeTo(2.0011, 0.0000001),
      );
    });

    test('serializes bounded pace and elevation analysis series', () {
      final paceSamples = [
        for (var index = 0; index < 400; index += 1)
          PaceGraphSample(
            elapsedSeconds: index,
            paceSecondsPerKm: 400,
            cumulativeDistanceMeters: index * 3,
          ),
      ];
      final elevationSamples = [
        for (var index = 0; index < 400; index += 1)
          ElevationAnalysisSample(
            distanceKm: index / 100,
            elevationMeters: 10 + index / 10,
          ),
      ];
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-analysis-request',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 8),
        durationSeconds: 3600,
        distanceMeters: 12000,
        avgPaceSecondsPerKm: 300,
        source: 'local_simulation',
        routePrivacy: 'private',
        paceGraphSamples: paceSamples,
        elevationAnalysisSeries: ElevationAnalysisSeries.localAccepted(
          samples: elevationSamples,
        ),
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);
      final pace = request['paceAnalysisSeries']! as Map<String, Object?>;
      final paceSerialized = pace['samples']! as List<Object?>;
      final elevation = request['elevationSeries']! as Map<String, Object?>;
      final elevationSerialized = elevation['samples']! as List<Object?>;

      expect(pace['source'], 'localAccepted');
      expect(pace['confidence'], 'derived');
      expect(paceSerialized, hasLength(360));
      expect(
        (paceSerialized.first! as Map<String, Object?>)['elapsedSeconds'],
        0,
      );
      expect(
        (paceSerialized.last! as Map<String, Object?>)['elapsedSeconds'],
        399,
      );
      expect(elevation['source'], 'runiacLocalAccepted');
      expect(elevation['confidence'], 'medium');
      expect(elevationSerialized, hasLength(360));
      expect(
        (elevationSerialized.first! as Map<String, Object?>)['distanceKm'],
        0,
      );
      expect(
        (elevationSerialized.last! as Map<String, Object?>)['distanceKm'],
        closeTo(3.99, 0.0001),
      );
    });
  });
}
