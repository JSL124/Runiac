// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../../run/domain/models/complete_run_result.dart';
import '../../run/domain/models/local_run_completion_payload.dart';
import '../../run/domain/models/run_activity_display_model.dart';
import '../../run/domain/models/run_feed_publish_source.dart';
import '../../run/domain/models/run_completion_error.dart';
import '../../run/domain/models/run_summary_snapshot.dart';
import '../../run/domain/repositories/run_repository.dart';
import '../data/local_pending_run_activity_store.dart';
import '../domain/models/user_progress_read_model.dart';
import 'data/activity_history_demo_snapshots.dart';

part 'current_session_activity_history_persistence.dart';
part 'current_session_activity_history_queries.dart';

class SessionCompletedRunActivity {
  const SessionCompletedRunActivity({
    required this.activityId,
    this.ownerUid,
    this.planEnrollmentId,
    this.scheduledWorkoutId,
    required this.display,
    required this.completionResult,
  });

  final String activityId;
  final String? ownerUid;
  final String? planEnrollmentId;
  final String? scheduledWorkoutId;
  final RunActivityDisplayModel display;
  final CompleteRunResult completionResult;
}

class RunSyncDebugSnapshot {
  const RunSyncDebugSnapshot({
    required this.ownerUid,
    required this.clientRunSessionId,
    required this.syncState,
    required this.syncAccepted,
    required this.syncAttemptCount,
    this.activityId,
    this.lastSyncAttemptedAt,
    this.lastSyncFailureCode,
    this.lastSyncFailureMessage,
  });

  final String ownerUid;
  final String clientRunSessionId;
  final RunSyncState syncState;
  final bool syncAccepted;
  final int syncAttemptCount;
  final String? activityId;
  final DateTime? lastSyncAttemptedAt;
  final String? lastSyncFailureCode;
  final String? lastSyncFailureMessage;
}

class RunCompletionContext {
  const RunCompletionContext._(this._ownerUid, this._ownerGeneration);

  final String _ownerUid;
  final int _ownerGeneration;
}

class CurrentSessionActivityHistoryStore extends ChangeNotifier {
  CurrentSessionActivityHistoryStore({
    DateTime Function()? now,
    String? ownerUid,
    this.persistence,
    this.onRemoteRunSynced,
  }) : _now = now ?? DateTime.now,
       _ownerUid = ownerUid;

  final DateTime Function() _now;
  final LocalPendingRunActivityStore? persistence;
  final Future<UserProgressReadModel> Function()? onRemoteRunSynced;
  final List<SessionCompletedRunActivity> _activities =
      <SessionCompletedRunActivity>[];
  final List<RunSyncDebugSnapshot> _syncDebugSnapshots =
      <RunSyncDebugSnapshot>[];
  Future<void> _pendingStorageMutation = Future<void>.value();
  Future<void>? _pendingSync;
  String? _ownerUid;
  var _ownerGeneration = 0;
  var _syncRequestSerial = 0;
  var _userProgressRefreshRevision = 0;
  UserProgressReadModel? _latestUserProgressRefresh;

  UnmodifiableListView<SessionCompletedRunActivity> get activities {
    return UnmodifiableListView(_activities);
  }

  Set<String> get completedScheduledWorkoutIds {
    return Set.unmodifiable(
      _activities
          .map((activity) => activity.scheduledWorkoutId)
          .whereType<String>()
          .where((value) => value.isNotEmpty),
    );
  }

  Set<String> completedScheduledWorkoutIdsForPlan(String planEnrollmentId) {
    if (planEnrollmentId.isEmpty) {
      return const <String>{};
    }
    return Set.unmodifiable(
      _activities
          .where((activity) => activity.planEnrollmentId == planEnrollmentId)
          .map((activity) => activity.scheduledWorkoutId)
          .whereType<String>()
          .where((value) => value.isNotEmpty),
    );
  }

  String? get ownerUid => _ownerUid;

  UnmodifiableListView<RunSyncDebugSnapshot> get syncDebugSnapshots {
    return UnmodifiableListView(_syncDebugSnapshots);
  }

  int get userProgressRefreshRevision => _userProgressRefreshRevision;

