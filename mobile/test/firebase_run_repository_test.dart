import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/data/firebase_run_repository.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_completion_error.dart';
import 'package:runiac_app/features/run/domain/models/xp_update_display_model.dart';
import 'package:runiac_app/features/run/domain/services/completed_run_title_formatter.dart';
import 'package:runiac_app/features/run/domain/services/pace_graph_data_builder.dart';

void main() {
  group('FirebaseRunRepository', () {
    test('maps callable response into CompleteRunResult', () async {
      final callable = _FakeCompleteRunCallable(
        response: <String, Object?>{
          'activityId': 'activity_123',
          'summaryId': 'summary_123',
          'progressionEventId': 'progression_123',
          'validationStatus': 'validated',
          'runSummary': <String, Object?>{
            'title': 'Repository Result Route',
            'startedAt': '2026-06-14T07:00:00.000Z',
            'endedAt': '2026-06-14T07:25:00.000Z',
            'distanceMeters': 3200,
            'durationSeconds': 1500,
            'averagePaceSecondsPerKm': 469,
            'displayDistance': '3.20 km',
            'displayDuration': '25:00',
            'displayPace': '469 sec/km',
            'routeLabel': 'Repository Result Route',
          },
          'progressionDisplay': <String, Object?>{
            'xpDelta': 60,
            'countsTowardLeaderboard': false,
            'status': 'awarded',
            'reason': 'run_completion_xp_awarded',
          },
          'message': 'Run completion accepted by emulator backend skeleton.',
        },
      );
      final repository = FirebaseRunRepository(callable: callable);

      final result = await repository.completeRun(_payload());

      expect(result.clientRunSessionId, 'local-session-20260614-0700');
      expect(result.activityId, 'activity_123');
      expect(result.summaryId, 'summary_123');
      expect(result.progressionEventId, 'progression_123');
      expect(result.validationStatus, 'validated');
      expect(
        result.summary.title,
        const CompletedRunTitleFormatter().format(
          completedAt: DateTime.utc(2026, 6, 14, 7, 25),
        ),
      );
      expect(result.summary.distanceKm, '3.20');
      expect(result.summary.duration, '25:00');
      expect(result.summary.avgPace, '7’49”');
      expect(result.summary.calories, '270');
      expect(result.summary.hasSufficientData, isTrue);
      expect(result.summary.paceGraph.isAvailable, isFalse);
      expect(result.summary.paceGraph.points, isEmpty);
      expect(result.progressionDisplay.xpDelta, 60);
      expect(result.progressionDisplay.countsTowardLeaderboard, isFalse);
      expect(result.progressionDisplay.status, 'awarded');
      expect(result.progressionDisplay.reason, 'run_completion_xp_awarded');
      expect(
        result.message,
        'Run completion accepted by emulator backend skeleton.',
      );
    });

    test(
      'callable summary defaults to Runiac GPS without heart rate',
      () async {
        final callable = _FakeCompleteRunCallable(
          response: _minimalCallableResponse(),
        );
        final repository = FirebaseRunRepository(callable: callable);

        final result = await repository.completeRun(_payload());

        expect(result.summary.sourceLabel, 'Runiac GPS');
        expect(result.summary.avgHeartRate, '--');
      },
    );

    test(
      'maps zero pace callable response to unavailable pace label',
      () async {
        final response = _minimalCallableResponse();
        final summary =
            Map<String, Object?>.from(
                response['runSummary']! as Map<String, Object?>,
              )
              ..['distanceMeters'] = 0
              ..['durationSeconds'] = 0
              ..['averagePaceSecondsPerKm'] = 0;
        final callable = _FakeCompleteRunCallable(
          response: <String, Object?>{...response, 'runSummary': summary},
        );
        final repository = FirebaseRunRepository(callable: callable);

        final result = await repository.completeRun(_payload());

        expect(result.summary.distanceKm, '0.00');
        expect(result.summary.duration, '0:00');
        expect(result.summary.avgPace, '--');
        expect(result.summary.avgHeartRate, '--');
        expect(result.summary.calories, '--');
        expect(result.summary.hasSufficientData, isFalse);
      },
    );

    test(
      'maps unreliable callable pace values to unavailable pace label',
      () async {
        const cases = <_SummaryPaceCase>[
          _SummaryPaceCase(
            label: 'short distance',
            distanceMeters: 49,
            durationSeconds: 300,
            paceSecondsPerKm: 360,
            expectedPace: '--',
          ),
          _SummaryPaceCase(
            label: 'short duration',
            distanceMeters: 1000,
            durationSeconds: 59,
            paceSecondsPerKm: 360,
            expectedPace: '--',
          ),
          _SummaryPaceCase(
            label: 'too fast',
            distanceMeters: 1000,
            durationSeconds: 180,
            paceSecondsPerKm: 149,
            expectedPace: '--',
          ),
          _SummaryPaceCase(
            label: 'too slow',
            distanceMeters: 1000,
            durationSeconds: 1900,
            paceSecondsPerKm: 1801,
            expectedPace: '--',
          ),
          _SummaryPaceCase(
            label: 'normal pace',
            distanceMeters: 1000,
            durationSeconds: 450,
            paceSecondsPerKm: 450,
            expectedPace: '7’30”',
          ),
        ];

        for (final testCase in cases) {
          final callable = _FakeCompleteRunCallable(
            response: _callableResponseWithSummary(
              distanceMeters: testCase.distanceMeters,
              durationSeconds: testCase.durationSeconds,
              paceSecondsPerKm: testCase.paceSecondsPerKm,
            ),
          );
          final repository = FirebaseRunRepository(callable: callable);

          final result = await repository.completeRun(_payload());

          expect(
            result.summary.avgPace,
            testCase.expectedPace,
            reason: testCase.label,
          );
          expect(
            result.summary.hasSufficientData,
            testCase.expectedPace != '--',
            reason: testCase.label,
          );
        }
      },
    );

    test('maps transient callable failures to retryable completion errors', () {
      const retryableCodes = <String>[
        'unavailable',
        'deadline-exceeded',
        'internal',
      ];

      for (final code in retryableCodes) {
        final repository = FirebaseRunRepository(
          callable: _FakeCompleteRunCallable(errorCode: code),
        );

        expect(
          () => repository.completeRun(_payload()),
          throwsA(
            isA<RunCompletionException>()
                .having((error) => error.code, 'code', code)
                .having((error) => error.isRetryable, 'isRetryable', isTrue),
          ),
        );
      }
    });

    test('maps invalid argument to non-retryable validation error', () {
      final repository = FirebaseRunRepository(
        callable: _FakeCompleteRunCallable(errorCode: 'invalid-argument'),
      );

      expect(
        () => repository.completeRun(_payload()),
        throwsA(
          isA<RunCompletionException>()
              .having((error) => error.code, 'code', 'invalid-argument')
              .having((error) => error.isRetryable, 'isRetryable', isFalse),
        ),
      );
    });

    test(
      'does not add protected backend-owned fields to callable request',
      () async {
        final callable = _FakeCompleteRunCallable(
          response: _minimalCallableResponse(),
        );
        final repository = FirebaseRunRepository(callable: callable);

        await repository.completeRun(_payload());

        const protectedFragments = <String>[
          'calorie',
          'xp',
          'streak',
          'level',
          'rank',
          'leaderboard',
          'validation',
          'subscription',
          'userRole',
        ];
        for (final key in callable.lastRequest.keys) {
          for (final fragment in protectedFragments) {
            expect(
              key.toLowerCase(),
              isNot(contains(fragment.toLowerCase())),
              reason: 'request key $key contains protected fragment $fragment',
            );
          }
        }
      },
    );

    test(
      'sends derived pace without raw graph or precise route fields',
      () async {
        final callable = _FakeCompleteRunCallable(
          response: _minimalCallableResponse(),
        );
        final repository = FirebaseRunRepository(callable: callable);

        final result = await repository.completeRun(
          _payload(
            paceGraphSamples: const <PaceGraphSample>[
              PaceGraphSample(elapsedSeconds: 60, paceSecondsPerKm: 410),
              PaceGraphSample(elapsedSeconds: 120, paceSecondsPerKm: 405),
              PaceGraphSample(elapsedSeconds: 180, paceSecondsPerKm: 408),
            ],
          ),
        );

        expect(callable.lastRequest['durationSeconds'], 1500);
        expect(callable.lastRequest['distanceMeters'], 3200);
        expect(callable.lastRequest['avgPaceSecondsPerKm'], 469);
        expect(callable.lastRequest['source'], 'mobile');
        expect(callable.lastRequest['routePrivacy'], 'private');
        expect(callable.lastRequest['routeLabel'], 'Repository Result Route');
        expect(callable.lastRequest['clientAppVersion'], 'm5-test');
        expect(callable.lastRequest['paceAnalysisSeries'], isA<Map>());
        expect(callable.lastRequest, isNot(contains('routeSnapshot')));
        expect(result.summary.paceGraph.isAvailable, isFalse);
        expect(result.summary.paceGraph.points, isEmpty);

        const forbiddenFragments = <String>[
          'paceGraphSamples',
          'graphSamples',
          'PaceGraphSample',
          'paceGraph',
          'routeSnapshot',
          'recordedAt',
          'altitudeMeters',
          'horizontalAccuracyMeters',
          'speedMetersPerSecond',
          'routeTrace',
          'polyline',
          'positions',
          'gpsSamples',
          'rawLocationSamples',
          'displayRouteSegments',
          'acceptedRouteSegments',
          'motionEvidence',
          'xp',
          'streak',
          'level',
          'rank',
          'leaderboard',
          'weeklyXp',
          'monthlyXp',
          'subscription',
        ];
        final serializedRequest = callable.lastRequest.entries
            .map((entry) => '${entry.key}:${entry.value}')
            .join('|');
        for (final fragment in forbiddenFragments) {
          expect(
            serializedRequest.toLowerCase(),
            isNot(contains(fragment.toLowerCase())),
            reason: 'callable request leaked forbidden fragment $fragment',
          );
        }
      },
    );
  });

  group('FirebaseRunRepository xp update mapping', () {
    test('maps an awarded progression block into display numerics', () async {
      final repository = FirebaseRunRepository(
        callable: _FakeCompleteRunCallable(
          response: _responseWithProgression(<String, Object?>{
            'xpDelta': 75,
            'countsTowardLeaderboard': false,
            'status': 'awarded',
            'reason': 'run_completion_xp_awarded',
            'totalXp': 1240,
            'previousTotalXp': 1165,
            'level': 4,
            'previousLevel': 4,
            'previousLevelProgressPercent': 30,
            'levelProgressPercent': 62,
            'nextLevelXp': 1500,
            'xpToNextLevel': 260,
            'previousStreak': 3,
            'streak': 4,
          }),
        ),
      );

      final xp = (await repository.completeRun(_payload())).xpUpdate;

      expect(xp.xpAwardState, XpAwardState.awarded);
      expect(xp.didLevelUp, isFalse);
      expect(xp.earnedXp, 75);
      expect(xp.earnedXpLabel, '+75 XP');
      expect(xp.totalXp, 1240);
      expect(xp.totalXpLabel, '1,240 XP');
      expect(xp.previousTotalXp, 1165);
      expect(xp.level, 4);
      expect(xp.previousLevel, 4);
      expect(xp.levelLabel, '4');
      expect(xp.progressTargetLabel, 'Progress to Level 5');
      expect(xp.xpRemainingLabel, '260 XP to Level 5');
      expect(xp.previousProgressFraction, closeTo(0.30, 1e-9));
      expect(xp.currentProgressFraction, closeTo(0.62, 1e-9));
      expect(xp.streakCount, 4);
      expect(xp.previousStreakCount, 3);
      expect(xp.streakChangeLabel, '3 → 4 days');
    });

    test('flags a level-up when level exceeds previous level', () async {
      final repository = FirebaseRunRepository(
        callable: _FakeCompleteRunCallable(
          response: _responseWithProgression(<String, Object?>{
            'xpDelta': 60,
            'countsTowardLeaderboard': false,
            'status': 'awarded',
            'reason': 'run_completion_xp_awarded',
            'totalXp': 120,
            'previousTotalXp': 60,
            'level': 2,
            'previousLevel': 1,
            'previousLevelProgressPercent': 60,
            'levelProgressPercent': 20,
            'nextLevelXp': 300,
            'xpToNextLevel': 180,
            'previousStreak': 1,
            'streak': 2,
          }),
        ),
      );

      final xp = (await repository.completeRun(_payload())).xpUpdate;

      expect(xp.xpAwardState, XpAwardState.awarded);
      expect(xp.didLevelUp, isTrue);
      expect(xp.level, 2);
      expect(xp.previousLevel, 1);
      expect(xp.levelLabel, '2');
      expect(xp.xpRemainingLabel, '180 XP to Level 3');
    });

    test(
      'renders a friendly not-awarded reason without fake numbers',
      () async {
        final repository = FirebaseRunRepository(
          callable: _FakeCompleteRunCallable(
            response: _responseWithProgression(<String, Object?>{
              'xpDelta': 0,
              'countsTowardLeaderboard': false,
              'status': 'not_awarded',
              'reason': 'daily_cap_reached',
              'totalXp': 200,
              'previousTotalXp': 200,
              'level': 3,
              'previousLevel': 3,
              'previousLevelProgressPercent': 40,
              'levelProgressPercent': 40,
              'nextLevelXp': 300,
              'xpToNextLevel': 100,
              'previousStreak': 5,
              'streak': 5,
            }),
          ),
        );

        final xp = (await repository.completeRun(_payload())).xpUpdate;

        expect(xp.xpAwardState, XpAwardState.notAwarded);
        expect(xp.earnedXp, 0);
        expect(xp.heroMessage, 'Daily XP cap reached — great effort today');
        expect(xp.totalXp, 200);
        expect(xp.streakCount, 5);
      },
    );

    test('maps a deferred progression block into a saved fallback', () async {
      final repository = FirebaseRunRepository(
        callable: _FakeCompleteRunCallable(
          response: _responseWithProgression(<String, Object?>{
            'xpDelta': 0,
            'countsTowardLeaderboard': false,
            'status': 'deferred',
            'reason': 'progression_formula_deferred',
          }),
        ),
      );

      final xp = (await repository.completeRun(_payload())).xpUpdate;

      expect(xp.xpAwardState, XpAwardState.deferred);
      expect(xp.earnedXp, 0);
      expect(xp.totalXp, 0);
      expect(xp.heroMessage, 'This run is saved. XP is being finalized.');
    });

    test('handles a max-level null next-level target', () async {
      final repository = FirebaseRunRepository(
        callable: _FakeCompleteRunCallable(
          response: _responseWithProgression(<String, Object?>{
            'xpDelta': 40,
            'countsTowardLeaderboard': false,
            'status': 'awarded',
            'reason': 'run_completion_xp_awarded',
            'totalXp': 999999,
            'previousTotalXp': 999959,
            'level': 100,
            'previousLevel': 100,
            'previousLevelProgressPercent': 100,
            'levelProgressPercent': 100,
            'nextLevelXp': null,
            'xpToNextLevel': null,
            'previousStreak': 9,
            'streak': 10,
          }),
        ),
      );

      final xp = (await repository.completeRun(_payload())).xpUpdate;

      expect(xp.xpAwardState, XpAwardState.awarded);
      expect(xp.progressTargetLabel, 'Max level reached');
      expect(xp.xpRemainingLabel, 'Max level reached');
      expect(xp.currentProgressFraction, closeTo(1.0, 1e-9));
    });
  });
}

