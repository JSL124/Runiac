import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/complete_run_result.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/progression_display_model.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_location_permission_status.dart';
import 'package:runiac_app/features/run/domain/models/run_map_view_state.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_diagnostics.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_state.dart';
import 'package:runiac_app/features/run/domain/models/xp_update_display_model.dart';
import 'package:runiac_app/features/run/domain/repositories/run_cadence_provider.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_permission_service.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_preview_provider.dart';
import 'package:runiac_app/features/run/domain/repositories/run_location_provider.dart';
import 'package:runiac_app/features/run/domain/repositories/run_foreground_service.dart';
import 'package:runiac_app/features/run/domain/repositories/run_notification_permission_service.dart';
import 'package:runiac_app/features/run/domain/repositories/run_repository.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';
import 'package:runiac_app/features/run/domain/services/pace_graph_data_builder.dart';
import 'package:runiac_app/features/run/domain/services/run_summary_local_analysis_merger.dart';
import 'package:runiac_app/features/run/presentation/active_run_session_coordinator.dart';
import 'package:runiac_app/features/run/presentation/controllers/run_tracking_controller.dart';
import 'package:runiac_app/features/run/presentation/models/planned_run_context.dart';
import 'package:runiac_app/features/run/presentation/run_launch_screen.dart';
import 'package:runiac_app/features/run/presentation/run_repository_scope.dart';
import 'package:runiac_app/features/run/presentation/view_summary_screen.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_map_placeholder.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_mapbox_surface_config.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_tracking_sheet_content.dart';
import 'package:runiac_app/features/you/data/local_pending_run_activity_store.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/plan_family_test_drafts.dart';
import 'support/premium_user_account_repository.dart';

const _demoMapboxPublicToken =
    'p'
    'k.demo-public-token';

BeginnerAdaptivePlanSnapshot _tenKPerformancePlan() {
  return const BeginnerAdaptivePlanGenerator().generate(
    planFamilyPerformanceDraft(
      goal: OnboardingGoal.tenK,
      style: OnboardingPlanStyle.performanceFocused,
      days: const [
        OnboardingPreferredDay.mon,
        OnboardingPreferredDay.tue,
        OnboardingPreferredDay.wed,
        OnboardingPreferredDay.thu,
      ],
    ),
  );
}

DateTime _weekdayDate(int weekday) {
  return DateTime(2026, 6, 21 + weekday);
}

void _useMobileRunSurface(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _useNarrowRunSurface(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(360, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _expectStatusLabelReadable(WidgetTester tester, String label) {
  final textFinder = find.text(label);
  expect(textFinder, findsOneWidget);

  final text = tester.widget<Text>(textFinder);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  expect(text.maxLines, 1);
}

void _expectSheetAdjacentRecenter({
  required WidgetTester tester,
  required Finder recenter,
  required Finder sheet,
}) {
  final gap = tester.getRect(sheet).top - tester.getRect(recenter).bottom;
  expect(gap, inInclusiveRange(8, 12));
}

Future<void> _openRunLaunch(
  WidgetTester tester, {
  ActiveRunSessionCoordinator? activeRunSessionCoordinator,
}) async {
  final coordinator =
      activeRunSessionCoordinator ?? _testActiveRunSessionCoordinator(tester);
  await tester.pumpWidget(
    RuniacApp(
      showSplash: false,
      enableForegroundGps: false,
      activeRunSessionCoordinator: coordinator,
    ),
  );
  await tester.tap(find.byTooltip('Run'));
  await tester.pumpAndSettle();
}

ActiveRunSessionCoordinator _testActiveRunSessionCoordinator(
  WidgetTester tester,
) {
  final activeRunSessionCoordinator = ActiveRunSessionCoordinator(
    clock: tester.binding.clock.now,
    foregroundTickStep: const Duration(seconds: 1),
  );
  addTearDown(activeRunSessionCoordinator.dispose);
  return activeRunSessionCoordinator;
}

Future<void> _pumpSufficientRun(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 60));
  await tester.pump(const Duration(seconds: 60));
}

_SufficientRunHarness _testSufficientRunHarness(WidgetTester tester) {
  final sampleBase = tester.binding.clock.now();
  final controller = RunTrackingController(
    locationProvider: ReplayRunLocationProvider([
      RunLocationReplaySample(
        activeOffset: Duration.zero,
        sample: RunLocationSample(
          recordedAt: sampleBase,
          latitude: 1.300000,
          longitude: 103.800000,
          horizontalAccuracyMeters: 5,
        ),
      ),
      RunLocationReplaySample(
        activeOffset: const Duration(seconds: 60),
        sample: RunLocationSample(
          recordedAt: sampleBase.add(const Duration(seconds: 60)),
          latitude: 1.301349,
          longitude: 103.800000,
          horizontalAccuracyMeters: 5,
          speedMetersPerSecond: 2.5,
        ),
      ),
      RunLocationReplaySample(
        activeOffset: const Duration(seconds: 120),
        sample: RunLocationSample(
          recordedAt: sampleBase.add(const Duration(seconds: 120)),
          latitude: 1.302698,
          longitude: 103.800000,
          horizontalAccuracyMeters: 5,
          speedMetersPerSecond: 2.5,
        ),
      ),
    ]),
  );
  final activeRunSessionCoordinator = ActiveRunSessionCoordinator(
    controller: controller,
    clock: tester.binding.clock.now,
    foregroundTickStep: const Duration(seconds: 1),
  );
  addTearDown(activeRunSessionCoordinator.dispose);
  return _SufficientRunHarness(controller, activeRunSessionCoordinator);
}

class _SufficientRunHarness {
  const _SufficientRunHarness(this.controller, this.coordinator);

  final RunTrackingController controller;
  final ActiveRunSessionCoordinator coordinator;
}

class _RoutePushRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

class _GrantedRunLocationPermissionService
    implements RunLocationPermissionService {
  const _GrantedRunLocationPermissionService();

  @override
  Future<RunLocationPermissionStatus> checkStatus() async {
    return RunLocationPermissionStatus.granted;
  }

  @override
  Future<RunLocationPermissionStatus> requestPermission() async {
    return RunLocationPermissionStatus.granted;
  }
}

class _ConfigurableRunLocationPermissionService
    implements RunLocationPermissionService {
  _ConfigurableRunLocationPermissionService({
    required this.checkedStatus,
    RunLocationPermissionStatus? requestedStatus,
  }) : requestedStatus = requestedStatus ?? checkedStatus;

  RunLocationPermissionStatus checkedStatus;
  RunLocationPermissionStatus requestedStatus;
  int checkCount = 0;
  int requestCount = 0;

  @override
  Future<RunLocationPermissionStatus> checkStatus() async {
    checkCount += 1;
    return checkedStatus;
  }

  @override
  Future<RunLocationPermissionStatus> requestPermission() async {
    requestCount += 1;
    checkedStatus = requestedStatus;
    return requestedStatus;
  }
}

class _GrantedRunNotificationPermissionService
    implements RunNotificationPermissionService {
  const _GrantedRunNotificationPermissionService();

  @override
  Future<RunNotificationPermissionStatus> requestPermission() async {
    return RunNotificationPermissionStatus.granted;
  }
}

class _FakeRunLocationPreviewProvider implements RunLocationPreviewProvider {
  _FakeRunLocationPreviewProvider({required this.sample});

  final RunLocationSample sample;
  int requestCount = 0;

  @override
  Future<RunLocationSample> currentLocation() async {
    requestCount += 1;
    return sample;
  }
}

class _CompletingRunLocationPreviewProvider
    implements RunLocationPreviewProvider {
  _CompletingRunLocationPreviewProvider();

  final Completer<RunLocationSample> completer = Completer<RunLocationSample>();
  int requestCount = 0;

  @override
  Future<RunLocationSample> currentLocation() async {
    requestCount += 1;
    return completer.future;
  }
}

class _ResultRunRepository implements RunRepository {
  _ResultRunRepository(this.result);

  final CompleteRunResult result;
  int completeRunCalls = 0;
  LocalRunCompletionPayload? lastPayload;

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    completeRunCalls += 1;
    lastPayload = payload;
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
      activityId: 'active-repo-activity',
      title: 'Active Repository Run',
      completedAtLabel: 'Today',
      distanceLabel: '0.08 km',
      durationLabel: '00:30',
      avgPaceLabel: '6’15”',
      routeLabel: 'Active Repository Route',
    );
  }

  @override
  Future<RunSummaryReadModel> loadLatestRunSummary() async {
    return const RunSummaryReadModel(
      summaryId: 'active-repo-summary',
      title: 'Active Repository Run',
      dateLabel: 'Today',
      timeLabel: '8:10 AM',
      distanceLabel: '0.08 km',
      avgPaceLabel: '6’15”',
      durationLabel: '00:30',
      avgHeartRateLabel: '--',
      caloriesLabel: '--',
      routeName: 'Active Repository Route',
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
    throw StateError('repository unavailable');
  }
}

class _FailOnceRunRepository extends _ResultRunRepository {
  _FailOnceRunRepository(super.result);

  bool _hasFailed = false;

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    completeRunCalls += 1;
    lastPayload = payload;
    if (!_hasFailed) {
      _hasFailed = true;
      throw StateError('repository unavailable');
    }
    return result;
  }
}

class _DelayedRunRepository extends _ResultRunRepository {
  _DelayedRunRepository(super.result);

  final Completer<CompleteRunResult> completer = Completer<CompleteRunResult>();

  @override
  Future<CompleteRunResult> completeRun(LocalRunCompletionPayload payload) {
    completeRunCalls += 1;
    lastPayload = payload;
    return completer.future;
  }
}

