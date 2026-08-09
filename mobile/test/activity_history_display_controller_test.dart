import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/complete_run_result.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/pace_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/xp_update_display_model.dart';
import 'package:runiac_app/features/you/data/local_pending_run_activity_store.dart';
import 'package:runiac_app/features/you/domain/models/activity_history_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/activity_history_repository.dart';
import 'package:runiac_app/features/you/data/static_activity_history_repository.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';
import 'package:runiac_app/features/you/presentation/activity_history_display_controller.dart';
import 'package:runiac_app/features/you/presentation/data/activity_history_demo_snapshots.dart';
import 'package:runiac_app/features/you/presentation/data/you_overview_demo_snapshots.dart';

void main() {
  const ownerUid = 'owner-1';

  group('ActivityHistoryDisplayController', () {
    test(
      'does not replace authenticated empty history with demo rows',
      () async {
        final controller = ActivityHistoryDisplayController(
          repository: _ImmediateActivityHistoryRepository(_emptyHistory()),
        );
        addTearDown(controller.dispose);
        final store = CurrentSessionActivityHistoryStore(ownerUid: ownerUid);
        addTearDown(store.dispose);

        await controller.load();

        expect(controller.recentRuns(store), isEmpty);
        expect(controller.months(store), isEmpty);
      },
    );

    test(
      'removes persisted pending run when remote history has matching client session',
      () async {
        final storage = MemoryLocalPendingRunActivityStore();
        final store = CurrentSessionActivityHistoryStore(
          ownerUid: ownerUid,
          persistence: storage,
        );
        final controller = ActivityHistoryDisplayController(
          repository: _ImmediateActivityHistoryRepository(
            ActivityHistoryReadModel(
              recentRuns: const <ActivityHistoryItemReadModel>[
                ActivityHistoryItemReadModel(
                  activityId: 'firestore-activity-1',
                  clientRunSessionId: 'client-session-1',
                  title: 'Completed Run',
                  completedAtLabel: '14/6/26',
                  distanceLabel: '0.00 km',
                  distanceMeters: 0,
                  paceLabel: '--',
                  durationLabel: '0:02',
                ),
              ],
              months: const <ActivityHistoryMonthReadModel>[],
            ),
          ),
          activityHistoryStore: store,
        );
        addTearDown(controller.dispose);
        addTearDown(store.dispose);
        await store.saveCompletedRun(
          _completionResult('client-session-1'),
          payload: _payload('client-session-1'),
        );

        await controller.load();
        await Future<void>.delayed(Duration.zero);

        expect(store.activities, isEmpty);
        expect(await storage.load(), isEmpty);
      },
    );

    test('keeps demo rows for the static repository path', () async {
      final controller = ActivityHistoryDisplayController(
        repository: const StaticActivityHistoryRepository(),
      );
      addTearDown(controller.dispose);
      final store = CurrentSessionActivityHistoryStore(ownerUid: ownerUid);
      addTearDown(store.dispose);

      await controller.load();

      expect(
        controller.recentRuns(store).map((run) => run.title),
        contains(youProgressSnapshot.runs.first.title),
      );
      expect(
        controller.months(store).map((month) => month.label),
        contains(activityHistoryDisplayData.first.label),
      );
    });

    test('ignores repository completion after dispose', () async {
      final repository = _DelayedActivityHistoryRepository();
      final controller = ActivityHistoryDisplayController(
        repository: repository,
      );
      addTearDown(() {
        if (!repository.completer.isCompleted) {
          repository.completer.complete(_emptyHistory());
        }
      });

      final load = controller.load();
      controller.dispose();
      repository.completer.complete(_emptyHistory());

      await expectLater(load, completes);
    });

    test(
      'removes local pending run when load receives matching client session',
      () async {
        final store = CurrentSessionActivityHistoryStore(ownerUid: ownerUid);
        final controller = ActivityHistoryDisplayController(
          repository: _ImmediateActivityHistoryRepository(
            ActivityHistoryReadModel(
              recentRuns: const <ActivityHistoryItemReadModel>[
                ActivityHistoryItemReadModel(
                  activityId: 'firestore-activity-1',
                  clientRunSessionId: 'client-session-1',
                  title: 'Completed Run',
                  completedAtLabel: '14/6/26',
                  distanceLabel: '0.00 km',
                  distanceMeters: 0,
                  paceLabel: '--',
                  durationLabel: '0:02',
                ),
              ],
              months: const <ActivityHistoryMonthReadModel>[],
            ),
          ),
          activityHistoryStore: store,
        );
        addTearDown(controller.dispose);
        addTearDown(store.dispose);
        store.registerCompletedRun(_completionResult('client-session-1'));

        await controller.load();

        expect(store.activities, isEmpty);
        expect(controller.recentRuns(store).map((run) => run.activityId), [
          'firestore-activity-1',
        ]);
      },
    );

    test(
      'recent runs and months projection do not notify the local pending store',
      () async {
        final controller = ActivityHistoryDisplayController(
          repository: _ImmediateActivityHistoryRepository(_emptyHistory()),
        );
        addTearDown(controller.dispose);
        final store = CurrentSessionActivityHistoryStore(ownerUid: ownerUid);
        addTearDown(store.dispose);
        var notificationCount = 0;
        store.addListener(() => notificationCount++);
        store.registerCompletedRun(_completionResult('client-session-1'));
        notificationCount = 0;

        controller.recentRuns(store);
        controller.months(store);

        expect(notificationCount, 0);
        expect(store.activities, isNotEmpty);
      },
    );

    test('projects numeric distance meters into display rows', () async {
      final controller = ActivityHistoryDisplayController(
        repository: _ImmediateActivityHistoryRepository(
          ActivityHistoryReadModel(
            recentRuns: const <ActivityHistoryItemReadModel>[
              ActivityHistoryItemReadModel(
                activityId: 'firestore-activity-1',
                title: 'Completed Run',
                completedAtLabel: '14/6/26',
                distanceLabel: 'label owned by formatter',
                distanceMeters: 4250,
                paceLabel: '7’10”',
                durationLabel: '30:28',
              ),
            ],
          ),
        ),
      );
      addTearDown(controller.dispose);
      final store = CurrentSessionActivityHistoryStore(ownerUid: ownerUid);
      addTearDown(store.dispose);

      await controller.load();

      expect(controller.recentRuns(store).single.distanceMeters, 4250);
    });

    test(
      'projects cadence analysis into Firestore-backed summary rows',
      () async {
        final cadence = CadenceAnalysisSeries.phoneMotionEstimated(
          samples: const [
            CadenceAnalysisSample.accepted(elapsedSeconds: 30, cadenceSpm: 95),
            CadenceAnalysisSample.accepted(elapsedSeconds: 90, cadenceSpm: 118),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cadenceSpm: 120,
            ),
          ],
        );
        final controller = ActivityHistoryDisplayController(
          repository: _ImmediateActivityHistoryRepository(
            ActivityHistoryReadModel(
              recentRuns: <ActivityHistoryItemReadModel>[
                ActivityHistoryItemReadModel(
                  activityId: 'firestore-activity-cadence',
                  title: 'Cadence Run',
                  completedAtLabel: '14/6/26',
                  distanceLabel: '3.20 km',
                  distanceMeters: 3200,
                  paceLabel: '7’49”',
                  durationLabel: '25:00',
                  cadenceAnalysisSeries: cadence,
                ),
              ],
            ),
          ),
        );
        addTearDown(controller.dispose);
        final store = CurrentSessionActivityHistoryStore(ownerUid: ownerUid);
        addTearDown(store.dispose);

        await controller.load();

        final summary = controller.recentRuns(store).single.summary;
        expect(summary.cadenceAnalysisSeries, same(cadence));
        expect(
          summary.cadenceAnalysisSeries?.validAcceptedSamples,
          hasLength(3),
        );
      },
    );

    test(
      'projects rich Firestore summary when local completion storage is empty',
      () async {
        // Given: a reinstall-like empty current-session store and an
        // authenticated repository read model carrying persisted rich data.
        final richSummary = RunSummarySnapshot(
          title: 'Persisted rich run',
          dateLabel: '14/6/26',
          timeLabel: '7:25 AM',
          distanceKm: '3.20',
          avgPace: '7’49”',
          duration: '25:00',
          avgHeartRate: '--',
          calories: '--',
          routeName: 'Private route',
          paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
            samples: const <PaceAnalysisSample>[
              PaceAnalysisSample.accepted(
                elapsedSeconds: 30,
                cumulativeDistanceMeters: 100,
                paceSecondsPerKm: 420,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 60,
                cumulativeDistanceMeters: 220,
                paceSecondsPerKm: 410,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 90,
                cumulativeDistanceMeters: 350,
                paceSecondsPerKm: 400,
              ),
            ],
          ),
          elevationSeries: ElevationAnalysisSeries.localAccepted(
            samples: const <ElevationAnalysisSample>[
              ElevationAnalysisSample(distanceKm: 0, elevationMeters: 10.5),
              ElevationAnalysisSample(distanceKm: 0.2, elevationMeters: 12),
            ],
          ),
          route: RunRouteSnapshot(
            segments: <List<RunLocationSample>>[
              <RunLocationSample>[
                RunLocationSample(
                  recordedAt: DateTime.fromMillisecondsSinceEpoch(
                    0,
                    isUtc: true,
                  ),
                  latitude: 1.301,
                  longitude: 103.801,
                ),
                RunLocationSample(
                  recordedAt: DateTime.fromMillisecondsSinceEpoch(
                    1000,
                    isUtc: true,
                  ),
                  latitude: 1.302,
                  longitude: 103.802,
                ),
              ],
            ],
            lastKnownLocation: RunLocationSample(
              recordedAt: DateTime.fromMillisecondsSinceEpoch(
                1000,
                isUtc: true,
              ),
              latitude: 1.302,
              longitude: 103.802,
            ),
          ),
        );
        final controller = ActivityHistoryDisplayController(
          repository: _ImmediateActivityHistoryRepository(
            ActivityHistoryReadModel(
              recentRuns: <ActivityHistoryItemReadModel>[
                ActivityHistoryItemReadModel(
                  activityId: 'persisted-rich-activity',
                  clientRunSessionId: 'persisted-rich-session',
                  title: richSummary.title,
                  completedAtLabel: richSummary.dateLabel,
                  distanceLabel: '${richSummary.distanceKm} km',
                  distanceMeters: 3200,
                  paceLabel: richSummary.avgPace,
                  durationLabel: richSummary.duration,
                  summarySnapshot: richSummary,
                  isTrustedPersistedRoutePreview: true,
                ),
              ],
            ),
          ),
        );
        addTearDown(controller.dispose);
        final store = CurrentSessionActivityHistoryStore(ownerUid: ownerUid);
        addTearDown(store.dispose);
        expect(store.activities, isEmpty);

        // When: Activity History loads and projects the remote row without any
        // current completion result to merge from local storage.
        await controller.load();
        final activity = controller.recentRuns(store).single;

        // Then: opening History/Summary receives the original typed snapshot,
        // and the explicit persisted-preview provenance survives projection.
        expect(activity.completionResult, isNull);
        expect(activity.summary, same(richSummary));
        expect(activity.summary.route.hasRoute, isTrue);
        expect(
          activity.summary.paceAnalysisSeries?.validAcceptedSamples,
          hasLength(3),
        );
        expect(activity.summary.elevationSeries.validSamples, hasLength(2));
        expect(activity.isTrustedPersistedRoutePreview, isTrue);
      },
    );
  });
}

