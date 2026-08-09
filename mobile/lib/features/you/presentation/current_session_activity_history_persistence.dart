part of 'current_session_activity_history.dart';

/// Keeps the activity history correct when a finished run cannot reach the
/// backend.
///
/// A run is saved locally the moment it ends, then synced. If the sync fails the
/// run must still appear in the history — losing it is the worst outcome — so
/// this extension records the failure, keeps the local copy, and retries later.
///
/// [isRunCompletionContextCurrent] guards every write: by the time a slow sync
/// returns, the user may have signed out or started another run, and applying a
/// stale result would corrupt the history that is now on screen.
extension CurrentSessionActivityHistoryPersistence
    on CurrentSessionActivityHistoryStore {
  Future<void> recordForegroundRunSyncFailure({
    required LocalRunCompletionPayload payload,
    required RunCompletionContext completionContext,
    required Object error,
  }) async {
    if (!isRunCompletionContextCurrent(completionContext)) {
      return;
    }
    final storage = persistence;
    if (storage == null) {
      return;
    }
    final failure = _classifySyncFailure(error);
    await _markPendingRunSyncFailed(
      storage: storage,
      ownerUid: completionContext._ownerUid,
      clientRunSessionId: payload.clientRunSessionId,
      failure: failure,
    );
  }

  Future<CompleteRunResult?> acceptForegroundCompletion(
    CompleteRunResult remoteResult, {
    required LocalRunCompletionPayload payload,
    required RunCompletionContext completionContext,
  }) async {
    if (!isRunCompletionContextCurrent(completionContext) ||
        !_looksLikeRemoteCompletion(remoteResult)) {
      return null;
    }
    final ownerUid = completionContext._ownerUid;
    final ownerGeneration = completionContext._ownerGeneration;
    final storage = persistence;
    if (storage == null) {
      registerCompletedRun(
        remoteResult,
        ownerUid: ownerUid,
        distanceMeters: payload.distanceMeters,
        planEnrollmentId: remoteResult.planCompletion.completed
            ? remoteResult.planCompletion.planEnrollmentId
            : null,
        scheduledWorkoutId: remoteResult.planCompletion.completed
            ? remoteResult.planCompletion.scheduledWorkoutId
            : null,
      );
      return remoteResult;
    }

    final acceptedRecord = await _mergePendingRunSyncAccepted(
      storage: storage,
      ownerUid: ownerUid,
      clientRunSessionId: payload.clientRunSessionId,
      remoteResult: remoteResult,
    );
    if (acceptedRecord == null ||
        !isRunCompletionContextCurrent(completionContext)) {
      return null;
    }

    _replaceCompletedRun(
      acceptedRecord.result,
      ownerUid: ownerUid,
      distanceMeters: acceptedRecord.payload.distanceMeters,
      planEnrollmentId: acceptedRecord.result.planCompletion.completed
          ? acceptedRecord.result.planCompletion.planEnrollmentId
          : null,
      scheduledWorkoutId: acceptedRecord.result.planCompletion.completed
          ? acceptedRecord.result.planCompletion.scheduledWorkoutId
          : null,
    );
    if (!acceptedRecord.payload.userConfirmedLowDataSave) {
      await _refreshUserProgressAfterRemoteSync(
        ownerUid: ownerUid,
        ownerGeneration: ownerGeneration,
      );
    }
    return acceptedRecord.result;
  }

  Future<void> restoreSavedActivities() async {
    final storage = persistence;
    if (storage == null) {
      return;
    }
    final ownerUid = _ownerUid;
    if (ownerUid == null) {
      return;
    }
    final ownerGeneration = _ownerGeneration;

    final records = await _enqueueStorageMutation(
      () => _loadPendingActivities(storage),
    );
    if (_ownerUid != ownerUid || _ownerGeneration != ownerGeneration) {
      return;
    }
    for (final record in records.reversed.where(
      (record) => record.ownerUid == ownerUid,
    )) {
      if (_ownerUid != ownerUid || _ownerGeneration != ownerGeneration) {
        return;
      }
      _upsertSyncDebugSnapshot(record);
      registerCompletedRun(
        record.result,
        ownerUid: record.ownerUid,
        distanceMeters: record.payload.distanceMeters,
        planEnrollmentId: record.result.planCompletion.completed
            ? record.result.planCompletion.planEnrollmentId
            : null,
        scheduledWorkoutId: record.result.planCompletion.completed
            ? record.result.planCompletion.scheduledWorkoutId
            : null,
      );
    }
  }

  Future<void> syncPendingRuns(RunRepository repository) async {
    _syncRequestSerial += 1;
    final activeSync = _pendingSync;
    if (activeSync != null) {
      return activeSync;
    }

    final sync = _drainPendingSyncRequests(repository);
    late final Future<void> trackedSync;
    trackedSync = sync.whenComplete(() {
      if (identical(_pendingSync, trackedSync)) {
        _pendingSync = null;
      }
    });
    _pendingSync = trackedSync;
    return trackedSync;
  }

  Future<void> _drainPendingSyncRequests(RunRepository repository) async {
    var completedSerial = 0;
    while (completedSerial != _syncRequestSerial) {
      completedSerial = _syncRequestSerial;
      await _syncPendingRuns(repository);
    }
  }

  Future<void> _syncPendingRuns(RunRepository repository) async {
    final storage = persistence;
    if (storage == null) {
      return;
    }
    final ownerUid = _ownerUid;
    if (ownerUid == null) {
      return;
    }
    final ownerGeneration = _ownerGeneration;

    final records = await _enqueueStorageMutation(
      () => _loadPendingActivities(storage),
    );
    if (_ownerUid != ownerUid || _ownerGeneration != ownerGeneration) {
      return;
    }
    final pendingRecords = records
        .where(
          (record) => record.ownerUid == ownerUid && record.shouldAttemptSync,
        )
        .toList(growable: false);

    for (final record in pendingRecords) {
      CompleteRunResult syncedResult;
      LocalPendingRunActivity syncingRecord;
      try {
        if (_ownerUid != ownerUid || _ownerGeneration != ownerGeneration) {
          return;
        }
        final markedRecord = await _markPendingRunSyncStarted(
          storage: storage,
          ownerUid: ownerUid,
          clientRunSessionId: record.clientRunSessionId,
        );
        if (markedRecord == null) {
          continue;
        }
        syncingRecord = markedRecord;
        if (_ownerUid != ownerUid || _ownerGeneration != ownerGeneration) {
          return;
        }
        syncedResult = await repository.completeRun(syncingRecord.payload);
      } catch (error, stackTrace) {
        final failure = _classifySyncFailure(error);
        await _markPendingRunSyncFailed(
          storage: storage,
          ownerUid: ownerUid,
          clientRunSessionId: record.clientRunSessionId,
          failure: failure,
        );
        _reportAsyncError(
          StateError('${failure.message} (${failure.code})'),
          stackTrace,
          'syncing a pending run',
          runSessionId: record.clientRunSessionId,
        );
        return;
      }
      if (_ownerUid != ownerUid || _ownerGeneration != ownerGeneration) {
        return;
      }
      if (!_looksLikeRemoteCompletion(syncedResult)) {
        await _markPendingRunSyncDeferred(
          storage: storage,
          ownerUid: ownerUid,
          clientRunSessionId: record.clientRunSessionId,
        );
        continue;
      }
      try {
        final syncedRecord = await _mergePendingRunSyncAccepted(
          storage: storage,
          ownerUid: ownerUid,
          clientRunSessionId: record.clientRunSessionId,
          remoteResult: syncedResult,
        );
        if (syncedRecord != null &&
            _ownerUid == ownerUid &&
            _ownerGeneration == ownerGeneration) {
          _replaceCompletedRun(
            syncedRecord.result,
            ownerUid: ownerUid,
            distanceMeters: syncedRecord.payload.distanceMeters,
            planEnrollmentId: syncedRecord.result.planCompletion.completed
                ? syncedRecord.result.planCompletion.planEnrollmentId
                : null,
            scheduledWorkoutId: syncedRecord.result.planCompletion.completed
                ? syncedRecord.result.planCompletion.scheduledWorkoutId
                : null,
          );
          if (!syncedRecord.payload.userConfirmedLowDataSave) {
            await _refreshUserProgressAfterRemoteSync(
              ownerUid: ownerUid,
              ownerGeneration: ownerGeneration,
            );
          }
        }
      } catch (error, stackTrace) {
        _reportAsyncError(
          error,
          stackTrace,
          'saving pending run sync state',
          runSessionId: record.clientRunSessionId,
        );
        return;
      }
    }
  }

  Future<void> _refreshUserProgressAfterRemoteSync({
    required String ownerUid,
    required int ownerGeneration,
  }) async {
    final refresh = onRemoteRunSynced;
    if (refresh == null) {
      return;
    }
    try {
      final progress = await refresh();
      if (_ownerUid != ownerUid || _ownerGeneration != ownerGeneration) {
        return;
      }
      _notifyUserProgressRefreshed(progress);
    } catch (error, stackTrace) {
      _reportAsyncError(
        error,
        stackTrace,
        'refreshing user progress after sync',
      );
    }
  }

  void reconcileWithRemote(Iterable<RunActivityDisplayModel> remoteActivities) {
    final remoteByClientRunSessionId = <String, RunActivityDisplayModel>{
      for (final activity in remoteActivities)
        if (activity.clientRunSessionId != null &&
            activity.clientRunSessionId!.isNotEmpty)
          activity.clientRunSessionId!: activity,
    };
    final remoteClientRunSessionIds = remoteByClientRunSessionId.keys.toSet();
    final remoteActivityIds = remoteActivities
        .map((activity) => activity.activityId)
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();
    if (remoteClientRunSessionIds.isEmpty && remoteActivityIds.isEmpty) {
      return;
    }

    var changed = false;
    final nextActivities = <SessionCompletedRunActivity>[];
    for (final activity in _activities) {
      final clientRunSessionId = activity.completionResult.clientRunSessionId;
      final remoteActivity = clientRunSessionId == null
          ? null
          : remoteByClientRunSessionId[clientRunSessionId];
      final hasRemoteMatch =
          remoteActivity != null ||
          remoteActivityIds.contains(activity.activityId);
      if (!hasRemoteMatch) {
        nextActivities.add(activity);
        continue;
      }
      if (_hasLocalOnlySnapshot(activity)) {
        final mergedActivity = remoteActivity == null
            ? activity
            : _mergeRemoteActivityIdentity(activity, remoteActivity);
        if (!identical(mergedActivity, activity)) {
          changed = true;
        }
        nextActivities.add(mergedActivity);
        continue;
      }
      changed = true;
    }
    if (changed) {
      _activities
        ..clear()
        ..addAll(nextActivities);
      _notifyActivityHistoryChanged();
      unawaited(
        _persistCurrentPendingActivities().catchError(
          (Object error, StackTrace stackTrace) => _reportAsyncError(
            error,
            stackTrace,
            'persisting reconciled run activities',
          ),
        ),
      );
    }
  }

  bool _hasLocalOnlySnapshot(SessionCompletedRunActivity activity) {
    final summary = activity.display.summary;
    return summary.route.hasRoute ||
        summary.paceGraph.isAvailable ||
        (summary.paceAnalysisSeries != null &&
            !summary.paceAnalysisSeries!.isUnavailable) ||
        (summary.cadenceAnalysisSeries != null &&
            !summary.cadenceAnalysisSeries!.isUnavailable) ||
        !summary.elevationSeries.isUnavailable;
  }

  Future<List<LocalPendingRunActivity>> _loadPendingActivities(
    LocalPendingRunActivityStore storage,
  ) async {
    try {
      return await storage.load();
    } catch (error, stackTrace) {
      _reportAsyncError(error, stackTrace, 'loading pending run activities');
      return const <LocalPendingRunActivity>[];
    }
  }

  Future<void> _persistCurrentPendingActivities() async {
    final storage = persistence;
    if (storage == null) {
      return;
    }
    final ownerUid = _ownerUid;
    if (ownerUid == null) {
      return;
    }

    await _enqueueStorageMutation(() async {
      final activitiesByClientRunSessionId =
          <String, SessionCompletedRunActivity>{
            for (final activity in _activities)
              if (activity.ownerUid == ownerUid &&
                  activity.completionResult.clientRunSessionId != null &&
                  activity.completionResult.clientRunSessionId!.isNotEmpty)
                activity.completionResult.clientRunSessionId!: activity,
          };
      final saved = await storage.load();
      final kept = <LocalPendingRunActivity>[
        for (final record in saved)
          if (record.ownerUid != ownerUid)
            record
          else if (activitiesByClientRunSessionId.containsKey(
            record.clientRunSessionId,
          ))
            record.copyWith(
              result: activitiesByClientRunSessionId[record.clientRunSessionId]!
                  .completionResult,
            ),
      ];
      await storage.save(kept);
    });
  }

  Future<LocalPendingRunActivity?> _mergePendingRunSyncAccepted({
    required LocalPendingRunActivityStore storage,
    required String ownerUid,
    required String clientRunSessionId,
    required CompleteRunResult remoteResult,
  }) {
    return _enqueueStorageMutation(() async {
      final saved = await storage.load();
      LocalPendingRunActivity? mergedRecord;
      final next = <LocalPendingRunActivity>[
        for (final record in saved)
          if (record.ownerUid == ownerUid &&
              record.clientRunSessionId == clientRunSessionId)
            mergedRecord = record.mergeRemoteCompletion(
              remoteResult,
              syncAccepted: true,
            )
          else
            record,
      ];
      if (mergedRecord != null) {
        await storage.save(next);
        _upsertSyncDebugSnapshot(mergedRecord);
      }
      return mergedRecord;
    });
  }

  Future<LocalPendingRunActivity?> _markPendingRunSyncStarted({
    required LocalPendingRunActivityStore storage,
    required String ownerUid,
    required String clientRunSessionId,
  }) {
    return _enqueueStorageMutation(() async {
      final saved = await storage.load();
      LocalPendingRunActivity? updatedRecord;
      final next = <LocalPendingRunActivity>[
        for (final record in saved)
          if (record.ownerUid == ownerUid &&
              record.clientRunSessionId == clientRunSessionId)
            updatedRecord = record.markPendingSync(_now().toUtc())
          else
            record,
      ];
      if (updatedRecord != null) {
        await storage.save(next);
        _upsertSyncDebugSnapshot(updatedRecord);
      }
      return updatedRecord;
    });
  }

  Future<LocalPendingRunActivity?> _markPendingRunSyncFailed({
    required LocalPendingRunActivityStore storage,
    required String ownerUid,
    required String clientRunSessionId,
    required _RunSyncFailure failure,
  }) {
    return _enqueueStorageMutation(() async {
      final saved = await storage.load();
      LocalPendingRunActivity? updatedRecord;
      final next = <LocalPendingRunActivity>[
        for (final record in saved)
          if (record.ownerUid == ownerUid &&
              record.clientRunSessionId == clientRunSessionId)
            updatedRecord = record.markSyncFailure(
              code: failure.code,
              message: failure.message,
              isRetryable: failure.isRetryable,
            )
          else
            record,
      ];
      if (updatedRecord != null) {
        await storage.save(next);
        _upsertSyncDebugSnapshot(updatedRecord);
      }
      return updatedRecord;
    });
  }

  Future<LocalPendingRunActivity?> _markPendingRunSyncDeferred({
    required LocalPendingRunActivityStore storage,
    required String ownerUid,
    required String clientRunSessionId,
  }) {
    return _enqueueStorageMutation(() async {
      final saved = await storage.load();
      LocalPendingRunActivity? updatedRecord;
      final next = <LocalPendingRunActivity>[
        for (final record in saved)
          if (record.ownerUid == ownerUid &&
              record.clientRunSessionId == clientRunSessionId)
            updatedRecord = record.markSyncDeferred()
          else
            record,
      ];
      if (updatedRecord != null) {
        await storage.save(next);
        _upsertSyncDebugSnapshot(updatedRecord);
      }
      return updatedRecord;
    });
  }

  _RunSyncFailure _classifySyncFailure(Object error) {
    if (error is RunCompletionException) {
      return _RunSyncFailure(
        code: error.code,
        message: _safeSyncFailureMessage(error.code),
        isRetryable: error.isRetryable,
      );
    }
    return _RunSyncFailure(
      code: 'unknown',
      message: _safeSyncFailureMessage('unknown'),
      isRetryable: true,
    );
  }

  String _safeSyncFailureMessage(String code) {
    if (code == 'unknown') {
      return 'Run sync failed.';
    }
    return 'Run sync failed with $code.';
  }

  void _replaceCompletedRun(
    CompleteRunResult result, {
    String? ownerUid,
    int? distanceMeters,
    String? planEnrollmentId,
    String? scheduledWorkoutId,
  }) {
    final clientRunSessionId = result.clientRunSessionId;
    if (clientRunSessionId != null) {
      _activities.removeWhere(
        (activity) =>
            activity.ownerUid == (ownerUid ?? _ownerUid) &&
            activity.completionResult.clientRunSessionId == clientRunSessionId,
      );
    }
    registerCompletedRun(
      result,
      ownerUid: ownerUid,
      distanceMeters: distanceMeters,
      planEnrollmentId: planEnrollmentId,
      scheduledWorkoutId: scheduledWorkoutId,
    );
  }

  SessionCompletedRunActivity _mergeRemoteActivityIdentity(
    SessionCompletedRunActivity activity,
    RunActivityDisplayModel remoteActivity,
  ) {
    final result = activity.completionResult.copyWith(
      activityId: remoteActivity.activityId,
    );
    final remotePublishSource = remoteActivity.feedPublishSource;
    final feedPublishSource =
        result.activityId.startsWith('activity_') &&
            remotePublishSource.isPublishable &&
            remotePublishSource.activityId == result.activityId
        ? RunFeedPublishSource.enabled(
            activityId: result.activityId,
            cacheIdentity:
                remotePublishSource.cacheIdentity ?? result.clientRunSessionId,
            allowsCurrentSessionRouteCapture: true,
            allowsMetricThumbnailFallback:
                remotePublishSource.allowsMetricThumbnailFallback,
          )
        : RunFeedPublishSource.disabled(
            remotePublishSource.disabledReason ??
                FeedPublishDisabledReason.notValidated,
          );
    return SessionCompletedRunActivity(
      activityId: result.activityId,
      ownerUid: activity.ownerUid,
      planEnrollmentId: activity.planEnrollmentId,
      scheduledWorkoutId: activity.scheduledWorkoutId,
      display: RunActivityDisplayModel(
        activityId: result.activityId,
        clientRunSessionId: result.clientRunSessionId,
        title: result.summary.title,
        timeAgoLabel: result.summary.dateTimeLabel,
        distanceLabel: '${result.summary.distanceKm} km',
        distanceMeters: activity.display.distanceMeters,
        paceLabel: result.summary.avgPace,
        durationLabel: result.summary.duration,
        summary: result.summary,
        completionResult: result,
        feedPublishSource: feedPublishSource,
      ),
      completionResult: result,
    );
  }
}

class _RunSyncFailure {
  const _RunSyncFailure({
    required this.code,
    required this.message,
    required this.isRetryable,
  });

  final String code;
  final String message;
  final bool isRetryable;
}