const _activeCompletionResult = CompleteRunResult(
  activityId: 'active-repo-activity',
  summaryId: 'active-repo-summary',
  progressionEventId: 'active-repo-progression',
  validationStatus: 'validated',
  summary: RunSummarySnapshot(
    title: 'Active Repository Run',
    dateLabel: 'Today',
    timeLabel: '8:10 AM',
    distanceKm: '0.08',
    avgPace: '6’15”',
    duration: '00:30',
    avgHeartRate: '--',
    calories: '--',
    routeName: 'Active Repository Route',
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
  message: 'Repository completion accepted.',
);

const _serverAwardedCompletionResult = CompleteRunResult(
  clientRunSessionId: 'server-session',
  activityId: 'activity_server_awarded',
  summaryId: 'summary_server_awarded',
  progressionEventId: 'progression_server_awarded',
  validationStatus: 'validated',
  summary: RunSummarySnapshot(
    title: 'Server Awarded Run',
    dateLabel: 'Today',
    timeLabel: '8:10 AM',
    distanceKm: '4.20',
    avgPace: '7’23”',
    duration: '31:00',
    avgHeartRate: '--',
    calories: '--',
    routeName: 'Canonical Server Route',
  ),
  progressionDisplay: ProgressionDisplayModel(
    xpDelta: 75,
    countsTowardLeaderboard: true,
    status: 'awarded',
    reason: 'validated_run',
  ),
  xpUpdate: XpUpdateDisplayModel(
    runnerName: 'Runiac Runner',
    earnedXpLabel: '+75 XP',
    totalXpLabel: '75 XP',
    levelLabel: 'Level 1',
    nextLevelLabel: 'Level 2',
    progressTargetLabel: '75 / 100 XP',
    xpRemainingLabel: '25 XP to next level',
    previousProgressFraction: 0,
    currentProgressFraction: 0.75,
    streakChangeLabel: '0 → 1 days',
    streakNote: 'First validated run in the streak.',
    didLevelUp: false,
    xpAwardState: XpAwardState.awarded,
    heroMessage: 'Earned from this run',
    earnedXp: 75,
    totalXp: 75,
    previousTotalXp: 0,
    level: 1,
    previousLevel: 1,
    streakCount: 1,
    previousStreakCount: 0,
  ),
  message: 'Server completion accepted.',
);

const _firebaseScalarCompletionResult = CompleteRunResult(
  clientRunSessionId: 'local-run-1',
  activityId: 'firebase-repo-activity',
  summaryId: 'firebase-repo-summary',
  progressionEventId: 'firebase-repo-progression',
  validationStatus: 'validated',
  summary: RunSummarySnapshot(
    title: 'Firebase Scalar Run',
    dateLabel: 'Today',
    timeLabel: '8:10 AM',
    distanceKm: '0.32',
    avgPace: '9’23”',
    duration: '03:00',
    avgHeartRate: '--',
    calories: '--',
    routeName: 'Firebase Scalar Route',
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
  message: 'Firebase completion accepted.',
);

RunLocationSample _previewSample() {
  return RunLocationSample(
    recordedAt: DateTime.utc(2026, 6, 14, 7),
    latitude: 1.3009,
    longitude: 103.8,
    horizontalAccuracyMeters: 5,
  );
}

RunSummarySnapshot _mergeBackendSummary() {
  return const RunSummarySnapshot(
    title: 'Backend Scalar Run',
    dateLabel: 'Today',
    timeLabel: '8:10 AM',
    distanceKm: '0.32',
    avgPace: '9’23”',
    duration: '03:00',
    avgHeartRate: '--',
    calories: '--',
    routeName: 'Backend Scalar Route',
  );
}

RunSummarySnapshot _lowDataMergeBackendSummary() {
  return const RunSummarySnapshot(
    title: 'Backend Low Data Run',
    dateLabel: 'Today',
    timeLabel: '8:10 AM',
    distanceKm: '0.04',
    avgPace: '--',
    duration: '00:42',
    avgHeartRate: '--',
    calories: '--',
    routeName: 'Backend Low Data Route',
    hasSufficientData: false,
  );
}

LocalRunCompletionPayload _localAnalysisMergePayload(String sessionId) {
  return LocalRunCompletionPayload(
    clientRunSessionId: sessionId,
    startedAt: DateTime.utc(2026, 6, 18, 8),
    completedAt: DateTime.utc(2026, 6, 18, 8, 6),
    durationSeconds: 360,
    distanceMeters: 760,
    avgPaceSecondsPerKm: 473,
    source: 'local_gps',
    routePrivacy: 'private',
    routeLabel: 'Local merge route',
    paceGraphSamples: const <PaceGraphSample>[
      PaceGraphSample(
        elapsedSeconds: 60,
        paceSecondsPerKm: 470,
        cumulativeDistanceMeters: 130,
      ),
      PaceGraphSample(
        elapsedSeconds: 120,
        paceSecondsPerKm: 474,
        cumulativeDistanceMeters: 255,
      ),
      PaceGraphSample(
        elapsedSeconds: 180,
        paceSecondsPerKm: 476,
        cumulativeDistanceMeters: 380,
      ),
      PaceGraphSample(
        elapsedSeconds: 240,
        paceSecondsPerKm: 472,
        cumulativeDistanceMeters: 510,
      ),
    ],
    cadenceAnalysisSeries: CadenceAnalysisSeries.localAccepted(
      samples: const [
        CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 168),
        CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 170),
        CadenceAnalysisSample.accepted(elapsedSeconds: 180, cadenceSpm: 171),
      ],
    ),
    elevationAnalysisSeries: ElevationAnalysisSeries.localAccepted(
      samples: const [
        ElevationAnalysisSample(distanceKm: 0, elevationMeters: 4),
        ElevationAnalysisSample(distanceKm: 0.4, elevationMeters: 7),
        ElevationAnalysisSample(distanceKm: 0.76, elevationMeters: 5),
      ],
    ),
  );
}

RunRouteSnapshot _localRouteSnapshot() {
  return RunRouteSnapshot(
    segments: [
      [
        RunLocationSample(
          recordedAt: DateTime.utc(2026, 6, 18, 8),
          latitude: 1.3,
          longitude: 103.8,
        ),
        RunLocationSample(
          recordedAt: DateTime.utc(2026, 6, 18, 8, 1),
          latitude: 1.3008,
          longitude: 103.8,
        ),
      ],
    ],
  );
}