  UserProgressReadModel? get latestUserProgressRefresh {
    return _latestUserProgressRefresh;
  }

  void recordUserProgressRefresh(UserProgressReadModel progress) {
    _notifyUserProgressRefreshed(progress);
  }

  void updateOwnerUid(String? ownerUid) {
    if (_ownerUid == ownerUid) {
      return;
    }
    _ownerUid = ownerUid;
    _ownerGeneration += 1;
    final hadState = _activities.isNotEmpty || _syncDebugSnapshots.isNotEmpty;
    _latestUserProgressRefresh = null;
    _userProgressRefreshRevision += 1;
    if (hadState) {
      _activities.clear();
      _syncDebugSnapshots.clear();
    }
    notifyListeners();
  }

  RunCompletionContext captureRunCompletionContext() {
    return RunCompletionContext._(_requireOwnerUid(), _ownerGeneration);
  }

  bool isRunCompletionContextCurrent(RunCompletionContext context) {
    return _ownerUid == context._ownerUid &&
        _ownerGeneration == context._ownerGeneration;
  }

  void registerCompletedRun(
    CompleteRunResult result, {
    String? ownerUid,
    int? distanceMeters,
    String? planEnrollmentId,
    String? scheduledWorkoutId,
  }) {
    final activity = SessionCompletedRunActivity(
      activityId: result.activityId,
      ownerUid: ownerUid ?? _ownerUid,
      planEnrollmentId: planEnrollmentId,
      scheduledWorkoutId: scheduledWorkoutId,
      display: RunActivityDisplayModel(
        activityId: result.activityId,
        clientRunSessionId: result.clientRunSessionId,
        title: result.summary.title,
        timeAgoLabel: result.summary.dateTimeLabel,
        distanceLabel: '${result.summary.distanceKm} km',
        distanceMeters: distanceMeters ?? _distanceMetersFor(result),
        paceLabel: result.summary.avgPace,
        durationLabel: result.summary.duration,
        summary: result.summary,
        completionResult: result,
        feedPublishSource: _feedPublishSourceForCompletion(result),
      ),
      completionResult: result,
    );

    _activities.removeWhere((item) => item.activityId == activity.activityId);
    _activities.insert(0, activity);
    notifyListeners();
  }

  Future<void> saveCompletedRun(
    CompleteRunResult result, {
    required LocalRunCompletionPayload payload,
  }) async {
    final ownerUid = _requireOwnerUid();
    final ownerGeneration = _ownerGeneration;
    final record = LocalPendingRunActivity.fromCompletedRun(
      ownerUid: ownerUid,
      result: result,
      payload: payload,
    );
    final storage = persistence;
    if (storage == null) {
      if (_ownerUid != ownerUid || _ownerGeneration != ownerGeneration) {
        return;
      }
      registerCompletedRun(
        record.result,
        ownerUid: record.ownerUid,
        distanceMeters: record.payload.distanceMeters,
      );
      return;
    }

    try {
      await _enqueueStorageMutation(() async {
        final existing = await storage.load();
        final next = <LocalPendingRunActivity>[
          record,
          for (final activity in existing)
            if (activity.ownerUid != record.ownerUid ||
                activity.clientRunSessionId != record.clientRunSessionId)
              activity,
        ];
        await storage.save(next);
      });
      if (_ownerUid != ownerUid || _ownerGeneration != ownerGeneration) {
        return;
      }
      _upsertSyncDebugSnapshot(record);
      registerCompletedRun(
        record.result,
        ownerUid: record.ownerUid,
        distanceMeters: record.payload.distanceMeters,
      );
    } catch (error, stackTrace) {
      _reportAsyncError(
        error,
        stackTrace,
        'saving a completed run locally',
        runSessionId: record.clientRunSessionId,
      );
      rethrow;
    }
  }

  int _distanceMetersFor(CompleteRunResult result) {
    final kilometers = double.tryParse(result.summary.distanceKm);
    if (kilometers == null || !kilometers.isFinite) {
      return 0;
    }
    return (kilometers * 1000).round();
  }

