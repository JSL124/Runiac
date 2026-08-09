import 'dart:ui';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/complete_run_result.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/pace_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/run_completion_request_adapter.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_display_model.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_completion_error.dart';
import 'package:runiac_app/features/run/domain/models/run_feed_publish_source.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_read_model.dart';
import 'package:runiac_app/features/run/domain/models/xp_update_display_model.dart';
import 'package:runiac_app/features/run/domain/repositories/run_repository.dart';
import 'package:runiac_app/features/run/domain/services/pace_graph_data_builder.dart';
import 'package:runiac_app/features/you/data/local_pending_run_activity_store.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_snapshot_thumbnail_cache.dart';

void main() {
  const ownerUid = 'owner-1';
  const otherOwnerUid = 'owner-2';

  test('restores saved pending run after store recreation', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final firstStore = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(firstStore.dispose);

    await firstStore.saveCompletedRun(
      _completionResult('persisted-client-session'),
      payload: _payload('persisted-client-session'),
    );

    final restoredStore = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(restoredStore.dispose);
    await restoredStore.restoreSavedActivities();

    expect(restoredStore.activities.map((run) => run.activityId), [
      'local-persisted-client-session',
    ]);
  });

  test(
    'tracks completed scheduled workout ids for generated plan progress',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);

      await store.saveCompletedRun(
        _completionResult('planned-client-session'),
        payload: _payload(
          'planned-client-session',
          scheduledWorkoutId: 'week-1-tue-controlled-steady-run',
        ),
      );

      expect(store.completedScheduledWorkoutIds, isEmpty);
      expect(
        store.completedScheduledWorkoutIdsForPlan('generated-plan-10k'),
        isEmpty,
      );

      final completionContext = store.captureRunCompletionContext();
      await store.acceptForegroundCompletion(
        _completionResult('planned-client-session').copyWith(
          activityId: 'activity_planned-client-session',
          summaryId: 'summary_planned-client-session',
          progressionEventId: 'progression_planned-client-session',
          planCompletion: const PlanCompletionResult(
            completed: true,
            planEnrollmentId: 'generated-plan-10k',
            scheduledWorkoutId: 'week-1-tue-controlled-steady-run',
          ),
        ),
        payload: _payload(
          'planned-client-session',
          scheduledWorkoutId: 'week-1-tue-controlled-steady-run',
        ),
        completionContext: completionContext,
      );

      expect(store.completedScheduledWorkoutIds, {
        'week-1-tue-controlled-steady-run',
      });
      expect(store.completedScheduledWorkoutIdsForPlan('generated-plan-10k'), {
        'week-1-tue-controlled-steady-run',
      });

      final restoredStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(restoredStore.dispose);
      await restoredStore.restoreSavedActivities();

      expect(restoredStore.completedScheduledWorkoutIds, {
        'week-1-tue-controlled-steady-run',
      });
      expect(
        restoredStore.completedScheduledWorkoutIdsForPlan('generated-plan-10k'),
        {'week-1-tue-controlled-steady-run'},
      );
      expect(
        restoredStore.completedScheduledWorkoutIdsForPlan(
          'regenerated-plan-10k',
        ),
        isEmpty,
      );
    },
  );

  test('restores saved pending run from shared preferences storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const storage = SharedPreferencesLocalPendingRunActivityStore(
      key: 'test.pendingRunActivities',
    );
    final firstStore = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(firstStore.dispose);

    await firstStore.saveCompletedRun(
      _completionResult('shared-prefs-client-session'),
      payload: _payload('shared-prefs-client-session'),
    );

    final restoredStore = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(restoredStore.dispose);
    await restoredStore.restoreSavedActivities();

    expect(restoredStore.activities.map((run) => run.activityId), [
      'local-shared-prefs-client-session',
    ]);
  });

  test(
    'restores saved pending run route snapshot after store recreation',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const storage = SharedPreferencesLocalPendingRunActivityStore(
        key: 'test.pendingRunActivitiesWithRoute',
      );
      final route = _routeSnapshot();
      final firstStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(firstStore.dispose);

      await firstStore.saveCompletedRun(
        _completionResult('route-client-session', route: route),
        payload: _payload('route-client-session'),
      );

      final restoredStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(restoredStore.dispose);
      await restoredStore.restoreSavedActivities();

      final restoredRoute =
          restoredStore.activities.single.display.summary.route;
      expect(restoredRoute.hasRoute, isTrue);
      expect(restoredRoute.segments.single, hasLength(3));
      expect(restoredRoute.lastKnownLocation?.latitude, 1.3033);
      expect(restoredRoute.lastKnownLocation?.longitude, 103.8333);
    },
  );

  test(
    'preserves never-synced payload route for the first retry after restart',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const storage = SharedPreferencesLocalPendingRunActivityStore(
        key: 'test.pendingNeverSyncedRunWithPayloadRoute',
      );
      final route = _routeSnapshot();
      final payload = _payload(
        'never-synced-route-client-session',
      ).copyWith(routeSnapshot: route);
      final beforeRetryRequest = RunCompletionRequestAdapter.toBackendRequest(
        payload,
      );
      final beforeRetryFingerprint = _routeThumbnailFingerprint(
        route,
        'never-synced-route',
      );
      final firstStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(firstStore.dispose);

      await firstStore.saveCompletedRun(
        _completionResult('never-synced-route-client-session', route: route),
        payload: payload,
      );
      expect((await storage.load()).single.syncAccepted, isFalse);

      final restoredStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(restoredStore.dispose);
      await restoredStore.restoreSavedActivities();
      final repository = _RecordingRunRepository();

      await restoredStore.syncPendingRuns(repository);

      final retriedPayload = repository.submittedPayloads.single;
      final afterRetryRequest = RunCompletionRequestAdapter.toBackendRequest(
        retriedPayload,
      );
      expect(
        afterRetryRequest['routePreview'],
        beforeRetryRequest['routePreview'],
      );
      expect(
        _routeThumbnailFingerprint(
          retriedPayload.routeSnapshot,
          'never-synced-route',
        ),
        beforeRetryFingerprint,
      );
      expect(retriedPayload.routeSnapshot.segments.single, hasLength(3));
    },
  );

  test(
    'restores rich local run snapshot from shared preferences storage',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const storage = SharedPreferencesLocalPendingRunActivityStore(
        key: 'test.pendingRichRunSnapshot',
      );
      final route = _routeSnapshot();
      final firstStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(firstStore.dispose);

      await firstStore.saveCompletedRun(
        _richCompletionResult('rich-client-session', route: route),
        payload: _richPayload('rich-client-session'),
      );

      final restoredStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(restoredStore.dispose);
      await restoredStore.restoreSavedActivities();

      final restoredActivity = restoredStore.activities.single;
      final restoredSummary = restoredActivity.display.summary;
      final restoredPayload = (await storage.load()).single.payload;

      expect(restoredSummary.hasSufficientData, isTrue);
      expect(restoredSummary.route.hasRoute, isTrue);
      expect(restoredSummary.paceGraph.isAvailable, isTrue);
      expect(restoredSummary.paceAnalysisSeries?.isLocalAcceptedSource, isTrue);
      expect(
        restoredSummary.cadenceAnalysisSeries?.isProductionAnalysisEligible,
        isTrue,
      );
      expect(restoredSummary.elevationSeries.isUnavailable, isFalse);
      expect(restoredPayload.paceGraphSamples, hasLength(4));
      expect(restoredPayload.cadenceAnalysisSeries?.samples, hasLength(3));
      expect(restoredPayload.elevationAnalysisSeries?.samples, hasLength(3));
      expect(
        restoredPayload.elevationUnavailableReason,
        ElevationUnavailableReason.none,
      );
    },
  );

  test('sync marks saved pending run after repository accepts it', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(store.dispose);
    final repository = _RecordingRunRepository();

    await store.saveCompletedRun(
      _completionResult('sync-client-session'),
      payload: _payload('sync-client-session'),
    );
    final savedBeforeSync = await storage.load();
    expect(savedBeforeSync.single.syncState, RunSyncState.localSaved);
    expect(store.syncDebugSnapshots.single.syncState, RunSyncState.localSaved);

    await store.syncPendingRuns(repository);

    expect(repository.completedClientRunSessionIds, ['sync-client-session']);
    final savedAfterSync = await storage.load();
    expect(savedAfterSync.map((run) => run.clientRunSessionId), [
      'sync-client-session',
    ]);
    expect(savedAfterSync.map((run) => run.syncAccepted), [true]);
    expect(savedAfterSync.single.syncState, RunSyncState.syncAccepted);
    expect(
      store.syncDebugSnapshots.single.syncState,
      RunSyncState.syncAccepted,
    );
    expect(store.activities.map((run) => run.activityId), [
      'activity_sync-client-session',
    ]);
  });

  test(
    'sync refreshes user progress after remote meaningful run is accepted',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      var progressRefreshCount = 0;
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
        onRemoteRunSynced: () async {
          progressRefreshCount += 1;
          return _progress('2 days');
        },
      );
      addTearDown(store.dispose);
      final repository = _RecordingRunRepository();

      await store.saveCompletedRun(
        _completionResult('progress-refresh-client-session'),
        payload: _payload('progress-refresh-client-session'),
      );

      await store.syncPendingRuns(repository);

      expect(progressRefreshCount, 1);
    },
  );

  test(
    'sync ignores user progress refresh completed after owner changes',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final refreshStarted = Completer<void>();
      final refreshProgress = Completer<UserProgressReadModel>();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
        onRemoteRunSynced: () {
          if (!refreshStarted.isCompleted) {
            refreshStarted.complete();
          }
          return refreshProgress.future;
        },
      );
      addTearDown(store.dispose);
      final repository = _RecordingRunRepository();

      await store.saveCompletedRun(
        _completionResult('owner-switch-refresh-client-session'),
        payload: _payload('owner-switch-refresh-client-session'),
      );

      final sync = store.syncPendingRuns(repository);
      await refreshStarted.future;

      store.updateOwnerUid(otherOwnerUid);
      refreshProgress.complete(_progress('2 days'));
      await sync;

      expect(store.latestUserProgressRefresh, isNull);
      expect(store.userProgressRefreshRevision, 1);
    },
  );

  test(
    'sync exposes pending state while repository call is in flight',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final repository = _DelayedRecordingRunRepository();

      await store.saveCompletedRun(
        _completionResult('pending-observable-client-session'),
        payload: _payload('pending-observable-client-session'),
      );

      final sync = store.syncPendingRuns(repository);
      await Future<void>.delayed(Duration.zero);

      final inFlight = await storage.load();
      expect(inFlight.single.syncState, RunSyncState.pendingSync);
      expect(
        store.syncDebugSnapshots.single.syncState,
        RunSyncState.pendingSync,
      );
      expect(inFlight.single.syncAttemptCount, 1);

      repository.complete();
      await sync;

      expect(
        (await storage.load()).single.syncState,
        RunSyncState.syncAccepted,
      );
    },
  );

  test('sync merges remote scalar identity into rich local snapshot', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(store.dispose);
    final repository = _RecordingRunRepository();

    await store.saveCompletedRun(
      _richCompletionResult(
        'rich-sync-client-session',
        route: _routeSnapshot(),
      ),
      payload: _richPayload('rich-sync-client-session'),
    );
    await store.syncPendingRuns(repository);

    final saved = (await storage.load()).single;
    expect(saved.syncAccepted, isTrue);
    expect(saved.result.activityId, 'activity_rich-sync-client-session');
    expect(saved.result.summaryId, 'summary_rich-sync-client-session');
    expect(
      saved.result.progressionEventId,
      'progression_rich-sync-client-session',
    );
    expect(
      store.activities.single.activityId,
      'activity_rich-sync-client-session',
    );
    expect(saved.result.summary.route.hasRoute, isTrue);
    expect(saved.result.summary.paceGraph.isAvailable, isTrue);
    expect(saved.result.summary.cadenceAnalysisSeries, isNotNull);
    expect(saved.result.summary.elevationSeries.isUnavailable, isFalse);
  });

  test('local completion identity is not publishable before validation', () {
    final store = CurrentSessionActivityHistoryStore(ownerUid: ownerUid);
    addTearDown(store.dispose);

    store.registerCompletedRun(_completionResult('local-feed-session'));

    final publishSource = store.activities.single.display.feedPublishSource;
    expect(publishSource.isPublishable, isFalse);
    expect(publishSource.activityId, isNull);
    expect(publishSource.disabledReason, FeedPublishDisabledReason.localOnly);
  });

  test(
    'retryable rich run survives restore and accepted retry keeps analysis',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const storage = SharedPreferencesLocalPendingRunActivityStore(
        key: 'test.pendingRetryableRichRun',
      );
      const clientRunSessionId = 'retryable-rich-client-session';
      final payload = _richPayload(clientRunSessionId);
      final firstStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(firstStore.dispose);

      await firstStore.saveCompletedRun(
        _richCompletionResult(clientRunSessionId, route: _routeSnapshot()),
        payload: payload,
      );
      await firstStore.syncPendingRuns(_RejectingRunRepository());

      final failedRecord = (await storage.load()).single;
      expect(failedRecord.syncState, RunSyncState.syncRetryableFailure);
      expect(failedRecord.clientRunSessionId, clientRunSessionId);
      expect(
        RunCompletionRequestAdapter.toBackendRequest(failedRecord.payload),
        RunCompletionRequestAdapter.toBackendRequest(payload),
      );

      final restoredStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(restoredStore.dispose);
      await restoredStore.restoreSavedActivities();
      final repository = _RecordingRunRepository();

      await restoredStore.syncPendingRuns(repository);

      expect(repository.submittedPayloads, hasLength(1));
      expect(
        RunCompletionRequestAdapter.toBackendRequest(
          repository.submittedPayloads.single,
        ),
        RunCompletionRequestAdapter.toBackendRequest(payload),
      );
      final accepted = (await storage.load()).single;
      expect(accepted.syncState, RunSyncState.syncAccepted);
      expect(accepted.result.activityId, 'activity_$clientRunSessionId');
      expect(accepted.result.clientRunSessionId, clientRunSessionId);
      expect(accepted.result.summary.route.hasRoute, isTrue);
      expect(accepted.result.summary.paceGraph.isAvailable, isTrue);
      expect(accepted.result.summary.cadenceAnalysisSeries, isNotNull);
      expect(accepted.result.summary.elevationSeries.isUnavailable, isFalse);
      expect(
        restoredStore.activities.single.display.feedPublishSource.isPublishable,
        isTrue,
      );
      expect(
        restoredStore.activities.single.display.feedPublishSource.activityId,
        'activity_$clientRunSessionId',
      );
    },
  );

  test(
    'merged rich local snapshot survives shared preferences restore',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const storage = SharedPreferencesLocalPendingRunActivityStore(
        key: 'test.pendingMergedRichRun',
      );
      final firstStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(firstStore.dispose);
      final repository = _RecordingRunRepository();

      await firstStore.saveCompletedRun(
        _richCompletionResult(
          'rich-restore-merged-client-session',
          route: _routeSnapshot(),
        ),
        payload: _richPayload('rich-restore-merged-client-session'),
      );
      await firstStore.syncPendingRuns(repository);

      final restoredStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(restoredStore.dispose);
      await restoredStore.restoreSavedActivities();

      final restoredActivity = restoredStore.activities.single;
      expect(
        restoredActivity.activityId,
        'activity_rich-restore-merged-client-session',
      );
      expect(restoredActivity.display.summary.route.hasRoute, isTrue);
      expect(restoredActivity.display.summary.paceGraph.isAvailable, isTrue);
      expect(restoredActivity.display.summary.cadenceAnalysisSeries, isNotNull);
      expect(
        restoredActivity.display.summary.elevationSeries.isUnavailable,
        isFalse,
      );
    },
  );

  test('low-data save stores confirmation and sync submits it', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(store.dispose);
    final repository = _RecordingRunRepository();

    await store.saveCompletedRun(
      _completionResult('confirmed-low-data-client-session'),
      payload: _payload(
        'confirmed-low-data-client-session',
        userConfirmedLowDataSave: true,
      ),
    );

    final savedBeforeSync = await storage.load();
    expect(savedBeforeSync.single.payload.userConfirmedLowDataSave, isTrue);

    await store.syncPendingRuns(repository);

    expect(repository.completedClientRunSessionIds, [
      'confirmed-low-data-client-session',
    ]);
    expect(
      repository.submittedPayloads.single.userConfirmedLowDataSave,
      isTrue,
    );
    expect(
      (await storage.load()).single.payload.userConfirmedLowDataSave,
      isTrue,
    );
    expect((await storage.load()).single.syncAccepted, isTrue);
  });

  test(
    'restores low-data save confirmation from shared preferences storage',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const storage = SharedPreferencesLocalPendingRunActivityStore(
        key: 'test.pendingConfirmedLowDataRun',
      );
      final firstStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(firstStore.dispose);

      await firstStore.saveCompletedRun(
        _completionResult('confirmed-low-data-shared-prefs-session'),
        payload: _payload(
          'confirmed-low-data-shared-prefs-session',
          userConfirmedLowDataSave: true,
        ),
      );

      final restored = await storage.load();

      expect(restored.single.payload.userConfirmedLowDataSave, isTrue);
    },
  );

  test('local-result sync is deferred and not resubmitted', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(store.dispose);
    final repository = _LocalResultRunRepository();

    await store.saveCompletedRun(
      _completionResult('static-sync-client-session'),
      payload: _payload('static-sync-client-session'),
    );
    await store.syncPendingRuns(repository);
    await store.syncPendingRuns(repository);

    expect((await storage.load()).map((run) => run.clientRunSessionId), [
      'static-sync-client-session',
    ]);
    expect((await storage.load()).map((run) => run.syncAccepted), [false]);
    expect((await storage.load()).map((run) => run.syncState), [
      RunSyncState.syncDeferred,
    ]);
    expect(repository.completedClientRunSessionIds, [
      'static-sync-client-session',
    ]);
  });

  test('deferred local-result sync does not refresh user progress', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    var progressRefreshCount = 0;
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
      onRemoteRunSynced: () async {
        progressRefreshCount += 1;
        return _progress('2 days');
      },
    );
    addTearDown(store.dispose);
    final repository = _LocalResultRunRepository();

    await store.saveCompletedRun(
      _completionResult('deferred-progress-client-session'),
      payload: _payload('deferred-progress-client-session'),
    );
    await store.syncPendingRuns(repository);

    expect(progressRefreshCount, 0);
  });

  test('accepted low-data save does not refresh user progress', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    var progressRefreshCount = 0;
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
      onRemoteRunSynced: () async {
        progressRefreshCount += 1;
        return _progress('2 days');
      },
    );
    addTearDown(store.dispose);
    final repository = _RecordingRunRepository();

    await store.saveCompletedRun(
      _completionResult('low-data-progress-client-session'),
      payload: _payload(
        'low-data-progress-client-session',
        userConfirmedLowDataSave: true,
      ),
    );
    await store.syncPendingRuns(repository);

    expect((await storage.load()).single.syncAccepted, isTrue);
    expect(progressRefreshCount, 0);
  });

  test('concurrent sync calls submit a pending run once', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(store.dispose);
    final repository = _DelayedRecordingRunRepository();

    await store.saveCompletedRun(
      _completionResult('concurrent-client-session'),
      payload: _payload('concurrent-client-session'),
    );

    final firstSync = store.syncPendingRuns(repository);
    final secondSync = store.syncPendingRuns(repository);
    await Future<void>.delayed(Duration.zero);

    expect(repository.completedClientRunSessionIds, [
      'concurrent-client-session',
    ]);

    repository.complete();
    await Future.wait([firstSync, secondSync]);

    expect(repository.completedClientRunSessionIds, [
      'concurrent-client-session',
    ]);
    expect((await storage.load()).map((run) => run.syncAccepted), [true]);
  });

  test(
    'active sync drains a new request saved while sync is in flight',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final repository = _DelayedRecordingRunRepository();

      await store.saveCompletedRun(
        _completionResult('first-in-flight-client-session'),
        payload: _payload('first-in-flight-client-session'),
      );

      final firstSync = store.syncPendingRuns(repository);
      await Future<void>.delayed(Duration.zero);

      await store.saveCompletedRun(
        _completionResult('second-in-flight-client-session'),
        payload: _payload('second-in-flight-client-session'),
      );
      final secondSync = store.syncPendingRuns(repository);

      repository.complete();
      await Future.wait([firstSync, secondSync]);

      expect(repository.completedClientRunSessionIds, [
        'first-in-flight-client-session',
        'second-in-flight-client-session',
      ]);
      expect((await storage.load()).map((run) => run.syncAccepted), [
        true,
        true,
      ]);
    },
  );

  test(
    'remote reconcile clears accepted pending run after read-side appears',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final repository = _RecordingRunRepository();

      await store.saveCompletedRun(
        _completionResult('reconcile-client-session'),
        payload: _payload('reconcile-client-session'),
      );
      await store.syncPendingRuns(repository);

      store.reconcileWithRemote([_remoteActivity('reconcile-client-session')]);
      await Future<void>.delayed(Duration.zero);

      expect(await storage.load(), isEmpty);
      expect(store.activities, isEmpty);
    },
  );

  test(
    'owner change clears debug snapshots after scalar reconcile removes run',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final repository = _RecordingRunRepository();

      await store.saveCompletedRun(
        _completionResult('debug-owner-client-session'),
        payload: _payload('debug-owner-client-session'),
      );
      await store.syncPendingRuns(repository);

      store.reconcileWithRemote([
        _remoteActivity('debug-owner-client-session'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(store.activities, isEmpty);
      expect(store.syncDebugSnapshots, isNotEmpty);

      store.updateOwnerUid(otherOwnerUid);

      expect(store.syncDebugSnapshots, isEmpty);
    },
  );

  test(
    'remote reconcile keeps accepted rich local snapshot after read-side appears',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final repository = _RecordingRunRepository();

      await store.saveCompletedRun(
        _richCompletionResult(
          'rich-reconcile-client-session',
          route: _routeSnapshot(),
        ),
        payload: _richPayload('rich-reconcile-client-session'),
      );
      await store.syncPendingRuns(repository);

      store.reconcileWithRemote([
        _remoteActivity('rich-reconcile-client-session'),
      ]);
      await Future<void>.delayed(Duration.zero);

      final saved = await storage.load();
      expect(saved.single.syncAccepted, isTrue);
      expect(store.activities, hasLength(1));
      final summary = store.activities.single.display.summary;
      expect(summary.route.hasRoute, isTrue);
      expect(summary.paceGraph.isAvailable, isTrue);
      expect(summary.cadenceAnalysisSeries, isNotNull);
      expect(summary.elevationSeries.isUnavailable, isFalse);
    },
  );

  test(
    'remote reconcile merges scalar identity into rich local snapshot',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final repository = _RecordingRunRepository();

      await store.saveCompletedRun(
        _richCompletionResult(
          'rich-reconcile-merge-client-session',
          route: _routeSnapshot(),
        ),
        payload: _richPayload('rich-reconcile-merge-client-session'),
      );
      await store.syncPendingRuns(repository);

      store.reconcileWithRemote([
        _remoteActivity('rich-reconcile-merge-client-session'),
      ]);
      await Future<void>.delayed(Duration.zero);

      final saved = await storage.load();
      expect(
        saved.single.result.activityId,
        'firestore-rich-reconcile-merge-client-session',
      );
      expect(
        store.activities.single.activityId,
        'firestore-rich-reconcile-merge-client-session',
      );
      final summary = store.activities.single.display.summary;
      expect(summary.route.hasRoute, isTrue);
      expect(summary.paceGraph.isAvailable, isTrue);
      expect(summary.cadenceAnalysisSeries, isNotNull);
      expect(summary.elevationSeries.isUnavailable, isFalse);
    },
  );

  test(
    'remote reconcile upgrades rich local snapshot to publishable source',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      const clientRunSessionId = 'rich-feed-reconcile-client-session';

      await store.saveCompletedRun(
        _richCompletionResult(clientRunSessionId, route: _routeSnapshot()),
        payload: _richPayload(clientRunSessionId),
      );

      store.reconcileWithRemote([
        _publishableRemoteActivity(clientRunSessionId),
      ]);
      await Future<void>.delayed(Duration.zero);

      final activity = store.activities.single;
      expect(activity.activityId, 'activity_$clientRunSessionId');
      expect(activity.display.feedPublishSource.isPublishable, isTrue);
      expect(
        activity.display.feedPublishSource.activityId,
        'activity_$clientRunSessionId',
      );
      expect(activity.display.summary.route.hasRoute, isTrue);
      expect(activity.display.summary.paceGraph.isAvailable, isTrue);
      expect(activity.display.summary.cadenceAnalysisSeries, isNotNull);
      expect(activity.display.summary.elevationSeries.isUnavailable, isFalse);
    },
  );

  test('local save failure does not leave an in-memory saved run', () async {
    final storage = _FailingSavePendingRunActivityStore();
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(store.dispose);

    await expectLater(
      store.saveCompletedRun(
        _completionResult('failed-save-client-session'),
        payload: _payload('failed-save-client-session'),
      ),
      throwsStateError,
    );

    expect(store.activities, isEmpty);
  });

  test(
    'save does not register in memory if owner changes before persistence completes',
    () async {
      final storage = _DelayedSavePendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);

      final save = store.saveCompletedRun(
        _completionResult('save-race-client-session'),
        payload: _payload('save-race-client-session'),
      );
      await Future<void>.delayed(Duration.zero);

      store.updateOwnerUid(otherOwnerUid);
      storage.completeSave();
      await save;

      expect(store.activities, isEmpty);
      expect((await storage.load()).single.ownerUid, ownerUid);
    },
  );

  test('sync keeps saved pending run when repository rejects it', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(store.dispose);
    final repository = _RejectingRunRepository();

    await store.saveCompletedRun(
      _completionResult('retry-client-session'),
      payload: _payload('retry-client-session'),
    );
    await store.syncPendingRuns(repository);

    expect(repository.completedClientRunSessionIds, ['retry-client-session']);
    expect((await storage.load()).map((run) => run.clientRunSessionId), [
      'retry-client-session',
    ]);
    expect(store.activities.map((run) => run.activityId), [
      'local-retry-client-session',
    ]);
    final saved = await storage.load();
    expect(saved.single.syncState, RunSyncState.syncRetryableFailure);
    expect(saved.single.lastSyncFailureCode, 'unknown');
    expect(saved.single.lastSyncFailureMessage, 'Run sync failed.');
    expect(
      store.syncDebugSnapshots.single.syncState,
      RunSyncState.syncRetryableFailure,
    );
  });

  test(
    'foreground completion failures retain a safe sync reason for retry',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final payload = _payload('foreground-failure-client-session');

      await store.saveCompletedRun(
        _completionResult(payload.clientRunSessionId),
        payload: payload,
      );
      await store.recordForegroundRunSyncFailure(
        payload: payload,
        completionContext: store.captureRunCompletionContext(),
        error: const RunCompletionException(
          code: 'unavailable',
          message: 'backend details must not reach the user',
          isRetryable: true,
        ),
      );

      final saved = (await storage.load()).single;
      expect(saved.syncState, RunSyncState.syncRetryableFailure);
      expect(saved.lastSyncFailureCode, 'unavailable');
      expect(saved.lastSyncFailureMessage, 'Run sync failed with unavailable.');
      expect(saved.lastSyncFailureMessage, isNot(contains('backend details')));
    },
  );

  test(
    'sync records non-retryable completion failures without resubmitting',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final repository = _RunCompletionErrorRepository(
        code: 'invalid-argument',
        message: 'callable rejected owner=owner-1 token=secret-123',
        isRetryable: false,
      );

      await store.saveCompletedRun(
        _completionResult('non-retryable-client-session'),
        payload: _payload('non-retryable-client-session'),
      );
      await store.syncPendingRuns(repository);
      await store.syncPendingRuns(repository);

      expect(repository.completedClientRunSessionIds, [
        'non-retryable-client-session',
      ]);
      final saved = await storage.load();
      expect(saved.single.syncAccepted, isFalse);
      expect(saved.single.syncState, RunSyncState.syncNonRetryableFailure);
      expect(saved.single.lastSyncFailureCode, 'invalid-argument');
      expect(
        saved.single.lastSyncFailureMessage,
        'Run sync failed with invalid-argument.',
      );
      expect(saved.single.lastSyncFailureMessage, isNot(contains('owner-1')));
      expect(saved.single.lastSyncFailureMessage, isNot(contains('secret')));
      expect(
        store.syncDebugSnapshots.single.syncState,
        RunSyncState.syncNonRetryableFailure,
      );
    },
  );

  test(
    'decode requeues invalid argument failures caused by cadence contracts',
    () {
      final payload = _richPayload(
        'legacy-cadence-client-session',
        cadenceAnalysisSeries: CadenceAnalysisSeries.phoneMotionEstimated(
          samples: const <CadenceAnalysisSample>[
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 301,
              cadenceSpm: 170,
            ),
          ],
        ),
      );
      final failed =
          LocalPendingRunActivity.fromCompletedRun(
            ownerUid: ownerUid,
            result: _completionResult(payload.clientRunSessionId),
            payload: payload,
          ).markSyncFailure(
            code: 'invalid-argument',
            message: 'Run sync failed with invalid-argument.',
            isRetryable: false,
          );

      final restored = LocalPendingRunActivity.tryDecode(failed.encode());

      expect(restored, isNotNull);
      expect(restored?.syncState, RunSyncState.syncRetryableFailure);
      expect(restored?.shouldAttemptSync, isTrue);
    },
  );

  test('decode keeps unrelated invalid argument failures non-retryable', () {
    final payload = _richPayload('valid-cadence-client-session');
    final failed =
        LocalPendingRunActivity.fromCompletedRun(
          ownerUid: ownerUid,
          result: _completionResult(payload.clientRunSessionId),
          payload: payload,
        ).markSyncFailure(
          code: 'invalid-argument',
          message: 'Run sync failed with invalid-argument.',
          isRetryable: false,
        );

    final restored = LocalPendingRunActivity.tryDecode(failed.encode());

    expect(restored, isNotNull);
    expect(restored?.syncState, RunSyncState.syncNonRetryableFailure);
    expect(restored?.shouldAttemptSync, isFalse);
  });

  test('restore and sync ignore pending runs for another owner', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final firstStore = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(firstStore.dispose);
    await firstStore.saveCompletedRun(
      _completionResult('owner-client-session'),
      payload: _payload('owner-client-session'),
    );

    final secondStore = CurrentSessionActivityHistoryStore(
      ownerUid: otherOwnerUid,
      persistence: storage,
    );
    addTearDown(secondStore.dispose);
    final repository = _RecordingRunRepository();

    await secondStore.restoreSavedActivities();
    await secondStore.syncPendingRuns(repository);

    expect(secondStore.activities, isEmpty);
    expect(repository.completedClientRunSessionIds, isEmpty);
    expect((await storage.load()).map((run) => run.ownerUid), [ownerUid]);
  });

  test(
    'same client session id from another owner does not overwrite pending',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final firstStore = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      final secondStore = CurrentSessionActivityHistoryStore(
        ownerUid: otherOwnerUid,
        persistence: storage,
      );
      addTearDown(firstStore.dispose);
      addTearDown(secondStore.dispose);

      await firstStore.saveCompletedRun(
        _completionResult('local-run-1'),
        payload: _payload('local-run-1'),
      );
      await secondStore.saveCompletedRun(
        _completionResult('local-run-1'),
        payload: _payload('local-run-1'),
      );

      expect((await storage.load()).map((run) => run.ownerUid), [
        otherOwnerUid,
        ownerUid,
      ]);
    },
  );

  test(
    'restore ignores loaded records if owner changes before load completes',
    () async {
      final storage = _DelayedLoadPendingRunActivityStore([
        LocalPendingRunActivity.fromCompletedRun(
          ownerUid: ownerUid,
          result: _completionResult('race-client-session'),
          payload: _payload('race-client-session'),
        ),
      ]);
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);

      final restore = store.restoreSavedActivities();
      await Future<void>.delayed(Duration.zero);

      store.updateOwnerUid(otherOwnerUid);
      storage.completeLoad();
      await restore;

      expect(store.activities, isEmpty);
    },
  );

  test(
    'sync stops if owner changes before repository call completes',
    () async {
      final storage = MemoryLocalPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final repository = _DelayedRecordingRunRepository();

      await store.saveCompletedRun(
        _completionResult('owner-switch-client-session'),
        payload: _payload('owner-switch-client-session'),
      );

      final sync = store.syncPendingRuns(repository);
      await Future<void>.delayed(Duration.zero);

      store.updateOwnerUid(otherOwnerUid);
      repository.complete();
      await sync;

      expect((await storage.load()).single.syncAccepted, isFalse);
    },
  );

  test('foreground accept defers nonvalidated canonical result', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(store.dispose);
    final payload = _richPayload('foreground-pending-validation');
    await store.saveCompletedRun(
      _richCompletionResult(payload.clientRunSessionId),
      payload: payload,
    );
    final context = store.captureRunCompletionContext();
    final remote = _completionResult(payload.clientRunSessionId).copyWith(
      activityId: 'activity_${payload.clientRunSessionId}',
      validationStatus: 'pending',
    );

    final accepted = await store.acceptForegroundCompletion(
      remote,
      payload: payload,
      completionContext: context,
    );

    expect(accepted, isNull);
    final saved = (await storage.load()).single;
    expect(saved.syncAccepted, isFalse);
    expect(saved.shouldAttemptSync, isTrue);
  });

  test('foreground accept refuses registration after owner change', () async {
    final storage = MemoryLocalPendingRunActivityStore();
    final store = CurrentSessionActivityHistoryStore(
      ownerUid: ownerUid,
      persistence: storage,
    );
    addTearDown(store.dispose);
    final payload = _richPayload('foreground-owner-switch');
    await store.saveCompletedRun(
      _richCompletionResult(payload.clientRunSessionId),
      payload: payload,
    );
    final context = store.captureRunCompletionContext();
    store.updateOwnerUid(otherOwnerUid);
    final local = _completionResult(payload.clientRunSessionId);
    final remote = local.copyWith(
      activityId: 'activity_${payload.clientRunSessionId}',
      validationStatus: 'validated',
    );

    final accepted = await store.acceptForegroundCompletion(
      remote,
      payload: payload,
      completionContext: context,
    );

    expect(accepted, isNull);
    expect(store.activities, isEmpty);
    final saved = (await storage.load()).single;
    expect(saved.ownerUid, ownerUid);
    expect(saved.syncAccepted, isFalse);
  });

  test(
    'foreground accept persistence failure keeps same session retryable',
    () async {
      final storage = _FailOnDemandPendingRunActivityStore();
      final store = CurrentSessionActivityHistoryStore(
        ownerUid: ownerUid,
        persistence: storage,
      );
      addTearDown(store.dispose);
      final payload = _richPayload('foreground-accept-save-failure');
      await store.saveCompletedRun(
        _richCompletionResult(payload.clientRunSessionId),
        payload: payload,
      );
      final context = store.captureRunCompletionContext();
      final local = _completionResult(payload.clientRunSessionId);
      final remote = local.copyWith(
        activityId: 'activity_${payload.clientRunSessionId}',
        validationStatus: 'validated',
      );
      storage.failNextSave = true;

      await expectLater(
        store.acceptForegroundCompletion(
          remote,
          payload: payload,
          completionContext: context,
        ),
        throwsStateError,
      );

      final saved = (await storage.load()).single;
      expect(saved.clientRunSessionId, payload.clientRunSessionId);
      expect(saved.syncAccepted, isFalse);
      expect(saved.shouldAttemptSync, isTrue);
    },
  );
}

