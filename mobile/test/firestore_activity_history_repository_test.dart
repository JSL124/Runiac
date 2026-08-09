import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/pace_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/run_feed_publish_source.dart';
import 'package:runiac_app/features/run/domain/services/completed_run_title_formatter.dart';
import 'package:runiac_app/features/you/data/firestore_activity_history_repository.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  group('FirestoreActivityHistoryRepository', () {
    test(
      'recomputes an incorrectly persisted generated title in local time',
      () async {
        final endedAt = DateTime.utc(2026, 7, 8, 13);
        final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
        final repository = FirestoreActivityHistoryRepository(
          authRepository: authRepository,
          reader: _FakeActivityHistorySummaryDocumentReader(
            documents: <ActivityHistorySummaryDocument>[
              _runSummaryDocument(
                id: 'summary-wednesday-night',
                ownerUid: 'test-auth-user-1',
                endedAt: endedAt,
                distanceMeters: 6470,
                durationSeconds: 2738,
                averagePaceSecondsPerKm: 423,
                title: 'Wednesday Afternoon Run',
                routeLabel: 'Runiac GPS',
              ),
            ],
          ),
        );

        final history = await repository.loadActivityHistory();

        expect(
          history.recentRuns.single.title,
          const CompletedRunTitleFormatter().format(completedAt: endedAt),
        );
      },
    );

    test('maps owner run summaries into grouped history', () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final reader = _FakeActivityHistorySummaryDocumentReader(
        documents: <ActivityHistorySummaryDocument>[
          _runSummaryDocument(
            id: 'summary-june-2',
            ownerUid: 'test-auth-user-1',
            clientRunSessionId: 'client-session-june-2',
            endedAt: DateTime(2026, 6, 14, 7, 25),
            distanceMeters: 3200,
            durationSeconds: 1500,
            averagePaceSecondsPerKm: 469,
            title: 'Authenticated Recovery Run',
            routeLabel: 'Repository Result Route',
          ),
          _runSummaryDocument(
            id: 'summary-june-1',
            ownerUid: 'test-auth-user-1',
            endedAt: DateTime(2026, 6, 12, 6, 40),
            distanceMeters: 2400,
            durationSeconds: 1260,
            averagePaceSecondsPerKm: 525,
            routeLabel: null,
          ),
          _runSummaryDocument(
            id: 'summary-may-1',
            ownerUid: 'test-auth-user-1',
            endedAt: DateTime(2026, 5, 31, 8, 5),
            distanceMeters: 5000,
            durationSeconds: 1800,
            averagePaceSecondsPerKm: 360,
            routeLabel: 'Park loop',
          ),
        ],
      );
      final repository = FirestoreActivityHistoryRepository(
        authRepository: authRepository,
        reader: reader,
      );

      final history = await repository.loadActivityHistory();

      expect(reader.readOwnerUids, <String>['test-auth-user-1']);
      expect(reader.readLimits, <int>[30, 30]);
      expect(history.recentRuns.map((run) => run.activityId), <String>[
        'summary-june-2',
        'summary-june-1',
        'summary-may-1',
      ]);
      expect(
        history.recentRuns.first.clientRunSessionId,
        'client-session-june-2',
      );
      expect(history.recentRuns.first.title, 'Authenticated Recovery Run');
      expect(history.recentRuns[1].title, 'Friday Morning Run');
      expect(history.recentRuns[2].title, 'Sunday Morning Run');
      expect(history.recentRuns.first.completedAtLabel, '14/6/26');
      expect(history.recentRuns.first.timeLabel, '7:25 AM');
      expect(history.recentRuns.first.distanceLabel, '3.20 km');
      expect(history.recentRuns.first.distanceMeters, 3200);
      expect(history.recentRuns.first.durationLabel, '25:00');
      expect(history.recentRuns.first.paceLabel, '7’49”');
      expect(
        history.recentRuns.first.routeNameLabel,
        'Repository Result Route',
      );
      expect(history.months.map((month) => month.label), <String>[
        'June 2026',
        'May 2026',
      ]);
      expect(
        history.months.first.activities.map((run) => run.activityId),
        <String>['summary-june-2', 'summary-june-1'],
      );
    });

    test('maps owner activities into progress-ready grouped history', () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final reader = _FakeActivityHistorySummaryDocumentReader(
        activityDocuments: <ActivityHistorySummaryDocument>[
          _activityDocument(
            id: 'activity-june-2',
            ownerUid: 'test-auth-user-1',
            clientRunSessionId: 'client-session-activity-june-2',
            completedAt: DateTime(2026, 6, 30, 7, 25),
            distanceMeters: 4250,
            durationSeconds: 1800,
            averagePaceSecondsPerKm: 424,
            title: 'Activity Table Recovery Run',
            routeLabel: 'Activities Route',
          ),
          _activityDocument(
            id: 'activity-june-1',
            ownerUid: 'test-auth-user-1',
            endedAt: DateTime(2026, 6, 2, 6, 40),
            distanceMeters: 3500,
            durationSeconds: 1620,
            averagePaceSecondsPerKm: 463,
          ),
        ],
      );
      final repository = FirestoreActivityHistoryRepository(
        authRepository: authRepository,
        reader: reader,
      );

      final history = await repository.loadActivityHistory();

      expect(reader.readOwnerUids, <String>['test-auth-user-1']);
      expect(reader.readActivityOwnerUids, <String>['test-auth-user-1']);
      expect(history.recentRuns.map((run) => run.activityId), <String>[
        'activity-june-2',
        'activity-june-1',
      ]);
      expect(
        history.recentRuns.first.clientRunSessionId,
        'client-session-activity-june-2',
      );
      expect(history.recentRuns.first.title, 'Activity Table Recovery Run');
      expect(history.recentRuns.first.completedAtLabel, '30/6/26');
      expect(history.recentRuns.first.timeLabel, '7:25 AM');
      expect(history.recentRuns.first.distanceLabel, '4.25 km');
      expect(history.recentRuns.first.distanceMeters, 4250);
      expect(history.recentRuns.first.routeNameLabel, 'Activities Route');
      expect(history.months.map((month) => month.label), <String>['June 2026']);
      expect(
        history.months.single.activities.map((run) => run.distanceMeters),
        <int>[4250, 3500],
      );
    });

    test(
      'does not double count duplicate summary and activity documents',
      () async {
        final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
        final repository = FirestoreActivityHistoryRepository(
          authRepository: authRepository,
          reader: _FakeActivityHistorySummaryDocumentReader(
            documents: <ActivityHistorySummaryDocument>[
              _runSummaryDocument(
                id: 'summary-duplicate',
                ownerUid: 'test-auth-user-1',
                clientRunSessionId: 'client-session-duplicate',
                endedAt: DateTime(2026, 6, 30, 7, 25),
                distanceMeters: 4250,
                title: 'Summary Wins',
              ),
            ],
            activityDocuments: <ActivityHistorySummaryDocument>[
              _activityDocument(
                id: 'activity-duplicate',
                ownerUid: 'test-auth-user-1',
                clientRunSessionId: 'client-session-duplicate',
                completedAt: DateTime(2026, 6, 30, 7, 25),
                distanceMeters: 4250,
                title: 'Activity Duplicate',
              ),
              _activityDocument(
                id: 'activity-unique',
                ownerUid: 'test-auth-user-1',
                endedAt: DateTime(2026, 6, 29, 7, 25),
                distanceMeters: 3000,
                title: 'Unique Activity',
              ),
            ],
          ),
        );

        final history = await repository.loadActivityHistory();

        expect(history.months.single.activities, hasLength(2));
        expect(history.months.single.activities.map((run) => run.title), [
          'Summary Wins',
          'Unique Activity',
        ]);
        expect(
          history.months.single.activities.fold<int>(
            0,
            (total, activity) => total + activity.distanceMeters,
          ),
          7250,
        );
      },
    );

    test('validated activity history row is feed publishable', () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final repository = FirestoreActivityHistoryRepository(
        authRepository: authRepository,
        reader: _FakeActivityHistorySummaryDocumentReader(
          documents: <ActivityHistorySummaryDocument>[
            _runSummaryDocument(
              id: 'summary-publishable',
              activityId: 'activity-publishable',
              ownerUid: 'test-auth-user-1',
              clientRunSessionId: 'client-session-publishable',
              endedAt: DateTime(2026, 6, 30, 7, 25),
              title: 'Summary Display Title',
            ),
          ],
          activityDocuments: <ActivityHistorySummaryDocument>[
            _activityDocument(
              id: 'activity-publishable',
              ownerUid: 'test-auth-user-1',
              clientRunSessionId: 'client-session-publishable',
              completedAt: DateTime(2026, 6, 30, 7, 25),
              status: 'validated',
              validationStatus: 'validated',
              title: 'Activity Backend Title',
            ),
          ],
        ),
      );

      final history = await repository.loadActivityHistory();
      final run = history.recentRuns.single;

      expect(run.title, 'Summary Display Title');
      expect(run.feedPublishSource.isPublishable, isTrue);
      expect(run.feedPublishSource.activityId, 'activity-publishable');
      expect(run.feedPublishSource.cacheIdentity, 'client-session-publishable');
    });

    test(
      'pending unvalidated orphan and insufficient history rows are not feed publishable',
      () async {
        final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
        final repository = FirestoreActivityHistoryRepository(
          authRepository: authRepository,
          reader: _FakeActivityHistorySummaryDocumentReader(
            documents: <ActivityHistorySummaryDocument>[
              _runSummaryDocument(
                id: 'orphan-summary',
                ownerUid: 'test-auth-user-1',
                endedAt: DateTime(2026, 6, 30, 7, 25),
              ),
            ],
            activityDocuments: <ActivityHistorySummaryDocument>[
              _activityDocument(
                id: 'pending-activity',
                ownerUid: 'test-auth-user-1',
                completedAt: DateTime(2026, 6, 29, 7, 25),
                status: 'pending',
                validationStatus: 'pending',
              ),
              _activityDocument(
                id: 'unvalidated-activity',
                ownerUid: 'test-auth-user-1',
                completedAt: DateTime(2026, 6, 28, 7, 25),
                status: 'validated',
                validationStatus: 'rejected',
              ),
              _activityDocument(
                id: 'insufficient-activity',
                ownerUid: 'test-auth-user-1',
                completedAt: DateTime(2026, 6, 27, 7, 25),
                status: 'validated',
                validationStatus: 'validated',
                distanceMeters: 0,
              ),
              _activityDocument(
                id: 'local-activity',
                ownerUid: 'test-auth-user-1',
                completedAt: DateTime(2026, 6, 26, 7, 25),
                status: 'validated',
                validationStatus: 'validated',
                activityId: 'local-client-session',
              ),
            ],
          ),
        );

        final history = await repository.loadActivityHistory();

        expect(
          history.months.single.activities.map(
            (run) => run.feedPublishSource.isPublishable,
          ),
          everyElement(isFalse),
        );
        expect(
          history.months.single.activities.map(
            (run) => run.feedPublishSource.disabledReason,
          ),
          containsAll([
            FeedPublishDisabledReason.orphanSummary,
            FeedPublishDisabledReason.notValidated,
            FeedPublishDisabledReason.insufficientData,
            FeedPublishDisabledReason.localOnly,
          ]),
        );
      },
    );

    test('does not double count fallback activity identities', () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final repository = FirestoreActivityHistoryRepository(
        authRepository: authRepository,
        reader: _FakeActivityHistorySummaryDocumentReader(
          documents: <ActivityHistorySummaryDocument>[
            _runSummaryDocument(
              id: 'summary-activity-id',
              activityId: 'activity-id-duplicate',
              ownerUid: 'test-auth-user-1',
              endedAt: DateTime(2026, 6, 30, 7, 25),
              distanceMeters: 4250,
              title: 'Summary Activity Id Wins',
            ),
          ],
          activityDocuments: <ActivityHistorySummaryDocument>[
            _activityDocument(
              id: 'activity-doc-activity-id',
              activityId: 'activity-id-duplicate',
              ownerUid: 'test-auth-user-1',
              completedAt: DateTime(2026, 6, 30, 7, 25),
              distanceMeters: 4250,
              title: 'Activity Id Duplicate',
            ),
            _activityDocument(
              id: 'same-document-id',
              ownerUid: 'test-auth-user-1',
              completedAt: DateTime(2026, 6, 29, 7, 25),
              distanceMeters: 3000,
              title: 'Document Id Wins',
            ),
            _activityDocument(
              id: 'same-document-id',
              ownerUid: 'test-auth-user-1',
              completedAt: DateTime(2026, 6, 29, 7, 25),
              distanceMeters: 9999,
              title: 'Document Id Duplicate',
            ),
          ],
        ),
      );

      final history = await repository.loadActivityHistory();

      expect(history.months.single.activities.map((run) => run.title), [
        'Summary Activity Id Wins',
        'Document Id Wins',
      ]);
      expect(
        history.months.single.activities.fold<int>(
          0,
          (total, activity) => total + activity.distanceMeters,
        ),
        7250,
      );
    });

    test('uses static fallback when no user is signed in', () async {
      final reader = _FakeActivityHistorySummaryDocumentReader();
      final repository = FirestoreActivityHistoryRepository(
        authRepository: FakeRuniacAuthRepository(),
        reader: reader,
      );

      final history = await repository.loadActivityHistory();

      expect(reader.readOwnerUids, isEmpty);
      expect(history.recentRuns, isNotEmpty);
      expect(history.months, isNotEmpty);
    });

    test('ignores wrong-owner document', () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final repository = FirestoreActivityHistoryRepository(
        authRepository: authRepository,
        reader: _FakeActivityHistorySummaryDocumentReader(
          documents: <ActivityHistorySummaryDocument>[
            _runSummaryDocument(
              id: 'owner-summary',
              ownerUid: 'test-auth-user-1',
              endedAt: DateTime(2026, 6, 14, 7, 25),
            ),
            _runSummaryDocument(
              id: 'wrong-owner-summary',
              ownerUid: 'other-user',
              endedAt: DateTime(2026, 6, 13, 7, 25),
            ),
          ],
        ),
      );

      final history = await repository.loadActivityHistory();

      expect(history.recentRuns.map((run) => run.activityId), <String>[
        'owner-summary',
      ]);
    });

    test(
      'limits recentRuns to three while months keeps grouped result',
      () async {
        final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
        final repository = FirestoreActivityHistoryRepository(
          authRepository: authRepository,
          reader: _FakeActivityHistorySummaryDocumentReader(
            documents: <ActivityHistorySummaryDocument>[
              _runSummaryDocument(
                id: 'summary-4',
                ownerUid: 'test-auth-user-1',
                endedAt: DateTime(2026, 6, 14, 7, 25),
              ),
              _runSummaryDocument(
                id: 'summary-3',
                ownerUid: 'test-auth-user-1',
                endedAt: DateTime(2026, 6, 13, 7, 25),
              ),
              _runSummaryDocument(
                id: 'summary-2',
                ownerUid: 'test-auth-user-1',
                endedAt: DateTime(2026, 6, 12, 7, 25),
              ),
              _runSummaryDocument(
                id: 'summary-1',
                ownerUid: 'test-auth-user-1',
                endedAt: DateTime(2026, 6, 11, 7, 25),
              ),
            ],
          ),
        );

        final history = await repository.loadActivityHistory();

        expect(history.recentRuns.map((run) => run.activityId), <String>[
          'summary-4',
          'summary-3',
          'summary-2',
        ]);
        expect(history.months, hasLength(1));
        expect(
          history.months.single.activities.map((run) => run.activityId),
          <String>['summary-4', 'summary-3', 'summary-2', 'summary-1'],
        );
      },
    );

    test('skips malformed docs', () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final repository = FirestoreActivityHistoryRepository(
        authRepository: authRepository,
        reader: _FakeActivityHistorySummaryDocumentReader(
          documents: <ActivityHistorySummaryDocument>[
            const ActivityHistorySummaryDocument(
              id: 'malformed-summary',
              data: <String, Object?>{
                'ownerUid': 'test-auth-user-1',
                'endedAt': 'not-a-date',
                'distanceMeters': 3200,
                'durationSeconds': 1500,
                'averagePaceSecondsPerKm': 469,
              },
            ),
            _runSummaryDocument(
              id: 'valid-summary',
              ownerUid: 'test-auth-user-1',
              endedAt: DateTime(2026, 6, 14, 7, 25),
            ),
          ],
        ),
      );

      final history = await repository.loadActivityHistory();

      expect(history.recentRuns.map((run) => run.activityId), <String>[
        'valid-summary',
      ]);
    });

    test('maps persisted cadence analysis series from summary docs', () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final repository = FirestoreActivityHistoryRepository(
        authRepository: authRepository,
        reader: _FakeActivityHistorySummaryDocumentReader(
          documents: <ActivityHistorySummaryDocument>[
            _runSummaryDocument(
              id: 'cadence-summary',
              ownerUid: 'test-auth-user-1',
              endedAt: DateTime(2026, 6, 14, 7, 25),
              cadenceAnalysisSeries: const <String, Object?>{
                'source': 'phoneSensorEstimated',
                'confidence': 'low',
                'samples': <Object?>[
                  {
                    'elapsedSeconds': 30,
                    'cadenceSpm': 95,
                    'status': 'accepted',
                  },
                  {
                    'elapsedSeconds': 90,
                    'cadenceSpm': 118,
                    'status': 'accepted',
                  },
                  {
                    'elapsedSeconds': 120,
                    'cadenceSpm': 120,
                    'status': 'accepted',
                  },
                ],
              },
            ),
          ],
        ),
      );

      final history = await repository.loadActivityHistory();
      final cadence = history.recentRuns.single.cadenceAnalysisSeries;

      expect(cadence?.source, CadenceAnalysisSource.phoneSensorEstimated);
      expect(cadence?.confidence, CadenceAnalysisConfidence.low);
      expect(cadence?.validAcceptedSamples, hasLength(3));
    });

    test(
      'hydrates authenticated masked route preview pace and elevation snapshots',
      () async {
        // Given: the signed-in owner's run summary contains the backend's
        // privacy-masked rich contract after local app storage is empty.
        final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
        final repository = FirestoreActivityHistoryRepository(
          authRepository: authRepository,
          reader: _FakeActivityHistorySummaryDocumentReader(
            documents: <ActivityHistorySummaryDocument>[
              _runSummaryDocument(
                id: 'rich-summary',
                ownerUid: 'test-auth-user-1',
                endedAt: DateTime.utc(2026, 6, 14, 7, 25),
                routePreview: const <String, Object?>{
                  'segments': <Object?>[
                    <String, Object?>{
                      'points': <Object?>[
                        <String, Object?>{
                          'latitude': 1.005,
                          'longitude': 103.801,
                        },
                        <String, Object?>{
                          'latitude': 1.302,
                          'longitude': 103.802,
                        },
                      ],
                    },
                  ],
                },
                paceAnalysisSeries: const <String, Object?>{
                  'source': 'localAccepted',
                  'confidence': 'derived',
                  'samples': <Object?>[
                    <String, Object?>{
                      'elapsedSeconds': 30,
                      'cumulativeDistanceMeters': 100.0,
                      'paceSecondsPerKm': 420,
                      'status': 'accepted',
                    },
                    <String, Object?>{
                      'elapsedSeconds': 60,
                      'cumulativeDistanceMeters': 220.0,
                      'paceSecondsPerKm': 410,
                      'status': 'accepted',
                    },
                    <String, Object?>{
                      'elapsedSeconds': 90,
                      'cumulativeDistanceMeters': 350.0,
                      'paceSecondsPerKm': 400,
                      'status': 'accepted',
                    },
                  ],
                },
                elevationSeries: const <String, Object?>{
                  'source': 'runiacLocalAccepted',
                  'confidence': 'medium',
                  'samples': <Object?>[
                    <String, Object?>{
                      'distanceKm': 0.0,
                      'elevationMeters': 10.5,
                    },
                    <String, Object?>{
                      'distanceKm': 0.2,
                      'elevationMeters': 12.0,
                    },
                  ],
                },
              ),
            ],
          ),
        );

        // When: Activity History hydrates from Firestore without a local
        // completion result or local pending-run store.
        final history = await repository.loadActivityHistory();
        final item = history.recentRuns.single;
        final summary = item.summarySnapshot;

        // Then: the typed snapshot retains all rich fields and is explicitly
        // trusted for owner-scoped persisted-preview thumbnail generation.
        expect(summary, isNotNull);
        expect(summary!.route.segments.single, hasLength(2));
        expect(
          summary.route.segments.single.first.recordedAt,
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
        expect(
          summary.route.segments.single.last.recordedAt,
          DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        );
        expect(summary.route.segments.single.first.altitudeMeters, isNull);
        expect(
          summary.route.segments.single.first.latitude,
          closeTo(1.005, 1e-9),
        );
        expect(summary.route.lastKnownLocation?.latitude, closeTo(1.302, 1e-9));
        expect(
          summary.route.lastKnownLocation?.longitude,
          closeTo(103.802, 1e-9),
        );
        expect(
          summary.paceAnalysisSeries?.source,
          PaceAnalysisSource.localAccepted,
        );
        expect(summary.paceAnalysisSeries?.validAcceptedSamples, hasLength(3));
        expect(
          summary.elevationSeries.source,
          ElevationAnalysisSource.runiacLocalAccepted,
        );
        expect(summary.elevationSeries.validSamples, hasLength(2));
        expect(item.isTrustedPersistedRoutePreview, isTrue);
      },
    );

    test(
      'reopened summary renders calories and the pace graph from the '
      'persisted series',
      () async {
        // Given: a signed-in owner's run summary carrying a complete pace
        // analysis series, i.e. a real run reopened from Activity History
        // rather than displayed straight after completion.
        final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
        final repository = FirestoreActivityHistoryRepository(
          authRepository: authRepository,
          reader: _FakeActivityHistorySummaryDocumentReader(
            documents: <ActivityHistorySummaryDocument>[
              _runSummaryDocument(
                id: 'graphable-summary',
                ownerUid: 'test-auth-user-1',
                endedAt: DateTime.utc(2026, 7, 24, 23, 24),
                paceAnalysisSeries: const <String, Object?>{
                  'source': 'localAccepted',
                  'confidence': 'derived',
                  'samples': <Object?>[
                    <String, Object?>{
                      'elapsedSeconds': 300,
                      'cumulativeDistanceMeters': 640.0,
                      'paceSecondsPerKm': 469,
                      'status': 'accepted',
                    },
                    <String, Object?>{
                      'elapsedSeconds': 600,
                      'cumulativeDistanceMeters': 1280.0,
                      'paceSecondsPerKm': 455,
                      'status': 'accepted',
                    },
                    <String, Object?>{
                      'elapsedSeconds': 900,
                      'cumulativeDistanceMeters': 1980.0,
                      'paceSecondsPerKm': 430,
                      'status': 'accepted',
                    },
                    <String, Object?>{
                      'elapsedSeconds': 1200,
                      'cumulativeDistanceMeters': 2600.0,
                      'paceSecondsPerKm': 480,
                      'status': 'accepted',
                    },
                  ],
                },
              ),
            ],
          ),
        );

        // When: Activity History hydrates the run from Firestore.
        final summary =
            (await repository.loadActivityHistory()).recentRuns.single
                .summarySnapshot;

        // Then: the summary screen has a renderable Pace Over Time graph
        // instead of the low-data guard, and shows the estimated calories the
        // scalar mapper already computes rather than a hardcoded em-dash.
        expect(summary, isNotNull);
        expect(summary!.paceGraph.isAvailable, isTrue);
        expect(summary.paceGraph.points, isNotEmpty);
        expect(summary.calories, isNot('--'));
        expect(int.parse(summary.calories), greaterThan(0));
      },
    );

    test('reopened summary without a persisted series keeps the pace guard', () async {
      // Given: an older run summary that predates pace-series persistence.
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final repository = FirestoreActivityHistoryRepository(
        authRepository: authRepository,
        reader: _FakeActivityHistorySummaryDocumentReader(
          documents: <ActivityHistorySummaryDocument>[
            _runSummaryDocument(
              id: 'seriesless-summary',
              ownerUid: 'test-auth-user-1',
              endedAt: DateTime.utc(2026, 7, 20, 22, 4),
            ),
          ],
        ),
      );

      // When: Activity History hydrates it.
      final summary =
          (await repository.loadActivityHistory()).recentRuns.single
              .summarySnapshot;

      // Then: the graph stays unavailable so the guard still explains the gap,
      // while calories remain derivable from the scalar fields.
      expect(summary, isNotNull);
      expect(summary!.paceGraph.isAvailable, isFalse);
      expect(summary.calories, isNot('--'));
    });

    test('rejects raw fields and unquantized persisted route previews', () async {
      // Given: raw route geometry, non-quantized coordinates, and masked
      // previews carrying forbidden timestamp/altitude fields.
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final invalidRoutes = <String, Map<String, Object?>>{
        'raw-route-snapshot': const <String, Object?>{
          'routeSnapshot': <String, Object?>{
            'segments': <Object?>[
              <String, Object?>{
                'points': <Object?>[
                  <String, Object?>{
                    'recordedAt': '2026-06-14T07:25:00.000Z',
                    'latitude': 1.301,
                    'longitude': 103.801,
                    'altitudeMeters': 12.0,
                  },
                ],
              },
            ],
          },
        },
        'unquantized-preview': const <String, Object?>{
          'routePreview': <String, Object?>{
            'segments': <Object?>[
              <String, Object?>{
                'points': <Object?>[
                  <String, Object?>{'latitude': 1.3014, 'longitude': 103.801},
                ],
              },
            ],
          },
        },
        'timestamp-preview': const <String, Object?>{
          'routePreview': <String, Object?>{
            'segments': <Object?>[
              <String, Object?>{
                'points': <Object?>[
                  <String, Object?>{
                    'latitude': 1.301,
                    'longitude': 103.801,
                    'recordedAt': '2026-06-14T07:25:00.000Z',
                  },
                ],
              },
            ],
          },
        },
        'altitude-preview': const <String, Object?>{
          'routePreview': <String, Object?>{
            'segments': <Object?>[
              <String, Object?>{
                'points': <Object?>[
                  <String, Object?>{
                    'latitude': 1.301,
                    'longitude': 103.801,
                    'altitudeMeters': 12.0,
                  },
                ],
              },
            ],
          },
        },
      };

      for (final invalidRoute in invalidRoutes.entries) {
        final scalarDocument = _runSummaryDocument(
          id: invalidRoute.key,
          ownerUid: 'test-auth-user-1',
          endedAt: DateTime.utc(2026, 6, 14, 7, 25),
        );
        final repository = FirestoreActivityHistoryRepository(
          authRepository: authRepository,
          reader: _FakeActivityHistorySummaryDocumentReader(
            documents: <ActivityHistorySummaryDocument>[
              ActivityHistorySummaryDocument(
                id: scalarDocument.id,
                data: <String, Object?>{
                  ...scalarDocument.data,
                  ...invalidRoute.value,
                },
              ),
            ],
          ),
        );

        // When: the untrusted route boundary is parsed.
        final item = (await repository.loadActivityHistory()).recentRuns.single;

        // Then: scalar history survives, but no raw/unquantized route can reach
        // the painter, Mapbox camera, or persisted-preview trust boundary.
        expect(
          item.summarySnapshot?.route.hasLocation,
          isFalse,
          reason: invalidRoute.key,
        );
        expect(
          item.isTrustedPersistedRoutePreview,
          isFalse,
          reason: invalidRoute.key,
        );
      }
    });

    test(
      'rejects sensitive history when authenticated owner changes mid-load',
      () async {
        // Given: owner A starts a delayed Firestore summary read containing a
        // privacy-masked location preview.
        final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
        final reader = _DelayedActivityHistorySummaryDocumentReader();
        final repository = FirestoreActivityHistoryRepository(
          authRepository: authRepository,
          reader: reader,
        );
        final load = repository.loadActivityHistory();
        await reader.summaryReadStarted.future;

        // When: authentication changes to owner B before owner A's query returns.
        authRepository.emitSignedIn(uid: 'test-auth-user-2');
        reader.summaryDocuments.complete(<ActivityHistorySummaryDocument>[
          _runSummaryDocument(
            id: 'stale-owner-route',
            ownerUid: 'test-auth-user-1',
            endedAt: DateTime.utc(2026, 6, 14, 7, 25),
            routePreview: const <String, Object?>{
              'segments': <Object?>[
                <String, Object?>{
                  'points': <Object?>[
                    <String, Object?>{'latitude': 1.301, 'longitude': 103.801},
                  ],
                },
              ],
            },
          ),
        ]);

        // Then: owner A's sensitive preview is rejected rather than projected
        // into owner B's session.
        await expectLater(
          load,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Activity history owner changed during load.',
            ),
          ),
        );
      },
    );

    test('skips malformed and wrong-owner activity docs', () async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final repository = FirestoreActivityHistoryRepository(
        authRepository: authRepository,
        reader: _FakeActivityHistorySummaryDocumentReader(
          activityDocuments: <ActivityHistorySummaryDocument>[
            const ActivityHistorySummaryDocument(
              id: 'malformed-activity',
              data: <String, Object?>{
                'ownerUid': 'test-auth-user-1',
                'completedAt': 'not-a-date',
                'distanceMeters': 3200,
                'durationSeconds': 1500,
                'averagePaceSecondsPerKm': 469,
              },
            ),
            _activityDocument(
              id: 'wrong-owner-activity',
              ownerUid: 'other-user',
              completedAt: DateTime(2026, 6, 13, 7, 25),
            ),
            _activityDocument(
              id: 'valid-activity',
              ownerUid: 'test-auth-user-1',
              completedAt: DateTime(2026, 6, 14, 7, 25),
            ),
          ],
        ),
      );

      final history = await repository.loadActivityHistory();

      expect(history.recentRuns.map((run) => run.activityId), <String>[
        'valid-activity',
      ]);
      expect(history.months.single.activities, hasLength(1));
    });
  });
}

