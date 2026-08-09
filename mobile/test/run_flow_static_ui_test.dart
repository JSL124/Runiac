import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runiac_app/app.dart';
import 'package:runiac_app/core/assets/runiac_assets.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';
import 'package:runiac_app/features/feed/data/feed_publish/feed_publish_service.dart';
import 'package:runiac_app/features/feed/presentation/current_session_feed.dart';
import 'package:runiac_app/features/feed/data/feed_publish/history_artifact_resolver.dart';
import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/activity_feedback_agent.dart';
import 'package:runiac_app/features/run/domain/models/cadence_graph_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/coaching_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/complete_run_result.dart';
import 'package:runiac_app/features/run/domain/models/cool_down_contract.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/pace_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/pace_graph_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/progression_display_model.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_source_display.dart';
import 'package:runiac_app/features/run/domain/models/run_feed_publish_source.dart';
import 'package:runiac_app/features/run/presentation/advanced_analysis_screen.dart';
import 'package:runiac_app/features/run/presentation/cool_down_guide_screen.dart';
import 'package:runiac_app/features/run/presentation/cool_down_screen.dart';
import 'package:runiac_app/features/run/presentation/models/stretch_exercise.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/xp_update_display_model.dart';
import 'package:runiac_app/features/run/domain/repositories/run_repository.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';
import 'package:runiac_app/features/run/domain/services/completed_run_title_formatter.dart';
import 'package:runiac_app/features/run/presentation/active_run_session_coordinator.dart';
import 'package:runiac_app/features/run/presentation/data/pace_graph_demo_snapshots.dart';
import 'package:runiac_app/features/run/presentation/data/run_completion_demo_snapshots.dart';
import 'package:runiac_app/features/run/presentation/run_launch_screen.dart';
import 'package:runiac_app/features/run/presentation/view_summary_screen.dart';
import 'package:runiac_app/features/run/presentation/widgets/advanced_analysis/advanced_analysis_charts.dart';
import 'package:runiac_app/features/run/presentation/widgets/advanced_analysis/advanced_analysis_splits_table.dart';
import 'package:runiac_app/features/run/presentation/widgets/completed_route_map_surface.dart';
import 'package:runiac_app/features/run/presentation/widgets/share_achievement_sheet.dart';
import 'package:runiac_app/features/run/presentation/xp_update_screen.dart';
import 'package:runiac_app/features/you/data/local_pending_run_activity_store.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';
import 'package:runiac_app/features/you/presentation/data/activity_history_demo_snapshots.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_snapshot_thumbnail_cache.dart';

import 'support/fake_runiac_auth_repository.dart';

final _forbiddenRunCompletionCopy = RegExp(
  r'XP|streak|Leaderboard|Activity saved|Saved activity|activity saved|'
  r'saved activity|backend completion|backend-completion|completed run|'
  r'run completed',
  caseSensitive: false,
);

final _forbiddenRealActivitySaveCopy = RegExp(
  r'Activity saved|Saved activity|activity saved|saved activity|'
  r'backend completion|backend-completion|completed run|run completed|'
  r'synced|uploaded',
  caseSensitive: false,
);

final _forbiddenXpUpdateCompetitiveCopy = RegExp(
  r'leaderboard|rank|ranking|percentile|beat others|division',
  caseSensitive: false,
);

const _defaultDemoCoachingHeadline = 'Imported run with steady rhythm';
const _defaultDemoCoachingMessage =
    'This demo run gives you enough pace detail for a simple rhythm note. The data suggests a steady run, which is useful for building consistency without chasing speed. Because this is demo/import data, the summary treats it as a learning note rather than a recording made by the app, and it does not judge effort from heart rate.';
const _defaultDemoNextFocus =
    'Keep the next easy run calm and repeatable, then compare the rhythm.';

final _forbiddenDemoCoachingCopy = RegExp(
  r'live GPS|tracked live|heart-rate zone|heart rate zone|zone|fatigue|'
  r'medical|exhaustion|overtraining|danger|threshold|max-effort|'
  r'max effort|XP|leaderboard|subscription|Premium',
  caseSensitive: false,
);

void _useCompactShareSheetSurface(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _useTallSummarySurface(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(800, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _advancedAnalysisSplitDistanceText(String text) {
  return find.byWidgetPredicate((widget) {
    return widget is Text &&
        widget.data == text &&
        widget.style?.fontSize == 12 &&
        widget.style?.fontWeight == FontWeight.w800 &&
        widget.textAlign == null &&
        widget.maxLines == 1 &&
        widget.overflow == TextOverflow.ellipsis;
  });
}

class _FakeActivityFeedbackAgent implements ActivityFeedbackAgent {
  @override
  Future<ActivityFeedbackBundle> explainRun(
    ActivityFeedbackRequest request,
  ) async {
    return const ActivityFeedbackBundle(
      source: ActivityFeedbackSource.generated,
      sections: ActivityFeedbackSections(
        summary: 'You completed a controlled run.',
        wentWell: 'Your pacing stayed repeatable.',
        improve: 'Ease into the first kilometre next time.',
        nextFocus: 'Keep the next run calm and steady.',
      ),
    );
  }
}

int _paceSeconds(String pace) {
  final match = RegExp(r"^(\d+)[’'](\d{1,2})").firstMatch(pace.trim());
  if (match == null) {
    throw FormatException('Invalid pace label', pace);
  }
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

Widget _shareSheetHarness() {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          return Center(
            child: FilledButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  barrierColor: Colors.black.withValues(alpha: 0.48),
                  builder: (context) =>
                      ShareAchievementSheet(summary: _summaryWithRoute()),
                );
              },
              child: const Text('Open share sheet'),
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _openPausedRun(WidgetTester tester) async {
  await tester.pumpWidget(
    RuniacApp(
      showSplash: false,
      enableForegroundGps: false,
      activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
    ),
  );

  await tester.tap(find.byTooltip('Run'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start run'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pause'));
  await tester.pumpAndSettle();
}

ActiveRunSessionCoordinator _testActiveRunSessionCoordinator(
  WidgetTester tester,
) {
  final activeRunSessionCoordinator = ActiveRunSessionCoordinator(
    clock: () => DateTime(2026, 6, 24, 8, 10),
    foregroundTickStep: const Duration(seconds: 1),
  );
  addTearDown(activeRunSessionCoordinator.dispose);
  return activeRunSessionCoordinator;
}

Future<void> _finishPausedRun(WidgetTester tester) async {
  final endButton = find.byKey(const Key('hold_to_end_button'));
  final holdGesture = await tester.startGesture(tester.getCenter(endButton));
  await tester.pump(const Duration(milliseconds: 3100));
  await holdGesture.up();
  await tester.pumpAndSettle();
}

class _ResultRunRepository implements RunRepository {
  _ResultRunRepository(this.result);

  final CompleteRunResult result;
  int completeRunCalls = 0;
  LocalRunCompletionPayload? lastPayload;
  final List<LocalRunCompletionPayload> payloads =
      <LocalRunCompletionPayload>[];

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    completeRunCalls += 1;
    lastPayload = payload;
    payloads.add(payload);
    return result;
  }

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CompleteRunResult> loadLatestCompletionResult() async {
    return result;
  }

  @override
  Future<RunActivityReadModel> loadLatestRunActivity() async {
    return const RunActivityReadModel(
      activityId: 'repo-activity',
      title: 'Repository Run',
      completedAtLabel: 'Today',
      distanceLabel: '5.40 km',
      durationLabel: '36:00',
      avgPaceLabel: '6’40”',
      routeLabel: 'Repository Route',
    );
  }

  @override
  Future<RunSummaryReadModel> loadLatestRunSummary() async {
    return const RunSummaryReadModel(
      summaryId: 'repo-summary',
      title: 'Repository Run',
      dateLabel: 'Today',
      timeLabel: '8:10 AM',
      distanceLabel: '5.40 km',
      avgPaceLabel: '6’40”',
      durationLabel: '36:00',
      avgHeartRateLabel: '138 bpm',
      caloriesLabel: '280 kcal',
      routeName: 'Repository Route',
    );
  }
}

class _FailingRunRepository extends _ResultRunRepository {
  _FailingRunRepository(super.result);

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    completeRunCalls += 1;
    lastPayload = payload;
    payloads.add(payload);
    throw StateError('repository unavailable');
  }
}

class _DelayedRunRepository extends _ResultRunRepository {
  _DelayedRunRepository(super.result);

  final Completer<CompleteRunResult> completer = Completer<CompleteRunResult>();

  @override
  Future<CompleteRunResult> completeRun(LocalRunCompletionPayload payload) {
    completeRunCalls += 1;
    lastPayload = payload;
    payloads.add(payload);
    return completer.future;
  }
}

/// Records the arguments the cool-down guide screen forwards to
/// [RunRepository.completeCoolDown] and returns a caller-supplied server
/// bonus response, so tests can assert the request shape and the merged
/// result without the guide screen ever calculating XP itself.
class _RecordingCoolDownRunRepository extends _ResultRunRepository {
  _RecordingCoolDownRunRepository(
    super.result, {
    required this.coolDownResult,
  });

  final CompleteRunResult coolDownResult;
  int completeCoolDownCalls = 0;
  String? lastCoolDownActivityId;
  String? lastCoolDownClientRunSessionId;

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) async {
    completeCoolDownCalls += 1;
    lastCoolDownActivityId = activityId;
    lastCoolDownClientRunSessionId = clientRunSessionId;
    return coolDownResult;
  }
}

/// Simulates the server's cool-down bonus request failing, so tests can
/// confirm the guide screen falls back silently to the original completion
/// result rather than surfacing an error.
class _FailingCoolDownRunRepository extends _ResultRunRepository {
  _FailingCoolDownRunRepository(super.result);

  int completeCoolDownCalls = 0;

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) async {
    completeCoolDownCalls += 1;
    throw StateError('cool-down bonus unavailable');
  }
}

const _runFlowFeedOwnerUid = 'run-flow-test-owner';
const _runFlowFeedActivityId = 'activity_run_flow_feed';
const _runFlowFeedClientSessionId = 'run-flow-feed-session';

final _runFlowHistoryPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAFgAAABYCAYAAABxlTA0AAAAjElEQVR42u3QMQEAAAQAMI1U0VosLhF8O1ZgkdXDn5AgWDCCBQtGsGDBCBaMYMGCESxYMIIFC5YgWDCCBQtGsGDBCBaMYMGCESxYMIIFC5YgWDCCBQtGsGDBCBaMYMGCESxYMIIFCxYhWDCCBQtGsGDBCBaMYMGCESxYMIIFC0awYAQLFoxgwYIRLJizDhyrPSUd4x4AAAAASUVORK5CYII=',
);

RunSummarySnapshot _summaryWithRoute() {
  final startedAt = DateTime.utc(2026, 6, 14, 7);
  return defaultRunSummarySnapshot.copyWith(
    route: RunRouteSnapshot(
      segments: [
        [
          RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300000,
            longitude: 103.800000,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 60)),
            latitude: 1.300500,
            longitude: 103.800850,
          ),
          RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 120)),
            latitude: 1.300899,
            longitude: 103.801250,
          ),
        ],
      ],
      lastKnownLocation: RunLocationSample(
        recordedAt: startedAt.add(const Duration(seconds: 120)),
        latitude: 1.300899,
        longitude: 103.801250,
      ),
    ),
  );
}

class _RunFlowFeedPublishFixture {
  _RunFlowFeedPublishFixture()
    : cache = ActivityRouteSnapshotThumbnailMemoryCache(),
      gateway = _RecordingFeedPublishGateway() {
    final request = ActivityRouteThumbnailRequest(
      route: defaultRunSummarySnapshot.route,
      logicalSize: const Size(88, 88),
      devicePixelRatio: 1,
      allowExternalStaticMap: true,
      isDemoRoute: false,
      isCurrentSessionRoute: true,
      activityId: _runFlowFeedClientSessionId,
    );
    cache.store(
      ActivityRouteSnapshotThumbnailCacheKey.fromRequest(request),
      ActivityRouteThumbnailResult.readyPng(_runFlowHistoryPng),
      ownerUid: _runFlowFeedOwnerUid,
    );
    historyArtifactResolver = CacheOnlyHistoryArtifactResolver(
      cache: cache,
      ownerUidProvider: () => _runFlowFeedOwnerUid,
    );
    feedPublishService = FeedPublishService(gateway: gateway);
  }

  final ActivityRouteSnapshotThumbnailMemoryCache cache;
  final _RecordingFeedPublishGateway gateway;
  late final HistoryArtifactResolver historyArtifactResolver;
  late final FeedPublishService feedPublishService;

  static const completionResult = CompleteRunResult(
    clientRunSessionId: _runFlowFeedClientSessionId,
    activityId: _runFlowFeedActivityId,
    summary: defaultRunSummarySnapshot,
    xpUpdate: defaultXpUpdateDisplayModel,
  );

  void dispose() => cache.clearOwner(_runFlowFeedOwnerUid);
}

class _RecordingFeedPublishGateway implements FeedPublishGateway {
  Uint8List? stagedPngBytes;
  var stageCalls = 0;
  var publishCalls = 0;
  final stageActivityIds = <String>[];
  final publishActivityIds = <String>[];

  @override
  Future<String> stage({
    required String activityId,
    required Uint8List pngBytes,
  }) async {
    stageCalls += 1;
    stageActivityIds.add(activityId);
    stagedPngBytes = pngBytes;
    return 'feed-thumbnail-staging/test/$activityId/thumbnail.png';
  }

  @override
  Future<FeedPublishResponse> publish({
    required String activityId,
    required String stagingPath,
  }) async {
    publishCalls += 1;
    publishActivityIds.add(activityId);
    return const FeedPublishResponse(postId: 'run-flow-feed-post');
  }
}

class _GeneratedTitleRunRepository extends _ResultRunRepository {
  _GeneratedTitleRunRepository() : super(_repositoryCompletionResult);

  String? generatedTitle;