RunActivityDisplayModel _remoteActivity(String clientRunSessionId) {
  final result = _completionResult(clientRunSessionId);
  return RunActivityDisplayModel(
    activityId: 'firestore-$clientRunSessionId',
    clientRunSessionId: clientRunSessionId,
    title: result.summary.title,
    timeAgoLabel: result.summary.dateTimeLabel,
    distanceLabel: '${result.summary.distanceKm} km',
    distanceMeters: 0,
    paceLabel: result.summary.avgPace,
    durationLabel: result.summary.duration,
    summary: result.summary,
  );
}

RunActivityDisplayModel _publishableRemoteActivity(String clientRunSessionId) {
  final result = _completionResult(clientRunSessionId);
  final activityId = 'activity_$clientRunSessionId';
  return RunActivityDisplayModel(
    activityId: activityId,
    clientRunSessionId: clientRunSessionId,
    title: result.summary.title,
    timeAgoLabel: result.summary.dateTimeLabel,
    distanceLabel: '${result.summary.distanceKm} km',
    distanceMeters: 0,
    paceLabel: result.summary.avgPace,
    durationLabel: result.summary.duration,
    summary: result.summary,
    feedPublishSource: RunFeedPublishSource.enabled(
      activityId: activityId,
      cacheIdentity: clientRunSessionId,
    ),
  );
}

