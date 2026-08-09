import 'package:flutter/foundation.dart';

import '../../you/presentation/current_session_activity_history.dart';
import '../data/static_run_repository.dart';
import '../domain/models/complete_run_result.dart';
import '../domain/models/local_run_completion_payload.dart';
import '../domain/repositories/run_repository.dart';
import '../domain/services/run_summary_local_analysis_merger.dart';

class RunCompletionCoordinator {
  const RunCompletionCoordinator();

  Future<CompleteRunResult> complete({
    required RunRepository repository,
    required LocalRunCompletionPayload payload,
    CurrentSessionActivityHistoryStore? activityHistoryStore,
  }) async {
    final localResult = _mergeLocalAnalysis(
      await const StaticRunRepository().completeRun(payload),
      payload,
    );
    if (!localResult.summary.hasSufficientData) {
      return localResult;
    }
    final store = activityHistoryStore;
    RunCompletionContext? completionContext;
    if (store != null) {
      try {
        completionContext = store.captureRunCompletionContext();
      } catch (error, stackTrace) {
        _report(
          error,
          stackTrace,
          'capturing run completion owner',
          runSessionId: payload.clientRunSessionId,
        );
      }
    }
    final shouldSaveLocally = store != null && completionContext != null;
    var didSaveLocally = false;

    if (shouldSaveLocally) {
      try {
        await store.saveCompletedRun(localResult, payload: payload);
        didSaveLocally = true;
      } catch (error, stackTrace) {
        _report(
          error,
          stackTrace,
          'saving a completed run locally',
          runSessionId: payload.clientRunSessionId,
        );
      }
    }

    try {
      final remoteResult = _mergeLocalAnalysis(
        await repository.completeRun(payload),
        payload,
      );
      if (store != null &&
          completionContext != null &&
          !store.isRunCompletionContextCurrent(completionContext)) {
        return localResult;
      }
      if (didSaveLocally) {
        try {
          final acceptedResult = await store!.acceptForegroundCompletion(
            remoteResult,
            payload: payload,
            completionContext: completionContext!,
          );
          return acceptedResult ?? localResult;
        } catch (error, stackTrace) {
          _report(
            error,
            stackTrace,
            'saving a completed run result',
            runSessionId: payload.clientRunSessionId,
          );
        }
      }
      return remoteResult;
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
        'completing a run',
        runSessionId: payload.clientRunSessionId,
      );
      if (didSaveLocally &&
          store != null &&
          completionContext != null &&
          store.isRunCompletionContextCurrent(completionContext)) {
        try {
          await store.recordForegroundRunSyncFailure(
            payload: payload,
            completionContext: completionContext,
            error: error,
          );
        } catch (persistenceError, persistenceStackTrace) {
          _report(
            persistenceError,
            persistenceStackTrace,
            'recording a run completion sync failure',
            runSessionId: payload.clientRunSessionId,
          );
        }
      }
      return localResult;
    }
  }

  CompleteRunResult _mergeLocalAnalysis(
    CompleteRunResult result,
    LocalRunCompletionPayload payload,
  ) {
    return result.copyWith(
      clientRunSessionId: payload.clientRunSessionId,
      summary: const RunSummaryLocalAnalysisMerger().merge(
        backendSummary: result.summary,
        localPayload: payload,
        localRoute: payload.routeSnapshot,
        resultClientRunSessionId: payload.clientRunSessionId,
      ),
    );
  }

  /// Reports a non-fatal failure in the completion flow, tagged with the run
  /// it belongs to.
  ///
  /// Every stage below — capturing the owner, the local save, the remote
  /// `completeRun`, the accepted-result merge, and the sync-failure record —
  /// reports under the same [runSessionId], so one run's completion can be
  /// followed end to end instead of appearing as unrelated errors. It is the
  /// same locally generated id already sent to the backend as
  /// `clientRunSessionId`, so tagging adds no new exposure; no coordinate,
  /// token, or account value goes into the context.
  /// Reporting is best effort and is swallowed: several of the call sites
  /// below are already handling a failed run, and letting the diagnostic path
  /// throw would escalate a recoverable completion failure into an unhandled
  /// one — losing the local result the runner is entitled to.
  void _report(
    Object error,
    StackTrace stackTrace,
    String operation, {
    required String runSessionId,
  }) {
    try {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac run tracking',
          context: ErrorDescription('$operation (runSessionId=$runSessionId)'),
        ),
      );
    } catch (_) {
      // Diagnostics must never change the run's outcome.
    }
  }
}