ActivityHistorySummaryDocument _runSummaryDocument({
  required String id,
  required String ownerUid,
  required DateTime endedAt,
  String? activityId,
  String? clientRunSessionId,
  int distanceMeters = 3200,
  int durationSeconds = 1500,
  int averagePaceSecondsPerKm = 469,
  String? routeLabel = 'Private route',
  String? title,
  Map<String, Object?>? cadenceAnalysisSeries,
  Map<String, Object?>? routePreview,
  Map<String, Object?>? paceAnalysisSeries,
  Map<String, Object?>? elevationSeries,
}) {
  final data = <String, Object?>{
    'ownerUid': ownerUid,
    'endedAt': endedAt,
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
    'averagePaceSecondsPerKm': averagePaceSecondsPerKm,
  };
  if (title != null) {
    data['title'] = title;
  }
  if (activityId != null) {
    data['activityId'] = activityId;
  }
  if (clientRunSessionId != null) {
    data['clientRunSessionId'] = clientRunSessionId;
  }
  if (routeLabel != null) {
    data['routeLabel'] = routeLabel;
  }
  if (cadenceAnalysisSeries != null) {
    data['cadenceAnalysisSeries'] = cadenceAnalysisSeries;
  }
  if (routePreview != null) {
    data['routePreview'] = routePreview;
  }
  if (paceAnalysisSeries != null) {
    data['paceAnalysisSeries'] = paceAnalysisSeries;
  }
  if (elevationSeries != null) {
    data['elevationSeries'] = elevationSeries;
  }

  return ActivityHistorySummaryDocument(id: id, data: data);
}