CompleteRunResult _completionResult(
  String clientRunSessionId, {
  RunRouteSnapshot route = RunRouteSnapshot.empty,
}) {
  return CompleteRunResult(
    clientRunSessionId: clientRunSessionId,
    activityId: 'local-$clientRunSessionId',
    summary: RunSummarySnapshot(
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
      route: route,
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

CompleteRunResult _richCompletionResult(
  String clientRunSessionId, {
  RunRouteSnapshot route = RunRouteSnapshot.empty,
}) {
  return CompleteRunResult(
    clientRunSessionId: clientRunSessionId,
    activityId: 'local-$clientRunSessionId',
    summary: RunSummarySnapshot(
      title: 'Completed Run',
      dateLabel: 'Today',
      timeLabel: '7:25 AM',
      distanceKm: '1.00',
      avgPace: '5:00',
      duration: '5:00',
      avgHeartRate: '--',
      calories: '--',
      routeName: 'Private route',
      hasSufficientData: true,
      paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
        samples: _paceAnalysisSamples(),
      ),
      cadenceAnalysisSeries: _cadenceAnalysisSeries(),
      elevationSeries: _elevationAnalysisSeries(),
      paceGraph: const PaceGraphDataBuilder().build(
        samples: _paceGraphSamples(),
        durationSeconds: 300,
        distanceMeters: 1000,
        averagePaceSecondsPerKm: 300,
      ),
      route: route,
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

RunRouteSnapshot _routeSnapshot() {
  final samples = <RunLocationSample>[
    RunLocationSample(
      recordedAt: DateTime.utc(2026, 6, 14, 9),
      latitude: 1.3001,
      longitude: 103.8301,
      altitudeMeters: 12,
      horizontalAccuracyMeters: 8,
      speedMetersPerSecond: 2.6,
    ),
    RunLocationSample(
      recordedAt: DateTime.utc(2026, 6, 14, 9, 0, 1),
      latitude: 1.3016,
      longitude: 103.8318,
      altitudeMeters: 14,
      horizontalAccuracyMeters: 7,
      speedMetersPerSecond: 2.8,
    ),
    RunLocationSample(
      recordedAt: DateTime.utc(2026, 6, 14, 9, 0, 2),
      latitude: 1.3033,
      longitude: 103.8333,
      altitudeMeters: 16,
      horizontalAccuracyMeters: 6,
      speedMetersPerSecond: 2.9,
    ),
  ];
  return RunRouteSnapshot(segments: [samples], lastKnownLocation: samples.last);
}

int _routeThumbnailFingerprint(RunRouteSnapshot route, String activityId) {
  return ActivityRouteSnapshotThumbnailCacheKey.fromRequest(
    ActivityRouteThumbnailRequest(
      route: route,
      logicalSize: const Size(120, 80),
      devicePixelRatio: 2,
      allowExternalStaticMap: true,
      isDemoRoute: false,
      isCurrentSessionRoute: true,
      activityId: activityId,
    ),
  ).routeFingerprint;
}

List<PaceGraphSample> _paceGraphSamples() {
  return const <PaceGraphSample>[
    PaceGraphSample(
      elapsedSeconds: 60,
      paceSecondsPerKm: 300,
      cumulativeDistanceMeters: 200,
    ),
    PaceGraphSample(
      elapsedSeconds: 120,
      paceSecondsPerKm: 295,
      cumulativeDistanceMeters: 400,
    ),
    PaceGraphSample(
      elapsedSeconds: 210,
      paceSecondsPerKm: 305,
      cumulativeDistanceMeters: 700,
    ),
    PaceGraphSample(
      elapsedSeconds: 300,
      paceSecondsPerKm: 300,
      cumulativeDistanceMeters: 1000,
    ),
  ];
}

List<PaceAnalysisSample> _paceAnalysisSamples() {
  return const <PaceAnalysisSample>[
    PaceAnalysisSample.accepted(
      elapsedSeconds: 60,
      cumulativeDistanceMeters: 200,
      paceSecondsPerKm: 300,
    ),
    PaceAnalysisSample.accepted(
      elapsedSeconds: 120,
      cumulativeDistanceMeters: 400,
      paceSecondsPerKm: 295,
    ),
    PaceAnalysisSample.accepted(
      elapsedSeconds: 210,
      cumulativeDistanceMeters: 700,
      paceSecondsPerKm: 305,
    ),
    PaceAnalysisSample.accepted(
      elapsedSeconds: 300,
      cumulativeDistanceMeters: 1000,
      paceSecondsPerKm: 300,
    ),
  ];
}

CadenceAnalysisSeries _cadenceAnalysisSeries() {
  return CadenceAnalysisSeries.phoneMotionEstimated(
    samples: const <CadenceAnalysisSample>[
      CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 170),
      CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 174),
      CadenceAnalysisSample.accepted(elapsedSeconds: 210, cadenceSpm: 172),
    ],
  );
}

ElevationAnalysisSeries _elevationAnalysisSeries() {
  return ElevationAnalysisSeries.localAccepted(
    samples: const <ElevationAnalysisSample>[
      ElevationAnalysisSample(distanceKm: 0, elevationMeters: 12),
      ElevationAnalysisSample(distanceKm: 0.5, elevationMeters: 18),
      ElevationAnalysisSample(distanceKm: 1, elevationMeters: 16),
    ],
  );
}

LocalRunCompletionPayload _payload(
  String clientRunSessionId, {
  bool userConfirmedLowDataSave = false,
  String? planEnrollmentId,
  String? scheduledWorkoutId,
}) {
  return LocalRunCompletionPayload(
    clientRunSessionId: clientRunSessionId,
    startedAt: DateTime.utc(2026, 6, 14, 9),
    completedAt: DateTime.utc(2026, 6, 14, 9, 0, 2),
    durationSeconds: 2,
    distanceMeters: 0,
    avgPaceSecondsPerKm: 0,
    source: 'mobile',
    routePrivacy: 'private',
    userConfirmedLowDataSave: userConfirmedLowDataSave,
    planEnrollmentId:
        planEnrollmentId ??
        (scheduledWorkoutId == null ? null : 'generated-plan-10k'),
    scheduledWorkoutId: scheduledWorkoutId,
  );
}

UserProgressReadModel _progress(String officialStreakLabel) {
  return UserProgressReadModel(
    userId: 'owner-1',
    officialStreakLabel: officialStreakLabel,
    levelLabel: '',
    totalXpLabel: '',
    weeklyXpLabel: '',
    monthlyXpLabel: '',
    weeklyDistanceLabel: '',
    goalProgressLabel: '',
  );
}

LocalRunCompletionPayload _richPayload(
  String clientRunSessionId, {
  CadenceAnalysisSeries? cadenceAnalysisSeries,
}) {
  return LocalRunCompletionPayload(
    clientRunSessionId: clientRunSessionId,
    startedAt: DateTime.utc(2026, 6, 14, 9),
    completedAt: DateTime.utc(2026, 6, 14, 9, 5),
    durationSeconds: 300,
    distanceMeters: 1000,
    avgPaceSecondsPerKm: 300,
    source: 'mobile',
    routePrivacy: 'private',
    paceGraphSamples: _paceGraphSamples(),
    cadenceAnalysisSeries: cadenceAnalysisSeries ?? _cadenceAnalysisSeries(),
    elevationAnalysisSeries: _elevationAnalysisSeries(),
    elevationUnavailableReason: ElevationUnavailableReason.none,
  );
}

class _RecordingRunRepository implements RunRepository {
  final List<String> completedClientRunSessionIds = <String>[];
  final List<LocalRunCompletionPayload> submittedPayloads =
      <LocalRunCompletionPayload>[];

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    completedClientRunSessionIds.add(payload.clientRunSessionId);
    submittedPayloads.add(payload);
    final result = _completionResult(payload.clientRunSessionId);
    return CompleteRunResult(
      clientRunSessionId: result.clientRunSessionId,
      activityId: 'activity_${payload.clientRunSessionId}',
      summaryId: 'summary_${payload.clientRunSessionId}',
      progressionEventId: 'progression_${payload.clientRunSessionId}',
      validationStatus: result.validationStatus,
      summary: result.summary,
      progressionDisplay: result.progressionDisplay,
      xpUpdate: result.xpUpdate,
      message: result.message,
    );
  }

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CompleteRunResult> loadLatestCompletionResult() {
    throw UnimplementedError();
  }

  @override
  Future<RunActivityReadModel> loadLatestRunActivity() {
    throw UnimplementedError();
  }

  @override
  Future<RunSummaryReadModel> loadLatestRunSummary() {
    throw UnimplementedError();
  }
}

class _DelayedRecordingRunRepository extends _RecordingRunRepository {
  final Completer<void> _completeRun = Completer<void>();

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    completedClientRunSessionIds.add(payload.clientRunSessionId);
    await _completeRun.future;
    final result = _completionResult(payload.clientRunSessionId);
    return CompleteRunResult(
      clientRunSessionId: result.clientRunSessionId,
      activityId: 'activity_${payload.clientRunSessionId}',
      summaryId: 'summary_${payload.clientRunSessionId}',
      progressionEventId: 'progression_${payload.clientRunSessionId}',
      validationStatus: result.validationStatus,
      summary: result.summary,
      progressionDisplay: result.progressionDisplay,
      xpUpdate: result.xpUpdate,
      message: result.message,
    );
  }

  void complete() {
    if (!_completeRun.isCompleted) {
      _completeRun.complete();
    }
  }
}

class _RejectingRunRepository extends _RecordingRunRepository {
  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    completedClientRunSessionIds.add(payload.clientRunSessionId);
    throw StateError('repository unavailable');
  }
}

