import '../models/complete_run_result.dart';
import '../models/local_run_completion_payload.dart';
import '../models/run_activity_read_model.dart';
import '../models/run_summary_read_model.dart';

abstract interface class RunRepository {
  Future<RunSummaryReadModel> loadLatestRunSummary();

  Future<CompleteRunResult> loadLatestCompletionResult();

  Future<RunActivityReadModel> loadLatestRunActivity();

  Future<CompleteRunResult> completeRun(LocalRunCompletionPayload payload);

  /// Requests the server-computed cool-down stretch XP bonus after the user
  /// finishes all cool-down stretch steps. The client never calculates the
  /// bonus itself — it only relays [activityId] and [clientRunSessionId] and
  /// renders whatever the backend returns.
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  });
}
