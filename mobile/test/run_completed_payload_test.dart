import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/run_completed_payload.dart';

void main() {
  group('RunCompletedPayload', () {
    test('constructs with client-observed raw run metrics', () {
      // Given: raw metrics observed by the Flutter run surface.
      final startedAt = DateTime.utc(2026, 6, 11, 22, 5);
      final completedAt = DateTime.utc(2026, 6, 11, 22, 38, 12);

      // When: the frontend prepares a future backend validation payload.
      final payload = RunCompletedPayload(
        clientRunSessionId: 'local-run-session-20260611-2205',
        startedAt: startedAt,
        completedAt: completedAt,
        durationSeconds: 1992,
        distanceMeters: 4030,
        avgPaceSecondsPerKm: 494,
        caloriesEstimate: 212,
        routeLabel: 'East Coast Park Loop',
        source: 'run_flow',
      );

      // Then: only client-observed raw activity fields are exposed.
      expect(payload.clientRunSessionId, 'local-run-session-20260611-2205');
      expect(payload.startedAt, startedAt);
      expect(payload.completedAt, completedAt);
      expect(payload.durationSeconds, 1992);
      expect(payload.distanceMeters, 4030);
      expect(payload.avgPaceSecondsPerKm, 494);
      expect(payload.caloriesEstimate, 212);
      expect(payload.routeLabel, 'East Coast Park Loop');
      expect(payload.source, 'run_flow');
    });

    test('allows realistically unavailable optional metrics', () {
      // Given: a completed run without route or calorie data.
      final startedAt = DateTime.utc(2026, 6, 11, 7, 0);
      final completedAt = DateTime.utc(2026, 6, 11, 7, 24);

      // When: the raw payload is constructed from the available metrics.
      final payload = RunCompletedPayload(
        clientRunSessionId: 'local-run-session-20260611-0700',
        startedAt: startedAt,
        completedAt: completedAt,
        durationSeconds: 1440,
        distanceMeters: 3200,
        avgPaceSecondsPerKm: 450,
        source: 'run_flow',
      );

      // Then: unavailable metrics remain absent instead of being invented.
      expect(payload.caloriesEstimate, isNull);
      expect(payload.routeLabel, isNull);
    });

    test('source stays backend-free and excludes trusted field names', () {
      // Given: the model source file.
      final source = File(
        'lib/features/run/domain/models/run_completed_payload.dart',
      ).readAsStringSync();

      // When: checking forbidden backend, persistence, and progression terms.
      const forbiddenTerms = [
        'Firebase',
        'firebase',
        'Firestore',
        'Auth',
        'SharedPreferences',
        'xp',
        'earnedXp',
        'totalXp',
        'level',
        'streak',
        'rank',
        'leaderboardScore',
        'weeklyXp',
        'monthlyXp',
        'subscriptionPrivilegeState',
        'validationStatus',
        'countsTowardProgression',
        'calculateXP',
        'calculateLevel',
        'calculateStreak',
        'save',
        'upload',
        'sync',
        'submit',
      ];

      // Then: the contract remains raw and frontend-only.
      for (final term in forbiddenTerms) {
        expect(source, isNot(contains(term)));
      }
    });
  });
}
