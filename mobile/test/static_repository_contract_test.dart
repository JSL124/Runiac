import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/data/static_viewer_access_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/viewer_access_repository.dart';
import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/feed/domain/repositories/feed_repository.dart';
import 'package:runiac_app/features/home/data/static_home_dashboard_repository.dart';
import 'package:runiac_app/features/home/domain/repositories/home_dashboard_repository.dart';
import 'package:runiac_app/features/leaderboard/data/static_leaderboard_repository.dart';
import 'package:runiac_app/features/leaderboard/domain/repositories/leaderboard_repository.dart';
import 'package:runiac_app/features/maps/data/static_shared_routes_repository.dart';
import 'package:runiac_app/features/maps/domain/repositories/shared_routes_repository.dart';
import 'package:runiac_app/features/run/data/static_run_repository.dart';
import 'package:runiac_app/features/run/domain/models/coaching_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/xp_update_display_model.dart';
import 'package:runiac_app/features/run/domain/repositories/run_repository.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';
import 'package:runiac_app/features/run/domain/services/completed_run_title_formatter.dart';
import 'package:runiac_app/features/run/domain/services/pace_graph_data_builder.dart';
import 'package:runiac_app/features/you/data/static_activity_history_repository.dart';
import 'package:runiac_app/features/you/domain/repositories/activity_history_repository.dart';

const _defaultDemoCoachingHeadline = 'Imported run with steady rhythm';
const _defaultDemoCoachingMessage =
    'This demo run gives you enough pace detail for a simple rhythm note. The data suggests a steady run, which is useful for building consistency without chasing speed. Because this is demo/import data, the summary treats it as a learning note rather than a recording made by the app, and it does not judge effort from heart rate.';
const _defaultDemoNextFocus =
    'Keep the next easy run calm and repeatable, then compare the rhythm.';

final _forbiddenDefaultDemoCoachingCopy = RegExp(
  r'live GPS|tracked live|heart-rate zone|heart rate zone|zone|fatigue|'
  r'medical|exhaustion|overtraining|danger|threshold|max-effort|'
  r'max effort|XP|leaderboard|subscription|Premium',
  caseSensitive: false,
);