class _LocalResultRunRepository extends _RecordingRunRepository {
  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    completedClientRunSessionIds.add(payload.clientRunSessionId);
    return _completionResult(payload.clientRunSessionId);
  }
}

class _RunCompletionErrorRepository extends _RecordingRunRepository {
  _RunCompletionErrorRepository({
    required this.code,
    required this.message,
    required this.isRetryable,
  });

  final String code;
  final String message;
  final bool isRetryable;

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    completedClientRunSessionIds.add(payload.clientRunSessionId);
    throw RunCompletionException(
      code: code,
      message: message,
      isRetryable: isRetryable,
    );
  }
}

class _FailingSavePendingRunActivityStore
    implements LocalPendingRunActivityStore {
  @override
  Future<List<LocalPendingRunActivity>> load() async {
    return const <LocalPendingRunActivity>[];
  }

  @override
  Future<void> save(List<LocalPendingRunActivity> activities) {
    throw StateError('local storage unavailable');
  }
}

class _FailOnDemandPendingRunActivityStore
    implements LocalPendingRunActivityStore {
  List<LocalPendingRunActivity> _activities = const <LocalPendingRunActivity>[];
  bool failNextSave = false;

  @override
  Future<List<LocalPendingRunActivity>> load() async {
    return List<LocalPendingRunActivity>.of(_activities);
  }

  @override
  Future<void> save(List<LocalPendingRunActivity> activities) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('accept persistence unavailable');
    }
    _activities = List<LocalPendingRunActivity>.of(activities);
  }
}