Map<String, Object?> _responseWithProgression(
  Map<String, Object?> progression,
) {
  return <String, Object?>{
    ..._minimalCallableResponse(),
    'progressionDisplay': progression,
  };
}

LocalRunCompletionPayload _payload({
  List<PaceGraphSample> paceGraphSamples = const <PaceGraphSample>[],
}) {
  return LocalRunCompletionPayload(
    clientRunSessionId: 'local-session-20260614-0700',
    startedAt: DateTime.utc(2026, 6, 14, 7),
    completedAt: DateTime.utc(2026, 6, 14, 7, 25),
    durationSeconds: 1500,
    distanceMeters: 3200,
    avgPaceSecondsPerKm: 469,
    source: 'local_simulation',
    routePrivacy: 'private',
    routeLabel: 'Repository Result Route',
    clientAppVersion: 'm5-test',
    paceGraphSamples: paceGraphSamples,
  );
}

Map<String, Object?> _minimalCallableResponse() {
  return <String, Object?>{
    'activityId': 'activity_123',
    'summaryId': 'summary_123',
    'progressionEventId': 'progression_123',
    'validationStatus': 'validated',
    'runSummary': <String, Object?>{
      'title': 'Completed Run',
      'startedAt': '2026-06-14T07:00:00.000Z',
      'endedAt': '2026-06-14T07:25:00.000Z',
      'distanceMeters': 3200,
      'durationSeconds': 1500,
      'averagePaceSecondsPerKm': 469,
      'displayDistance': '3.20 km',
      'displayDuration': '25:00',
      'displayPace': '469 sec/km',
    },
    'progressionDisplay': <String, Object?>{
      'xpDelta': 60,
      'countsTowardLeaderboard': false,
      'status': 'awarded',
      'reason': 'run_completion_xp_awarded',
    },
    'message': 'Accepted.',
  };
}