void main() {
  setUp(() {
    // RunLaunchScreen reads voice-coaching settings from the real
    // SharedPreferences-backed repository (no fake is injected by these
    // widget tests). Without mock initial values, SharedPreferences.
    // getInstance() never resolves in the test harness (no platform-channel
    // responder), which would hang `_startRun`'s settings reload forever.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('default run session ids stay unique across controller recreation', () {
    final firstController = RunTrackingController();
    addTearDown(firstController.dispose);
    final secondController = RunTrackingController();
    addTearDown(secondController.dispose);

    firstController.start(startedAt: DateTime.utc(2026, 6, 18, 8));
    secondController.start(startedAt: DateTime.utc(2026, 6, 18, 9));

    expect(firstController.state.clientRunSessionId, isNotEmpty);
    expect(secondController.state.clientRunSessionId, isNotEmpty);
    expect(
      secondController.state.clientRunSessionId,
      isNot(firstController.state.clientRunSessionId),
      reason:
          'Fresh app/controller sessions must not reuse the same '
          'clientRunSessionId because Firestore IDs are deterministic.',
    );
  });

  test('explicit run session id is preserved', () {
    final controller = RunTrackingController();
    addTearDown(controller.dispose);

    controller.start(
      startedAt: DateTime.utc(2026, 6, 18, 8),
      clientRunSessionId: 'manual-session-id',
    );

    expect(controller.state.clientRunSessionId, 'manual-session-id');
  });

  test('local analysis merge requires matching client run session id', () {
    const merger = RunSummaryLocalAnalysisMerger();
    final payload = _localAnalysisMergePayload('payload-session');
    final localRoute = _localRouteSnapshot();
    final matchedResult = CompleteRunResult(
      clientRunSessionId: 'payload-session',
      summary: _mergeBackendSummary(),
      xpUpdate: _activeCompletionResult.xpUpdate,
    );
    final mismatchedResult = CompleteRunResult(
      clientRunSessionId: 'other-session',
      summary: _mergeBackendSummary(),
      xpUpdate: _activeCompletionResult.xpUpdate,
    );

    final matched = merger.merge(
      backendSummary: matchedResult.summary,
      localPayload: payload,
      localRoute: localRoute,
      resultClientRunSessionId: matchedResult.clientRunSessionId,
    );
    final mismatched = merger.merge(
      backendSummary: mismatchedResult.summary,
      localPayload: payload,
      localRoute: localRoute,
      resultClientRunSessionId: mismatchedResult.clientRunSessionId,
    );

    expect(matched.route.hasRoute, isTrue);
    expect(matched.paceGraph.isAvailable, isTrue);
    expect(matched.paceAnalysisSeries?.isLocalAcceptedSource, isTrue);
    expect(matched.cadenceAnalysisSeries, isNotNull);
    expect(matched.elevationSeries.isUnavailable, isFalse);
    expect(mismatched.route.hasRoute, isFalse);
    expect(mismatched.paceGraph.isAvailable, isFalse);
    expect(mismatched.paceAnalysisSeries, isNull);
    expect(mismatched.cadenceAnalysisSeries, isNull);
    expect(mismatched.elevationSeries.isUnavailable, isTrue);
  });

  test('low-data local analysis merge preserves route only', () {
    const merger = RunSummaryLocalAnalysisMerger();
    final payload = _localAnalysisMergePayload('payload-session');
    final localRoute = _localRouteSnapshot();

    final merged = merger.merge(
      backendSummary: _lowDataMergeBackendSummary(),
      localPayload: payload,
      localRoute: localRoute,
      resultClientRunSessionId: payload.clientRunSessionId,
    );

    expect(merged.hasSufficientData, isFalse);
    expect(merged.route.hasRoute, isTrue);
    expect(merged.paceGraph.isAvailable, isFalse);
    expect(merged.paceAnalysisSeries, isNull);
    expect(merged.cadenceAnalysisSeries, isNull);
    expect(merged.elevationSeries.isUnavailable, isTrue);
    expect(
      merged.elevationSeries.unavailableReason,
      ElevationUnavailableReason.lowDataSummary,
    );
  });

  test(
    'prewarmRunLaunchPreviewCurrentPosition returns a sample when permission is granted',
    () async {
      final permissionService = _ConfigurableRunLocationPermissionService(
        checkedStatus: RunLocationPermissionStatus.granted,
      );
      final previewProvider = _FakeRunLocationPreviewProvider(
        sample: _previewSample(),
      );

      final previewSample = await prewarmRunLaunchPreviewCurrentPosition(
        enableForegroundGps: true,
        permissionService: permissionService,
        locationPreviewProvider: previewProvider,
      );

      expect(previewSample?.latitude, 1.3009);
      expect(previewSample?.longitude, 103.8);
      expect(permissionService.checkCount, 1);
      expect(permissionService.requestCount, 0);
      expect(previewProvider.requestCount, 1);
    },
  );

  test(
    'prewarmRunLaunchPreviewCurrentPosition does not prompt when permission is not granted',
    () async {
      final permissionService = _ConfigurableRunLocationPermissionService(
        checkedStatus: RunLocationPermissionStatus.denied,
      );
      final previewProvider = _FakeRunLocationPreviewProvider(
        sample: _previewSample(),
      );

      final previewSample = await prewarmRunLaunchPreviewCurrentPosition(
        enableForegroundGps: true,
        permissionService: permissionService,
        locationPreviewProvider: previewProvider,
      );

      expect(previewSample, isNull);
      expect(permissionService.checkCount, 1);
      expect(permissionService.requestCount, 0);
      expect(previewProvider.requestCount, 0);
    },
  );

  testWidgets('Run launch top GPS pill fits GPS ready on narrow phones', (
    WidgetTester tester,
  ) async {
    _useNarrowRunSurface(tester);
    final previewProvider = _FakeRunLocationPreviewProvider(
      sample: _previewSample(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          locationProvider: ReplayRunLocationProvider(const []),
          locationPreviewProvider: previewProvider,
          permissionService: const _GrantedRunLocationPermissionService(),
          notificationPermissionService:
              const _GrantedRunNotificationPermissionService(),
          foregroundService: const NoopRunForegroundService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    _expectStatusLabelReadable(tester, 'GPS ready');
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Run settings'), findsOneWidget);

    await tester.tap(find.byTooltip('Run settings'));
    await tester.pumpAndSettle();

    expect(find.text('Run Settings'), findsOneWidget);
    expect(find.text('Voice progress updates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch top GPS pill keeps active labels readable', (
    WidgetTester tester,
  ) async {
    _useNarrowRunSurface(tester);
    final sampleBase = DateTime.now().add(const Duration(days: 1));

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: RunLocationSample(
                recordedAt: sampleBase.add(const Duration(seconds: 1)),
                latitude: 1.3,
                longitude: 103.8,
                horizontalAccuracyMeters: 5,
              ),
            ),
          ]),
          locationPreviewProvider: _FakeRunLocationPreviewProvider(
            sample: _previewSample(),
          ),
          permissionService: const _GrantedRunLocationPermissionService(),
          notificationPermissionService:
              const _GrantedRunNotificationPermissionService(),
          foregroundService: const NoopRunForegroundService(),
          activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    _expectStatusLabelReadable(tester, 'GPS active');
    expect(find.text('Start run'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch top GPS pill handles approximate location label', (
    WidgetTester tester,
  ) async {
    _useNarrowRunSurface(tester);
    final sampleBase = DateTime.now().add(const Duration(days: 1));

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: RunLocationSample(
                recordedAt: sampleBase.add(const Duration(seconds: 1)),
                latitude: 1.3,
                longitude: 103.8,
                horizontalAccuracyMeters: 5,
              ),
            ),
          ], locationAccuracyStatus: RunTrackingLocationAccuracyStatus.reduced),
          locationPreviewProvider: _FakeRunLocationPreviewProvider(
            sample: _previewSample(),
          ),
          permissionService: const _GrantedRunLocationPermissionService(),
          notificationPermissionService:
              const _GrantedRunNotificationPermissionService(),
          foregroundService: const NoopRunForegroundService(),
          activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    _expectStatusLabelReadable(tester, 'Approximate location');
    expect(find.text('Start run'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default Run tab enters foreground GPS mode', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: RunLaunchScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsNothing);
    expect(find.text('Start run'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Run launch renders duration objective with estimated distance as supporting copy',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);

      await tester.pumpWidget(
        const MaterialApp(
          home: RunLaunchScreen(
            enableForegroundGps: false,
            plannedWorkout: PlannedRunContext(
              title: 'Easy run',
              durationMinutes: 30,
              planTitle: 'Base Builder',
              planFamilyLabel: 'Beginner Base',
              workoutKindLabel: 'Easy Run',
              intensityLabel: 'Easy',
              steps: ['Run relaxed for 30 minutes.'],
              supportiveNote: 'Keep the effort conversational.',
              sourceLabel: 'Generated onboarding plan',
              objectiveKind: PlannedRunObjectiveKind.duration,
              primaryValueLabel: '30 min',
              primaryUnitLabel: 'easy run',
              estimatedDistanceLabel: '~4.0 km',
              estimateConfidence: PlannedRunEstimateConfidence.medium,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EASY RUN'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('easy run'), findsOneWidget);
      expect(find.text('Easy effort · About ~4.0 km estimate'), findsOneWidget);
      expect(find.text('Start run'), findsOneWidget);
      expect(find.text('4.5'), findsNothing);
      expect(find.text('km easy run'), findsNothing);
      expect(find.textContaining('Goal'), findsNothing);
      expect(find.textContaining('target'), findsNothing);
      expect(find.textContaining('required'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('completed planned run launch explains extra run before starting', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: RunLaunchScreen(
          enableForegroundGps: false,
          plannedWorkout: PlannedRunContext(
            title: 'Easy run',
            durationMinutes: 30,
            planTitle: 'Base Builder',
            planFamilyLabel: 'Beginner Base',
            workoutKindLabel: 'Easy Run',
            intensityLabel: 'Easy',
            steps: ['Run relaxed for 30 minutes.'],
            supportiveNote: 'Extra run mode keeps this separate.',
            sourceLabel: 'Generated onboarding plan',
            objectiveKind: PlannedRunObjectiveKind.duration,
            primaryValueLabel: '30 min',
            primaryUnitLabel: 'easy run',
            alreadyCompletedToday: true,
            planEnrollmentId: 'generated-plan-base-builder',
            scheduledWorkoutId: 'week-1-tue-easy-run',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EASY RUN COMPLETE'), findsOneWidget);
    expect(
      find.text(
        "Today's planned run is already complete. Start an extra run? It will be saved to your activity history, but it will not count as another planned session.",
      ),
      findsOneWidget,
    );
    expect(find.text('Extra run mode keeps this separate.'), findsNothing);
    expect(find.text('Start run'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch Start run updates sheet without pushing a route', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    final observer = _RoutePushRecorder();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const RunLaunchScreen(enableForegroundGps: false),
      ),
    );
    await tester.pumpAndSettle();
    observer.pushedRoutes.clear();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Run settings'), findsOneWidget);
    expect(find.text('TODAY\'S PLAN'), findsOneWidget);
    expect(find.text('Start run'), findsOneWidget);
    expect(find.byKey(const Key('run_plan_progress_bar')), findsNothing);
    expect(find.text('DISTANCE'), findsNothing);
    expect(find.text('TIME'), findsNothing);
    expect(find.text('AVG PACE'), findsNothing);
    expect(find.text('CURRENT PACE'), findsNothing);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Resume'), findsNothing);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    expect(observer.pushedRoutes, isEmpty);
    expect(find.byType(RunLaunchScreen), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.byTooltip('Run settings'), findsNothing);
    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('TODAY\'S PLAN'), findsNothing);
    expect(find.text('Start run'), findsNothing);
    expect(find.text('0.00 of 4.50 km'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byKey(const Key('run_plan_progress_bar')), findsOneWidget);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('AVG PACE'), findsNothing);
    expect(find.text('CURRENT PACE'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Resume'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duration planned run shows active time progress', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunTrackingSheetContent(
            state: const RunTrackingState(
              phase: RunTrackingPhase.active,
              clientRunSessionId: 'duration-progress-test',
              startedAt: null,
              completedAt: null,
              elapsedSeconds: 754,
              distanceMeters: 1200,
              averagePaceSecondsPerKm: 628,
              currentPaceSecondsPerKm: 620,
              routePrivacy: 'private',
              source: 'local_simulation',
              locationStatus: RunTrackingLocationStatus.demo,
              diagnostics: RunTrackingDiagnostics.initial(),
            ),
            plannedWorkout: const PlannedRunContext(
              title: 'Easy run',
              durationMinutes: 30,
              planTitle: 'Base Builder',
              planFamilyLabel: 'Beginner Base',
              workoutKindLabel: 'Easy Run',
              intensityLabel: 'Easy',
              steps: ['Run relaxed for 30 minutes.'],
              supportiveNote: 'Keep the effort conversational.',
              sourceLabel: 'Generated onboarding plan',
              objectiveKind: PlannedRunObjectiveKind.duration,
              primaryValueLabel: '30 min',
              primaryUnitLabel: 'easy run',
            ),
            onPause: () {},
            onResume: () {},
            onEnd: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12:34 of 30:00'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.byKey(const Key('run_plan_progress_bar')), findsOneWidget);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('1.20'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('12:34'), findsOneWidget);
    expect(find.text('0.00 of 4.50 km'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rest day planned run hides plan progress bar', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: RunLaunchScreen(
          enableForegroundGps: false,
          plannedWorkout: PlannedRunContext(
            title: 'Today\'s plan',
            durationMinutes: 0,
            planTitle: '10K Performance Build',
            planFamilyLabel: 'Performance',
            workoutKindLabel: 'Rest day',
            intensityLabel: 'Recovery',
            steps: ['Rest or light mobility.'],
            supportiveNote: 'Let the body absorb the week.',
            sourceLabel: 'Generated onboarding plan',
            objectiveKind: PlannedRunObjectiveKind.restDay,
            primaryValueLabel: 'Rest day',
            primaryUnitLabel: '',
            supportLabel: 'Recovery today · no run target',
            secondarySupportLabel: 'Optional easy run only if you feel fresh',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TODAY\'S PLAN'), findsOneWidget);
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Recovery today · no run target'), findsOneWidget);
    expect(find.text('4.5'), findsNothing);
    expect(find.text('km easy run'), findsNothing);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('run_plan_progress_bar')), findsNothing);
    expect(find.textContaining(' of '), findsNothing);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Run launch abnormal pause shows Resume and End with English warning',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final sampleBase = DateTime.now().add(const Duration(days: 1));
      final repository = _ResultRunRepository(_activeCompletionResult);

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            repository: repository,
            enableForegroundGps: false,
            locationProvider: ReplayRunLocationProvider([
              RunLocationReplaySample(
                activeOffset: Duration.zero,
                sample: RunLocationSample(
                  recordedAt: sampleBase,
                  latitude: 1.300000,
                  longitude: 103.800000,
                  horizontalAccuracyMeters: 5,
                ),
              ),
              for (final seconds in [1, 2, 3])
                RunLocationReplaySample(
                  activeOffset: Duration(seconds: seconds),
                  sample: RunLocationSample(
                    recordedAt: sampleBase.add(Duration(seconds: seconds)),
                    latitude: 1.300000 + (0.000063 * seconds),
                    longitude: 103.800000,
                    horizontalAccuracyMeters: 5,
                    speedMetersPerSecond: 7,
                  ),
                ),
            ]),
            activeRunSessionCoordinator: _testActiveRunSessionCoordinator(
              tester,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Tracking paused'), findsOneWidget);
      expect(find.text(abnormalMovementGuidance), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Pause'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
      expect(find.byKey(const Key('hold_to_end_button')), findsOneWidget);
      expect(find.text('End'), findsOneWidget);

      final endButton = find.byKey(const Key('hold_to_end_button'));
      final holdGesture = await tester.startGesture(
        tester.getCenter(endButton),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await holdGesture.up();
      await tester.pumpAndSettle();

      expect(repository.completeRunCalls, 0);
      expect(repository.lastPayload, isNull);
      expect(find.text('Cool down'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Run launch real GPS path waits without showing demo mode', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          locationProvider: ReplayRunLocationProvider(const []),
          locationPreviewProvider: _FakeRunLocationPreviewProvider(
            sample: _previewSample(),
          ),
          permissionService: const _GrantedRunLocationPermissionService(),
          notificationPermissionService:
              const _GrantedRunNotificationPermissionService(),
          foregroundService: const NoopRunForegroundService(),
          activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GPS ready'), findsOneWidget);
    expect(find.text('Demo mode'), findsNothing);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Waiting for GPS'), findsOneWidget);
    expect(find.text('Demo mode'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch real GPS path becomes active after accepted sample', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    final sampleBase = DateTime.now().add(const Duration(days: 1));

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: RunLocationSample(
                recordedAt: sampleBase.add(const Duration(seconds: 1)),
                latitude: 1.3,
                longitude: 103.8,
                horizontalAccuracyMeters: 5,
              ),
            ),
          ]),
          locationPreviewProvider: _FakeRunLocationPreviewProvider(
            sample: _previewSample(),
          ),
          permissionService: const _GrantedRunLocationPermissionService(),
          notificationPermissionService:
              const _GrantedRunNotificationPermissionService(),
          foregroundService: const NoopRunForegroundService(),
          activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('GPS active'), findsOneWidget);
    expect(
      find.text('GPS is ready. Start moving to measure distance.'),
      findsNothing,
    );
    expect(find.text('Demo mode'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch real GPS path shows weak after rejected accuracy', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    final sampleBase = DateTime.now().add(const Duration(days: 1));

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: RunLocationSample(
                recordedAt: sampleBase.add(const Duration(seconds: 1)),
                latitude: 1.3,
                longitude: 103.8,
                horizontalAccuracyMeters: 250,
              ),
            ),
          ]),
          locationPreviewProvider: _FakeRunLocationPreviewProvider(
            sample: _previewSample(),
          ),
          permissionService: const _GrantedRunLocationPermissionService(),
          notificationPermissionService:
              const _GrantedRunNotificationPermissionService(),
          foregroundService: const NoopRunForegroundService(),
          activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('GPS weak'), findsOneWidget);
    expect(
      find.text('GPS signal is weak. Keep moving in an open area.'),
      findsNothing,
    );
    expect(find.text('Demo mode'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RunMapPlaceholder renders local route polyline and runner marker',
    (WidgetTester tester) async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: RunMapPlaceholder(
              mapViewState: RunMapViewState(
                currentPosition: RunLocationSample(
                  recordedAt: startedAt.add(const Duration(seconds: 60)),
                  latitude: 1.300899,
                  longitude: 103.800000,
                ),
                routeSegments: [
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
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('run_map_route_polyline')), findsOneWidget);
      expect(find.byKey(const Key('run_map_runner_marker')), findsOneWidget);
      expect(find.byKey(const Key('run_map_recenter_button')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RunMapPlaceholder manual pan shows recenter and recenter restores follow',
    (WidgetTester tester) async {
      var isFollowingRunner = true;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox.expand(
                child: RunMapPlaceholder(
                  isFollowingRunner: isFollowingRunner,
                  onManualPan: () {
                    setState(() => isFollowingRunner = false);
                  },
                  onRecenter: () {
                    setState(() => isFollowingRunner = true);
                  },
                ),
              );
            },
          ),
        ),
      );

      expect(find.byKey(const Key('run_map_recenter_button')), findsNothing);

      await tester.drag(
        find.byKey(const Key('run_map_interaction_layer')),
        const Offset(40, 0),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('run_map_recenter_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('run_map_recenter_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('run_map_recenter_button')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('RunLaunchScreen shows persistent recenter above the sheet', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);

    await tester.pumpWidget(
      const MaterialApp(home: RunLaunchScreen(enableForegroundGps: false)),
    );
    await tester.pumpAndSettle();

    var recenter = find.byKey(const Key('run_map_recenter_button'));
    var sheet = find.byKey(const Key('runLaunchBottomSheet'));
    final planLabel = find.text('TODAY\'S PLAN');
    expect(recenter, findsOneWidget);
    _expectSheetAdjacentRecenter(
      tester: tester,
      recenter: recenter,
      sheet: sheet,
    );
    expect(planLabel, findsOneWidget);
    expect(
      tester.getRect(sheet).right - tester.getRect(recenter).right,
      closeTo(28, 1),
    );
    expect(
      tester.getRect(recenter).overlaps(tester.getRect(planLabel)),
      isFalse,
    );

    await tester.drag(
      find.byKey(const Key('run_map_interaction_layer')),
      const Offset(48, 0),
    );
    await tester.pump();

    recenter = find.byKey(const Key('run_map_recenter_button'));
    sheet = find.byKey(const Key('runLaunchBottomSheet'));
    expect(recenter, findsOneWidget);
    _expectSheetAdjacentRecenter(
      tester: tester,
      recenter: recenter,
      sheet: sheet,
    );

    await tester.tap(recenter);
    await tester.pump();

    expect(find.byKey(const Key('run_map_recenter_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RunLaunchScreen recenter is a gentle no-op before current location',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final permissionService = _ConfigurableRunLocationPermissionService(
        checkedStatus: RunLocationPermissionStatus.deniedForever,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(permissionService: permissionService),
        ),
      );
      await tester.pump();

      final recenter = find.byKey(const Key('run_map_recenter_button'));
      expect(recenter, findsOneWidget);

      await tester.tap(recenter);
      await tester.pump();

      expect(find.byKey(const Key('run_map_recenter_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RunLaunchScreen seeded preview current position reaches the map on first build',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final permissionService = _ConfigurableRunLocationPermissionService(
        checkedStatus: RunLocationPermissionStatus.granted,
      );
      final previewProvider = _CompletingRunLocationPreviewProvider();
      RunMapboxSurfaceConfig? firstConfig;
      final seededPreviewSample = _previewSample();

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            locationProvider: ReplayRunLocationProvider(const []),
            locationPreviewProvider: previewProvider,
            permissionService: permissionService,
            initialPreviewCurrentPosition: seededPreviewSample,
            mapboxAccessToken: _demoMapboxPublicToken,
            mapboxBuilder: (context, config) {
              firstConfig ??= config;
              return const ColoredBox(color: Colors.black);
            },
          ),
        ),
      );

      expect(firstConfig?.mapViewState.previewPosition, seededPreviewSample);
      expect(firstConfig?.mapViewState.currentPosition, isNull);
      expect(firstConfig?.mapViewState.displayPosition, seededPreviewSample);
      expect(firstConfig?.mapViewState.routeSegments, isEmpty);
      expect(firstConfig?.isFollowingRunner, isTrue);
      expect(find.text('Start run'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RunLaunchScreen does not request permission on entry when denied',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final permissionService = _ConfigurableRunLocationPermissionService(
        checkedStatus: RunLocationPermissionStatus.denied,
      );
      final previewProvider = _FakeRunLocationPreviewProvider(
        sample: _previewSample(),
      );
      RunMapboxSurfaceConfig? capturedConfig;

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            locationPreviewProvider: previewProvider,
            permissionService: permissionService,
            mapboxAccessToken: _demoMapboxPublicToken,
            mapboxBuilder: (context, config) {
              capturedConfig = config;
              return const ColoredBox(color: Colors.black);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(permissionService.checkCount, 1);
      expect(permissionService.requestCount, 0);
      expect(previewProvider.requestCount, 0);
      expect(find.text('Tap location'), findsOneWidget);
      expect(capturedConfig?.mapViewState.currentPosition, isNull);
      expect(find.byKey(const Key('run_map_recenter_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RunLaunchScreen granted entry fetches preview current position for map',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final permissionService = _ConfigurableRunLocationPermissionService(
        checkedStatus: RunLocationPermissionStatus.granted,
      );
      final previewProvider = _FakeRunLocationPreviewProvider(
        sample: _previewSample(),
      );
      RunMapboxSurfaceConfig? capturedConfig;

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            locationProvider: ReplayRunLocationProvider(const []),
            locationPreviewProvider: previewProvider,
            permissionService: permissionService,
            mapboxAccessToken: _demoMapboxPublicToken,
            mapboxBuilder: (context, config) {
              capturedConfig = config;
              return const ColoredBox(color: Colors.black);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(permissionService.checkCount, 1);
      expect(permissionService.requestCount, 0);
      expect(previewProvider.requestCount, 1);
      expect(find.text('GPS ready'), findsOneWidget);
      expect(capturedConfig?.mapViewState.previewPosition?.latitude, 1.3009);
      expect(capturedConfig?.mapViewState.currentPosition, isNull);
      expect(capturedConfig?.mapViewState.displayPosition?.latitude, 1.3009);
      expect(capturedConfig?.mapViewState.routeSegments, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RunLaunchScreen recenter requests permission then keeps button visible',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final permissionService = _ConfigurableRunLocationPermissionService(
        checkedStatus: RunLocationPermissionStatus.denied,
        requestedStatus: RunLocationPermissionStatus.granted,
      );
      final previewProvider = _FakeRunLocationPreviewProvider(
        sample: _previewSample(),
      );
      final configs = <RunMapboxSurfaceConfig>[];

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            locationProvider: ReplayRunLocationProvider(const []),
            locationPreviewProvider: previewProvider,
            permissionService: permissionService,
            mapboxAccessToken: _demoMapboxPublicToken,
            mapboxBuilder: (context, config) {
              configs.add(config);
              return const ColoredBox(color: Colors.black);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('run_map_recenter_button')));
      await tester.pumpAndSettle();

      expect(permissionService.requestCount, 1);
      expect(previewProvider.requestCount, 1);
      expect(find.byKey(const Key('run_map_recenter_button')), findsOneWidget);
      expect(find.text('GPS ready'), findsOneWidget);
      expect(configs.last.mapViewState.previewPosition?.latitude, 1.3009);
      expect(configs.last.mapViewState.currentPosition, isNull);
      expect(configs.last.mapViewState.displayPosition?.latitude, 1.3009);
      expect(configs.last.isFollowingRunner, isTrue);
      expect(
        configs.map((config) => config.recenterRequestId),
        contains(greaterThanOrEqualTo(1)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('RunLaunchScreen preview position does not seed active metrics', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    final permissionService = _ConfigurableRunLocationPermissionService(
      checkedStatus: RunLocationPermissionStatus.granted,
    );
    final previewProvider = _FakeRunLocationPreviewProvider(
      sample: _previewSample(),
    );
    final configs = <RunMapboxSurfaceConfig>[];

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          locationProvider: ReplayRunLocationProvider(const []),
          locationPreviewProvider: previewProvider,
          permissionService: permissionService,
          notificationPermissionService:
              const _GrantedRunNotificationPermissionService(),
          foregroundService: const NoopRunForegroundService(),
          mapboxAccessToken: _demoMapboxPublicToken,
          mapboxBuilder: (context, config) {
            configs.add(config);
            return const ColoredBox(color: Colors.black);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(configs.last.mapViewState.previewPosition, isNotNull);
    expect(configs.last.mapViewState.currentPosition, isNull);
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('0.00 of 4.50 km'), findsOneWidget);
    expect(find.text('--:--/km'), findsOneWidget);
    expect(configs.last.mapViewState.previewPosition?.latitude, 1.3009);
    expect(configs.last.mapViewState.currentPosition, isNull);
    expect(configs.last.mapViewState.displayPosition?.latitude, 1.3009);
    expect(configs.last.mapViewState.routeSegments, isEmpty);
    expect(
      configs.map((config) => config.recenterRequestId),
      isNot(contains(1)),
    );
    expect(configs.last.recenterRequestId, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RunLaunchScreen manual pan before GPS ready prevents auto camera recenter',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final permissionService = _ConfigurableRunLocationPermissionService(
        checkedStatus: RunLocationPermissionStatus.granted,
      );
      final previewProvider = _CompletingRunLocationPreviewProvider();
      final configs = <RunMapboxSurfaceConfig>[];

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            locationProvider: ReplayRunLocationProvider(const []),
            locationPreviewProvider: previewProvider,
            permissionService: permissionService,
            mapboxAccessToken: _demoMapboxPublicToken,
            mapboxBuilder: (context, config) {
              configs.add(config);
              return GestureDetector(
                key: const Key('fake_mapbox_pan_layer'),
                onPanUpdate: (_) => config.onManualPan?.call(),
                child: const ColoredBox(color: Colors.black),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(previewProvider.requestCount, 1);
      expect(configs.last.mapViewState.currentPosition, isNull);
      expect(configs.last.isFollowingRunner, isTrue);

      await tester.drag(
        find.byKey(const Key('fake_mapbox_pan_layer')),
        const Offset(48, 0),
      );
      await tester.pump();

      expect(configs.last.isFollowingRunner, isFalse);

      previewProvider.completer.complete(_previewSample());
      await tester.pumpAndSettle();

      expect(find.text('GPS ready'), findsOneWidget);
      expect(configs.last.mapViewState.previewPosition?.latitude, 1.3009);
      expect(configs.last.mapViewState.currentPosition, isNull);
      expect(configs.last.mapViewState.displayPosition?.latitude, 1.3009);
      expect(configs.last.isFollowingRunner, isFalse);
      expect(
        configs.map((config) => config.recenterRequestId),
        isNot(contains(1)),
      );
      expect(configs.last.recenterRequestId, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('RunLaunchScreen selects Mapbox path when token is present', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    RunMapboxSurfaceConfig? capturedConfig;

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          enableForegroundGps: false,
          mapboxAccessToken: _demoMapboxPublicToken,
          mapboxBuilder: (context, config) {
            capturedConfig = config;
            return const ColoredBox(
              key: Key('fake_launch_mapbox_surface'),
              color: Colors.black,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('run_mapbox_surface_selected')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('run_mapbox_placeholder_selected')),
      findsNothing,
    );
    expect(find.byKey(const Key('fake_launch_mapbox_surface')), findsOneWidget);
    expect(find.byType(RunMapPlaceholder), findsNothing);
    expect(capturedConfig, isNotNull);
    expect(capturedConfig!.accessToken, _demoMapboxPublicToken);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RunLaunchScreen follow QA overlay reports screen and resume', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          enableForegroundGps: false,
          enableMapboxFollowQa: true,
          mapboxAccessToken: _demoMapboxPublicToken,
          mapboxBuilder: (context, config) {
            return const ColoredBox(
              key: Key('fake_launch_mapbox_surface'),
              color: Colors.black,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();

    expect(
      find.byKey(const Key('run_mapbox_follow_qa_overlay')),
      findsOneWidget,
    );
    expect(find.text('map: mapbox'), findsOneWidget);
    expect(find.text('screen: launch'), findsOneWidget);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pumpAndSettle();

    expect(find.text('resume: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RunLaunchScreen recenter forwards a Mapbox camera recenter intent',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final configs = <RunMapboxSurfaceConfig>[];

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            enableForegroundGps: false,
            mapboxAccessToken: _demoMapboxPublicToken,
            mapboxBuilder: (context, config) {
              configs.add(config);
              return GestureDetector(
                key: const Key('fake_mapbox_pan_layer'),
                onPanUpdate: (_) => config.onManualPan?.call(),
                child: const ColoredBox(color: Colors.black),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('fake_mapbox_pan_layer')),
        const Offset(48, 0),
      );
      await tester.pump();

      final recenter = find.byKey(const Key('run_map_recenter_button'));
      expect(recenter, findsOneWidget);

      await tester.pump(const Duration(seconds: 1));

      expect(configs.last.isFollowingRunner, isFalse);

      await tester.tap(recenter);
      await tester.pump();
      await tester.pump();

      expect(
        configs.map((config) => config.isFollowingRunner),
        contains(false),
      );
      expect(configs.last.isFollowingRunner, isTrue);
      expect(configs.map((config) => config.recenterRequestId), contains(1));
      expect(configs.last.recenterRequestId, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('RunLaunchScreen sheet drag does not disable Mapbox follow', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    final configs = <RunMapboxSurfaceConfig>[];

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          enableForegroundGps: false,
          mapboxAccessToken: _demoMapboxPublicToken,
          mapboxBuilder: (context, config) {
            configs.add(config);
            return GestureDetector(
              key: const Key('fake_mapbox_pan_layer'),
              onPanUpdate: (_) => config.onManualPan?.call(),
              child: const ColoredBox(color: Colors.black),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    expect(configs.last.isFollowingRunner, isTrue);

    await tester.drag(
      find.byKey(const Key('runLaunchBottomSheet')),
      const Offset(0, 80),
    );
    await tester.pump();

    expect(configs.last.isFollowingRunner, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RunLaunchScreen keeps Mapbox follow disabled after resume tick',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final configs = <RunMapboxSurfaceConfig>[];

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            enableForegroundGps: false,
            mapboxAccessToken: _demoMapboxPublicToken,
            mapboxBuilder: (context, config) {
              configs.add(config);
              return GestureDetector(
                key: const Key('fake_mapbox_pan_layer'),
                onPanUpdate: (_) => config.onManualPan?.call(),
                child: const ColoredBox(color: Colors.black),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('fake_mapbox_pan_layer')),
        const Offset(48, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(configs.last.isFollowingRunner, isFalse);

      await tester.tap(find.byKey(const Key('run_map_recenter_button')));
      await tester.pump();

      expect(configs.last.isFollowingRunner, isTrue);
      expect(configs.last.recenterRequestId, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Run launch starts deterministic active local tracking', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    await _openRunLaunch(tester);

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('Start run'), findsOneWidget);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('0.00 of 4.50 km'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byKey(const Key('run_plan_progress_bar')), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
    expect(find.text('--:--/km'), findsOneWidget);
    expect(find.text('AVG PACE'), findsNothing);
    expect(find.text('CURRENT PACE'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Resume'), findsNothing);

    await tester.pump(const Duration(seconds: 10));

    expect(find.text('00:10'), findsOneWidget);
    expect(find.textContaining('of 4.50 km'), findsOneWidget);
    expect(find.text('1%'), findsOneWidget);
    expect(find.text('--:--/km'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch shows auto pause with paused controls', (
    WidgetTester tester,
  ) async {
    _useNarrowRunSurface(tester);
    final sampleBase = DateTime.now().add(const Duration(days: 1));

    await tester.pumpWidget(
      MaterialApp(
        home: RunLaunchScreen(
          locationProvider: ReplayRunLocationProvider([
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 1),
              sample: RunLocationSample(
                recordedAt: sampleBase.add(const Duration(seconds: 1)),
                latitude: 1.300000,
                longitude: 103.800000,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 0.1,
              ),
            ),
            RunLocationReplaySample(
              activeOffset: const Duration(seconds: 7),
              sample: RunLocationSample(
                recordedAt: sampleBase.add(const Duration(seconds: 7)),
                latitude: 1.300009,
                longitude: 103.800000,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 0.1,
              ),
            ),
          ]),
          locationPreviewProvider: _FakeRunLocationPreviewProvider(
            sample: _previewSample(),
          ),
          permissionService: const _GrantedRunLocationPermissionService(),
          notificationPermissionService:
              const _GrantedRunNotificationPermissionService(),
          foregroundService: const NoopRunForegroundService(),
          activeRunSessionCoordinator: _testActiveRunSessionCoordinator(tester),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    for (var tick = 0; tick < 7; tick += 1) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();

    _expectStatusLabelReadable(tester, 'Paused');
    expect(find.text('00:06'), findsOneWidget);
    expect(find.text('0.00 of 4.50 km'), findsOneWidget);
    expect(find.text('--:--/km'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run pause, resume, and hold End keep local state untrusted', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    await _openRunLaunch(tester);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));

    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pumpAndSettle();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    expect(find.byKey(const Key('hold_to_end_button')), findsOneWidget);
    expect(find.text('Pause'), findsNothing);

    await tester.pump(const Duration(seconds: 10));

    expect(find.text('00:10'), findsOneWidget);
    expect(find.textContaining('of 4.50 km'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('00:10'), findsNothing);
    expect(find.text('0.02 of 4.50 km'), findsNothing);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);
    expect(find.text('End'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('hold_to_end_button')));
    await tester.pumpAndSettle();

    expect(find.text('Cool down'), findsNothing);
    expect(find.text('Paused'), findsOneWidget);

    final endButton = find.byKey(const Key('hold_to_end_button'));
    final endCenter = tester.getCenter(endButton);
    final gesture = await tester.startGesture(endCenter);
    await tester.pump(const Duration(milliseconds: 1200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Cool down'), findsNothing);
    expect(find.text('Paused'), findsOneWidget);

    final holdGesture = await tester.startGesture(endCenter);
    await tester.pump(const Duration(milliseconds: 1600));
    await holdGesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Cool down'), findsOneWidget);
    expect(find.textContaining('XP'), findsNothing);
    expect(find.textContaining('streak'), findsNothing);
    expect(find.textContaining('Leaderboard'), findsNothing);
    expect(
      find.textContaining(
        'validation'
        'Status',
      ),
      findsNothing,
    );
    expect(
      find.textContaining(
        'countsToward'
        'Progression',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run pause and resume keep the launch sheet geometry stable', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    await _openRunLaunch(tester);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('runLaunchBottomSheet'));
    expect(sheet, findsOneWidget);
    expect(find.byKey(const Key('trackingSheetContent')), findsOneWidget);
    expect(find.byKey(const Key('runningActions')), findsOneWidget);
    expect(find.byKey(const Key('pausedActions')), findsNothing);
    final runningRect = tester.getRect(sheet);

    await tester.tap(find.byKey(const Key('pauseRunButton')));
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.byKey(const Key('trackingSheetContent')), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pausedActions')), findsOneWidget);
    expect(find.byKey(const Key('runningActions')), findsNothing);
    final pausedRect = tester.getRect(sheet);
    expect((pausedRect.top - runningRect.top).abs(), lessThanOrEqualTo(1));
    expect(
      (pausedRect.bottom - runningRect.bottom).abs(),
      lessThanOrEqualTo(1),
    );

    await tester.tap(find.byKey(const Key('resumeRunButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('runningActions')), findsOneWidget);
    expect(find.byKey(const Key('pausedActions')), findsNothing);
    final resumedRect = tester.getRect(sheet);
    expect((resumedRect.top - runningRect.top).abs(), lessThanOrEqualTo(1));
    expect(
      (resumedRect.bottom - runningRect.bottom).abs(),
      lessThanOrEqualTo(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch pre-run sheet collapses and expands from handle', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    await _openRunLaunch(tester);

    final sheet = find.byKey(const Key('runLaunchBottomSheet'));
    final handle = find.byKey(const Key('runLaunchSheetHandleArea'));
    expect(sheet, findsOneWidget);
    expect(handle, findsOneWidget);
    expect(find.byKey(const Key('runLaunchSheetHandle')), findsOneWidget);
    expect(find.byKey(const Key('preRunSheetContent')), findsOneWidget);
    expect(find.text('TODAY\'S PLAN'), findsOneWidget);
    expect(find.text('Start run'), findsOneWidget);

    final expandedRect = tester.getRect(sheet);
    await tester.drag(handle, const Offset(0, 700));
    await tester.pumpAndSettle();

    final collapsedRect = tester.getRect(sheet);
    expect(find.byKey(const Key('runLaunchSheetHandle')), findsOneWidget);
    expect(
      find.byKey(const Key('runLaunchSheetCollapsedContent')),
      findsOneWidget,
    );
    expect(find.text('TODAY\'S PLAN'), findsNothing);
    expect(find.text('Start run'), findsNothing);
    expect(collapsedRect.height, lessThan(expandedRect.height));
    expect(collapsedRect.height, greaterThan(40));

    await tester.drag(handle, const Offset(0, -700));
    await tester.pumpAndSettle();

    final reexpandedRect = tester.getRect(sheet);
    expect(find.byKey(const Key('preRunSheetContent')), findsOneWidget);
    expect(find.text('TODAY\'S PLAN'), findsOneWidget);
    expect(find.text('Start run'), findsOneWidget);
    expect((reexpandedRect.height - expandedRect.height).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch running sheet collapses while tracking continues', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    await _openRunLaunch(tester);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('runLaunchBottomSheet'));
    final handle = find.byKey(const Key('runLaunchSheetHandleArea'));
    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Resume'), findsNothing);

    final expandedRect = tester.getRect(sheet);
    await tester.drag(handle, const Offset(0, 700));
    await tester.pumpAndSettle();

    final collapsedRect = tester.getRect(sheet);
    expect(find.byKey(const Key('runLaunchSheetHandle')), findsOneWidget);
    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsNothing);
    expect(find.text('TIME'), findsNothing);
    expect(find.text('DISTANCE'), findsNothing);
    expect(collapsedRect.height, lessThan(expandedRect.height));
    expect(collapsedRect.height, greaterThan(40));

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsNothing);

    await tester.drag(handle, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('00:00'), findsNothing);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Resume'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch reopens active app-level session as running', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    var now = DateTime(2026, 6, 17, 8);
    final activeRunSessionCoordinator = ActiveRunSessionCoordinator(
      clock: () => now,
      foregroundTickStep: const Duration(seconds: 1),
    );
    addTearDown(activeRunSessionCoordinator.dispose);
    await _openRunLaunch(
      tester,
      activeRunSessionCoordinator: activeRunSessionCoordinator,
    );

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('00:03'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 8));

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    expect(find.text('Start run'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('00:08'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notification reopen restores the app-level active session as running',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      var now = DateTime(2026, 6, 17, 8);
      final activeRunSessionCoordinator = ActiveRunSessionCoordinator(
        clock: () => now,
        foregroundTickStep: const Duration(seconds: 1),
      );
      addTearDown(activeRunSessionCoordinator.dispose);
      await _openRunLaunch(
        tester,
        activeRunSessionCoordinator: activeRunSessionCoordinator,
      );

      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);

      final handled = await tester.binding.handlePopRoute();
      expect(handled, isTrue);
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 10));

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          activeRunSessionCoordinator: activeRunSessionCoordinator,
          initialRunOpenIntent: const RunOpenIntent.notification(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RunLaunchScreen), findsOneWidget);
      expect(find.text('Start run'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('00:10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('notification reopen keeps duration planned run progress', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    var now = DateTime(2026, 6, 17, 8);
    final activeRunSessionCoordinator = ActiveRunSessionCoordinator(
      clock: () => now,
      foregroundTickStep: const Duration(seconds: 1),
    );
    final generatedPlanStore = CurrentSessionGeneratedPlanStore()
      ..setActivePlan(_tenKPerformancePlan());
    addTearDown(activeRunSessionCoordinator.dispose);
    addTearDown(generatedPlanStore.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        activeRunSessionCoordinator: activeRunSessionCoordinator,
        currentSessionGeneratedPlanStore: generatedPlanStore,
        youProgressToday: _weekdayDate(DateTime.tuesday),
      ),
    );
    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    expect(find.text('25 min'), findsOneWidget);
    expect(find.text('4.5'), findsNothing);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 10));

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        activeRunSessionCoordinator: activeRunSessionCoordinator,
        currentSessionGeneratedPlanStore: generatedPlanStore,
        initialRunOpenIntent: const RunOpenIntent.notification(),
        youProgressToday: _weekdayDate(DateTime.tuesday),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RunLaunchScreen), findsOneWidget);
    expect(find.text('Start run'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('00:10 of 25:00'), findsOneWidget);
    expect(find.text('0.00 of 4.50 km'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system resume reopens an app-level active run from the shell', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    var now = DateTime(2026, 6, 17, 8);
    final activeRunSessionCoordinator = ActiveRunSessionCoordinator(
      clock: () => now,
      foregroundTickStep: const Duration(seconds: 1),
    );
    addTearDown(activeRunSessionCoordinator.dispose);
    await _openRunLaunch(
      tester,
      activeRunSessionCoordinator: activeRunSessionCoordinator,
    );

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(RunLaunchScreen), findsNothing);
    now = now.add(const Duration(seconds: 12));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(RunLaunchScreen), findsOneWidget);
    expect(find.text('Start run'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('00:12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch paused sheet collapses without resuming or ending', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    await _openRunLaunch(tester);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pauseRunButton')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('runLaunchBottomSheet'));
    final handle = find.byKey(const Key('runLaunchSheetHandleArea'));
    expect(find.text('Paused'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    expect(find.byKey(const Key('hold_to_end_button')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsNothing);

    final expandedRect = tester.getRect(sheet);
    await tester.drag(handle, const Offset(0, 700));
    await tester.pumpAndSettle();

    final collapsedRect = tester.getRect(sheet);
    expect(find.byKey(const Key('runLaunchSheetHandle')), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsNothing);
    expect(find.byKey(const Key('hold_to_end_button')), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsNothing);
    expect(find.text('Cool down'), findsNothing);
    expect(collapsedRect.height, lessThan(expandedRect.height));
    expect(collapsedRect.height, greaterThan(40));

    await tester.drag(handle, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    expect(find.byKey(const Key('hold_to_end_button')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsNothing);
    expect(find.text('Cool down'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run launch collapse and expand do not push routes', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    final observer = _RoutePushRecorder();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const RunLaunchScreen(enableForegroundGps: false),
      ),
    );
    await tester.pumpAndSettle();
    observer.pushedRoutes.clear();

    final handle = find.byKey(const Key('runLaunchSheetHandleArea'));
    await tester.drag(handle, const Offset(0, 700));
    await tester.pumpAndSettle();

    expect(observer.pushedRoutes, isEmpty);
    expect(find.byKey(const Key('runLaunchSheetHandle')), findsOneWidget);
    expect(find.text('TODAY\'S PLAN'), findsNothing);

    await tester.tap(handle);
    await tester.pumpAndSettle();

    expect(observer.pushedRoutes, isEmpty);
    expect(find.text('TODAY\'S PLAN'), findsOneWidget);

    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    expect(observer.pushedRoutes, isEmpty);
    expect(find.byType(RunLaunchScreen), findsOneWidget);
    expect(find.text('Demo mode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Paused End exposes accessible long press and hold progress', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    final semantics = tester.ensureSemantics();

    await _openRunLaunch(tester);
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pumpAndSettle();

    final endSemantics = find.bySemanticsLabel('Hold to end run');
    expect(endSemantics, findsOneWidget);
    expect(find.text('Hold for 1.5 seconds to finish your run'), findsNothing);
    final endNode = tester.getSemantics(endSemantics);
    final endData = endNode.getSemanticsData();
    expect(endData.hint, 'Hold for 1.5 seconds to finish your run');
    expect(endData.hasAction(SemanticsAction.longPress), isTrue);
    expect(find.byKey(const Key('hold_to_end_progress_gauge')), findsNothing);

    final endButton = find.byKey(const Key('hold_to_end_button'));
    final gesture = await tester.startGesture(tester.getCenter(endButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    final gauge = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('hold_to_end_progress_gauge')),
    );
    expect(gauge.value, greaterThan(0));
    expect(gauge.value, lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hold_to_end_progress_gauge')), findsNothing);
    expect(find.text('Cool down'), findsNothing);
    expect(find.text('Paused'), findsOneWidget);

    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('RunLaunchScreen keeps shared Pause Resume and End behavior', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);

    await tester.pumpWidget(
      const MaterialApp(home: RunLaunchScreen(enableForegroundGps: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Resume'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pumpAndSettle();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    expect(find.byKey(const Key('hold_to_end_button')), findsOneWidget);
    expect(find.text('Pause'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);
    expect(find.text('End'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pumpAndSettle();

    final endButton = find.byKey(const Key('hold_to_end_button'));
    await tester.tap(endButton);
    await tester.pumpAndSettle();

    expect(find.text('Cool down'), findsNothing);
    expect(find.text('Paused'), findsOneWidget);

    final holdGesture = await tester.startGesture(tester.getCenter(endButton));
    await tester.pump(const Duration(milliseconds: 1600));
    await holdGesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Cool down'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RunLaunchScreen uses injected server completion for summary and XP',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final repository = _ResultRunRepository(_serverAwardedCompletionResult);
      final runHarness = _testSufficientRunHarness(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: RunLaunchScreen(
            repository: repository,
            enableForegroundGps: false,
            activeRunSessionCoordinator: runHarness.coordinator,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      await _pumpSufficientRun(tester);

      runHarness.controller.pause(pausedAt: tester.binding.clock.now());
      await tester.pumpAndSettle();
      final endButton = find.byKey(const Key('hold_to_end_button'));
      final holdGesture = await tester.startGesture(
        tester.getCenter(endButton),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await holdGesture.up();
      await tester.pumpAndSettle();

      expect(repository.completeRunCalls, 1);
      expect(repository.lastPayload, isNotNull);
      expect(find.text('Cool down'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
      await tester.pumpAndSettle();

      final summaryScreen = tester.widget<ViewSummaryScreen>(
        find.byType(ViewSummaryScreen),
      );
      expect(
        summaryScreen.completionResult?.activityId,
        'activity_server_awarded',
      );
      expect(summaryScreen.completionResult?.progressionDisplay.xpDelta, 75);
      expect(summaryScreen.completionResult?.xpUpdate.levelLabel, 'Level 1');
      expect(
        summaryScreen.completionResult?.xpUpdate.streakChangeLabel,
        '0 → 1 days',
      );
      expect(find.text('Server Awarded Run'), findsOneWidget);

      await tester.ensureVisible(find.text('View XP Update'));
      await tester.tap(find.text('View XP Update'));
      await tester.pumpAndSettle();

      expect(find.text('+75 XP'), findsOneWidget);
      expect(find.text('Lv.Level 1'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RunLaunchScreen sends tracked completion result through cool down to summary',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final repository = _ResultRunRepository(_serverAwardedCompletionResult);
      final historyStore = CurrentSessionActivityHistoryStore(
        ownerUid: 'test-owner',
        persistence: MemoryLocalPendingRunActivityStore(),
      );
      final runHarness = _testSufficientRunHarness(tester);
      runHarness.controller.start(
        startedAt: tester.binding.clock.now(),
        routeLabel: 'Injected repository route',
      );
      runHarness.controller.advanceBy(const Duration(seconds: 120));
      addTearDown(historyStore.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CurrentSessionActivityHistoryScope(
            store: historyStore,
            child: RunRepositoryScope(
              repository: repository,
              child: RunLaunchScreen(
                enableForegroundGps: false,
                activeRunSessionCoordinator: runHarness.coordinator,
              ),
            ),
          ),
        ),
      );
      // The harness controller is already running, so the screen reopens
      // straight into the running sheet — there is no Start run button here.
      await tester.pumpAndSettle();
      await _pumpSufficientRun(tester);

      runHarness.controller.pause(pausedAt: tester.binding.clock.now());
      await tester.pumpAndSettle();

      final endButton = find.byKey(const Key('hold_to_end_button'));
      final holdGesture = await tester.startGesture(
        tester.getCenter(endButton),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await holdGesture.up();
      await tester.pumpAndSettle();

      expect(repository.completeRunCalls, 1);
      expect(repository.lastPayload, isNotNull);
      expect(find.text('Cool down'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
      await tester.pumpAndSettle();

      final summaryScreen = tester.widget<ViewSummaryScreen>(
        find.byType(ViewSummaryScreen),
      );
      expect(
        summaryScreen.completionResult?.activityId,
        'activity_server_awarded',
      );
      expect(summaryScreen.completionResult?.progressionDisplay.xpDelta, 75);
      expect(summaryScreen.completionResult?.xpUpdate.levelLabel, 'Level 1');
      expect(
        summaryScreen.completionResult?.xpUpdate.streakChangeLabel,
        '0 → 1 days',
      );
      expect(
        find.text(summaryScreen.completionResult!.summary.title),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('View XP Update'));
      await tester.tap(find.text('View XP Update'));
      await tester.pumpAndSettle();

      expect(find.text('+75 XP'), findsOneWidget);
      expect(find.text('Lv.Level 1'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RunLaunchScreen completed-plan extra runs do not register planned completion ids',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final historyStore = CurrentSessionActivityHistoryStore(
        ownerUid: 'test-owner',
        persistence: MemoryLocalPendingRunActivityStore(),
      );
      final runHarness = _testSufficientRunHarness(tester);
      addTearDown(historyStore.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CurrentSessionActivityHistoryScope(
            store: historyStore,
            child: RunLaunchScreen(
              enableForegroundGps: false,
              activeRunSessionCoordinator: runHarness.coordinator,
              plannedWorkout: const PlannedRunContext(
                title: 'Easy run',
                durationMinutes: 30,
                planTitle: 'Base Builder',
                planFamilyLabel: 'Beginner Base',
                workoutKindLabel: 'Easy Run',
                intensityLabel: 'Easy',
                steps: ['Run relaxed for 30 minutes.'],
                supportiveNote: 'Extra run mode keeps this separate.',
                sourceLabel: 'Generated onboarding plan',
                objectiveKind: PlannedRunObjectiveKind.duration,
                alreadyCompletedToday: true,
                planEnrollmentId: 'generated-plan-base-builder',
                scheduledWorkoutId: 'week-1-tue-easy-run',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      await _pumpSufficientRun(tester);

      runHarness.controller.pause(pausedAt: tester.binding.clock.now());
      await tester.pumpAndSettle();

      final endButton = find.byKey(const Key('hold_to_end_button'));
      final holdGesture = await tester.startGesture(
        tester.getCenter(endButton),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await holdGesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Cool down'), findsOneWidget);
      expect(
        historyStore.completedScheduledWorkoutIdsForPlan(
          'generated-plan-base-builder',
        ),
        isEmpty,
      );
      expect(historyStore.completedScheduledWorkoutIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RunLaunchScreen preserves local advanced analysis after Firebase completion',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final startedAt = DateTime.utc(2026, 6, 18, 8);
      var now = startedAt;
      final cadenceProvider = FakeRunCadenceProvider(
        cadencePattern: const <double>[168, 170, 172],
      );
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: Duration.zero,
            sample: RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.300000,
              longitude: 103.800000,
              altitudeMeters: 4,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 60),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 60)),
              latitude: 1.301349,
              longitude: 103.800000,
              altitudeMeters: 5.2,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 120),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 120)),
              latitude: 1.302698,
              longitude: 103.800000,
              altitudeMeters: 8.4,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 180),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 180)),
              latitude: 1.304047,
              longitude: 103.800000,
              altitudeMeters: 6.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 240),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 240)),
              latitude: 1.305396,
              longitude: 103.800000,
              altitudeMeters: 7.4,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 300),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 300)),
              latitude: 1.306745,
              longitude: 103.800000,
              altitudeMeters: 9.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 360),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 360)),
              latitude: 1.308094,
              longitude: 103.800000,
              altitudeMeters: 7.2,
            ),
          ),
        ]),
        cadenceProvider: cadenceProvider,
      );
      final activeRunSessionCoordinator = ActiveRunSessionCoordinator(
        controller: controller,
        clock: () => now,
        foregroundTickStep: const Duration(seconds: 1),
      );
      addTearDown(activeRunSessionCoordinator.dispose);
      addTearDown(cadenceProvider.dispose);
      final repository = _ResultRunRepository(_firebaseScalarCompletionResult);
      final historyStore = CurrentSessionActivityHistoryStore(
        ownerUid: 'test-owner',
        persistence: MemoryLocalPendingRunActivityStore(),
      );
      addTearDown(historyStore.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CurrentSessionActivityHistoryScope(
            store: historyStore,
            child: RunRepositoryScope(
              repository: repository,
              child: RunLaunchScreen(
                enableForegroundGps: false,
                activeRunSessionCoordinator: activeRunSessionCoordinator,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      now = startedAt.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 60));
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 60)),
      );
      await tester.pump();
      now = startedAt.add(const Duration(seconds: 120));
      await tester.pump(const Duration(seconds: 60));
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 120)),
      );
      await tester.pump();
      now = startedAt.add(const Duration(seconds: 180));
      await tester.pump(const Duration(seconds: 60));
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 180)),
      );
      await tester.pump();
      now = startedAt.add(const Duration(seconds: 240));
      await tester.pump(const Duration(seconds: 60));
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 240)),
      );
      await tester.pump();
      now = startedAt.add(const Duration(seconds: 300));
      await tester.pump(const Duration(seconds: 60));
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 300)),
      );
      await tester.pump();
      now = startedAt.add(const Duration(seconds: 360));
      await tester.pump(const Duration(seconds: 60));
      cadenceProvider.emitNext(
        recordedAt: startedAt.add(const Duration(seconds: 360)),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
      await tester.pumpAndSettle();

      final endButton = find.byKey(const Key('hold_to_end_button'));
      final holdGesture = await tester.startGesture(
        tester.getCenter(endButton),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await holdGesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
      await tester.pumpAndSettle();

      expect(
        repository.lastPayload?.paceGraphSamples,
        hasLength(greaterThanOrEqualTo(3)),
      );
      expect(repository.lastPayload?.cadenceAnalysisSeries, isNotNull);
      expect(repository.lastPayload?.elevationAnalysisSeries, isNotNull);
      expect(find.text('Firebase Scalar Run'), findsNothing);
      final summaryScreen = tester.widget<ViewSummaryScreen>(
        find.byType(ViewSummaryScreen),
      );
      final summary = summaryScreen.completionResult!.summary;
      final advancedAnalysis = const AdvancedAnalysisSnapshotBuilder()
          .fromRunSummary(summary);
      expect(summary.distanceKm, '0.75');
      expect(summary.duration, isNot('--'));
      expect(summary.avgPace, isNot('--'));
      expect(
        summary.paceGraph.isAvailable,
        isTrue,
        reason:
            'payload duration=${repository.lastPayload?.durationSeconds}, '
            'distance=${repository.lastPayload?.distanceMeters}, '
            'samples=${repository.lastPayload?.paceGraphSamples.length}',
      );
      expect(summary.paceAnalysisSeries?.isLocalAcceptedSource, isTrue);
      expect(summary.cadenceAnalysisSeries, isNotNull);
      expect(summary.elevationSeries.isUnavailable, isFalse);
      expect(advancedAnalysis.elevation.elevationGraph.isAvailable, isTrue);
      expect(advancedAnalysis.elevation.totalGain.valueLabel, '+6 m');
      expect(advancedAnalysis.elevation.highestPoint.valueLabel, '9 m');
      expect(advancedAnalysis.elevation.lowestPoint.valueLabel, '4 m');
      expect(summary.route.hasRoute, isTrue);
      expect(summary.avgHeartRate, '--');
      expect(find.text('More Details'), findsOneWidget);

      await tester.ensureVisible(find.text('More Details'));
      await tester.tap(find.text('More Details'));
      await tester.pumpAndSettle();

      expect(find.text('Pace Analysis'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('advanced_analysis_pace_graph_unavailable')),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('advanced_analysis_split_1_km')))
            .data,
        '0.75',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('advanced_analysis_split_1_pace')),
            )
            .data,
        isNot('--'),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('advanced_analysis_split_1_elev')),
          matching: find.text('--'),
        ),
        findsOneWidget,
      );
      expect(find.text('Running Form / Cadence'), findsOneWidget);
      expect(find.text('Cadence is unavailable for this run.'), findsNothing);
      expect(find.text('170'), findsWidgets);
      expect(find.text('168'), findsWidgets);
      expect(find.text('172'), findsWidgets);
      expect(find.text('Stable'), findsWidgets);
      expect(find.text('Elevation Analysis'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('advanced_analysis_elevation_graph_unavailable'),
        ),
        findsNothing,
      );
      expect(find.text('+6'), findsOneWidget);
      expect(find.text('9'), findsWidgets);
      expect(find.text('4'), findsWidgets);
      expect(find.text('m'), findsAtLeastNWidgets(3));
      expect(find.text('Mostly Flat'), findsOneWidget);
    },
  );

  testWidgets(
    'completed run appears first in You Activity History and replays merged analysis',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final startedAt = DateTime.utc(2026, 6, 18, 8);
      var now = startedAt;
      final cadenceProvider = FakeRunCadenceProvider(
        cadencePattern: const <double>[168, 170, 172],
      );
      final controller = RunTrackingController(
        locationProvider: ReplayRunLocationProvider([
          RunLocationReplaySample(
            activeOffset: Duration.zero,
            sample: RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.300000,
              longitude: 103.800000,
              altitudeMeters: 4,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 60),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 60)),
              latitude: 1.301349,
              longitude: 103.800000,
              altitudeMeters: 5.2,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 120),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 120)),
              latitude: 1.302698,
              longitude: 103.800000,
              altitudeMeters: 8.4,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 180),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 180)),
              latitude: 1.304047,
              longitude: 103.800000,
              altitudeMeters: 6.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 240),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 240)),
              latitude: 1.305396,
              longitude: 103.800000,
              altitudeMeters: 7.4,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 300),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 300)),
              latitude: 1.306745,
              longitude: 103.800000,
              altitudeMeters: 9.1,
            ),
          ),
          RunLocationReplaySample(
            activeOffset: const Duration(seconds: 360),
            sample: RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 360)),
              latitude: 1.308094,
              longitude: 103.800000,
              altitudeMeters: 7.2,
            ),
          ),
        ]),
        cadenceProvider: cadenceProvider,
      );
      final activeRunSessionCoordinator = ActiveRunSessionCoordinator(
        controller: controller,
        clock: () => now,
        foregroundTickStep: const Duration(seconds: 1),
      );
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final historyStore = CurrentSessionActivityHistoryStore(
        ownerUid: authRepository.currentUser?.uid,
        persistence: MemoryLocalPendingRunActivityStore(),
      );
      addTearDown(activeRunSessionCoordinator.dispose);
      addTearDown(cadenceProvider.dispose);
      addTearDown(historyStore.dispose);
      addTearDown(authRepository.dispose);
      final repository = _ResultRunRepository(_firebaseScalarCompletionResult);

      await tester.pumpWidget(
        MaterialApp(
          home: CurrentSessionActivityHistoryScope(
            store: historyStore,
            child: RunRepositoryScope(
              repository: repository,
              child: RunLaunchScreen(
                enableForegroundGps: false,
                activeRunSessionCoordinator: activeRunSessionCoordinator,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      for (final elapsed in const [60, 120, 180, 240, 300, 360]) {
        now = startedAt.add(Duration(seconds: elapsed));
        await tester.pump(const Duration(seconds: 60));
        cadenceProvider.emitNext(recordedAt: now);
        await tester.pump();
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
      await tester.pumpAndSettle();

      final endButton = find.byKey(const Key('hold_to_end_button'));
      final holdGesture = await tester.startGesture(
        tester.getCenter(endButton),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await holdGesture.up();
      await tester.pumpAndSettle();

      expect(historyStore.activities, isNotEmpty);
      final localIdentityKey =
          historyStore.activities.first.display.identityKey;

      await tester.pumpWidget(
        RuniacApp(
          authRepository: authRepository,
          showSplash: false,
          enableForegroundGps: false,
          activeRunSessionCoordinator: activeRunSessionCoordinator,
          currentSessionActivityHistoryStore: historyStore,
          // Premium so the replayed summary's advanced analysis stays
          // reachable without the Basic paywall intercept.
          userAccountRepository: const PremiumUserAccountRepository(),
        ),
      );
      await tester.tap(find.byTooltip('You'));
      await tester.pumpAndSettle();

      final seeAll = find.byKey(const ValueKey('recent_running_see_all'));
      await Scrollable.ensureVisible(tester.element(seeAll), alignment: 0.55);
      await tester.pumpAndSettle();
      await tester.tap(seeAll);
      await tester.pumpAndSettle();

      final sessionCard = find.byKey(
        ValueKey('activity_history_card_$localIdentityKey'),
      );
      final firstFallbackCard = find.byKey(
        const ValueKey('activity_history_card_Pace Graph QA Run'),
      );
      expect(sessionCard, findsOneWidget);
      expect(firstFallbackCard, findsOneWidget);
      expect(
        tester.getTopLeft(sessionCard).dy,
        lessThan(tester.getTopLeft(firstFallbackCard).dy),
      );

      await tester.tap(sessionCard);
      await tester.pumpAndSettle();

      expect(find.text('Firebase Scalar Run'), findsNothing);
      expect(find.text('0.75'), findsWidgets);
      final summaryScreen = tester.widget<ViewSummaryScreen>(
        find.byType(ViewSummaryScreen),
      );
      final replayedSummary =
          summaryScreen.completionResult?.summary ?? summaryScreen.summary;
      expect(replayedSummary.paceAnalysisSeries?.isLocalAcceptedSource, isTrue);
      expect(replayedSummary.cadenceAnalysisSeries, isNotNull);
      expect(replayedSummary.elevationSeries.isUnavailable, isFalse);
      expect(replayedSummary.route.hasRoute, isTrue);

      await tester.ensureVisible(find.text('More Details'));
      await tester.tap(find.text('More Details'));
      await tester.pumpAndSettle();

      expect(find.text('Pace Analysis'), findsOneWidget);
      expect(find.text('Running Form / Cadence'), findsOneWidget);
      expect(find.text('Elevation Analysis'), findsOneWidget);
    },
  );

  testWidgets('RunLaunchScreen skips background sync for insufficient data', (
    WidgetTester tester,
  ) async {
    _useMobileRunSurface(tester);
    final repository = _FailingRunRepository(_activeCompletionResult);
    final pendingStore = MemoryLocalPendingRunActivityStore();
    final historyStore = CurrentSessionActivityHistoryStore(
      ownerUid: 'test-owner',
      persistence: pendingStore,
    );
    final runHarness = _testSufficientRunHarness(tester);
    addTearDown(historyStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CurrentSessionActivityHistoryScope(
          store: historyStore,
          child: RunRepositoryScope(
            repository: repository,
            child: RunLaunchScreen(
              enableForegroundGps: false,
              activeRunSessionCoordinator: runHarness.coordinator,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    // Deliberately collect no usable samples: this is the
    // insufficient-data path, so the run must never be submitted.
    await tester.pump(const Duration(seconds: 1));

    runHarness.controller.pause(pausedAt: tester.binding.clock.now());
    await tester.pumpAndSettle();

    final endButton = find.byKey(const Key('hold_to_end_button'));
    final holdGesture = await tester.startGesture(tester.getCenter(endButton));
    await tester.pump(const Duration(milliseconds: 1600));
    await holdGesture.up();
    await tester.pumpAndSettle();

    expect(repository.completeRunCalls, 0);
    expect(repository.lastPayload, isNull);
    expect(await pendingStore.load(), isEmpty);
    expect(find.text('Cool down'), findsOneWidget);
    expect(
      find.text('Run completion is unavailable. Please try again.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RunLaunchScreen leaves retry queue empty for insufficient data',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final repository = _FailOnceRunRepository(_activeCompletionResult);
      final pendingStore = MemoryLocalPendingRunActivityStore();
      final historyStore = CurrentSessionActivityHistoryStore(
        ownerUid: 'test-owner',
        persistence: pendingStore,
      );
      final runHarness = _testSufficientRunHarness(tester);
      addTearDown(historyStore.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CurrentSessionActivityHistoryScope(
            store: historyStore,
            child: RunRepositoryScope(
              repository: repository,
              child: RunLaunchScreen(
                enableForegroundGps: false,
                activeRunSessionCoordinator: runHarness.coordinator,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      // Deliberately collect no usable samples: this is the
      // insufficient-data path, so the run must never be submitted.
      await tester.pump(const Duration(seconds: 1));

      runHarness.controller.pause(pausedAt: tester.binding.clock.now());
      await tester.pumpAndSettle();

      final endButton = find.byKey(const Key('hold_to_end_button'));
      final firstHold = await tester.startGesture(tester.getCenter(endButton));
      await tester.pump(const Duration(milliseconds: 1600));
      await firstHold.up();
      await tester.pumpAndSettle();

      expect(repository.completeRunCalls, 0);
      expect(await pendingStore.load(), isEmpty);
      expect(find.text('Cool down'), findsOneWidget);

      await historyStore.syncPendingRuns(repository);
      expect(repository.completeRunCalls, 0);
      expect(await pendingStore.load(), isEmpty);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Skip to Summary'));
      await tester.pumpAndSettle();

      expect(find.text('Active Repository Run'), findsNothing);
      // An insufficient run still lands on a summary, but a zeroed local one:
      // nothing was submitted, so no server-backed activity can be shown.
      expect(find.text('0.00'), findsOneWidget);
      expect(find.text('Saturday Morning Run'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RunLaunchScreen does not block cool down when no background sync starts',
    (WidgetTester tester) async {
      _useMobileRunSurface(tester);
      final repository = _DelayedRunRepository(_activeCompletionResult);
      final historyStore = CurrentSessionActivityHistoryStore(
        ownerUid: 'test-owner',
        persistence: MemoryLocalPendingRunActivityStore(),
      );
      final runHarness = _testSufficientRunHarness(tester);
      addTearDown(historyStore.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CurrentSessionActivityHistoryScope(
            store: historyStore,
            child: RunRepositoryScope(
              repository: repository,
              child: RunLaunchScreen(
                enableForegroundGps: false,
                activeRunSessionCoordinator: runHarness.coordinator,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pumpAndSettle();
      // Deliberately collect no usable samples: this is the
      // insufficient-data path, so the run must never be submitted.
      await tester.pump(const Duration(seconds: 1));

      runHarness.controller.pause(pausedAt: tester.binding.clock.now());
      await tester.pumpAndSettle();

      final endButton = find.byKey(const Key('hold_to_end_button'));
      final holdGesture = await tester.startGesture(
        tester.getCenter(endButton),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await holdGesture.up();
      await tester.pump();

      expect(repository.completeRunCalls, 0);
      expect(repository.lastPayload, isNull);
      expect(find.text('Saving'), findsNothing);
      expect(find.text('Cool down'), findsOneWidget);

      repository.completer.complete(_activeCompletionResult);
      await tester.pumpAndSettle();

      expect(repository.completeRunCalls, 0);
      expect(find.text('Cool down'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