ActivityHistorySummaryDocument _activityDocument({
  required String id,
  required String ownerUid,
  DateTime? completedAt,
  DateTime? endedAt,
  String? activityId,
  String? clientRunSessionId,
  int distanceMeters = 3200,
  int durationSeconds = 1500,
  int averagePaceSecondsPerKm = 469,
  String? routeLabel = 'Private route',
  String? title,
  String? status,
  String? validationStatus,
}) {
  final data = <String, Object?>{
    'ownerUid': ownerUid,
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
    'averagePaceSecondsPerKm': averagePaceSecondsPerKm,
  };
  if (completedAt != null) {
    data['completedAt'] = completedAt;
  }
  if (endedAt != null) {
    data['endedAt'] = endedAt;
  }
  if (title != null) {
    data['title'] = title;
  }
  if (activityId != null) {
    data['activityId'] = activityId;
  }
  if (clientRunSessionId != null) {
    data['clientRunSessionId'] = clientRunSessionId;
  }
  if (routeLabel != null) {
    data['routeLabel'] = routeLabel;
  }
  if (status != null) {
    data['status'] = status;
  }
  if (validationStatus != null) {
    data['validationStatus'] = validationStatus;
  }

  return ActivityHistorySummaryDocument(id: id, data: data);
}

class _FakeActivityHistorySummaryDocumentReader
    implements ActivityHistorySummaryDocumentReader {
  _FakeActivityHistorySummaryDocumentReader({
    this.documents = const <ActivityHistorySummaryDocument>[],
    this.activityDocuments = const <ActivityHistorySummaryDocument>[],
  });

  final List<ActivityHistorySummaryDocument> documents;
  final List<ActivityHistorySummaryDocument> activityDocuments;
  final List<String> readOwnerUids = <String>[];
  final List<String> readActivityOwnerUids = <String>[];
  final List<int> readLimits = <int>[];

  @override
  Future<List<ActivityHistorySummaryDocument>> loadRunSummaries({
    required String ownerUid,
    required int limit,
  }) async {
    readOwnerUids.add(ownerUid);
    readLimits.add(limit);
    return documents;
  }

  @override
  Future<List<ActivityHistorySummaryDocument>> loadActivities({
    required String ownerUid,
    required int limit,
  }) async {
    readActivityOwnerUids.add(ownerUid);
    readLimits.add(limit);
    return activityDocuments;
  }
}

class _DelayedActivityHistorySummaryDocumentReader
    implements ActivityHistorySummaryDocumentReader {
  final summaryReadStarted = Completer<void>();
  final summaryDocuments = Completer<List<ActivityHistorySummaryDocument>>();

  @override
  Future<List<ActivityHistorySummaryDocument>> loadRunSummaries({
    required String ownerUid,
    required int limit,
  }) {
    summaryReadStarted.complete();
    return summaryDocuments.future;
  }

  @override
  Future<List<ActivityHistorySummaryDocument>> loadActivities({
    required String ownerUid,
    required int limit,
  }) async {
    return const <ActivityHistorySummaryDocument>[];
  }
}