class _ImmediateActivityHistoryRepository implements ActivityHistoryRepository {
  const _ImmediateActivityHistoryRepository(this.history);

  final ActivityHistoryReadModel history;

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    return history;
  }
}

class _DelayedActivityHistoryRepository implements ActivityHistoryRepository {
  final completer = Completer<ActivityHistoryReadModel>();

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() {
    return completer.future;
  }
}

ActivityHistoryReadModel _emptyHistory() {
  return ActivityHistoryReadModel(
    recentRuns: const <ActivityHistoryItemReadModel>[],
    months: const <ActivityHistoryMonthReadModel>[],
  );
}

CompleteRunResult _completionResult(String clientRunSessionId) {
  return CompleteRunResult(
    clientRunSessionId: clientRunSessionId,
    activityId: 'local-$clientRunSessionId',
    summary: const RunSummarySnapshot(
      title: 'Completed Run',
      dateLabel: 'Today',
      timeLabel: '7:25 AM',
      distanceKm: '0.00',
      avgPace: '--',
      duration: '0:02',
      avgHeartRate: '--',
      calories: '--',
      routeName: 'Private route',
      hasSufficientData: false,
    ),
    xpUpdate: const XpUpdateDisplayModel(
      runnerName: 'Runiac Runner',
      earnedXpLabel: '+0 XP',
      totalXpLabel: 'Deferred by backend',
      levelLabel: 'Pending',
      nextLevelLabel: 'Pending',
      progressTargetLabel: 'Pending',
      xpRemainingLabel: 'Formula pending',
      previousProgressFraction: 0,
      currentProgressFraction: 0,
      streakChangeLabel: 'Deferred',
      streakNote: 'Backend validation accepted the run.',
      didLevelUp: false,
    ),
  );
}

LocalRunCompletionPayload _payload(String clientRunSessionId) {
  return LocalRunCompletionPayload(
    clientRunSessionId: clientRunSessionId,
    startedAt: DateTime.utc(2026, 6, 14, 9),
    completedAt: DateTime.utc(2026, 6, 14, 9, 0, 2),
    durationSeconds: 2,
    distanceMeters: 0,
    avgPaceSecondsPerKm: 0,
    source: 'mobile',
    routePrivacy: 'private',
  );
}
