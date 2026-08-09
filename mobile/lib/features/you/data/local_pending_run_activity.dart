part of 'local_pending_run_activity_store.dart';

enum RunSyncState {
  localSaved,
  pendingSync,
  syncDeferred,
  syncAccepted,
  syncRetryableFailure,
  syncNonRetryableFailure,
}

class LocalPendingRunActivity {
  const LocalPendingRunActivity({
    required this.ownerUid,
    required this.clientRunSessionId,
    required this.result,
    required this.payload,
    this.syncAccepted = false,
    RunSyncState? syncState,
    this.syncAttemptCount = 0,
    this.lastSyncAttemptedAt,
    this.lastSyncFailureCode,
    this.lastSyncFailureMessage,
  }) : syncState =
           syncState ??
           (syncAccepted ? RunSyncState.syncAccepted : RunSyncState.localSaved);

  factory LocalPendingRunActivity.fromCompletedRun({
    required String ownerUid,
    required CompleteRunResult result,
    required LocalRunCompletionPayload payload,
  }) {
    return LocalPendingRunActivity(
      ownerUid: ownerUid,
      clientRunSessionId: payload.clientRunSessionId,
      result: result.copyWith(clientRunSessionId: payload.clientRunSessionId),
      payload: payload,
    );
  }

  final String ownerUid;
  final String clientRunSessionId;
  final CompleteRunResult result;
  final LocalRunCompletionPayload payload;
  final bool syncAccepted;
  final RunSyncState syncState;
  final int syncAttemptCount;
  final DateTime? lastSyncAttemptedAt;
  final String? lastSyncFailureCode;
  final String? lastSyncFailureMessage;

  bool get shouldAttemptSync {
    return !syncAccepted &&
        syncState != RunSyncState.syncDeferred &&
        syncState != RunSyncState.syncNonRetryableFailure;
  }

  LocalPendingRunActivity copyWith({
    CompleteRunResult? result,
    bool? syncAccepted,
    RunSyncState? syncState,
    int? syncAttemptCount,
  }) {
    return LocalPendingRunActivity(
      ownerUid: ownerUid,
      clientRunSessionId: clientRunSessionId,
      result: result ?? this.result,
      payload: payload,
      syncAccepted: syncAccepted ?? this.syncAccepted,
      syncState: syncState ?? this.syncState,
      syncAttemptCount: syncAttemptCount ?? this.syncAttemptCount,
      lastSyncAttemptedAt: lastSyncAttemptedAt,
      lastSyncFailureCode: lastSyncFailureCode,
      lastSyncFailureMessage: lastSyncFailureMessage,
    );
  }

  LocalPendingRunActivity markPendingSync(DateTime attemptedAt) {
    return LocalPendingRunActivity(
      ownerUid: ownerUid,
      clientRunSessionId: clientRunSessionId,
      result: result,
      payload: payload,
      syncAccepted: false,
      syncState: RunSyncState.pendingSync,
      syncAttemptCount: syncAttemptCount + 1,
      lastSyncAttemptedAt: attemptedAt,
    );
  }

  LocalPendingRunActivity markSyncFailure({
    required String code,
    required String message,
    required bool isRetryable,
  }) {
    return LocalPendingRunActivity(
      ownerUid: ownerUid,
      clientRunSessionId: clientRunSessionId,
      result: result,
      payload: payload,
      syncAccepted: false,
      syncState: isRetryable
          ? RunSyncState.syncRetryableFailure
          : RunSyncState.syncNonRetryableFailure,
      syncAttemptCount: syncAttemptCount,
      lastSyncAttemptedAt: lastSyncAttemptedAt,
      lastSyncFailureCode: code,
      lastSyncFailureMessage: message,
    );
  }

  LocalPendingRunActivity markSyncDeferred() {
    return LocalPendingRunActivity(
      ownerUid: ownerUid,
      clientRunSessionId: clientRunSessionId,
      result: result,
      payload: payload,
      syncAccepted: false,
      syncState: RunSyncState.syncDeferred,
      syncAttemptCount: syncAttemptCount,
      lastSyncAttemptedAt: lastSyncAttemptedAt,
    );
  }

  LocalPendingRunActivity mergeRemoteCompletion(
    CompleteRunResult remoteResult, {
    bool? syncAccepted,
  }) {
    return copyWith(
      result: result.copyWith(
        clientRunSessionId: clientRunSessionId,
        activityId: remoteResult.activityId,
        summaryId: remoteResult.summaryId,
        progressionEventId: remoteResult.progressionEventId,
        validationStatus: remoteResult.validationStatus,
        progressionDisplay: remoteResult.progressionDisplay,
        planCompletion: remoteResult.planCompletion,
        xpUpdate: remoteResult.xpUpdate,
        message: remoteResult.message,
      ),
      syncAccepted: syncAccepted,
      syncState: syncAccepted == true ? RunSyncState.syncAccepted : syncState,
      syncAttemptCount: syncAttemptCount,
    );
  }

  String encode() => jsonEncode(_localPendingRunActivityToJson(this));

  static LocalPendingRunActivity? tryDecode(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return _localPendingRunActivityFromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
