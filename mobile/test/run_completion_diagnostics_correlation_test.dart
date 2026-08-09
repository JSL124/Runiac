import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/domain/models/complete_run_result.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_read_model.dart';
import 'package:runiac_app/features/run/domain/repositories/run_repository.dart';
import 'package:runiac_app/features/run/presentation/run_completion_coordinator.dart';

/// A repository whose remote completion always fails, so the coordinator's
/// failure-reporting path is the one under test.
class _FailingRunRepository implements RunRepository {
  @override
  Future<CompleteRunResult> completeRun(LocalRunCompletionPayload payload) {
    throw StateError('remote completeRun refused the run');
  }

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CompleteRunResult> loadLatestCompletionResult() =>
      throw UnimplementedError();

  @override
  Future<RunActivityReadModel> loadLatestRunActivity() =>
      throw UnimplementedError();

  @override
  Future<RunSummaryReadModel> loadLatestRunSummary() =>
      throw UnimplementedError();
}

LocalRunCompletionPayload _payload(String clientRunSessionId) {
  return LocalRunCompletionPayload(
    clientRunSessionId: clientRunSessionId,
    startedAt: DateTime.utc(2026, 6, 14, 9),
    completedAt: DateTime.utc(2026, 6, 14, 9, 15),
    durationSeconds: 900,
    distanceMeters: 3000,
    avgPaceSecondsPerKm: 300,
    source: 'mobile',
    routePrivacy: 'private',
  );
}

void main() {
  group('run completion diagnostics', () {
    test('tags a completion failure with its run session id', () async {
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      final result = await const RunCompletionCoordinator().complete(
        repository: _FailingRunRepository(),
        payload: _payload('correlated-completion-run'),
      );

      // The run still falls back to the local result: diagnostics must not
      // change what the runner gets.
      expect(result.clientRunSessionId, 'correlated-completion-run');

      final runTrackingReports = reported
          .where((details) => details.library == 'runiac run tracking')
          .toList(growable: false);
      expect(runTrackingReports, isNotEmpty);

      for (final details in runTrackingReports) {
        final context = details.context.toString();
        // Every stage of one completion reports under the same correlation
        // key, so the flow can be followed end to end.
        expect(context, contains('runSessionId=correlated-completion-run'));
        // Diagnostics stay scalar.
        expect(context, isNot(contains('latitude')));
        expect(context, isNot(contains('longitude')));
      }

      expect(
        runTrackingReports.map((details) => details.context.toString()),
        anyElement(contains('completing a run')),
      );
    });

    test('a failing diagnostic sink does not fail the run', () async {
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        throw StateError('diagnostic sink failed');
      };
      addTearDown(() => FlutterError.onError = previousOnError);

      // The coordinator still resolves to the local result rather than
      // letting the reporting failure escape as the run's outcome.
      final result = await const RunCompletionCoordinator().complete(
        repository: _FailingRunRepository(),
        payload: _payload('sink-failure-run'),
      );

      expect(result.clientRunSessionId, 'sink-failure-run');
    });
  });
}