void main() {
  group('Repository contracts', () {
    test('interfaces expose read-only load methods', () {
      expect(UserProfileRepository, isA<Type>());
      expect(ActivityHistoryRepository, isA<Type>());
      expect(LeaderboardRepository, isA<Type>());
      expect(SharedRoutesRepository, isA<Type>());
      expect(ViewerAccessRepository, isA<Type>());
      expect(HomeDashboardRepository, isA<Type>());
      expect(RunRepository, isA<Type>());
      expect(FeedRepository, isA<Type>());
    });

    test('Feed repository reads through a viewer-scoped context', () async {
      const repository = StaticFeedRepository();
      final feedRepository = repository as FeedRepository;

      final feed = await feedRepository.loadFeed(
        const FeedViewerContext(
          currentUserId: 'runner-current',
          acceptedFriendUserIds: <String>{'runner-friend'},
        ),
      );

      expect(feed.posts.map((post) => post.authorUserId), [
        'runner-current',
        'runner-friend',
      ]);
    });

    test('repository interfaces expose only approved methods', () {
      const repositoryContracts = <_RepositoryContract>[
        _RepositoryContract(
          path:
              'lib/features/profile/domain/repositories/'
              'user_profile_repository.dart',
          declarations: <String>[
            'Future<UserProfileReadModel> loadUserProfile();',
          ],
        ),
        _RepositoryContract(
          path:
              'lib/features/you/domain/repositories/'
              'activity_history_repository.dart',
          declarations: <String>[
            'Future<ActivityHistoryReadModel> loadActivityHistory();',
          ],
        ),
        _RepositoryContract(
          path:
              'lib/features/leaderboard/domain/repositories/'
              'leaderboard_repository.dart',
          declarations: <String>[
            'Future<LeaderboardReadModel> loadLeaderboard();',
            'Future<LeaderboardReadModel> loadRegion({required String regionId});',
          ],
        ),
        _RepositoryContract(
          path:
              'lib/features/maps/domain/repositories/'
              'shared_routes_repository.dart',
          declarations: <String>[
            'Future<SharedRoutesReadModel> loadSharedRoutes();',
          ],
        ),
        _RepositoryContract(
          path:
              'lib/features/profile/domain/repositories/'
              'viewer_access_repository.dart',
          declarations: <String>[
            'Future<ViewerAccessReadModel> loadViewerAccess();',
          ],
        ),
        _RepositoryContract(
          path:
              'lib/features/home/domain/repositories/'
              'home_dashboard_repository.dart',
          declarations: <String>[
            'Future<HomeDashboardReadModel> loadHomeDashboard();',
          ],
        ),
        _RepositoryContract(
          path: 'lib/features/run/domain/repositories/run_repository.dart',
          declarations: <String>[
            'Future<RunSummaryReadModel> loadLatestRunSummary();',
            'Future<CompleteRunResult> loadLatestCompletionResult();',
            'Future<RunActivityReadModel> loadLatestRunActivity();',
            'Future<CompleteRunResult> completeRun(LocalRunCompletionPayload payload);',
            'Future<CompleteRunResult> completeCoolDown({ required String activityId, required String clientRunSessionId, });',
          ],
          allowedCommandMethods: <String>['completeRun', 'completeCoolDown'],
        ),
      ];

      for (final contract in repositoryContracts) {
        final source = File(contract.path).readAsStringSync();
        final className = contract.path
            .split('/')
            .last
            .replaceFirst('.dart', '')
            .split('_')
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join();
        final declarations = _repositoryInterfaceDeclarations(
          source,
          className,
        );
        final methods = declarations.map(_repositoryMethodName).toList();

        expect(declarations, contract.declarations, reason: contract.path);
        for (final method in methods) {
          expect(method, isNotNull, reason: contract.path);
          expect(
            method!.startsWith('load') ||
                contract.allowedCommandMethods.contains(method),
            isTrue,
            reason:
                '${contract.path} contains an unapproved repository member: '
                '$declarations',
          );
        }

        for (final verb in _trustedMutationVerbs) {
          for (final declaration in declarations) {
            if (contract.allowedCommandMethods.contains(verb)) {
              continue;
            }
            expect(
              declaration,
              isNot(contains(RegExp('\\b$verb\\b'))),
              reason: '${contract.path} exposes $verb in $declaration',
            );
          }
        }
      }
    });

    test('Run repository does not expose raw completion payloads', () {
      final source = File(
        'lib/features/run/domain/repositories/run_repository.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('RunCompletedPayload')));
      expect(source, contains('LocalRunCompletionPayload'));
    });
  });

  group('Static repositories', () {
    test(
      'Feed repository returns posts visible to the current user or friends',
      () async {
        const viewerContext = FeedViewerContext(
          currentUserId: 'runner-current',
          acceptedFriendUserIds: <String>{'runner-friend'},
        );

        final feed = await StaticFeedRepository().loadFeed(viewerContext);
        final visibleAuthorIds = feed.posts
            .map((post) => post.authorUserId)
            .toSet();

        expect(visibleAuthorIds, contains('runner-current'));
        expect(visibleAuthorIds, contains('runner-friend'));
        expect(
          visibleAuthorIds,
          everyElement(isIn(<String>{'runner-current', 'runner-friend'})),
        );
      },
    );

    test('return demo-preserving profile values', () async {
      final repository = StaticUserProfileRepository();

      final profile = await repository.loadUserProfile();

      expect(profile.displayName, 'Runiac Runner');
    });

    test('return demo-preserving selected shared route', () async {
      final repository = StaticSharedRoutesRepository();

      final routes = await repository.loadSharedRoutes();

      expect(routes.selectedRoute.title, 'Marina Bay easy loop');
    });

    test('return display-only viewer access labels', () async {
      final repository = StaticViewerAccessRepository();

      final access = await repository.loadViewerAccess();

      expect(access.subscriptionStatusLabel, isNotEmpty);
      expect(access.userRoleLabel, isNotEmpty);
    });

    test('return demo-preserving Home dashboard values', () async {
      final repository = StaticHomeDashboardRepository();

      final dashboard = await repository.loadHomeDashboard();

      expect(dashboard.todayPlanTitle, '20 min easy run');
      expect(dashboard.goalTitle, 'First 10K Preparation');
      expect(dashboard.goalProgressLabel, '43%');
      expect(dashboard.streakLabel, '6 days');
      expect(dashboard.xpLabel, '1,240 xp');
      expect(dashboard.levelLabel, '360 XP to Lv.13');
      expect(dashboard.weeklySummaryLabel, 'Week 3 of 8');
    });

    test('return demo-preserving Run values', () async {
      final repository = StaticRunRepository();
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-session-20260614-0700',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 25),
        durationSeconds: 1500,
        distanceMeters: 3200,
        avgPaceSecondsPerKm: 469,
        source: 'local_simulation',
        routePrivacy: 'private',
        routeLabel: 'Repository Result Route',
        clientAppVersion: 'm3-test',
      );

      final summary = await repository.loadLatestRunSummary();
      final completion = await repository.loadLatestCompletionResult();
      final completedRun = await repository.completeRun(payload);
      final activity = await repository.loadLatestRunActivity();

      expect(summary.title, 'Saturday Morning Run');
      expect(summary.distanceLabel, '4.03 km');
      expect(summary.avgPaceLabel, '6’30”');
      expect(summary.routeName, 'East Coast Park Loop');
      expect(completion.xpUpdate.earnedXpLabel, '+120 XP');
      expect(completion.xpUpdate.streakChangeLabel, '5 → 6 days');
      expect(completion.summary.sourceLabel, 'Demo import');
      expect(
        completion.summary.coachingSummary.source,
        CoachingSummarySource.ruleBased,
      );
      expect(
        completion.summary.coachingSummary.interpretationId,
        CoachingInterpretationId.steadyEffortInterpretation,
      );
      expect(
        completion.summary.coachingSummary.headline,
        _defaultDemoCoachingHeadline,
      );
      expect(
        completion.summary.coachingSummary.message,
        _defaultDemoCoachingMessage,
      );
      expect(
        completion.summary.coachingSummary.nextAction,
        _defaultDemoNextFocus,
      );
      expect(completion.summary.coachingSummary.bullets, isEmpty);
      expect(
        completion.summary.coachingSummary.message.split(RegExp(r'\s+')),
        hasLength(inInclusiveRange(35, 80)),
      );
      expect(
        RegExp(r'[.!?]').allMatches(completion.summary.coachingSummary.message),
        hasLength(inInclusiveRange(2, 4)),
      );
      expect(
        completion.summary.coachingSummary.message,
        isNot(contains(_forbiddenDefaultDemoCoachingCopy)),
      );
      expect(completedRun.activityId, 'static-local-session-20260614-0700');
      expect(completedRun.xpUpdate.xpAwardState, XpAwardState.syncPending);
      expect(completedRun.xpUpdate.totalXpLabel, 'Saved on this device');
      expect(completedRun.clientRunSessionId, 'local-session-20260614-0700');
      expect(
        completedRun.summaryId,
        'static-summary-local-session-20260614-0700',
      );
      expect(
        completedRun.progressionEventId,
        'static-progression-local-session-20260614-0700',
      );
      expect(completedRun.validationStatus, 'validated');
      expect(
        completedRun.summary.title,
        const CompletedRunTitleFormatter().format(
          completedAt: payload.completedAt,
        ),
      );
      expect(completedRun.summary.distanceKm, '3.20');
      expect(completedRun.summary.duration, '25:00');
      expect(completedRun.summary.avgPace, '7’49”');
      expect(completedRun.summary.calories, '270');
      expect(completedRun.summary.hasSufficientData, isTrue);
      expect(completedRun.progressionDisplay.xpDelta, 0);
      expect(completedRun.progressionDisplay.countsTowardLeaderboard, isFalse);
      expect(completedRun.progressionDisplay.status, 'deferred');
      expect(
        completedRun.progressionDisplay.reason,
        'progression_formula_deferred',
      );
      expect(activity.title, 'Saturday Morning Run');
      expect(activity.routeLabel, 'East Coast Park Loop');
    });

    test('completed local run stays Runiac GPS without heart rate', () async {
      final repository = StaticRunRepository();
      final payload = LocalRunCompletionPayload(
        clientRunSessionId: 'local-source-hr-session',
        startedAt: DateTime.utc(2026, 6, 14, 7),
        completedAt: DateTime.utc(2026, 6, 14, 7, 25),
        durationSeconds: 1500,
        distanceMeters: 3200,
        avgPaceSecondsPerKm: 469,
        source: 'local_simulation',
        routePrivacy: 'private',
        routeLabel: 'Repository Result Route',
        clientAppVersion: 'hwi-v1-a-test',
      );

      final completedRun = await repository.completeRun(payload);

      expect(completedRun.summary.sourceLabel, 'Runiac GPS');
      expect(completedRun.summary.avgHeartRate, '--');
    });

    test(
      'completeRun returns deterministic rule-based coaching summary',
      () async {
        final repository = StaticRunRepository();

        final completedRun = await repository.completeRun(
          _localRunCompletionPayload(
            sessionId: 'rule-based-coaching-session',
            distanceMeters: 3200,
            durationSeconds: 1500,
            paceSecondsPerKm: 469,
          ),
        );

        expect(
          completedRun.summary.coachingSummary.source,
          CoachingSummarySource.ruleBased,
        );
        expect(
          completedRun.summary.coachingSummary.sectionTitle,
          'Coaching Summary',
        );
        expect(
          completedRun.summary.coachingSummary.interpretationId,
          CoachingInterpretationId.scalarOnlyInterpretation,
        );
        expect(completedRun.summary.coachingSummary.headline, isNotEmpty);
        expect(completedRun.summary.coachingSummary.message, isNotEmpty);
        expect(completedRun.summary.coachingSummary.bullets, isEmpty);
        expect(
          completedRun.summary.coachingSummary.message.split(RegExp(r'\s+')),
          hasLength(greaterThanOrEqualTo(35)),
        );
        expect(completedRun.summary.coachingSummary.nextAction, isNotEmpty);
      },
    );

    test(
      'completeRun returns zero summary values for zero run payloads',
      () async {
        final repository = StaticRunRepository();
        final payload = LocalRunCompletionPayload(
          clientRunSessionId: 'zero-run-session',
          startedAt: DateTime.utc(2026, 6, 14, 7),
          completedAt: DateTime.utc(2026, 6, 14, 7),
          durationSeconds: 0,
          distanceMeters: 0,
          avgPaceSecondsPerKm: 0,
          source: 'local_simulation',
          routePrivacy: 'private',
          routeLabel: 'Easy local route',
          clientAppVersion: 'zero-run-test',
        );

        final completedRun = await repository.completeRun(payload);

        expect(
          completedRun.summary.title,
          const CompletedRunTitleFormatter().format(
            completedAt: payload.completedAt,
          ),
        );
        expect(completedRun.summary.distanceKm, '0.00');
        expect(completedRun.summary.duration, '0:00');
        expect(completedRun.summary.avgPace, '--');
        expect(completedRun.summary.avgHeartRate, '--');
        expect(completedRun.summary.calories, '--');
        expect(completedRun.summary.hasSufficientData, isFalse);
        expect(completedRun.summary.routeName, 'Easy local route');
        expect(completedRun.summary.title, isNot('Easy local route'));
        expect(completedRun.summary.distanceKm, isNot('4.03'));
        expect(completedRun.summary.avgPace, isNot('6’30”'));
        expect(completedRun.summary.duration, isNot('30:15'));
        expect(completedRun.summary.avgHeartRate, isNot('145'));
        expect(completedRun.summary.calories, isNot('145'));
        expect(completedRun.summary.routeName, isNot('East Coast Park Loop'));
        expect(completedRun.xpUpdate.earnedXpLabel, '+0 XP');
        expect(completedRun.xpUpdate.streakChangeLabel, 'Not updated yet');
      },
    );

    test('completeRun hides unreliable summary pace values', () async {
      final repository = StaticRunRepository();

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
        final completedRun = await repository.completeRun(
          _localRunCompletionPayload(
            sessionId: 'summary-pace-${testCase.label.replaceAll(' ', '-')}',
            distanceMeters: testCase.distanceMeters,
            durationSeconds: testCase.durationSeconds,
            paceSecondsPerKm: testCase.paceSecondsPerKm,
          ),
        );

        expect(
          completedRun.summary.avgPace,
          testCase.expectedPace,
          reason: testCase.label,
        );
        expect(
          completedRun.summary.hasSufficientData,
          testCase.expectedPace != '--',
          reason: testCase.label,
        );
      }
    });

    test('completeRun builds local pace graph from payload samples', () async {
      final repository = StaticRunRepository();
      const samples = <PaceGraphSample>[
        PaceGraphSample(elapsedSeconds: 60, paceSecondsPerKm: 400),
        PaceGraphSample(elapsedSeconds: 180, paceSecondsPerKm: 410),
        PaceGraphSample(elapsedSeconds: 300, paceSecondsPerKm: 420),
      ];

      final completedRun = await repository.completeRun(
        _localRunCompletionPayload(
          sessionId: 'summary-pace-graph-local-samples',
          distanceMeters: 1000,
          durationSeconds: 450,
          paceSecondsPerKm: 450,
          paceGraphSamples: samples,
        ),
      );

      final graph = completedRun.summary.paceGraph;

      expect(completedRun.summary.hasSufficientData, isTrue);
      expect(graph.isAvailable, isTrue);
      expect(graph.points.map((point) => point.elapsedSeconds), <int>[
        60,
        180,
        300,
      ]);
      expect(graph.points.map((point) => point.paceSecondsPerKm), <int>[
        400,
        410,
        420,
      ]);
      expect(graph.totalDurationSeconds, 450);
      expect(graph.averagePaceSecondsPerKm, 450);
    });

    test(
      'completeRun does not attach fixture graph when local samples are absent',
      () async {
        final repository = StaticRunRepository();

        final completedRun = await repository.completeRun(
          _localRunCompletionPayload(
            sessionId: 'summary-pace-graph-no-local-samples',
            distanceMeters: 1000,
            durationSeconds: 450,
            paceSecondsPerKm: 450,
          ),
        );

        expect(completedRun.summary.hasSufficientData, isTrue);
        expect(completedRun.summary.paceGraph.isAvailable, isFalse);
        expect(completedRun.summary.paceGraph.points, isEmpty);
      },
    );

    test(
      'completeRun returns unavailable graph when local graph samples are insufficient',
      () async {
        final repository = StaticRunRepository();

        final completedRun = await repository.completeRun(
          _localRunCompletionPayload(
            sessionId: 'summary-pace-graph-insufficient-local-samples',
            distanceMeters: 1000,
            durationSeconds: 450,
            paceSecondsPerKm: 450,
            paceGraphSamples: const <PaceGraphSample>[
              PaceGraphSample(elapsedSeconds: 60, paceSecondsPerKm: 400),
              PaceGraphSample(elapsedSeconds: 180, paceSecondsPerKm: 410),
            ],
          ),
        );

        expect(completedRun.summary.hasSufficientData, isTrue);
        expect(completedRun.summary.paceGraph.isAvailable, isFalse);
        expect(completedRun.summary.paceGraph.points, isEmpty);
      },
    );

    test(
      'completeRun carries accountable local pace samples into analysis',
      () async {
        final repository = StaticRunRepository();

        final completedRun = await repository.completeRun(
          _localRunCompletionPayload(
            sessionId: 'summary-accountable-pace-analysis',
            distanceMeters: 1000,
            durationSeconds: 450,
            paceSecondsPerKm: 450,
            paceGraphSamples: const <PaceGraphSample>[
              PaceGraphSample(
                elapsedSeconds: 60,
                paceSecondsPerKm: 500,
                cumulativeDistanceMeters: 125,
              ),
              PaceGraphSample(
                elapsedSeconds: 120,
                paceSecondsPerKm: 470,
                cumulativeDistanceMeters: 250,
              ),
              PaceGraphSample(
                elapsedSeconds: 240,
                paceSecondsPerKm: 490,
                cumulativeDistanceMeters: 500,
              ),
            ],
          ),
        );

        final series = completedRun.summary.paceAnalysisSeries;
        final analysis = const AdvancedAnalysisSnapshotBuilder().fromRunSummary(
          completedRun.summary,
        );

        expect(series, isNotNull);
        expect(series!.isLocalAcceptedSource, isTrue);
        expect(
          series.validAcceptedSamples.map((sample) => sample.paceSecondsPerKm),
          <int>[500, 470, 490],
        );
        expect(analysis.pace.fastestPace.valueLabel, '7’50”');
        expect(analysis.pace.slowestPace.valueLabel, '8’20”');
        expect(analysis.pace.paceStability.valueLabel, '81');
      },
    );

    test(
      'completeRun returns unavailable graph when summary pace is unreliable',
      () async {
        final repository = StaticRunRepository();

        final completedRun = await repository.completeRun(
          _localRunCompletionPayload(
            sessionId: 'summary-pace-graph-unreliable-summary-pace',
            distanceMeters: 1000,
            durationSeconds: 450,
            paceSecondsPerKm: 149,
            paceGraphSamples: const <PaceGraphSample>[
              PaceGraphSample(elapsedSeconds: 60, paceSecondsPerKm: 400),
              PaceGraphSample(elapsedSeconds: 180, paceSecondsPerKm: 410),
              PaceGraphSample(elapsedSeconds: 300, paceSecondsPerKm: 420),
            ],
          ),
        );

        expect(completedRun.summary.hasSufficientData, isFalse);
        expect(completedRun.summary.paceGraph.isAvailable, isFalse);
        expect(completedRun.summary.paceGraph.points, isEmpty);
      },
    );

    test(
      'return read-only activity history and leaderboard snapshots',
      () async {
        final activityHistoryRepository = StaticActivityHistoryRepository();
        final leaderboardRepository = StaticLeaderboardRepository();

        final history = await activityHistoryRepository.loadActivityHistory();
        final leaderboard = await leaderboardRepository.loadLeaderboard();

        expect(history.recentRuns, isNotEmpty);
        expect(leaderboard.entries, isNotEmpty);
      },
    );

    test('new Home and Run seam files stay Firebase-free', () {
      const seamPaths = <String>[
        'lib/features/home/domain/repositories/home_dashboard_repository.dart',
        'lib/features/home/data/static_home_dashboard_repository.dart',
        'lib/features/run/domain/repositories/run_repository.dart',
        'lib/features/run/data/static_run_repository.dart',
      ];
      const forbiddenBackendTerms = <String>[
        'Firebase',
        'Firestore',
        'FirebaseAuth',
        'FirebaseFirestore',
        'firebase_core',
        'cloud_firestore',
        'firebase_auth',
        'collection(',
        'doc(',
        'set(',
        'update(',
      ];

      for (final path in seamPaths) {
        final source = File(path).readAsStringSync();

        for (final term in forbiddenBackendTerms) {
          expect(source, isNot(contains(term)), reason: '$path contains $term');
        }
      }
    });
  });
}