  String _requireOwnerUid() {
    final ownerUid = _ownerUid;
    if (ownerUid == null || ownerUid.isEmpty) {
      throw StateError('Cannot persist a run without an authenticated owner.');
    }
    return ownerUid;
  }

  bool _looksLikeRemoteCompletion(CompleteRunResult result) {
    return RunFeedPublishSource.isCanonicalValidatedCompletion(result);
  }

  RunFeedPublishSource _feedPublishSourceForCompletion(
    CompleteRunResult result,
  ) {
    return RunFeedPublishSource.fromCompletion(result);
  }

  Future<T> _enqueueStorageMutation<T>(Future<T> Function() action) {
    final run = _pendingStorageMutation.then(
      (_) => action(),
      onError: (Object _, StackTrace _) => action(),
    );
    _pendingStorageMutation = run.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return run;
  }

  /// Reports a non-fatal persistence failure, tagged with [runSessionId] when
  /// the failure belongs to one identifiable run, so it lines up with the
  /// `runiac run tracking` reports the completion flow emits for that same
  /// run. The id is the one already sent to the backend as
  /// `clientRunSessionId`; no coordinate, token, or account value is included.
  ///
  /// [runSessionId] is deliberately optional: the batch paths here (loading
  /// the pending queue, reconciling against remote, refreshing progress after
  /// a sync) span many runs or none, and inventing an id for them would
  /// suggest a correlation that does not exist.
  void _reportAsyncError(
    Object error,
    StackTrace stackTrace,
    String operation, {
    String? runSessionId,
  }) {
    try {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac activity history',
          context: ErrorDescription(
            runSessionId == null
                ? operation
                : '$operation (runSessionId=$runSessionId)',
          ),
        ),
      );
    } catch (_) {
      // Best effort, like the completion coordinator's reporter: a failing
      // diagnostic sink must not decide whether a run persists. Several call
      // sites `rethrow` right after this, and that rethrow must carry the
      // real persistence error, not a reporting one.
    }
  }

  void _notifyActivityHistoryChanged() {
    notifyListeners();
  }

  void _notifyUserProgressRefreshed(UserProgressReadModel progress) {
    _latestUserProgressRefresh = progress;
    _userProgressRefreshRevision += 1;
    notifyListeners();
  }

  void _upsertSyncDebugSnapshot(LocalPendingRunActivity record) {
    final snapshot = RunSyncDebugSnapshot(
      ownerUid: record.ownerUid,
      clientRunSessionId: record.clientRunSessionId,
      syncState: record.syncState,
      syncAccepted: record.syncAccepted,
      syncAttemptCount: record.syncAttemptCount,
      activityId: record.result.activityId,
      lastSyncAttemptedAt: record.lastSyncAttemptedAt,
      lastSyncFailureCode: record.lastSyncFailureCode,
      lastSyncFailureMessage: record.lastSyncFailureMessage,
    );
    _syncDebugSnapshots.removeWhere(
      (item) =>
          item.ownerUid == snapshot.ownerUid &&
          item.clientRunSessionId == snapshot.clientRunSessionId,
    );
    _syncDebugSnapshots.insert(0, snapshot);
    assert(() {
      debugPrint(
        'Runiac run sync ${snapshot.clientRunSessionId}: '
        '${snapshot.syncState.name}'
        '${snapshot.lastSyncFailureCode == null ? '' : ' '
                  '(${snapshot.lastSyncFailureCode})'}',
      );
      return true;
    }());
  }
}

class CurrentSessionActivityHistoryScope
    extends InheritedNotifier<CurrentSessionActivityHistoryStore> {
  const CurrentSessionActivityHistoryScope({
    required CurrentSessionActivityHistoryStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static CurrentSessionActivityHistoryStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<
          CurrentSessionActivityHistoryScope
        >()
        ?.notifier;
  }

  static CurrentSessionActivityHistoryStore? maybeRead(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<CurrentSessionActivityHistoryScope>()
        ?.notifier;
  }

  static CurrentSessionActivityHistoryStore of(BuildContext context) {
    final store = maybeOf(context);
    assert(store != null, 'No CurrentSessionActivityHistoryScope found.');
    return store!;
  }
}