  @override
  Future<CompleteRunResult> completeRun(LocalRunCompletionPayload payload) {
    completeRunCalls += 1;
    lastPayload = payload;
    payloads.add(payload);
    final title = const CompletedRunTitleFormatter().format(
      completedAt: payload.completedAt,
    );
    generatedTitle = title;
    return Future<CompleteRunResult>.value(
      CompleteRunResult(
        activityId: result.activityId,
        summaryId: result.summaryId,
        progressionEventId: result.progressionEventId,
        validationStatus: result.validationStatus,
        summary: RunSummarySnapshot(
          title: title,
          dateLabel: result.summary.dateLabel,
          timeLabel: result.summary.timeLabel,
          distanceKm: result.summary.distanceKm,
          avgPace: result.summary.avgPace,
          duration: result.summary.duration,
          avgHeartRate: result.summary.avgHeartRate,
          calories: result.summary.calories,
          routeName: result.summary.routeName,
        ),
        progressionDisplay: result.progressionDisplay,
        xpUpdate: result.xpUpdate,
        message: result.message,
      ),
    );
  }
}

const _repositoryCompletionResult = CompleteRunResult(
  activityId: 'repo-activity',
  summaryId: 'repo-summary',
  progressionEventId: 'repo-progression',
  validationStatus: 'validated',
  summary: RunSummarySnapshot(
    title: 'Repository Result Run',
    dateLabel: 'Today',
    timeLabel: '8:10 AM',
    distanceKm: '5.40',
    avgPace: '6’40”',
    duration: '36:00',
    avgHeartRate: '138',
    calories: '280',
    routeName: 'Repository Route',
  ),
  progressionDisplay: ProgressionDisplayModel(
    xpDelta: 0,
    countsTowardLeaderboard: false,
    status: 'deferred',
    reason: 'progression_formula_deferred',
  ),
  xpUpdate: XpUpdateDisplayModel(
    runnerName: 'Maya',
    earnedXpLabel: '+0 XP',
    totalXpLabel: '0 XP',
    levelLabel: '0',
    nextLevelLabel: '1',
    progressTargetLabel: 'Progress deferred',
    xpRemainingLabel: 'Pending',
    previousProgressFraction: 0,
    currentProgressFraction: 0,
    streakChangeLabel: 'Deferred',
    streakNote: 'Accepted.',
    didLevelUp: false,
  ),
  message: 'Static repository completion accepted.',
);

/// The server's cool-down XP bonus response merged on top of
/// [_repositoryCompletionResult]: an 'awarded' progression display with a
/// positive xpDelta and a non-null totalXp, so `mergeCoolDownBonus` actually
/// folds it in (sums the two deltas, adopts the bonus response's totals).
final _repositoryCoolDownBonusResult = _repositoryCompletionResult.copyWith(
  progressionDisplay: const ProgressionDisplayModel(
    xpDelta: 10,
    countsTowardLeaderboard: true,
    status: 'awarded',
    reason: 'cool_down_stretch_bonus_awarded',
    totalXp: 155,
    level: 2,
    previousTotalXp: 145,
    previousLevel: 2,
    previousLevelProgressPercent: 45,
    levelProgressPercent: 55,
    xpToNextLevel: 45,
    nextLevelXp: 200,
  ),
);

const _lowDataCompletionResult = CompleteRunResult(
  clientRunSessionId: 'low-data-client-session',
  activityId: 'repo-low-data-activity',
  summaryId: 'repo-low-data-summary',
  progressionEventId: 'repo-low-data-progression',
  validationStatus: 'validated',
  summary: RunSummarySnapshot(
    title: 'Low Data Run',
    dateLabel: 'Today',
    timeLabel: '8:10 AM',
    distanceKm: '0.00',
    avgPace: '--',
    duration: '0:00',
    avgHeartRate: '--',
    calories: '--',
    routeName: 'Private route',
    hasSufficientData: false,
  ),
  progressionDisplay: ProgressionDisplayModel(
    xpDelta: 0,
    countsTowardLeaderboard: false,
    status: 'deferred',
    reason: 'progression_formula_deferred',
  ),
  xpUpdate: XpUpdateDisplayModel(
    runnerName: 'Maya',
    earnedXpLabel: '+0 XP',
    totalXpLabel: '0 XP',
    levelLabel: '0',
    nextLevelLabel: '1',
    progressTargetLabel: 'Progress deferred',
    xpRemainingLabel: 'Pending',
    previousProgressFraction: 0,
    currentProgressFraction: 0,
    streakChangeLabel: 'Deferred',
    streakNote: 'Accepted.',
    didLevelUp: false,
  ),
  message: 'Accepted.',
);

