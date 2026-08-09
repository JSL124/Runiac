import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_completion_request_adapter.dart';

void main() {
  group('RunCompletionRequestAdapter location privacy', () {
    test('excludes raw location trace fields from backend request', () {
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-location-privacy',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 10),
        durationSeconds: 600,
        distanceMeters: 1500,
        avgPaceSecondsPerKm: 400,
        source: 'local_replay',
        routePrivacy: 'private',
      );

      final request = RunCompletionRequestAdapter.toBackendRequest(payload);

      expect(request.keys, isNot(contains('latitude')));
      expect(request.keys, isNot(contains('longitude')));
      expect(request.keys, isNot(contains('samples')));
      expect(request.keys, isNot(contains('routeTrace')));
      expect(request.keys, isNot(contains('polyline')));
      expect(request.keys, isNot(contains('positions')));
      expect(request.keys, isNot(contains('gpsSamples')));
      expect(request.keys, isNot(contains('rawLocationSamples')));
      expect(request.keys, isNot(contains('diagnostics')));
      expect(request.keys, isNot(contains('startupReadiness')));
      expect(request.keys, isNot(contains('readiness')));
      expect(request.keys, isNot(contains('acceptedSampleCount')));
      expect(request.keys, isNot(contains('rejectedSampleCount')));
      expect(request.keys, isNot(contains('latestRejectionReason')));
      expect(request.keys, isNot(contains('latestHorizontalAccuracyMeters')));
      expect(request.keys, isNot(contains('horizontalAccuracy')));
      expect(request.keys, isNot(contains('accuracyBucket')));
      expect(request.keys, isNot(contains('routeSamples')));
      expect(request.keys, isNot(contains('rawMotion')));
      expect(request.keys, isNot(contains('motionSamples')));
      expect(request.keys, isNot(contains('classifierEvidence')));
      expect(request.keys, isNot(contains('abnormalMovement')));
      expect(request.keys, isNot(contains('abnormalFlags')));
      expect(request.keys, isNot(contains('xp')));
      expect(request.keys, isNot(contains('leaderboardScore')));
      expect(request.keys, isNot(contains('streak')));
      expect(request.keys, isNot(contains('rank')));
      expect(request.keys, isNot(contains('level')));
      expect(request.keys, isNot(contains('weeklyXp')));
      expect(request.keys, isNot(contains('monthlyXp')));
      expect(
        request.keys,
        isNot(contains('validatedActivityContributionState')),
      );
      expect(request.values.join(' '), isNot(contains('latitude')));
      expect(request.values.join(' '), isNot(contains('longitude')));
    });
  });
}