LocalRunCompletionPayload _localRunCompletionPayload({
  required String sessionId,
  required int distanceMeters,
  required int durationSeconds,
  required int paceSecondsPerKm,
  List<PaceGraphSample> paceGraphSamples = const <PaceGraphSample>[],
}) {
  return LocalRunCompletionPayload(
    clientRunSessionId: sessionId,
    startedAt: DateTime.utc(2026, 6, 14, 7),
    completedAt: DateTime.utc(
      2026,
      6,
      14,
      7,
    ).add(Duration(seconds: durationSeconds)),
    durationSeconds: durationSeconds,
    distanceMeters: distanceMeters,
    avgPaceSecondsPerKm: paceSecondsPerKm,
    source: 'local_simulation',
    routePrivacy: 'private',
    routeLabel: 'Easy local route',
    clientAppVersion: 'summary-pace-test',
    paceGraphSamples: paceGraphSamples,
  );
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

const _trustedMutationVerbs = <String>[
  'calculate',
  'derive',
  'aggregate',
  'validate',
  'award',
  'increment',
  'publish',
  'approve',
  'reject',
  'suspend',
  'set',
  'update',
  'delete',
  'completeRun',
  'submitRun',
  'saveRun',
  'syncRun',
  'validateRun',
  'uploadRun',
  'persistRun',
];

class _RepositoryContract {
  const _RepositoryContract({
    required this.path,
    required this.declarations,
    this.allowedCommandMethods = const <String>[],
  });

  final String path;
  final List<String> declarations;
  final List<String> allowedCommandMethods;
}

List<String> _repositoryInterfaceDeclarations(String source, String className) {
  final uncommentedSource = _removeDartComments(source);
  final classMatch = RegExp(
    'abstract\\s+interface\\s+class\\s+$className\\s*{',
  ).firstMatch(uncommentedSource);

  expect(classMatch, isNotNull, reason: 'Missing $className declaration');

  final bodyStart = classMatch!.end;
  var depth = 1;
  for (var index = bodyStart; index < uncommentedSource.length; index += 1) {
    final char = uncommentedSource[index];

    if (char == '{') {
      depth += 1;
    } else if (char == '}') {
      depth -= 1;

      if (depth == 0) {
        return _splitTopLevelDeclarations(
          uncommentedSource.substring(bodyStart, index),
        );
      }
    }
  }

  fail('Missing closing brace for $className');
}

String _removeDartComments(String source) {
  return source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*', multiLine: true), '');
}

List<String> _splitTopLevelDeclarations(String body) {
  final declarations = <String>[];
  final buffer = StringBuffer();
  var angleDepth = 0;
  var parenthesisDepth = 0;
  var bracketDepth = 0;

  for (var index = 0; index < body.length; index += 1) {
    final char = body[index];

    if (char == '<') {
      angleDepth += 1;
    } else if (char == '>' && angleDepth > 0) {
      angleDepth -= 1;
    } else if (char == '(') {
      parenthesisDepth += 1;
    } else if (char == ')' && parenthesisDepth > 0) {
      parenthesisDepth -= 1;
    } else if (char == '[') {
      bracketDepth += 1;
    } else if (char == ']' && bracketDepth > 0) {
      bracketDepth -= 1;
    }

    buffer.write(char);

    if (char == ';' &&
        angleDepth == 0 &&
        parenthesisDepth == 0 &&
        bracketDepth == 0) {
      declarations.add(_normalizeDeclaration(buffer.toString()));
      buffer.clear();
    }
  }

  final trailingBody = buffer.toString().trim();
  expect(trailingBody, isEmpty, reason: 'Unexpected repository body content');

  return declarations;
}

String _normalizeDeclaration(String declaration) {
  return declaration.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _repositoryMethodName(String declaration) {
  return RegExp(
    r'^[A-Za-z0-9_<>, ?]+ ([A-Za-z0-9]+)\([^;]*\);$',
  ).firstMatch(declaration)?.group(1);
}