class _DelayedLoadPendingRunActivityStore
    implements LocalPendingRunActivityStore {
  _DelayedLoadPendingRunActivityStore(this._activities);

  final List<LocalPendingRunActivity> _activities;
  final Completer<void> _loadCompleter = Completer<void>();

  @override
  Future<List<LocalPendingRunActivity>> load() async {
    await _loadCompleter.future;
    return List<LocalPendingRunActivity>.of(_activities);
  }

  @override
  Future<void> save(List<LocalPendingRunActivity> activities) async {}

  void completeLoad() {
    if (!_loadCompleter.isCompleted) {
      _loadCompleter.complete();
    }
  }
}

class _DelayedSavePendingRunActivityStore
    implements LocalPendingRunActivityStore {
  final Completer<void> _saveCompleter = Completer<void>();
  List<LocalPendingRunActivity> _activities = const <LocalPendingRunActivity>[];

  @override
  Future<List<LocalPendingRunActivity>> load() async {
    return List<LocalPendingRunActivity>.of(_activities);
  }

  @override
  Future<void> save(List<LocalPendingRunActivity> activities) async {
    await _saveCompleter.future;
    _activities = List<LocalPendingRunActivity>.of(activities);
  }

  void completeSave() {
    if (!_saveCompleter.isCompleted) {
      _saveCompleter.complete();
    }
  }
}