void main() {
  setUp(() {
    // RunLaunchScreen reads voice-coaching settings from the real
    // SharedPreferences-backed repository (no fake is injected by these
    // widget tests). Without mock initial values, SharedPreferences.
    // getInstance() never resolves in the test harness (no platform-channel
    // responder), which would hang `_startRun`'s settings reload forever.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Run item opens and protects local active finish controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
      ),
    );

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Run settings'), findsOneWidget);
    expect(find.text('TODAY\'S PLAN'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('km easy run'), findsOneWidget);
    expect(find.text('Pace 7:10-7:40 / km · ~32 min'), findsOneWidget);
    expect(find.text('Switch route'), findsNothing);
    expect(find.text('Start run'), findsOneWidget);
    expect(find.text('Waiting for GPS'), findsNothing);
    expect(find.text('DISTANCE'), findsNothing);
    expect(find.text('TIME'), findsNothing);
    expect(find.text('AVG PACE'), findsNothing);
    expect(find.byKey(const Key('run_plan_progress_bar')), findsNothing);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Resume'), findsNothing);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Maps'), findsNothing);
    expect(find.text('Leaderboard'), findsNothing);
    expect(find.text('You'), findsNothing);

    await tester.tap(find.byTooltip('Run settings'));
    await tester.pumpAndSettle();

    expect(find.text('Run Settings'), findsOneWidget);
    expect(find.text('Voice progress updates'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('TODAY\'S PLAN'), findsNothing);
    expect(find.text('RUNNING'), findsNothing);
    expect(find.text('0.00 of 4.50 km'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byKey(const Key('run_plan_progress_bar')), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
    expect(find.text('AVG PACE'), findsNothing);
    expect(find.text('CURRENT PACE'), findsOneWidget);
    expect(find.text('--:--/km'), findsOneWidget);
    expect(find.text('HEART'), findsNothing);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Resume'), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.byTooltip('Run settings'), findsNothing);
    expect(find.text('Waiting for GPS'), findsNothing);
    expect(find.text('Start run'), findsNothing);

    await tester.pump(const Duration(seconds: 10));

    expect(find.text('00:10'), findsOneWidget);
    expect(find.textContaining('of 4.50 km'), findsOneWidget);
    expect(find.text('1%'), findsOneWidget);
    expect(find.text('--:--/km'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('Hold to end'), findsNothing);
    expect(find.text('Keep holding...'), findsNothing);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.textContaining('of 4.50 km'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('00:10'), findsOneWidget);
    expect(find.text('AVG PACE'), findsNothing);
    expect(find.text('CURRENT PACE'), findsOneWidget);
    expect(find.text('--:--/km'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));

    expect(find.text('00:10'), findsOneWidget);
    expect(find.textContaining('of 4.50 km'), findsOneWidget);
    expect(find.text('Run summary'), findsNothing);
    expect(find.textContaining('XP'), findsNothing);
    expect(find.textContaining('streak'), findsNothing);
    expect(find.text('Leaderboard'), findsNothing);

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('Hold to end'), findsNothing);
    expect(find.text('Keep holding...'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('00:10'), findsNothing);
    expect(find.text('0.02 of 4.50 km'), findsNothing);
  });

  testWidgets('Run finish opens Cool down page with placeholder actions', (
    WidgetTester tester,
  ) async {
    await _openPausedRun(tester);

    await _finishPausedRun(tester);

    expect(find.text('Cool down'), findsOneWidget);
    expect(
      find.text('Great job! Now let’s cool down and stretch.'),
      findsOneWidget,
    );
    expect(find.text('Why cool-down?'), findsOneWidget);
    expect(
      find.text(
        'A gentle cool-down helps your heart rate settle and can reduce muscle soreness.',
      ),
      findsOneWidget,
    );
    expect(find.text('Slow Walk'), findsOneWidget);
    expect(find.text('3-5 min'), findsOneWidget);
    expect(find.text('Stretching'), findsOneWidget);
    expect(find.text('~6 min · 8 exercises'), findsOneWidget);
    expect(find.text('Start Cool-down'), findsOneWidget);
    expect(find.text('Skip to Summary'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.textContaining(_forbiddenRunCompletionCopy), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
    await tester.pumpAndSettle();

    expect(find.text('Easy local route'), findsNothing);
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
    expect(find.text('--'), findsAtLeastNWidgets(3));
    expect(find.text('0:00'), findsWidgets);
    expect(find.text('Saturday Morning Run'), findsNothing);
    expect(find.text('East Coast Park Loop'), findsNothing);
    expect(find.text('4.03'), findsNothing);
    expect(find.text('6’30”'), findsNothing);
    expect(find.text('30:15'), findsNothing);
    expect(find.text('Pace Over Time'), findsOneWidget);
    expect(find.text('Splits'), findsOneWidget);
    expect(find.text('Coaching Summary'), findsOneWidget);
    expect(find.text('AI Coaching Summary'), findsNothing);
    expect(
      find.text(
        'This run has limited data, so the summary stays careful and simple. Completion still matters because it gives you a check-in point. Heart-rate data was not available, and the pace graph is not usable, so this note avoids effort or pacing claims.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('steady pace'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Share Route'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'View XP Update'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Go to Home'), findsOneWidget);
    expect(find.text('XP & Streak Update'), findsNothing);
    expect(find.textContaining(_forbiddenRealActivitySaveCopy), findsNothing);
  });

  testWidgets(
    'Run finish builds local summary before repository sync decision',
    (WidgetTester tester) async {
      final repository = _ResultRunRepository(_repositoryCompletionResult);

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            repository: repository,
            enableForegroundGps: false,
            activeRunSessionCoordinator: _testActiveRunSessionCoordinator(
              tester,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      await _finishPausedRun(tester);

      expect(repository.completeRunCalls, 0);
      expect(repository.lastPayload, isNull);
      expect(find.text('Cool down'), findsOneWidget);
      expect(find.text('Repository Result Run'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
      await tester.pumpAndSettle();

      expect(find.text('Repository Result Run'), findsNothing);
      expect(find.text('Repository Route'), findsNothing);
      expect(find.text('0.00'), findsOneWidget);
      expect(find.text('0:00'), findsWidgets);
      expect(find.text('138 bpm'), findsNothing);
      expect(find.text('Saturday Morning Run'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'View XP Update'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Run finish displays generated completion title in summary', (
    WidgetTester tester,
  ) async {
    final repository = _GeneratedTitleRunRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          repository: repository,
          enableForegroundGps: false,
          activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
        ),
      ),
    );

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    await _finishPausedRun(tester);

    expect(repository.completeRunCalls, 0);
    expect(repository.lastPayload, isNull);
    expect(repository.generatedTitle, isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
    await tester.pumpAndSettle();

    expect(find.text('Repository Result Run'), findsNothing);
    expect(find.text('Repository Route'), findsNothing);
    expect(find.text('Saturday Morning Run'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Immediate Run finish shows zero summary instead of demo fallback',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            enableForegroundGps: false,
            activeRunSessionCoordinator: _testActiveRunSessionCoordinator(
              tester,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      await _finishPausedRun(tester);

      expect(find.text('Cool down'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
      await tester.pumpAndSettle();

      expect(find.text('Easy local route'), findsNothing);
      expect(find.text('0.00'), findsOneWidget);
      expect(find.text('0:00'), findsWidgets);
      expect(find.text('--'), findsAtLeastNWidgets(3));
      expect(find.text('-- bpm'), findsNothing);
      expect(find.text('-- kcal'), findsNothing);
      expect(find.text('Saturday Morning Run'), findsNothing);
      expect(find.text('East Coast Park Loop'), findsNothing);
      expect(find.text('4.03'), findsNothing);
      expect(find.text('6’30”'), findsNothing);
      expect(find.text('30:15'), findsNothing);
      expect(find.text('145 bpm'), findsNothing);
      expect(find.text('145 kcal'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Run finish reaches cool down when repository sync would fail', (
    WidgetTester tester,
  ) async {
    final repository = _FailingRunRepository(_repositoryCompletionResult);

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          repository: repository,
          enableForegroundGps: false,
        ),
      ),
    );

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    await _finishPausedRun(tester);

    expect(repository.completeRunCalls, 0);
    expect(repository.lastPayload, isNull);
    expect(find.text('Cool down'), findsOneWidget);
    expect(
      find.text('Run completion is unavailable. Please try again.'),
      findsNothing,
    );
    expect(find.text('End'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run finish does not wait for repository before cool down', (
    WidgetTester tester,
  ) async {
    final repository = _DelayedRunRepository(_repositoryCompletionResult);

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          repository: repository,
          enableForegroundGps: false,
        ),
      ),
    );

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    await _finishPausedRun(tester);
    await tester.pump();

    expect(repository.completeRunCalls, 0);
    expect(repository.lastPayload, isNull);
    expect(find.text('Saving'), findsNothing);
    expect(find.text('Cool down'), findsOneWidget);
    expect(find.text('End'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('View summary static content and actions match design', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);
    final feedFixture = _RunFlowFeedPublishFixture();
    addTearDown(feedFixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ViewSummaryScreen(
          completionResult: _RunFlowFeedPublishFixture.completionResult,
          feedPublishService: feedFixture.feedPublishService,
          historyArtifactResolver: feedFixture.historyArtifactResolver,
        ),
      ),
    );

    final summaryScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(summaryScaffold.backgroundColor, RuniacColors.white);
    expect(find.text('Saturday Morning Run'), findsOneWidget);
    expect(find.text('Today · 7:06 AM'), findsOneWidget);
    expect(find.byTooltip('Back to cool down'), findsOneWidget);
    expect(find.byTooltip('Share summary'), findsOneWidget);
    expect(find.text('East Coast Park Loop'), findsNothing);
    expect(find.text('Run complete'), findsNothing);
    expect(find.text('4.03'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
    expect(find.text('6’30”'), findsOneWidget);
    expect(find.text('Avg Pace'), findsOneWidget);
    expect(find.text('30:15'), findsWidgets);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('145 bpm'), findsOneWidget);
    expect(find.text('145 kcal'), findsOneWidget);
    expect(find.text('Avg Heart Rate'), findsOneWidget);
    expect(find.text('Est. calories'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    expect(find.byIcon(Icons.speed_rounded), findsNothing);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsNothing);
    expect(find.text('Pace Over Time'), findsOneWidget);
    expect(find.text('4:00'), findsNothing);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('13:00'), findsNothing);
    expect(find.text('6:00'), findsOneWidget);
    expect(find.text('6:40'), findsOneWidget);
    expect(find.text('7:20'), findsOneWidget);
    expect(find.text('More run data needed'), findsNothing);
    final summarySplits = const AdvancedAnalysisSnapshotBuilder()
        .fromRunSummary(defaultRunSummarySnapshot)
        .pace
        .splits
        .value!;

    expect(find.text('Advanced Analysis'), findsNothing);
    expect(find.text('Splits'), findsOneWidget);
    expect(find.text('Km'), findsOneWidget);
    expect(find.text('Pace'), findsOneWidget);
    expect(find.text('Elev'), findsOneWidget);
    expect(find.text('HR'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('advanced_analysis_split_1_km')))
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('advanced_analysis_split_1_pace')))
          .data,
      summarySplits[0].paceLabel,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('advanced_analysis_split_2_km')))
          .data,
      '2',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('advanced_analysis_split_2_pace')))
          .data,
      summarySplits[1].paceLabel,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('advanced_analysis_split_1_elev')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '--',
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('advanced_analysis_split_1_hr')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '--',
    );
    expect(
      find.byType(AdvancedAnalysisSplitBar),
      findsNWidgets(summarySplits.length),
    );
    expect(find.text('Heart rate zones, cadence & elevation'), findsNothing);
    expect(find.text('Easy'), findsNothing);
    expect(find.text('72%'), findsNothing);
    expect(find.text('Steady'), findsNothing);
    expect(find.text('22%'), findsNothing);
    expect(find.text('Hard'), findsNothing);
    expect(find.text('6%'), findsNothing);
    expect(find.text('More Details'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.text('Coaching Summary'), findsOneWidget);
    expect(find.text('AI Coaching Summary'), findsNothing);
    expect(find.text(_defaultDemoCoachingMessage), findsOneWidget);
    expect(find.text(_defaultDemoCoachingHeadline), findsOneWidget);
    expect(find.text('Next Run Tip'), findsNothing);
    expect(find.text('Next Focus'), findsOneWidget);
    expect(find.text('Next Action'), findsNothing);
    expect(find.text('Next Run Tip:'), findsNothing);
    expect(find.text(_defaultDemoNextFocus), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Share Route'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'View XP Update'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Home'), findsNothing);
    expect(find.textContaining(_forbiddenRealActivitySaveCopy), findsNothing);

    await tester.tap(find.byTooltip('Share summary'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Share Your Activity'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'More Details'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'More Details'));
    await tester.pumpAndSettle();

    expect(find.text('Run Quality'), findsOneWidget);
    expect(find.text('Building consistency'), findsOneWidget);
    expect(find.text('Phone-tracked effort'), findsNothing);

    await tester.tap(find.byTooltip('Back to summary'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Share Route'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Share Route'));
    await tester.pumpAndSettle();

    expect(find.text('Share Your Achievement'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Close'), findsNothing);
    expect(find.text('Post to Feed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('share-feed-preview-profile-badge')),
      findsOneWidget,
    );
    expect(find.text('Route sharing will be available soon.'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Post to Feed'));
    await tester.pumpAndSettle();
    expect(find.text('Share Your Achievement'), findsNothing);
    expect(feedFixture.gateway.stagedPngBytes, same(_runFlowHistoryPng));
    expect(feedFixture.gateway.publishCalls, 1);
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'View XP Update'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'View XP Update'));
    await tester.pumpAndSettle();

    expect(find.text('XP & Streak Update'), findsOneWidget);
    expect(find.text('Nice work, Jinseo!'), findsOneWidget);
    expect(find.text('+120 XP'), findsOneWidget);
    expect(find.text('Earned from this run'), findsNothing);
  });

  testWidgets(
    'Activity feedback overlay blocks then restores summary actions',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: ViewSummaryScreen(
            activityFeedbackAgent: _FakeActivityFeedbackAgent(),
          ),
        ),
      );

      expect(find.byTooltip('Activity feedback'), findsOneWidget);
      expect(find.byTooltip('Share summary'), findsOneWidget);

      await tester.tap(find.byTooltip('Activity feedback'));
      await tester.pump();
      expect(find.text('Analysing your run...'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('You completed a controlled run.'), findsOneWidget);
      await tester.tap(find.byTooltip('Next feedback step'));
      await tester.pumpAndSettle();
      expect(find.text('Went well'), findsOneWidget);
      expect(find.text('Your pacing stayed repeatable.'), findsOneWidget);

      await tester.tap(find.byTooltip('Share summary'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Share Your Activity'), findsNothing);

      await tester.tap(find.byTooltip('Close activity feedback'));
      await tester.pumpAndSettle();
      expect(find.text('Went well'), findsNothing);

      await tester.tap(find.byTooltip('Share summary'));
      await tester.pumpAndSettle();
      expect(find.text('Share Your Activity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ViewSummary disables Feed for noncanonical completion identities', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);
    for (final scenario in <(CompleteRunResult, String)>[
      (
        const CompleteRunResult(
          activityId: 'static-summary-activity',
          summary: defaultRunSummarySnapshot,
          xpUpdate: defaultXpUpdateDisplayModel,
        ),
        'This run is still local. Save it to your account before posting to Feed.',
      ),
      (
        const CompleteRunResult(
          activityId: 'activity_pending_validation',
          validationStatus: 'pending',
          summary: defaultRunSummarySnapshot,
          xpUpdate: defaultXpUpdateDisplayModel,
        ),
        'This run is still being validated. Try posting again after validation finishes.',
      ),
    ]) {
      await tester.pumpWidget(
        MaterialApp(home: ViewSummaryScreen(completionResult: scenario.$1)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Share Route'));
      await tester.pumpAndSettle();
      expect(find.text(scenario.$2), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Share Route opens a Feed confirmation preview', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);
    final feedFixture = _RunFlowFeedPublishFixture();
    final feedStore = CurrentSessionFeedStore(ownerUid: _runFlowFeedOwnerUid);
    addTearDown(feedFixture.dispose);
    addTearDown(feedStore.dispose);
    await tester.pumpWidget(
      CurrentSessionFeedScope(
        store: feedStore,
        child: MaterialApp(
          home: ViewSummaryScreen(
            completionResult: _RunFlowFeedPublishFixture.completionResult,
            feedPublishService: feedFixture.feedPublishService,
            historyArtifactResolver: feedFixture.historyArtifactResolver,
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Share Route'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Share Route'));
    await tester.pumpAndSettle();

    expect(find.text('Share Your Achievement'), findsOneWidget);
    expect(find.text('Post to Feed'), findsOneWidget);
    expect(find.text('East Coast Park Loop'), findsNothing);
    expect(find.text('4.03 km'), findsOneWidget);
    expect(find.text('6’30” / km'), findsOneWidget);
    expect(find.text('30:15'), findsAtLeastNWidgets(2));
    expect(find.text('Route sharing will be available soon.'), findsNothing);
    final preview = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
    );
    expect((preview.image as MemoryImage).bytes, same(_runFlowHistoryPng));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(feedFixture.gateway.stageCalls, 0);
    expect(feedFixture.gateway.publishCalls, 0);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Share Route'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Post to Feed'));
    await tester.pumpAndSettle();

    expect(find.text('Share Your Achievement'), findsNothing);
    expect(feedFixture.gateway.stageCalls, 1);
    expect(feedFixture.gateway.publishCalls, 1);
    expect(feedFixture.gateway.stagedPngBytes, same(_runFlowHistoryPng));
    expect(
      feedStore.thumbnailFor('run-flow-feed-post'),
      same(_runFlowHistoryPng),
    );
  });

  testWidgets(
    'Share Route uses a summary route thumbnail when no artifact resolver is injected',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      final gateway = _RecordingFeedPublishGateway();
      final routeSummary = _summaryWithRoute();
      await tester.pumpWidget(
        MaterialApp(
          home: ViewSummaryScreen(
            completionResult: CompleteRunResult(
              clientRunSessionId: _runFlowFeedClientSessionId,
              activityId: _runFlowFeedActivityId,
              summary: routeSummary,
              xpUpdate: defaultXpUpdateDisplayModel,
            ),
            feedPublishService: FeedPublishService(gateway: gateway),
          ),
        ),
      );

      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Share Route'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Share Route'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Share Your Achievement'), findsOneWidget);
      expect(
        find.text(
          'Your private route preview is unavailable. Your run is still saved.',
        ),
        findsNothing,
      );
      final preview = tester.widget<Image>(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is MemoryImage,
        ),
      );
      final bytes = (preview.image as MemoryImage).bytes;
      expect(bytes, isNot(same(_runFlowHistoryPng)));
      expect(bytes.sublist(0, 8), const <int>[137, 80, 78, 71, 13, 10, 26, 10]);

      await tester.tap(find.widgetWithText(FilledButton, 'Post to Feed'));
      await tester.pumpAndSettle();

      expect(gateway.stageCalls, 1);
      expect(gateway.publishCalls, 1);
      expect(gateway.stagedPngBytes, same(bytes));
    },
  );

  testWidgets(
    'Share Route keeps the route preview for a local run while posting stays disabled',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: ViewSummaryScreen(
            summary: _summaryWithRoute(),
            feedPublishSource: const RunFeedPublishSource.disabled(
              FeedPublishDisabledReason.localOnly,
            ),
          ),
        ),
      );

      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Share Route'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Share Route'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Share Your Achievement'), findsOneWidget);
      expect(
        find.text(
          'This run is still local. Save it to your account before posting to Feed.',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is MemoryImage,
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Post to Feed'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'Activity History Share Route uses canonical backend activity id',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      final feedFixture = _RunFlowFeedPublishFixture();
      addTearDown(feedFixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ViewSummaryScreen(
            feedPublishSource: const RunFeedPublishSource.enabled(
              activityId: 'history-backend-activity',
              cacheIdentity: _runFlowFeedClientSessionId,
              allowsCurrentSessionRouteCapture: true,
            ),
            feedPublishService: feedFixture.feedPublishService,
            historyArtifactResolver: feedFixture.historyArtifactResolver,
          ),
        ),
      );

      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Share Route'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Share Route'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Post to Feed'));
      await tester.pumpAndSettle();

      expect(feedFixture.gateway.stageActivityIds, <String>[
        'history-backend-activity',
      ]);
      expect(feedFixture.gateway.publishActivityIds, <String>[
        'history-backend-activity',
      ]);
      expect(feedFixture.gateway.stagedPngBytes, same(_runFlowHistoryPng));
    },
  );

  testWidgets('View summary accepts selected static run summary data', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: ViewSummaryScreen(
          summary: RunSummarySnapshot(
            title: 'Recovery Jog',
            dateLabel: '4/11/26',
            timeLabel: '8:10 PM',
            distanceKm: '5.17',
            avgPace: '7’40”',
            duration: '39:38',
            avgHeartRate: '132',
            calories: '286',
            routeName: 'Park Connector Recovery Loop',
          ),
        ),
      ),
    );

    expect(find.text('Recovery Jog'), findsOneWidget);
    expect(find.text('4/11/26 · 8:10 PM'), findsOneWidget);
    expect(find.text('Park Connector Recovery Loop'), findsNothing);
    expect(find.text('5.17'), findsOneWidget);
    expect(find.text('7’40”'), findsOneWidget);
    expect(find.text('39:38'), findsOneWidget);
    expect(find.text('132 bpm'), findsOneWidget);
    expect(find.text('286 kcal'), findsOneWidget);
    expect(find.text('Saturday Morning Run'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Share Route'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'View XP Update'), findsOneWidget);

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'More Details'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'More Details'));
    await tester.pumpAndSettle();

    expect(find.text('Recovery Jog'), findsOneWidget);
    expect(find.text('4/11/26 · 8:10 PM'), findsOneWidget);
    expect(find.text('Saturday Morning Run'), findsNothing);

    final advancedAnalysis = tester.widget<AdvancedAnalysisScreen>(
      find.byType(AdvancedAnalysisScreen),
    );
    final snapshot = advancedAnalysis.analysisSnapshot;

    expect(snapshot, isNotNull);
    expect(snapshot!.performance.duration.valueLabel, '39:38');
    expect(snapshot.performance.distance.valueLabel, '5.17');
    expect(snapshot.pace.averagePace.valueLabel, '7’40”');
    expect(
      snapshot.performance.duration.availability,
      AdvancedAnalysisMetricAvailability.available,
    );
    expect(snapshot.performance.duration.isTrustedProduction, isTrue);
    expect(snapshot.performance.score.isTrustedProduction, isFalse);
    expect(
      snapshot.performance.scoreMode,
      AdvancedAnalysisScoreSourceMode.mobileOnly,
    );
    expect(snapshot.pace.fastestPace.isTrustedProduction, isFalse);
    expect(find.text('Pace Analysis'), findsOneWidget);
    expect(find.text('7’40”'), findsOneWidget);
    expect(find.text('5’58”'), findsNothing);
    expect(find.text('7’05”'), findsNothing);
    expect(find.text('86'), findsNothing);
    expect(find.text('--'), findsAtLeastNWidgets(8));
    expect(
      find.byKey(const ValueKey('advanced_analysis_pace_graph_unavailable')),
      findsOneWidget,
    );
    expect(find.text('Pace Over Distance'), findsOneWidget);
    expect(find.text('Km'), findsOneWidget);
    expect(find.text('Pace'), findsOneWidget);
    expect(find.text('Elev'), findsOneWidget);
    expect(find.text('HR'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('--'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('1'), findsNothing);
    expect(_advancedAnalysisSplitDistanceText('2'), findsNothing);
    expect(_advancedAnalysisSplitDistanceText('3'), findsNothing);
    expect(_advancedAnalysisSplitDistanceText('4'), findsNothing);
    expect(_advancedAnalysisSplitDistanceText('0.03'), findsNothing);
    expect(find.text('1 km'), findsNothing);
    expect(find.text('2 km'), findsNothing);
    expect(find.text('3 km'), findsNothing);
    expect(find.text('4 km'), findsNothing);
    expect(find.text('0.03 km'), findsNothing);
    expect(find.text('4.03 km'), findsNothing);
    expect(find.text('4.03 ...'), findsNothing);
    expect(find.text('6’24”'), findsNothing);
    expect(find.text('6’33”'), findsNothing);
    expect(find.text('6’41”'), findsNothing);
    expect(find.text('6’21”'), findsNothing);
    expect(find.text('0’16”'), findsNothing);
    expect(find.text('--'), findsAtLeastNWidgets(8));
    expect(
      find.text(
        'Your pace slowed slightly in the middle section but recovered well in the final part.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Heart Rate Analysis'));

    expect(find.text('145'), findsNothing);
    expect(find.text('158'), findsNothing);
    expect(find.text('130–150'), findsNothing);
    expect(find.text('72'), findsNothing);
    expect(find.text('Target Zone'), findsNothing);
    expect(find.text('Time in Zone'), findsNothing);
    expect(
      find.text('Heart rate was not recorded for this run.'),
      findsOneWidget,
    );
  });

  testWidgets('View summary passes available pace graph into Advanced Analysis', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);
    const snapshotGraph = PaceGraphSnapshot(
      isAvailable: true,
      points: [
        PaceGraphPoint(
          elapsedSeconds: 0,
          progressFraction: 0,
          paceSecondsPerKm: 500,
          distanceProgressFraction: 0,
        ),
        PaceGraphPoint(
          elapsedSeconds: 120,
          progressFraction: 0.5,
          paceSecondsPerKm: 470,
          distanceProgressFraction: 0.2,
        ),
        PaceGraphPoint(
          elapsedSeconds: 240,
          progressFraction: 1,
          paceSecondsPerKm: 490,
          distanceProgressFraction: 1,
        ),
      ],
      yAxisLabels: ['7:40', '8:00', '8:20'],
      xAxisLabels: ['0:00', '2:00', '4:00'],
      distanceAxisLabels: ['0 km', '0.2 km', '0.5 km'],
      paceRangeMinSecondsPerKm: 460,
      paceRangeMaxSecondsPerKm: 520,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ViewSummaryScreen(
          summary: RunSummarySnapshot(
            title: 'Local Graph Run',
            dateLabel: '4/11/26',
            timeLabel: '8:10 PM',
            distanceKm: '0.50',
            avgPace: '8’00”',
            duration: '4:00',
            avgHeartRate: '--',
            calories: '32',
            routeName: 'Private route',
            paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
              samples: <PaceAnalysisSample>[
                PaceAnalysisSample.accepted(
                  elapsedSeconds: 60,
                  cumulativeDistanceMeters: 125,
                  paceSecondsPerKm: 500,
                ),
                PaceAnalysisSample.accepted(
                  elapsedSeconds: 120,
                  cumulativeDistanceMeters: 250,
                  paceSecondsPerKm: 470,
                ),
                PaceAnalysisSample.accepted(
                  elapsedSeconds: 240,
                  cumulativeDistanceMeters: 500,
                  paceSecondsPerKm: 490,
                ),
              ],
            ),
            paceGraph: snapshotGraph,
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'More Details'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'More Details'));
    await tester.pumpAndSettle();

    final pacePainters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<AdvancedAnalysisPaceChartPainter>();
    final pacePainter = pacePainters.singleWhere(
      (painter) => identical(painter.graph, snapshotGraph),
    );

    expect(
      pacePainters.any((painter) => identical(painter.graph, snapshotGraph)),
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('advanced_analysis_pace_graph_unavailable')),
      findsNothing,
    );
    expect(find.text('Pace Over Distance'), findsOneWidget);
    expect(find.text('7’50”'), findsOneWidget);
    expect(find.text('8’20”'), findsOneWidget);
    expect(find.text('81'), findsOneWidget);
    expect(pacePainter.snapshotXAxisLabels, ['0 km', '0.2 km', '0.5 km']);
    expect(pacePainter.snapshotXAxisLabels, isNot(contains('0:00')));
    expect(pacePainter.snapshotXAxisLabels, isNot(contains('2:00')));
    expect(pacePainter.snapshotXAxisLabels, isNot(contains('4:00')));
    expect(pacePainter.snapshotXProgressFractions, [0, 0.2, 1]);
    expect(
      pacePainter.snapshotXProgressFractions,
      isNot(
        equals(
          snapshotGraph.points.map((point) => point.progressFraction).toList(),
        ),
      ),
    );
    expect(find.text('Km'), findsOneWidget);
    expect(find.text('Pace'), findsOneWidget);
    expect(find.text('Elev'), findsOneWidget);
    expect(find.text('HR'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('--'), findsNothing);
    expect(_advancedAnalysisSplitDistanceText('0.50'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('1'), findsNothing);
    expect(_advancedAnalysisSplitDistanceText('2'), findsNothing);
    expect(_advancedAnalysisSplitDistanceText('3'), findsNothing);
    expect(_advancedAnalysisSplitDistanceText('4'), findsNothing);
    expect(_advancedAnalysisSplitDistanceText('0.03'), findsNothing);
    expect(find.text('1 km'), findsNothing);
    expect(find.text('2 km'), findsNothing);
    expect(find.text('3 km'), findsNothing);
    expect(find.text('4 km'), findsNothing);
    expect(find.text('0.03 km'), findsNothing);
    expect(find.text('4.03 km'), findsNothing);
    expect(find.text('4.03 ...'), findsNothing);
    expect(find.text('4’00”'), findsOneWidget);
    expect(find.text('6’24”'), findsNothing);
    expect(find.text('6’33”'), findsNothing);
    expect(find.text('6’41”'), findsNothing);
    expect(find.text('6’21”'), findsNothing);
    expect(find.text('0’16”'), findsNothing);
    expect(find.text('--'), findsAtLeastNWidgets(4));
    expect(
      find.text(
        'Your pace slowed slightly in the middle section but recovered well in the final part.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Activity History Pace Graph QA run renders accountable pace metrics',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      final qaActivity = activityHistoryDisplayData.first.activities.first;
      final qaSummary = qaActivity.summary;

      expect(qaActivity.title, 'Pace Graph QA Run');
      expect(qaSummary.sourceType, RunSourceType.runiacGps);
      expect(qaSummary.paceGraph.isAvailable, isTrue);
      expect(qaSummary.paceAnalysisSeries, isNotNull);
      expect(qaSummary.paceAnalysisSeries!.isLocalAcceptedSource, isTrue);
      expect(
        qaSummary.paceAnalysisSeries!.validAcceptedSamples,
        hasLength(greaterThanOrEqualTo(3)),
      );

      await tester.pumpWidget(
        MaterialApp(home: ViewSummaryScreen(summary: qaSummary)),
      );

      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'More Details'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'More Details'));
      await tester.pumpAndSettle();

      final advancedAnalysis = tester.widget<AdvancedAnalysisScreen>(
        find.byType(AdvancedAnalysisScreen),
      );
      final snapshot = advancedAnalysis.analysisSnapshot;
      final pace = snapshot?.pace;
      final cadence = snapshot?.formCadence;

      expect(snapshot, isNotNull);
      expect(pace, isNotNull);
      expect(cadence, isNotNull);
      expect(pace!.fastestPace.valueLabel, isNot('--'));
      expect(pace.slowestPace.valueLabel, isNot('--'));
      expect(pace.paceStability.valueLabel, isNot('--'));
      expect(
        _paceSeconds(pace.fastestPace.valueLabel!),
        lessThan(_paceSeconds(pace.slowestPace.valueLabel!)),
      );

      final pacePainters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<AdvancedAnalysisPaceChartPainter>();
      expect(
        pacePainters.any(
          (painter) => identical(painter.graph, qaSummary.paceGraph),
        ),
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('advanced_analysis_pace_graph_unavailable')),
        findsNothing,
      );
      expect(find.text('Pace Analysis'), findsOneWidget);
      expect(find.text(pace.fastestPace.valueLabel!), findsOneWidget);
      expect(find.text(pace.slowestPace.valueLabel!), findsOneWidget);
      expect(find.text(pace.paceStability.valueLabel!), findsOneWidget);
      expect(_advancedAnalysisSplitDistanceText('1'), findsOneWidget);
      expect(_advancedAnalysisSplitDistanceText('0.10'), findsOneWidget);
      expect(
        find.text(
          'Your pace slowed slightly in the middle section but recovered well in the final part.',
        ),
        findsOneWidget,
      );

      expect(
        cadence!.cadenceGraph.availability,
        AdvancedAnalysisMetricAvailability.available,
      );
      expect(
        cadence.cadenceGraph.source,
        AdvancedAnalysisMetricSource.localGpsDerived,
      );
      final cadenceGraph = cadence.cadenceGraph.value;
      expect(cadenceGraph, isNotNull);
      expect(cadenceGraph!.isAvailable, isTrue);
      expect(cadenceGraph.points.map((point) => point.cadenceSpm), [
        173,
        170,
        172,
        174,
        176,
      ]);
      expect(cadenceGraph.points.first.elapsedSeconds, 0);
      expect(cadenceGraph.points.first.progressFraction, 0);
      expect(cadenceGraph.lowestCadencePoint?.cadenceSpm, 170);
      expect(cadenceGraph.highestCadencePoint?.cadenceSpm, 176);
      expect(cadenceGraph.targetLabel, demoCadenceGraphTargetLabel);
      expect(cadenceGraph.targetMinCadenceSpm, demoCadenceGraphTargetMinSpm);
      expect(cadenceGraph.targetMaxCadenceSpm, demoCadenceGraphTargetMaxSpm);
      expect(cadenceGraph.targetKind, CadenceGraphTargetKind.demo);

      await tester.ensureVisible(find.text('Running Form / Cadence'));
      expect(find.text('Running Form / Cadence'), findsOneWidget);
      expect(find.text('173'), findsOneWidget);
      expect(find.text('170'), findsOneWidget);
      expect(find.text('176'), findsOneWidget);
      expect(find.text('Stable'), findsWidgets);

      final cadencePainters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<AdvancedAnalysisCadenceChartPainter>();
      expect(
        cadencePainters.any(
          (painter) => identical(painter.graph, cadenceGraph),
        ),
        isTrue,
      );
    },
  );

  testWidgets('View summary renders snapshot-backed split rows', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);
    const snapshotGraph = PaceGraphSnapshot(
      isAvailable: true,
      points: [
        PaceGraphPoint(
          elapsedSeconds: 0,
          progressFraction: 0,
          paceSecondsPerKm: 390,
          distanceProgressFraction: 0,
        ),
        PaceGraphPoint(
          elapsedSeconds: 360,
          progressFraction: 0.25,
          paceSecondsPerKm: 360,
          distanceProgressFraction: 1 / 4.03,
        ),
        PaceGraphPoint(
          elapsedSeconds: 750,
          progressFraction: 0.5,
          paceSecondsPerKm: 390,
          distanceProgressFraction: 2 / 4.03,
        ),
        PaceGraphPoint(
          elapsedSeconds: 1170,
          progressFraction: 0.75,
          paceSecondsPerKm: 420,
          distanceProgressFraction: 3 / 4.03,
        ),
        PaceGraphPoint(
          elapsedSeconds: 1560,
          progressFraction: 0.98,
          paceSecondsPerKm: 390,
          distanceProgressFraction: 4 / 4.03,
        ),
      ],
      yAxisLabels: ['6:00', '6:30', '7:00'],
      xAxisLabels: ['0:00', '13:13', '26:26'],
      distanceAxisLabels: ['0 km', '2 km', '4.03 km'],
      totalDurationSeconds: 1586,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: ViewSummaryScreen(
          summary: RunSummarySnapshot(
            title: 'Local Split Run',
            dateLabel: '4/11/26',
            timeLabel: '8:10 PM',
            distanceKm: '4.03 km',
            avgPace: '6’30” / km',
            duration: '26:26',
            avgHeartRate: '--',
            calories: '212',
            routeName: 'Private route',
            paceGraph: snapshotGraph,
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'More Details'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'More Details'));
    await tester.pumpAndSettle();

    expect(find.text('Pace Analysis'), findsOneWidget);
    expect(find.text('Km'), findsOneWidget);
    expect(find.text('Pace'), findsOneWidget);
    expect(find.text('Elev'), findsOneWidget);
    expect(find.text('HR'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('1'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('2'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('3'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('4'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('0.03'), findsOneWidget);
    expect(find.text('6’00”'), findsOneWidget);
    expect(find.text('6’30”'), findsWidgets);
    expect(find.text('7’00”'), findsOneWidget);
    expect(find.text('0’26”'), findsOneWidget);
    expect(find.text('6’24”'), findsNothing);
    expect(find.text('6’33”'), findsNothing);
    expect(find.text('6’41”'), findsNothing);
    expect(find.text('6’21”'), findsNothing);
    expect(find.text('0’16”'), findsNothing);
    expect(find.text('--'), findsAtLeastNWidgets(10));
    expect(
      find.text(
        'Your pace slowed slightly in the middle section but recovered well in the final part.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'View summary renders deterministic coaching summary without AI label by default',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);

      await tester.pumpWidget(const MaterialApp(home: ViewSummaryScreen()));

      expect(find.text('Coaching Summary'), findsOneWidget);
      expect(find.text('AI Coaching Summary'), findsNothing);
      expect(find.text(_defaultDemoCoachingHeadline), findsOneWidget);
      expect(find.text(_defaultDemoCoachingMessage), findsOneWidget);
      expect(find.text('Next Focus'), findsOneWidget);
      expect(find.text('Next Action'), findsNothing);
      expect(find.text(_defaultDemoNextFocus), findsOneWidget);
      expect(
        _defaultDemoCoachingMessage.split(RegExp(r'\s+')),
        hasLength(inInclusiveRange(35, 80)),
      );
      expect(
        RegExp(r'[.!?]').allMatches(_defaultDemoCoachingMessage),
        hasLength(inInclusiveRange(2, 4)),
      );
      expect(
        _defaultDemoCoachingMessage,
        isNot(contains(_forbiddenDemoCoachingCopy)),
      );
    },
  );

  testWidgets('ui_renders_multisentence_coaching_message', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);

    const message =
        'This was a short but useful run. The available pace points suggest a steady rhythm, which is a useful sign for building consistency. Since heart-rate data was not available, the safest takeaway is your pacing rhythm rather than how hard it felt.';

    await tester.pumpWidget(
      const MaterialApp(
        home: ViewSummaryScreen(
          summary: RunSummarySnapshot(
            title: 'Short Steady Run',
            dateLabel: 'Today',
            timeLabel: '7:10 AM',
            distanceKm: '0.72',
            avgPace: '7’20”',
            duration: '5:45',
            avgHeartRate: '--',
            calories: '43',
            routeName: 'Private route',
            coachingSummary: CoachingSummarySnapshot(
              source: CoachingSummarySource.ruleBased,
              headline: 'A short, steady start',
              message: message,
              nextAction:
                  'Next time, add a few easy minutes while keeping the same calm start.',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Coaching Summary'), findsOneWidget);
    expect(find.text('A short, steady start'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    expect(find.text('Next Focus'), findsOneWidget);
    expect(find.text('Next Action'), findsNothing);
    expect(
      find.text(
        'Next time, add a few easy minutes while keeping the same calm start.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'View summary maps AI source to AI Coaching Summary only when explicitly returned',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: ViewSummaryScreen(
            summary: defaultRunSummarySnapshot.copyWith(
              coachingSummary: const CoachingSummarySnapshot(
                source: CoachingSummarySource.aiGenerated,
                headline: 'AI source summary headline',
                message:
                    'This synthetic summary is supplied only by an explicit AI source.',
                bullets: ['Synthetic AI bullet from returned model.'],
                nextAction: 'Use returned model copy only.',
              ),
            ),
          ),
        ),
      );

      expect(find.text('AI Coaching Summary'), findsOneWidget);
      expect(find.text('Coaching Summary'), findsNothing);
      expect(find.text('AI source summary headline'), findsOneWidget);
      expect(
        find.text(
          'This synthetic summary is supplied only by an explicit AI source.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Synthetic AI bullet from returned model.'),
        findsOneWidget,
      );
      expect(find.text('Use returned model copy only.'), findsOneWidget);
    },
  );

  testWidgets(
    'View summary renders completed route preview when route exists',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      await tester.pumpWidget(
        MaterialApp(
          home: ViewSummaryScreen(
            summary: RunSummarySnapshot(
              title: 'Completed Route Run',
              dateLabel: 'Today',
              timeLabel: '8:10 AM',
              distanceKm: '0.30',
              avgPace: '6’40”',
              duration: '2:00',
              avgHeartRate: '--',
              calories: '27',
              routeName: 'Actual Local Route',
              route: RunRouteSnapshot(
                segments: [
                  [
                    RunLocationSample(
                      recordedAt: startedAt,
                      latitude: 1.300000,
                      longitude: 103.800000,
                    ),
                    RunLocationSample(
                      recordedAt: startedAt.add(const Duration(seconds: 60)),
                      latitude: 1.300899,
                      longitude: 103.800000,
                    ),
                  ],
                ],
                lastKnownLocation: RunLocationSample(
                  recordedAt: startedAt.add(const Duration(seconds: 60)),
                  latitude: 1.300899,
                  longitude: 103.800000,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('summary_route_preview_route')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('summary_route_preview_dot')), findsNothing);
      expect(
        find.byKey(const Key('summary_route_preview_placeholder')),
        findsNothing,
      );
      expect(find.text('Actual Local Route'), findsNothing);
    },
  );

  testWidgets('View summary map preview removes route label pill overlay', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);
    final startedAt = DateTime.utc(2026, 6, 14, 7);

    await tester.pumpWidget(
      MaterialApp(
        home: ViewSummaryScreen(
          summary: RunSummarySnapshot(
            title: 'Completed Route Run',
            dateLabel: 'Today',
            timeLabel: '8:10 AM',
            distanceKm: '0.30',
            avgPace: '6’40”',
            duration: '2:00',
            avgHeartRate: '--',
            calories: '27',
            routeName: 'Easy local route',
            route: RunRouteSnapshot(
              segments: [
                [
                  RunLocationSample(
                    recordedAt: startedAt,
                    latitude: 1.300000,
                    longitude: 103.800000,
                  ),
                  RunLocationSample(
                    recordedAt: startedAt.add(const Duration(seconds: 60)),
                    latitude: 1.300899,
                    longitude: 103.800000,
                  ),
                ],
              ],
              lastKnownLocation: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 60)),
                latitude: 1.300899,
                longitude: 103.800000,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Easy local route'), findsNothing);
  });

  testWidgets(
    'View summary uses Mapbox completed route preview when token is available',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      CompletedRouteMapboxSurfaceConfig? capturedConfig;

      await tester.pumpWidget(
        MaterialApp(
          home: ViewSummaryScreen(
            mapboxAccessToken: 'pk.summary-test-token',
            mapboxBuilder: (context, config) {
              capturedConfig = config;
              return const ColoredBox(
                key: Key('fake_summary_mapbox_preview'),
                color: Colors.black,
              );
            },
            summary: RunSummarySnapshot(
              title: 'Mapbox Route Run',
              dateLabel: 'Today',
              timeLabel: '8:10 AM',
              distanceKm: '0.30',
              avgPace: '6’40”',
              duration: '2:00',
              avgHeartRate: '--',
              calories: '27',
              routeName: 'Actual Local Route',
              route: RunRouteSnapshot(
                segments: [
                  [
                    RunLocationSample(
                      recordedAt: startedAt,
                      latitude: 1.300000,
                      longitude: 103.800000,
                    ),
                    RunLocationSample(
                      recordedAt: startedAt.add(const Duration(seconds: 60)),
                      latitude: 1.300899,
                      longitude: 103.800000,
                    ),
                  ],
                ],
                lastKnownLocation: RunLocationSample(
                  recordedAt: startedAt.add(const Duration(seconds: 60)),
                  latitude: 1.300899,
                  longitude: 103.800000,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('summary_route_mapbox_preview_selected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('fake_summary_mapbox_preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('summary_route_preview_route')),
        findsNothing,
      );
      expect(capturedConfig, isNotNull);
      expect(capturedConfig!.isExpanded, isFalse);
      expect(capturedConfig!.route.hasRoute, isTrue);
      expect(capturedConfig!.accessToken, 'pk.summary-test-token');
    },
  );

  testWidgets(
    'View summary renders last-location dot when completed route is unavailable',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      final recordedAt = DateTime.utc(2026, 6, 14, 7, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: ViewSummaryScreen(
            summary: RunSummarySnapshot(
              title: 'Location Only Run',
              dateLabel: 'Today',
              timeLabel: '8:11 AM',
              distanceKm: '0.00',
              avgPace: '--',
              duration: '0:30',
              avgHeartRate: '--',
              calories: '--',
              routeName: 'Private route',
              route: RunRouteSnapshot(
                lastKnownLocation: RunLocationSample(
                  recordedAt: recordedAt,
                  latitude: 1.300100,
                  longitude: 103.800000,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('summary_route_preview_dot')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('summary_route_preview_route')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('summary_route_preview_placeholder')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'View summary keeps neutral placeholder when no route or location exists',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);

      await tester.pumpWidget(
        const MaterialApp(
          home: ViewSummaryScreen(
            summary: RunSummarySnapshot(
              title: 'No Location Run',
              dateLabel: 'Today',
              timeLabel: '8:12 AM',
              distanceKm: '0.00',
              avgPace: '--',
              duration: '0:00',
              avgHeartRate: '--',
              calories: '--',
              routeName: 'Private route',
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('summary_route_preview_placeholder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('summary_route_preview_route')),
        findsNothing,
      );
      expect(find.byKey(const Key('summary_route_preview_dot')), findsNothing);
    },
  );

  testWidgets('Tapping route preview opens and closes expanded map', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);
    final startedAt = DateTime.utc(2026, 6, 14, 7);

    await tester.pumpWidget(
      MaterialApp(
        home: ViewSummaryScreen(
          mapboxAccessToken: 'pk.summary-test-token',
          mapboxBuilder: (context, config) {
            return ColoredBox(
              key: Key(
                config.isExpanded
                    ? 'fake_summary_mapbox_expanded'
                    : 'fake_summary_mapbox_preview',
              ),
              color: Colors.black,
            );
          },
          summary: RunSummarySnapshot(
            title: 'Expanded Route Run',
            dateLabel: 'Today',
            timeLabel: '8:10 AM',
            distanceKm: '0.30',
            avgPace: '6’40”',
            duration: '2:00',
            avgHeartRate: '--',
            calories: '27',
            routeName: 'Actual Local Route',
            route: RunRouteSnapshot(
              segments: [
                [
                  RunLocationSample(
                    recordedAt: startedAt,
                    latitude: 1.300000,
                    longitude: 103.800000,
                  ),
                  RunLocationSample(
                    recordedAt: startedAt.add(const Duration(seconds: 60)),
                    latitude: 1.300899,
                    longitude: 103.800000,
                  ),
                ],
              ],
              lastKnownLocation: RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 60)),
                latitude: 1.300899,
                longitude: 103.800000,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('summary_route_preview_tap_target')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('summary_route_expanded_screen')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('fake_summary_mapbox_expanded')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('summary_route_expanded_close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('summary_route_expanded_screen')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('fake_summary_mapbox_preview')),
      findsOneWidget,
    );
  });

  testWidgets(
    'View summary shows unavailable completion metrics without fake units',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);

      await tester.pumpWidget(
        const MaterialApp(
          home: ViewSummaryScreen(
            completionResult: CompleteRunResult(
              activityId: 'unavailable-metrics-activity',
              summaryId: 'unavailable-metrics-summary',
              progressionEventId: 'unavailable-metrics-progression',
              validationStatus: 'validated',
              summary: RunSummarySnapshot(
                title: 'Tracked Completion Run',
                dateLabel: 'Today',
                timeLabel: '8:10 AM',
                distanceKm: '3.20',
                avgPace: '7’49”',
                duration: '25:00',
                avgHeartRate: '--',
                calories: '--',
                routeName: 'Tracked Private Route',
              ),
              progressionDisplay: ProgressionDisplayModel(
                xpDelta: 0,
                countsTowardLeaderboard: false,
                status: 'deferred',
                reason: 'progression_formula_deferred',
              ),
              xpUpdate: XpUpdateDisplayModel(
                runnerName: 'Runiac Runner',
                earnedXpLabel: '+0 XP',
                totalXpLabel: 'Deferred by backend',
                levelLabel: 'Pending',
                nextLevelLabel: 'Pending',
                progressTargetLabel: 'Progression deferred',
                xpRemainingLabel: 'Backend formula pending',
                previousProgressFraction: 0,
                currentProgressFraction: 0,
                streakChangeLabel: 'Deferred',
                streakNote: 'Backend validation accepted the run.',
                didLevelUp: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Tracked Completion Run'), findsOneWidget);
      expect(find.text('Tracked Private Route'), findsNothing);
      expect(find.text('3.20'), findsOneWidget);
      expect(find.text('7’49”'), findsOneWidget);
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('Est. calories'), findsOneWidget);
      expect(find.text('--'), findsAtLeastNWidgets(2));
      expect(find.text('-- bpm'), findsNothing);
      expect(find.text('-- kcal'), findsNothing);
      expect(find.text('145 bpm'), findsNothing);
      expect(find.text('145 kcal'), findsNothing);
    },
  );

  testWidgets('Summary shows truthful heart rate source states', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: ViewSummaryScreen(
          summary: RunSummarySnapshot(
            title: 'Local GPS Run',
            dateLabel: 'Today',
            timeLabel: '8:10 AM',
            distanceKm: '3.20',
            avgPace: '7’49”',
            duration: '25:00',
            avgHeartRate: '--',
            calories: '270',
            routeName: 'Private route',
          ),
        ),
      ),
    );

    expect(find.text('Runiac GPS'), findsOneWidget);
    expect(find.text('Avg Heart Rate'), findsOneWidget);
    expect(find.text('--'), findsAtLeastNWidgets(1));
    expect(find.text('-- bpm'), findsNothing);
    expect(
      find.text('Heart rate unavailable for Runiac GPS runs.'),
      findsNothing,
    );
    expect(
      find.text('Heart rate was not shared by this source.'),
      findsNothing,
    );
    expect(find.text('Pace Over Time'), findsOneWidget);
    expect(find.text('Splits'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: ViewSummaryScreen(
          summary: RunSummarySnapshot(
            title: 'Imported Watch Run',
            dateLabel: 'Today',
            timeLabel: '8:10 AM',
            distanceKm: '5.12',
            avgPace: '6’45”',
            duration: '34:32',
            avgHeartRate: '145',
            calories: '312',
            routeName: 'Imported route',
            sourceType: RunSourceType.appleHealth,
          ),
        ),
      ),
    );

    expect(find.text('Apple Health'), findsOneWidget);
    expect(find.text('145 bpm'), findsOneWidget);
    expect(
      find.text('Heart rate unavailable for Runiac GPS runs.'),
      findsNothing,
    );
    expect(
      find.text('Heart rate was not shared by this source.'),
      findsNothing,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: ViewSummaryScreen(
          summary: RunSummarySnapshot(
            title: 'Imported No HR Run',
            dateLabel: 'Today',
            timeLabel: '8:10 AM',
            distanceKm: '4.03',
            avgPace: '6’30”',
            duration: '30:15',
            avgHeartRate: '--',
            calories: '242',
            routeName: 'Imported route',
            sourceType: RunSourceType.healthConnect,
          ),
        ),
      ),
    );

    expect(find.text('Health Connect'), findsOneWidget);
    expect(find.text('Avg Heart Rate'), findsOneWidget);
    expect(find.text('--'), findsAtLeastNWidgets(1));
    expect(find.text('-- bpm'), findsNothing);
    expect(
      find.text('Heart rate was not shared by this source.'),
      findsNothing,
    );
    expect(
      find.text('Heart rate unavailable for Runiac GPS runs.'),
      findsNothing,
    );
  });

  testWidgets('Low-data view summary softens copy and routes home', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: ViewSummaryScreen(
          completionResult: CompleteRunResult(
            activityId: 'low-data-activity',
            summaryId: 'low-data-summary',
            progressionEventId: 'low-data-progression',
            validationStatus: 'validated',
            summary: RunSummarySnapshot(
              title: 'Short Start',
              dateLabel: 'Today',
              timeLabel: '8:10 AM',
              distanceKm: '0.02',
              avgPace: '--',
              duration: '0:35',
              avgHeartRate: '--',
              calories: '--',
              routeName: 'Easy local route',
              hasSufficientData: false,
              coachingSummary: CoachingSummarySnapshot(
                source: CoachingSummarySource.ruleBased,
                headline: 'A simple check-in run',
                message:
                    'This run has limited data, so the summary stays careful and simple. Completion still matters because it gives you a check-in point. Heart-rate data was not available, and the pace graph is not usable, so this note avoids effort or pacing claims.',
                nextAction: 'Try one short easy run with GPS ready.',
              ),
            ),
            progressionDisplay: ProgressionDisplayModel(
              xpDelta: 0,
              countsTowardLeaderboard: false,
              status: 'deferred',
              reason: 'progression_formula_deferred',
            ),
            xpUpdate: XpUpdateDisplayModel(
              runnerName: 'Runiac Runner',
              earnedXpLabel: '+0 XP',
              totalXpLabel: 'Deferred by backend',
              levelLabel: 'Pending',
              nextLevelLabel: 'Pending',
              progressTargetLabel: 'Progression deferred',
              xpRemainingLabel: 'Backend formula pending',
              previousProgressFraction: 0,
              currentProgressFraction: 0,
              streakChangeLabel: 'Deferred',
              streakNote: 'Backend validation accepted the run.',
              didLevelUp: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Short Start'), findsOneWidget);
    expect(find.text('0.02'), findsOneWidget);
    expect(find.text('0:35'), findsOneWidget);
    expect(find.text('--'), findsAtLeastNWidgets(3));
    expect(find.text('Coaching Summary'), findsOneWidget);
    expect(find.text('AI Coaching Summary'), findsNothing);
    expect(
      find.text(
        'This run has limited data, so the summary stays careful and simple. Completion still matters because it gives you a check-in point. Heart-rate data was not available, and the pace graph is not usable, so this note avoids effort or pacing claims.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('steady pace'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Share Route'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'View XP Update'), findsNothing);
  });

  testWidgets('low-data Summary guards hardcoded analysis graphs', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: ViewSummaryScreen(
          completionResult: CompleteRunResult(
            activityId: 'low-data-analysis-activity',
            summaryId: 'low-data-analysis-summary',
            progressionEventId: 'low-data-analysis-progression',
            validationStatus: 'validated',
            summary: RunSummarySnapshot(
              title: 'Short Start',
              dateLabel: 'Today',
              timeLabel: '8:10 AM',
              distanceKm: '0.02',
              avgPace: '--',
              duration: '0:35',
              avgHeartRate: '--',
              calories: '--',
              routeName: 'Easy local route',
              hasSufficientData: false,
            ),
            progressionDisplay: ProgressionDisplayModel(
              xpDelta: 0,
              countsTowardLeaderboard: false,
              status: 'deferred',
              reason: 'progression_formula_deferred',
            ),
            xpUpdate: XpUpdateDisplayModel(
              runnerName: 'Runiac Runner',
              earnedXpLabel: '+0 XP',
              totalXpLabel: 'Deferred by backend',
              levelLabel: 'Pending',
              nextLevelLabel: 'Pending',
              progressTargetLabel: 'Progression deferred',
              xpRemainingLabel: 'Backend formula pending',
              previousProgressFraction: 0,
              currentProgressFraction: 0,
              streakChangeLabel: 'Deferred',
              streakNote: 'Backend validation accepted the run.',
              didLevelUp: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pace Over Time'), findsOneWidget);
    expect(find.text('Splits'), findsOneWidget);
    expect(find.text('More run data needed'), findsNWidgets(2));
    expect(
      find.text('Pace insights will appear after a longer run.'),
      findsNWidgets(2),
    );
    expect(find.text('Performance Overview'), findsNothing);

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'More Details'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'More Details'));
    await tester.pumpAndSettle();

    expect(
      find.text('Run a little longer to unlock analysis.'),
      findsOneWidget,
    );
    expect(find.text('Performance Overview'), findsNothing);
    expect(find.byType(AdvancedAnalysisScreen), findsNothing);
  });

  testWidgets(
    'fixture-backed pace graph can render filtered spike run labels',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: ViewSummaryScreen(
            summary: defaultRunSummarySnapshot.copyWith(
              paceGraph: gpsSpikeRunPaceGraph,
            ),
          ),
        ),
      );

      expect(find.text('Pace Over Time'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('8:00'), findsOneWidget);
      expect(find.text('16:00'), findsOneWidget);
      expect(find.text('24:10'), findsOneWidget);
      expect(find.text('1:20'), findsNothing);
      expect(find.text('45:00'), findsNothing);
      expect(find.text('More run data needed'), findsNothing);
    },
  );

  testWidgets('View summary keeps slow pace y-axis labels on one line', (
    WidgetTester tester,
  ) async {
    _useTallSummarySurface(tester);

    const slowLabelGraph = PaceGraphSnapshot(
      isAvailable: true,
      points: [
        PaceGraphPoint(
          elapsedSeconds: 0,
          progressFraction: 0,
          paceSecondsPerKm: 710,
        ),
        PaceGraphPoint(
          elapsedSeconds: 226,
          progressFraction: 0.5,
          paceSecondsPerKm: 780,
        ),
        PaceGraphPoint(
          elapsedSeconds: 452,
          progressFraction: 1,
          paceSecondsPerKm: 860,
        ),
      ],
      yAxisLabels: ['11:50', '15:05', '18:20'],
      xAxisLabels: ['0:00', '3:00', '7:32'],
      totalDurationSeconds: 452,
      averagePaceSecondsPerKm: 729,
      paceRangeMinSecondsPerKm: 710,
      paceRangeMaxSecondsPerKm: 1100,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ViewSummaryScreen(
          summary: defaultRunSummarySnapshot.copyWith(
            paceGraph: slowLabelGraph,
          ),
        ),
      ),
    );

    expect(find.text('Pace Over Time'), findsOneWidget);
    for (final label in ['11:50', '15:05', '18:20']) {
      final labelFinder = find.text(label);
      expect(labelFinder, findsOneWidget);
      expect(tester.getSize(labelFinder).height, lessThanOrEqualTo(11));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'View summary share icon opens Share Your Activity bottom sheet',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      await tester.pumpWidget(const MaterialApp(home: ViewSummaryScreen()));

      expect(find.byTooltip('Share summary'), findsOneWidget);
      expect(find.text('Share Your Activity'), findsNothing);

      await tester.tap(find.byTooltip('Share summary'));
      await tester.pumpAndSettle();

      expect(find.text('Saturday Morning Run'), findsWidgets);
      expect(find.text('Share Your Activity'), findsOneWidget);
    },
  );

  testWidgets(
    'Share achievement sheet renders real activity metrics and new actions',
    (WidgetTester tester) async {
      _useCompactShareSheetSurface(tester);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      String? copiedText;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall methodCall,
      ) async {
        if (methodCall.method == 'Clipboard.setData') {
          copiedText = (methodCall.arguments as Map)['text'] as String?;
          return null;
        }
        return null;
      });

      await tester.pumpWidget(_shareSheetHarness());

      await tester.tap(find.text('Open share sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Share Your Activity'), findsOneWidget);
      // Real values sourced from defaultRunSummarySnapshot via
      // _summaryWithRoute(); distance/pace/duration also render on the
      // transparent overlay card (page 2), so those repeat.
      expect(find.text('4.03'), findsWidgets);
      expect(find.text('km'), findsWidgets);
      expect(find.text('6’30”'), findsWidgets);
      expect(find.text('Avg pace'), findsWidgets);
      expect(find.text('30:15'), findsWidgets);
      expect(find.text('Time'), findsWidgets);
      expect(find.text('Avg HR'), findsOneWidget);
      expect(find.text('145'), findsWidgets);
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('Saturday Morning Run'), findsOneWidget);
      expect(find.text('East Coast Park Loop'), findsOneWidget);
      expect(find.text('Imported run with steady rhythm'), findsOneWidget);
      expect(find.text('Edit card'), findsNothing);
      expect(find.text('Change theme'), findsNothing);
      expect(find.text('Runiac'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('run_share_activity_card_solid')),
          matching: find.image(AssetImage(RuniacAssets.runiacWordmarkLogo)),
        ),
        findsOneWidget,
      );
      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('Copy to Clipboard'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(
        find.byKey(const Key('run_share_activity_map_fallback')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('run_share_activity_map_image')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Copy to Clipboard'));
      await tester.pump();

      expect(find.text('Activity copied to clipboard'), findsOneWidget);
      expect(copiedText, 'I ran 4.03 km in 30:15 at 6’30” pace on Runiac.');
    },
  );

  testWidgets('Share achievement sheet fits iPhone-height surfaces', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_shareSheetHarness());

    await tester.tap(find.text('Open share sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Share Your Activity'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Share achievement sheet close dismisses without leaving summary',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);
      await tester.pumpWidget(const MaterialApp(home: ViewSummaryScreen()));

      await tester.tap(find.byTooltip('Share summary'));
      await tester.pumpAndSettle();

      expect(find.text('Share Your Activity'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.text('Share Your Activity'), findsNothing);
      expect(find.text('Saturday Morning Run'), findsOneWidget);
      expect(find.text('Run saved'), findsNothing);
    },
  );

  testWidgets(
    'Share achievement sheet carousel swipes to the transparent overlay card',
    (WidgetTester tester) async {
      // A generously tall surface: at common phone heights (e.g. the 900pt
      // compact surface used elsewhere in this file) the transparent overlay
      // card's distance hero (share_achievement_sheet.dart _TransparentDistanceHero)
      // overflows by a few pixels because, unlike the solid card's hero, it is
      // not wrapped in a FittedBox. That is a pre-existing widget layout gap
      // outside this test task's scope (no lib/ changes here); using a taller
      // surface keeps this test focused on carousel/page-swap behaviour
      // without tripping over that unrelated overflow.
      tester.view
        ..physicalSize = const Size(390, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_shareSheetHarness());

      await tester.tap(find.text('Open share sheet'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('run_share_activity_card_solid')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('run_share_activity_page_indicator')),
        findsOneWidget,
      );

      await tester.drag(
        find.byKey(const Key('run_share_activity_carousel')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      final transparentCard = find.byKey(
        const Key('run_share_activity_card_transparent'),
      );
      expect(transparentCard, findsOneWidget);
      expect(
        find.descendant(
          of: transparentCard,
          matching: find.byKey(const Key('run_share_activity_transparent_sign')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: transparentCard,
          matching: find.byKey(
            const Key('run_share_activity_transparent_logo'),
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Advanced analysis screen no longer exposes a share action',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdvancedAnalysisScreen(
            title: defaultRunSummarySnapshot.title,
            subtitle: defaultRunSummarySnapshot.dateTimeLabel,
            analysisSnapshot: const AdvancedAnalysisSnapshotBuilder()
                .fromRunSummary(defaultRunSummarySnapshot),
          ),
        ),
      );

      expect(find.byTooltip('Share advanced analysis'), findsNothing);
    },
  );

  testWidgets('Advanced Analysis renders handoff sections and sample values', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdvancedAnalysisScreen(
          title: defaultRunSummarySnapshot.title,
          subtitle: defaultRunSummarySnapshot.dateTimeLabel,
          analysisSnapshot: const AdvancedAnalysisSnapshotBuilder()
              .fromRunSummary(defaultRunSummarySnapshot),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, RuniacColors.background);

    expect(find.text('Saturday Morning Run'), findsOneWidget);
    expect(find.text('Today · 7:06 AM'), findsOneWidget);
    expect(find.text('Run Quality'), findsOneWidget);
    expect(find.text('Building consistency'), findsOneWidget);
    expect(find.text('Phone-tracked effort'), findsNothing);
    expect(find.text('/ 100'), findsOneWidget);
    expect(find.text('Good Endurance'), findsOneWidget);
    expect(find.text('Controlled HR'), findsNothing);

    expect(find.text('Pace Analysis'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('advanced_analysis_pace_graph_unavailable')),
      findsOneWidget,
    );
    expect(_advancedAnalysisSplitDistanceText('1'), findsOneWidget);
    expect(_advancedAnalysisSplitDistanceText('0.03'), findsOneWidget);
    expect(find.text('1 km'), findsNothing);
    expect(find.text('0.03 km'), findsNothing);
    expect(find.text('4.03 km'), findsNothing);
    expect(find.text('4.03 ...'), findsNothing);
    await tester.ensureVisible(find.text('Heart Rate Analysis'));

    expect(find.text('Heart Rate Analysis'), findsOneWidget);
    expect(find.text('Target Zone'), findsNothing);
    expect(find.text('Time in Zone'), findsNothing);
    expect(
      find.text('Heart rate was not recorded for this run.'),
      findsOneWidget,
    );
    expect(find.text('Zone 2'), findsNothing);
    expect(find.text('54%'), findsNothing);
    expect(
      find.text(
        'Heart-rate zones are calculated from available wearable samples for this run.',
      ),
      findsNothing,
    );

    await tester.ensureVisible(find.text('Running Form / Cadence'));

    expect(find.text('Elevation Analysis'), findsOneWidget);
    expect(find.text('+12'), findsNothing);
    expect(find.text('11'), findsNothing);
    expect(find.text('Mostly Flat'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('advanced_analysis_elevation_graph_unavailable'),
      ),
      findsOneWidget,
    );
    expect(find.text('Running Form / Cadence'), findsOneWidget);
    expect(find.text('164'), findsNothing);
    expect(find.text('160–175'), findsNothing);
    expect(find.text('Unavailable'), findsNothing);
    expect(find.text('--'), findsWidgets);
    expect(find.text('Cadence is unavailable for this run.'), findsOneWidget);
    expect(find.text('Recovery Recommendation'), findsNothing);
    expect(find.text('5–8 min'), findsNothing);
    expect(find.text('Drink water'), findsNothing);
    expect(find.text('Ready in 24 hours'), findsNothing);
    expect(find.textContaining(_forbiddenRealActivitySaveCopy), findsNothing);
  });

  testWidgets(
    'Advanced Analysis does not claim steady heart rate when heart rate is unavailable',
    (WidgetTester tester) async {
      _useTallSummarySurface(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: AdvancedAnalysisScreen(
            title: defaultRunSummarySnapshot.title,
            subtitle: defaultRunSummarySnapshot.dateTimeLabel,
            analysisSnapshot: const AdvancedAnalysisSnapshotBuilder()
                .fromRunSummary(defaultRunSummarySnapshot),
          ),
        ),
      );

      await tester.ensureVisible(find.text('Elevation Analysis'));

      expect(find.textContaining('steady heart rate'), findsNothing);
      expect(
        find.text(
          'Route insights use the movement data available for this run.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'View summary removes run complete banner while keeping summary content visible',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: ViewSummaryScreen()));

      expect(find.text('Run complete'), findsNothing);
      expect(find.text('4.03'), findsOneWidget);
      expect(find.text('Pace Over Time'), findsOneWidget);
      expect(find.text('East Coast Park Loop'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('View XP Update opens reward screen and Home exits it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ViewSummaryScreen()));

    expect(find.widgetWithText(FilledButton, 'View XP Update'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Home'), findsNothing);

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'View XP Update'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'View XP Update'));
    await tester.pumpAndSettle();

    expect(find.text('XP & Streak Update'), findsOneWidget);
    expect(find.text('Nice work, Jinseo!'), findsOneWidget);
    expect(find.text('+120 XP'), findsOneWidget);
    expect(find.text('Total XP'), findsOneWidget);
    expect(find.text('2,520 XP'), findsOneWidget);
    // The stamped-in new streak fully replaces the old value.
    expect(find.text('6 days'), findsOneWidget);
    expect(find.text('5 days'), findsNothing);
    expect(find.text('Great consistency!'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Home'), findsOneWidget);
    expect(
      find.textContaining(_forbiddenXpUpdateCompetitiveCopy),
      findsNothing,
    );

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Home'));
    await tester.tap(find.widgetWithText(FilledButton, 'Home'));
    await tester.pumpAndSettle();

    expect(find.text('XP & Streak Update'), findsNothing);
    expect(find.text('Saturday Morning Run'), findsOneWidget);
  });

  testWidgets('Low-data Summary Go to Home asks before saving', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byTooltip('Home'))).push(
      MaterialPageRoute<void>(
        builder: (context) => const ViewSummaryScreen(
          summary: RunSummarySnapshot(
            title: 'Short Check-in Run',
            dateLabel: 'Today',
            timeLabel: '8:10 AM',
            distanceKm: '0.00',
            avgPace: '--',
            duration: '0:00',
            avgHeartRate: '--',
            calories: '--',
            routeName: 'Easy local route',
            hasSufficientData: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('More run data needed'), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Go to Home'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'View XP Update'), findsNothing);
    expect(find.text('XP & Streak Update'), findsNothing);
    expect(find.text('+120 XP'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Go to Home'));
    await tester.pumpAndSettle();

    expect(find.text('Save this short run?'), findsOneWidget);
    expect(
      find.text(
        'This run has limited data, so it may not be useful for analysis. You can still keep it in your running history.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Discard'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save run'), findsOneWidget);
    expect(find.text('Short Check-in Run'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save run'));
    await tester.pumpAndSettle();

    expect(find.text('Short Check-in Run'), findsNothing);
    expect(find.text('XP & Streak Update'), findsNothing);
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Run'), findsOneWidget);
  });

  testWidgets(
    'Low-data run discard does not call repository or persist pending',
    (WidgetTester tester) async {
      final repository = _ResultRunRepository(_lowDataCompletionResult);
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final storage = MemoryLocalPendingRunActivityStore();
      final historyStore = CurrentSessionActivityHistoryStore(
        ownerUid: authRepository.currentUser?.uid,
        persistence: storage,
      );
      addTearDown(historyStore.dispose);
      addTearDown(authRepository.dispose);

      await tester.pumpWidget(
        RuniacApp(
          authRepository: authRepository,
          showSplash: false,
          enableForegroundGps: false,
          runRepository: repository,
          currentSessionActivityHistoryStore: historyStore,
          activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
        ),
      );

      await tester.tap(find.byTooltip('Run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      await _finishPausedRun(tester);

      expect(repository.completeRunCalls, 0);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Go to Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(repository.completeRunCalls, 0);
      expect(await storage.load(), isEmpty);
      expect(historyStore.activities, isEmpty);
      expect(find.byTooltip('Home'), findsOneWidget);
    },
  );

  testWidgets('Low-data run save calls repository only after Save run', (
    WidgetTester tester,
  ) async {
    final repository = _ResultRunRepository(_lowDataCompletionResult);
    final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
    final storage = MemoryLocalPendingRunActivityStore();
    final historyStore = CurrentSessionActivityHistoryStore(
      ownerUid: authRepository.currentUser?.uid,
      persistence: storage,
    );
    addTearDown(historyStore.dispose);
    addTearDown(authRepository.dispose);

    await tester.pumpWidget(
      RuniacApp(
        authRepository: authRepository,
        showSplash: false,
        enableForegroundGps: false,
        runRepository: repository,
        currentSessionActivityHistoryStore: historyStore,
        activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
      ),
    );

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    await _finishPausedRun(tester);

    expect(repository.completeRunCalls, 0);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Go to Home'));
    await tester.pumpAndSettle();
    expect(repository.completeRunCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Save run'));
    await tester.pumpAndSettle();

    expect(repository.completeRunCalls, 1);
    expect(repository.lastPayload?.clientRunSessionId, isNotEmpty);
    expect(
      repository.lastPayload?.clientRunSessionId,
      startsWith('local-run-'),
    );
    expect(repository.lastPayload?.userConfirmedLowDataSave, isTrue);
    expect(historyStore.activities, isNotEmpty);
    expect(find.byTooltip('Home'), findsOneWidget);
  });

  testWidgets('XP Update Home returns to the app Home root', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Home'), findsOneWidget);

    Navigator.of(tester.element(find.byTooltip('Home'))).push(
      MaterialPageRoute<void>(builder: (context) => const ViewSummaryScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'View XP Update'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Home'), findsNothing);

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'View XP Update'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'View XP Update'));
    await tester.pumpAndSettle();

    expect(find.text('XP & Streak Update'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Home'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Home'));
    await tester.tap(find.widgetWithText(FilledButton, 'Home'));
    await tester.pumpAndSettle();

    expect(find.text('XP & Streak Update'), findsNothing);
    expect(find.text('Saturday Morning Run'), findsNothing);
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Run'), findsOneWidget);
  });

  testWidgets('XP Update renders supplied backend-ready display model values', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: XpUpdateScreen(
          model: XpUpdateDisplayModel(
            runnerName: 'Maya',
            earnedXpLabel: '+80 XP',
            totalXpLabel: '1,840 XP',
            levelLabel: '9',
            nextLevelLabel: '10',
            progressTargetLabel: 'Progress to Lv.10',
            xpRemainingLabel: '220 XP to go',
            previousProgressFraction: 0.41,
            currentProgressFraction: 0.49,
            streakChangeLabel: '2 \u2192 3 days',
            streakNote: 'Steady return!',
            didLevelUp: false,
            xpAwardState: XpAwardState.awarded,
            heroMessage: 'Earned from this run',
            earnedXp: 80,
            totalXp: 1840,
            level: 9,
            previousLevel: 9,
            streakCount: 3,
            previousStreakCount: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nice work, Maya!'), findsOneWidget);
    expect(find.text('+80 XP'), findsOneWidget);
    expect(find.text('1,840 XP'), findsOneWidget);
    expect(find.text('Lv.9'), findsOneWidget);
    expect(find.text('Progress to Lv.10'), findsOneWidget);
    expect(find.text('220 XP to go'), findsOneWidget);
    // The stamped-in new streak fully replaces the old value.
    expect(find.text('3 days'), findsOneWidget);
    expect(find.text('2 days'), findsNothing);
    expect(find.text('Steady return!'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Home'), findsOneWidget);
    expect(find.text('Nice work, Jinseo!'), findsNothing);
    expect(find.text('+120 XP'), findsNothing);
    expect(
      find.textContaining(_forbiddenXpUpdateCompetitiveCopy),
      findsNothing,
    );
  });

  testWidgets('XP Update source stays display-only and backend free', (
    WidgetTester tester,
  ) async {
    final screenSource = File(
      'lib/features/run/presentation/xp_update_screen.dart',
    ).readAsStringSync();
    final modelSource = File(
      'lib/features/run/domain/models/xp_update_display_model.dart',
    ).readAsStringSync();

    expect(modelSource, contains('class XpUpdateDisplayModel'));
    expect(
      screenSource,
      contains('../domain/models/xp_update_display_model.dart'),
    );
    expect(screenSource, isNot(contains('class RunReward')));
    expect(modelSource, isNot(contains('class RunReward')));
    expect(screenSource, isNot(contains('_demoReward')));
    expect(modelSource, isNot(contains('_demoReward')));
    for (final forbidden in [
      'calculateXP',
      'calculateXp',
      'calculateLevel',
      'calculateStreak',
      'Firebase',
      'firebase',
      'Firestore',
      'Auth',
      'SharedPreferences',
    ]) {
      expect(screenSource, isNot(contains(forbidden)));
      expect(modelSource, isNot(contains(forbidden)));
    }
    for (final forbiddenCall in [
      RegExp(r'\bcollection\s*\('),
      RegExp(r'\bdoc\s*\('),
      RegExp(r'\bset\s*\('),
      RegExp(r'\bupdate\s*\('),
    ]) {
      expect(screenSource, isNot(contains(forbiddenCall)));
      expect(modelSource, isNot(contains(forbiddenCall)));
    }
  });

  testWidgets(
    'View summary scrolls with local clamping no-overscroll behavior',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ViewSummaryScreen()));

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      final localNoOverscrollConfiguration = find.byWidgetPredicate(
        (widget) =>
            widget is ScrollConfiguration &&
            widget.behavior.runtimeType.toString() == '_NoOverscrollBehavior',
      );

      expect(scrollView.physics, isA<ClampingScrollPhysics>());
      expect(localNoOverscrollConfiguration, findsOneWidget);

      final scrollConfiguration = tester.widget<ScrollConfiguration>(
        localNoOverscrollConfiguration,
      );
      expect(
        scrollConfiguration.behavior.getScrollPhysics(
          tester.element(find.byType(SingleChildScrollView)),
        ),
        isA<ClampingScrollPhysics>(),
      );

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();

      expect(find.text('View XP Update'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cool down page fits compact screens without scroll containers', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 667);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: CoolDownScreen()));

    expect(find.text('Cool down'), findsOneWidget);
    expect(find.text('Start Cool-down'), findsOneWidget);
    expect(find.text('Skip to Summary'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Start Cool-down'));
    await tester.pumpAndSettle();

    expect(find.text('Cool down guide'), findsOneWidget);
    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('Slow Walk'), findsOneWidget);
    expect(find.text('Walk slowly to lower your heart rate.'), findsOneWidget);
    expect(find.text('Keep your breathing relaxed.'), findsOneWidget);
    expect(find.text('Walk at an easy pace.'), findsOneWidget);
    expect(
      find.text('Let your heart rate come down gradually.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.textContaining(_forbiddenRealActivitySaveCopy), findsNothing);
  });

  testWidgets(
    'Cool down skip preserves the exact completion result and payload',
    (WidgetTester tester) async {
      final completionPayload = LocalRunCompletionPayload(
        clientRunSessionId: 'cool-down-session',
        startedAt: DateTime.utc(2026, 7, 12, 20),
        completedAt: DateTime.utc(2026, 7, 12, 20, 31),
        durationSeconds: 1860,
        distanceMeters: 4200,
        avgPaceSecondsPerKm: 443,
        source: 'gps',
        routePrivacy: 'private',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CoolDownScreen(
            completionResult: _repositoryCompletionResult,
            completionPayload: completionPayload,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
      await tester.pumpAndSettle();

      final summary = tester.widget<ViewSummaryScreen>(
        find.byType(ViewSummaryScreen),
      );
      expect(summary.completionResult, same(_repositoryCompletionResult));
      expect(summary.completionPayload, same(completionPayload));
    },
  );

  testWidgets(
    'Guided cool down completion requests the server bonus once and forwards the merged result',
    (WidgetTester tester) async {
      final completionPayload = LocalRunCompletionPayload(
        clientRunSessionId: 'guided-cool-down-session',
        startedAt: DateTime.utc(2026, 7, 12, 20),
        completedAt: DateTime.utc(2026, 7, 12, 20, 31),
        durationSeconds: 1860,
        distanceMeters: 4200,
        avgPaceSecondsPerKm: 443,
        source: 'gps',
        routePrivacy: 'private',
      );
      final fake = _RecordingCoolDownRunRepository(
        _repositoryCompletionResult,
        coolDownResult: _repositoryCoolDownBonusResult,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CoolDownScreen(
            repository: fake,
            completionResult: _repositoryCompletionResult,
            completionPayload: completionPayload,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Start Cool-down'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      // Step through all 14 stretch steps: each of the first 13 timers
      // expiring prompts a confirmation dialog that must be dismissed
      // before advancing; the 14th auto-completes the phase.
      for (final step in stretchSteps.sublist(0, stretchSteps.length - 1)) {
        await tester.pump(Duration(seconds: step.seconds));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pump(Duration(seconds: stretchSteps.last.seconds));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await tester.pumpAndSettle();

      expect(fake.completeCoolDownCalls, 1);
      expect(fake.lastCoolDownActivityId, 'repo-activity');
      // _repositoryCompletionResult.clientRunSessionId is null, so the
      // session id must be resolved from the local completion payload.
      expect(fake.lastCoolDownClientRunSessionId, 'guided-cool-down-session');

      final summary = tester.widget<ViewSummaryScreen>(
        find.byType(ViewSummaryScreen),
      );
      expect(summary.completionResult, isNot(same(_repositoryCompletionResult)));
      expect(summary.completionResult!.progressionDisplay.xpDelta, 10);
      expect(summary.completionResult!.progressionDisplay.status, 'awarded');
      expect(summary.completionResult!.progressionDisplay.totalXp, 155);
      expect(summary.completionResult!.xpUpdate.earnedXpLabel, '+10 XP');
      expect(summary.completionPayload, same(completionPayload));
    },
  );

  testWidgets(
    'Guided cool down completion falls back silently when the server bonus request fails',
    (WidgetTester tester) async {
      final completionPayload = LocalRunCompletionPayload(
        clientRunSessionId: 'guided-cool-down-session',
        startedAt: DateTime.utc(2026, 7, 12, 20),
        completedAt: DateTime.utc(2026, 7, 12, 20, 31),
        durationSeconds: 1860,
        distanceMeters: 4200,
        avgPaceSecondsPerKm: 443,
        source: 'gps',
        routePrivacy: 'private',
      );
      final fake = _FailingCoolDownRunRepository(_repositoryCompletionResult);

      await tester.pumpWidget(
        MaterialApp(
          home: CoolDownScreen(
            repository: fake,
            completionResult: _repositoryCompletionResult,
            completionPayload: completionPayload,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Start Cool-down'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      for (final step in stretchSteps.sublist(0, stretchSteps.length - 1)) {
        await tester.pump(Duration(seconds: step.seconds));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pump(Duration(seconds: stretchSteps.last.seconds));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await tester.pumpAndSettle();

      expect(fake.completeCoolDownCalls, 1);

      final summary = tester.widget<ViewSummaryScreen>(
        find.byType(ViewSummaryScreen),
      );
      expect(summary.completionResult, same(_repositoryCompletionResult));
      expect(summary.completionPayload, same(completionPayload));
    },
  );

  testWidgets(
    'Cool down guide never requests the server bonus for a partial stretch phase',
    (WidgetTester tester) async {
      final fake = _RecordingCoolDownRunRepository(
        _repositoryCompletionResult,
        coolDownResult: _repositoryCoolDownBonusResult,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CoolDownScreen(
            repository: fake,
            completionResult: _repositoryCompletionResult,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Start Cool-down'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      // Advance a few stretch steps manually, but never reach the 14th
      // (final) step, so the phase never completes and Finish never appears.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(FilledButton, 'Next stretch'));
        await tester.pump();
      }

      expect(find.widgetWithText(FilledButton, 'Finish'), findsNothing);
      expect(fake.completeCoolDownCalls, 0);
    },
  );

  testWidgets(
    'Cool down skip to summary never requests the server bonus',
    (WidgetTester tester) async {
      final fake = _RecordingCoolDownRunRepository(
        _repositoryCompletionResult,
        coolDownResult: _repositoryCoolDownBonusResult,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CoolDownScreen(
            repository: fake,
            completionResult: _repositoryCompletionResult,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
      await tester.pumpAndSettle();

      expect(fake.completeCoolDownCalls, 0);

      final summary = tester.widget<ViewSummaryScreen>(
        find.byType(ViewSummaryScreen),
      );
      expect(summary.completionResult, same(_repositoryCompletionResult));
    },
  );

  testWidgets('Cool down guide supports walk pause stretch and finish states', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoolDownGuideScreen(timerEnabled: false)),
    );

    expect(find.text('Cool down guide'), findsOneWidget);
    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('Stretch'), findsOneWidget);
    expect(find.text('03:00'), findsOneWidget);
    expect(find.text('REMAINING'), findsOneWidget);
    expect(find.text('Slow Walk'), findsOneWidget);
    expect(find.text('Walk slowly to lower your heart rate.'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Tips'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Stretch'));
    await tester.pumpAndSettle();

    expect(find.text('03:00'), findsOneWidget);
    expect(find.text('Slow Walk'), findsOneWidget);
    expect(find.text('Gentle Stretch'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();

    expect(find.text('00:25'), findsOneWidget);
    expect(find.text('Stretch 1 of 8'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Standing Calf Stretch'), findsOneWidget);
    expect(find.text('Calf stretch'), findsOneWidget);
    expect(find.text('Gentle Stretch'), findsNothing);
    expect(find.text('Slow Walk'), findsNothing);
    expect(find.text('Tips'), findsNothing);
    expect(find.text('Stretch slowly — never bounce.'), findsNothing);
    expect(find.text('Keep your breathing steady.'), findsNothing);
    expect(find.text('Stop if anything feels sharp.'), findsNothing);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();

    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('00:25'), findsOneWidget);
    expect(find.byTooltip('Resume'), findsOneWidget);

    await tester.tap(find.text('Walk'));
    await tester.pump();

    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('00:25'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: CoolDownGuideScreen(timerEnabled: true, initialSecondsLeft: 1),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('Walk complete'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsNothing);
    expect(find.text('Gentle Stretch'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: CoolDownGuideScreen(timerEnabled: false, initialSecondsLeft: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('Walk complete'), findsOneWidget);
    expect(
      find.text('Nicely done. Let’s move into some gentle stretching.'),
      findsOneWidget,
    );
    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.text('Gentle Stretch'), findsOneWidget);
    expect(find.text('~6 min · gentle recovery'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Stretch'));
    await tester.pumpAndSettle();

    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('Walk complete'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();

    expect(find.text('00:25'), findsOneWidget);
    expect(find.text('Stretch 1 of 8'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Standing Calf Stretch'), findsOneWidget);
    expect(find.text('Calf stretch'), findsOneWidget);
    expect(find.text('Gentle Stretch'), findsNothing);
    expect(find.text('Tips'), findsNothing);
    expect(find.text('Ease through each stretch and breathe.'), findsNothing);
    expect(find.text('Stretch slowly — never bounce.'), findsNothing);
    expect(find.text('Keep your breathing steady.'), findsNothing);
    expect(find.text('Stop if anything feels sharp.'), findsNothing);

    // Manual advance via the primary CTA (now 'Next stretch' while running)
    // moves from the left-side step to the right-side step of the same
    // exercise.
    await tester.tap(find.widgetWithText(FilledButton, 'Next stretch'));
    await tester.pump();

    expect(find.text('00:25'), findsOneWidget);
    expect(find.text('Stretch 1 of 8'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
    expect(find.text('Standing Calf Stretch'), findsOneWidget);
    expect(find.text('Saturday Morning Run'), findsNothing);

    // A dedicated real-timer instance covers auto-advance-on-expiry, the
    // no-side exercises (no Left/Right pill), and the full 14-step sequence
    // through to phase completion.
    await tester.pumpWidget(
      const MaterialApp(
        home: CoolDownGuideScreen(
          timerEnabled: true,
          initialPhase: CoolDownPhase.stretch,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('00:25'), findsOneWidget);
    expect(find.text('Stretch 1 of 8'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Standing Calf Stretch'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Next stretch'));
    await tester.pump();

    expect(find.text('Stretch 1 of 8'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);

    // Letting the real timer run out the full 25s prompts a confirmation
    // dialog instead of silently auto-advancing; confirming moves to the
    // next step.
    await tester.pump(const Duration(seconds: 25));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Time’s up!'), findsOneWidget);
    expect(find.text('Ready for the next stretch?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Stretch 2 of 8'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Standing Quadriceps Stretch'), findsOneWidget);
    expect(find.text('Front thigh stretch'), findsOneWidget);
    expect(find.text('00:25'), findsOneWidget);

    // Manually advance the remaining per-side steps (index 2 through 11)
    // to reach the first no-side exercise, Kneeling Shin Stretch (index 12).
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.widgetWithText(FilledButton, 'Next stretch'));
      await tester.pump();
    }

    expect(find.text('Stretch 7 of 8'), findsOneWidget);
    expect(find.text('Kneeling Shin Stretch'), findsOneWidget);
    expect(find.text('Shin stretch'), findsOneWidget);
    expect(find.text('00:20'), findsOneWidget);
    expect(find.text('Left'), findsNothing);
    expect(find.text('Right'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Next stretch'));
    await tester.pump();

    expect(find.text('Stretch 8 of 8'), findsOneWidget);
    expect(find.text("Child's Pose"), findsOneWidget);
    expect(find.text('Lower back and spine release'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('Left'), findsNothing);
    expect(find.text('Right'), findsNothing);

    // Tapping the CTA on the final running step completes the phase.
    await tester.tap(find.widgetWithText(FilledButton, 'Next stretch'));
    await tester.pump();

    expect(find.text('Cool-down complete'), findsOneWidget);
    expect(
      find.text('That’s your recovery done. Great work today.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Finish'), findsOneWidget);
    expect(find.text('UP NEXT'), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.textContaining(_forbiddenRealActivitySaveCopy), findsNothing);

    // Deep-link contract: rendering directly into an already-complete
    // stretch phase (initialSecondsLeft: 0) pins the last stretch step and
    // shows the complete state immediately. Checked here, before the real
    // navigation below replaces this widget tree with ViewSummaryScreen.
    await tester.pumpWidget(
      const MaterialApp(
        home: CoolDownGuideScreen(
          timerEnabled: false,
          initialPhase: CoolDownPhase.stretch,
          initialSecondsLeft: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cool-down complete'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();

    expect(find.text('Saturday Morning Run'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'View XP Update'), findsOneWidget);
    expect(find.text('XP & Streak Update'), findsNothing);
  });

  test('Run launch source isolates static display snapshots', () {
    final source = File(
      'lib/features/run/presentation/run_launch_screen.dart',
    ).readAsStringSync();
    final trackingSheetSource = File(
      'lib/features/run/presentation/widgets/run_tracking_sheet_content.dart',
    ).readAsStringSync();
    final snapshotSource = File(
      'lib/features/run/presentation/data/run_launch_demo_snapshots.dart',
    ).readAsStringSync();

    expect(source, contains('data/run_launch_demo_snapshots.dart'));
    expect(source, contains('runLaunchDemoSnapshot'));
    expect(source, contains('RunTrackingController'));
    expect(source, contains('RunSheetMode'));
    // RunActiveScreen was the pre-sheet "run in progress" screen; it is gone
    // and RunLaunchScreen owns preRun/running/paused. Keep guarding the name
    // so the retired screen is not reintroduced as a second run surface.
    expect(source, isNot(contains('RunActiveScreen')));
    expect(
      source,
      isNot(
        contains(
          'MaterialPageRoute<void>(builder: (context) => const RunActiveScreen())',
        ),
      ),
    );
    expect(trackingSheetSource, contains('RunTrackingSnapshot'));
    expect(trackingSheetSource, contains('run_plan_progress_bar'));
    expect(source, isNot(contains('class _RunLaunchDisplaySnapshot')));
    expect(source, isNot(contains('class _RunLiveDisplaySnapshot')));
    expect(snapshotSource, contains('class RunLaunchDemoSnapshot'));
    expect(snapshotSource, contains('class RunLiveDemoSnapshot'));
    expect(snapshotSource, contains('const runLaunchDemoSnapshot'));
    expect(snapshotSource, contains('const runLiveDemoSnapshot'));
    expect(source, isNot(contains(RegExp(r'\bonCompleted\b'))));
    expect(source, isNot(contains('bool _completed')));
    expect(source, isNot(contains('completedRun')));
    expect(source, isNot(contains('calculateRunCompletion')));
    expect(source, isNot(contains('saveActivity')));
  });

  testWidgets('Android back dismisses static Run launch surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );

    await tester.tap(find.byTooltip('Feed'));
    await tester.pumpAndSettle();
    expect(find.text('Feed'), findsOneWidget);

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();
    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('Feed'), findsNothing);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('Demo mode'), findsNothing);
    expect(find.text('Feed'), findsOneWidget);
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Feed'), findsOneWidget);
    expect(find.byTooltip('Run'), findsOneWidget);
    expect(find.byTooltip('Leaderboard'), findsOneWidget);
    expect(find.byTooltip('You'), findsOneWidget);
  });

  test(
    'Stretch catalog stays in sync with the cool-down backend contract',
    () {
      // The cool-down guide screen only requests the server XP bonus after
      // all `stretchSteps` complete; the domain-owned
      // `coolDownStretchStepCount` constant must always match that count.
      expect(stretchSteps.length, coolDownStretchStepCount);
    },
  );
}