Map<String, Object?> _callableResponseWithSummary({
  required int distanceMeters,
  required int durationSeconds,
  required int paceSecondsPerKm,
}) {
  final response = _minimalCallableResponse();
  final summary =
      Map<String, Object?>.from(response['runSummary']! as Map<String, Object?>)
        ..['distanceMeters'] = distanceMeters
        ..['durationSeconds'] = durationSeconds
        ..['averagePaceSecondsPerKm'] = paceSecondsPerKm;
  return <String, Object?>{...response, 'runSummary': summary};
}

class _SummaryPaceCase {
  const _SummaryPaceCase({
    required this.label,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.paceSecondsPerKm,
    required this.expectedPace,
  });

  final String label;
  final int distanceMeters;
  final int durationSeconds;
  final int paceSecondsPerKm;
  final String expectedPace;
}

class _FakeCompleteRunCallable implements CompleteRunCallable {
  _FakeCompleteRunCallable({this.response, this.errorCode});

  final Map<String, Object?>? response;
  final String? errorCode;
  Map<String, Object?> lastRequest = <String, Object?>{};

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    lastRequest = request;
    final code = errorCode;
    if (code != null) {
      throw CompleteRunCallableException(code: code, message: 'Failed.');
    }

    return response ?? _minimalCallableResponse();
  }
}
