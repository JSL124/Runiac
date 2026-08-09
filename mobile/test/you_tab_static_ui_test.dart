import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/app.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';
import 'package:runiac_app/features/auth/data/non_production_auth_repository.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/cadence_graph_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/complete_run_result.dart';
import 'package:runiac_app/features/run/domain/models/local_run_completion_payload.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_display_model.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_read_model.dart';
import 'package:runiac_app/features/run/domain/repositories/run_repository.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';
import 'package:runiac_app/features/run/presentation/advanced_analysis_screen.dart';
import 'package:runiac_app/features/run/presentation/active_run_session_coordinator.dart';
import 'package:runiac_app/features/run/presentation/data/pace_graph_demo_snapshots.dart';
import 'package:runiac_app/features/run/presentation/data/run_completion_demo_snapshots.dart';
import 'package:runiac_app/features/run/presentation/view_summary_screen.dart';
import 'package:runiac_app/features/run/presentation/widgets/advanced_analysis/advanced_analysis_charts.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/you/data/static_activity_history_repository.dart';
import 'package:runiac_app/features/you/data/local_pending_run_activity_store.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';
import 'package:runiac_app/features/you/presentation/data/activity_history_demo_snapshots.dart';
import 'package:runiac_app/features/you/presentation/data/you_overview_demo_snapshots.dart';
import 'package:runiac_app/features/you/domain/models/activity_history_read_model.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/activity_history_repository.dart';
import 'package:runiac_app/features/you/domain/repositories/user_progress_repository.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';
import 'package:runiac_app/features/you/presentation/widgets/compact_run_activity_card.dart';
import 'package:runiac_app/features/you/presentation/widgets/monthly_distance_graph.dart';
import 'package:runiac_app/features/you/presentation/widgets/you_progress_surface.dart';
import 'package:runiac_app/features/you/presentation/you_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/premium_user_account_repository.dart';

final _progressToday = DateTime(2026, 6, 30);

Future<void> _openYouTab(
  WidgetTester tester, {
  ActiveRunSessionCoordinator? activeRunSessionCoordinator,
  CurrentSessionActivityHistoryStore? activityHistoryStore,
  ActivityHistoryRepository? activityHistoryRepository,
  RuniacAuthRepository? authRepository,
  bool showAuth = false,
  bool premiumAccount = false,
  UserProgressRepository userProgressRepository =
      const _TestUserProgressRepository('1 day'),
}) async {
  await tester.pumpWidget(
    RuniacApp(
      showSplash: false,
      showAuth: showAuth,
      enableForegroundGps: false,
      activeRunSessionCoordinator: activeRunSessionCoordinator,
      currentSessionActivityHistoryStore: activityHistoryStore,
      activityHistoryRepository:
          activityHistoryRepository ?? const StaticActivityHistoryRepository(),
      authRepository: authRepository ?? const NonProductionAuthRepository(),
      userProgressRepository: userProgressRepository,
      // Premium so premium-gated summary surfaces (advanced analysis,
      // coaching) stay reachable in QA flows without the paywall intercept.
      userAccountRepository: premiumAccount
          ? const PremiumUserAccountRepository()
          : const StaticUserAccountRepository(),
      youProgressToday: _progressToday,
    ),
  );
  await tester.tap(find.byTooltip('You'));
  await tester.pumpAndSettle();
}

class _AuthAwareUserProgressRepository implements UserProgressRepository {
  const _AuthAwareUserProgressRepository({
    required this.authRepository,
    required this.labelsByUid,
  });

  final RuniacAuthRepository authRepository;
  final Map<String, String> labelsByUid;

  @override
  Future<UserProgressReadModel> loadUserProgress() async {
    final uid = authRepository.currentUser?.uid ?? 'signed-out';
    return UserProgressReadModel(
      userId: uid,
      officialStreakLabel: labelsByUid[uid] ?? '',
      levelLabel: '',
      totalXpLabel: '',
      weeklyXpLabel: '',
      monthlyXpLabel: '',
      weeklyDistanceLabel: '',
      goalProgressLabel: '',
    );
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() {
    return loadUserProgress();
  }
}

class _TestUserProgressRepository implements UserProgressRepository {
  const _TestUserProgressRepository(this.officialStreakLabel);

  final String officialStreakLabel;

  @override
  Future<UserProgressReadModel> loadUserProgress() async {
    return UserProgressReadModel(
      userId: 'test-user-progress',
      officialStreakLabel: officialStreakLabel,
      levelLabel: '',
      totalXpLabel: '',
      weeklyXpLabel: '',
      monthlyXpLabel: '',
      weeklyDistanceLabel: '',
      goalProgressLabel: '',
    );
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() {
    return loadUserProgress();
  }
}

class _HoldingUserProgressRepository implements UserProgressRepository {
  final Completer<UserProgressReadModel> _completer =
      Completer<UserProgressReadModel>();

  void complete(String officialStreakLabel) {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete(
      UserProgressReadModel(
        userId: 'test-user-progress',
        officialStreakLabel: officialStreakLabel,
        levelLabel: '',
        totalXpLabel: '',
        weeklyXpLabel: '',
        monthlyXpLabel: '',
        weeklyDistanceLabel: '',
        goalProgressLabel: '',
      ),
    );
  }

  @override
  Future<UserProgressReadModel> loadUserProgress() {
    return _completer.future;
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() {
    return loadUserProgress();
  }
}

class _HoldingActivityHistoryRepository implements ActivityHistoryRepository {
  final Completer<ActivityHistoryReadModel> _completer =
      Completer<ActivityHistoryReadModel>();

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() => _completer.future;
}

class _DateReloadUserProgressRepository implements UserProgressRepository {
  final Completer<UserProgressReadModel> _reload =
      Completer<UserProgressReadModel>();
  var _loadCount = 0;

  void completeReload(String officialStreakLabel) {
    if (_reload.isCompleted) {
      return;
    }
    _reload.complete(_progress(officialStreakLabel));
  }

  @override
  Future<UserProgressReadModel> loadUserProgress() {
    _loadCount += 1;
    if (_loadCount == 1) {
      return Future.value(_progress('4 days'));
    }
    return _reload.future;
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() {
    return loadUserProgress();
  }

  UserProgressReadModel _progress(String officialStreakLabel) {
    return UserProgressReadModel(
      userId: 'test-user-progress',
      officialStreakLabel: officialStreakLabel,
      levelLabel: '',
      totalXpLabel: '',
      weeklyXpLabel: '',
      monthlyXpLabel: '',
      weeklyDistanceLabel: '',
      goalProgressLabel: '',
    );
  }
}

class _MutableUserProgressRepository implements UserProgressRepository {
  _MutableUserProgressRepository({
    required this.initialLabel,
    required this.refreshedLabel,
  }) : _currentLabel = initialLabel;

  final String initialLabel;
  final String refreshedLabel;
  String _currentLabel;
  var refreshCount = 0;

  @override
  Future<UserProgressReadModel> loadUserProgress() async {
    return _progress(_currentLabel);
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() async {
    refreshCount += 1;
    _currentLabel = refreshedLabel;
    return _progress(_currentLabel);
  }

  UserProgressReadModel _progress(String label) {
    return UserProgressReadModel(
      userId: 'test-user-progress',
      officialStreakLabel: label,
      levelLabel: '',
      totalXpLabel: '',
      weeklyXpLabel: '',
      monthlyXpLabel: '',
      weeklyDistanceLabel: '',
      goalProgressLabel: '',
    );
  }
}

class _DelayedLoadUserProgressRepository implements UserProgressRepository {
  _DelayedLoadUserProgressRepository({required this.refreshedLabel});

  final String refreshedLabel;
  final Completer<UserProgressReadModel> _loadCompleter =
      Completer<UserProgressReadModel>();
  var refreshCount = 0;

  void completeLoad(String label) {
    if (_loadCompleter.isCompleted) {
      return;
    }
    _loadCompleter.complete(_progress(label));
  }

  @override
  Future<UserProgressReadModel> loadUserProgress() {
    return _loadCompleter.future;
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() async {
    refreshCount += 1;
    return _progress(refreshedLabel);
  }

  UserProgressReadModel _progress(String label) {
    return UserProgressReadModel(
      userId: 'test-user-progress',
      officialStreakLabel: label,
      levelLabel: '',
      totalXpLabel: '',
      weeklyXpLabel: '',
      monthlyXpLabel: '',
      weeklyDistanceLabel: '',
      goalProgressLabel: '',
    );
  }
}

class _RemoteAcceptingRunRepository implements RunRepository {
  const _RemoteAcceptingRunRepository();

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    return _sessionCompletion(
      activityId: 'activity_${payload.clientRunSessionId}',
      title: 'Synced Run',
      distanceKm: '3.00',
    ).copyWith(
      clientRunSessionId: payload.clientRunSessionId,
      summaryId: 'summary_${payload.clientRunSessionId}',
      progressionEventId: 'progression_${payload.clientRunSessionId}',
    );
  }

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CompleteRunResult> loadLatestCompletionResult() {
    throw UnimplementedError();
  }

  @override
  Future<RunActivityReadModel> loadLatestRunActivity() {
    throw UnimplementedError();
  }

  @override
  Future<RunSummaryReadModel> loadLatestRunSummary() {
    throw UnimplementedError();
  }
}

class _LocalResultRunRepository implements RunRepository {
  const _LocalResultRunRepository();

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    return _sessionCompletion(
      activityId: 'local_${payload.clientRunSessionId}',
      title: 'Local Result',
      distanceKm: '3.00',
    ).copyWith(clientRunSessionId: payload.clientRunSessionId);
  }

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CompleteRunResult> loadLatestCompletionResult() {
    throw UnimplementedError();
  }

  @override
  Future<RunActivityReadModel> loadLatestRunActivity() {
    throw UnimplementedError();
  }

  @override
  Future<RunSummaryReadModel> loadLatestRunSummary() {
    throw UnimplementedError();
  }
}

class _AggregateProgressRepository implements ActivityHistoryRepository {
  const _AggregateProgressRepository();

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    final activities = [
      _activity(
        id: 'aggregate-week',
        title: 'Aggregate Week Run',
        date: '30/6/26',
        distance: 'label hidden',
        distanceMeters: 4250,
      ),
      _activity(
        id: 'aggregate-month',
        title: 'Aggregate Month Run',
        date: '2/6/26',
        distance: 'label hidden',
        distanceMeters: 3500,
      ),
      _activity(
        id: 'aggregate-year',
        title: 'Aggregate Year Run',
        date: '4/5/26',
        distance: 'label hidden',
        distanceMeters: 8100,
      ),
      _activity(
        id: 'aggregate-all',
        title: 'Aggregate All Run',
        date: '24/12/25',
        distance: 'label hidden',
        distanceMeters: 1050,
      ),
      _activity(
        id: 'aggregate-invalid',
        title: 'Aggregate Invalid Distance',
        date: '30/6/26',
        distance: 'distance pending',
        distanceMeters: 0,
      ),
    ];

    return ActivityHistoryReadModel(
      recentRuns: activities.take(3).toList(growable: false),
      months: [
        ActivityHistoryMonthReadModel(
          label: 'June 2026',
          activities: [activities[0], activities[1], activities[4]],
        ),
        ActivityHistoryMonthReadModel(
          label: 'May 2026',
          activities: [activities[2]],
        ),
        ActivityHistoryMonthReadModel(
          label: 'December 2025',
          activities: [activities[3]],
        ),
      ],
    );
  }

  ActivityHistoryItemReadModel _activity({
    required String id,
    required String title,
    required String date,
    required String distance,
    required int distanceMeters,
  }) {
    return ActivityHistoryItemReadModel(
      activityId: id,
      title: title,
      completedAtLabel: date,
      distanceLabel: distance,
      distanceMeters: distanceMeters,
      paceLabel: '7’10”',
      durationLabel: '22:56',
      timeLabel: '7:20 AM',
      routeNameLabel: 'Aggregate Test Route',
    );
  }
}

class _DelayedSecondActivityHistoryRepository
    implements ActivityHistoryRepository {
  final Completer<ActivityHistoryReadModel> _secondLoadCompleter =
      Completer<ActivityHistoryReadModel>();
  var loadCount = 0;

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() {
    loadCount += 1;
    if (loadCount == 1) {
      return Future<ActivityHistoryReadModel>.value(_activityHistory());
    }
    return _secondLoadCompleter.future;
  }

  ActivityHistoryReadModel _activityHistory() {
    final activities = [
      _activity(
        id: 'cached-week',
        title: 'Cached Week Run',
        date: '30/6/26',
        distanceMeters: 4250,
      ),
      _activity(
        id: 'cached-month',
        title: 'Cached Month Run',
        date: '2/6/26',
        distanceMeters: 3500,
      ),
      _activity(
        id: 'cached-year',
        title: 'Cached Year Run',
        date: '4/5/26',
        distanceMeters: 8100,
      ),
    ];

    return ActivityHistoryReadModel(
      recentRuns: activities.take(3).toList(growable: false),
      months: [
        ActivityHistoryMonthReadModel(
          label: 'June 2026',
          activities: [activities[0], activities[1]],
        ),
        ActivityHistoryMonthReadModel(
          label: 'May 2026',
          activities: [activities[2]],
        ),
      ],
    );
  }

  ActivityHistoryItemReadModel _activity({
    required String id,
    required String title,
    required String date,
    required int distanceMeters,
  }) {
    return ActivityHistoryItemReadModel(
      activityId: id,
      title: title,
      completedAtLabel: date,
      distanceLabel: 'label hidden',
      distanceMeters: distanceMeters,
      paceLabel: '7’10”',
      durationLabel: '22:56',
      timeLabel: '7:20 AM',
      routeNameLabel: 'Cached Test Route',
    );
  }
}

class _WeeklyBoundaryProgressRepository implements ActivityHistoryRepository {
  const _WeeklyBoundaryProgressRepository();

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    final activities = [
      _activity(
        id: 'previous-sunday',
        title: 'Previous Sunday Run',
        date: '28/6/26',
        distanceMeters: 10000,
      ),
      _activity(
        id: 'monday-boundary',
        title: 'Monday Boundary Run',
        date: '29/6/26',
        distanceMeters: 1000,
      ),
      _activity(
        id: 'tuesday-current',
        title: 'Tuesday Current Run',
        date: '30/6/26',
        distanceMeters: 2000,
      ),
      _activity(
        id: 'sunday-boundary',
        title: 'Sunday Boundary Run',
        date: '5/7/26',
        distanceMeters: 3000,
      ),
      _activity(
        id: 'next-monday',
        title: 'Next Monday Run',
        date: '6/7/26',
        distanceMeters: 20000,
      ),
    ];

    return ActivityHistoryReadModel(
      recentRuns: activities.toList(growable: false),
      months: [
        ActivityHistoryMonthReadModel(
          label: 'July 2026',
          activities: [activities[3], activities[4]],
        ),
        ActivityHistoryMonthReadModel(
          label: 'June 2026',
          activities: [activities[0], activities[1], activities[2]],
        ),
      ],
    );
  }

  ActivityHistoryItemReadModel _activity({
    required String id,
    required String title,
    required String date,
    required int distanceMeters,
  }) {
    return ActivityHistoryItemReadModel(
      activityId: id,
      title: title,
      completedAtLabel: date,
      distanceLabel: 'label hidden',
      distanceMeters: distanceMeters,
      paceLabel: '7’10”',
      durationLabel: '22:56',
      timeLabel: '7:20 AM',
      routeNameLabel: 'Weekly Boundary Route',
    );
  }
}

class _OfficialStreakBoundaryRepository implements ActivityHistoryRepository {
  const _OfficialStreakBoundaryRepository();

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    final activities = [
      _activity(
        id: 'official-boundary-today',
        title: 'Official Boundary Today',
        date: '30/6/26',
      ),
      _activity(
        id: 'official-boundary-yesterday',
        title: 'Official Boundary Yesterday',
        date: '29/6/26',
      ),
    ];

    return ActivityHistoryReadModel(
      recentRuns: activities.toList(growable: false),
      months: [
        ActivityHistoryMonthReadModel(
          label: 'June 2026',
          activities: activities,
        ),
      ],
    );
  }

  ActivityHistoryItemReadModel _activity({
    required String id,
    required String title,
    required String date,
  }) {
    return ActivityHistoryItemReadModel(
      activityId: id,
      title: title,
      completedAtLabel: date,
      distanceLabel: '3.20 km',
      distanceMeters: 3200,
      paceLabel: '7’10”',
      durationLabel: '22:56',
      timeLabel: '7:20 AM',
      routeNameLabel: 'Official Boundary Route',
    );
  }
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

Future<void> _openActivityHistoryFromYou(
  WidgetTester tester, {
  bool premiumAccount = false,
}) async {
  await _openYouTab(tester, premiumAccount: premiumAccount);
  await _tapRecentRunningSeeAll(tester);
}

Future<void> _tapRecentRunningSeeAll(WidgetTester tester) async {
  final seeAll = find.byKey(const ValueKey('recent_running_see_all'));
  await Scrollable.ensureVisible(tester.element(seeAll), alignment: 0.55);
  await tester.pumpAndSettle();
  await tester.tap(seeAll);
  await tester.pumpAndSettle();
}

CompleteRunResult _sessionCompletion({
  required String activityId,
  required String title,
  required String distanceKm,
  String dateLabel = 'Today',
  bool hasSufficientData = true,
  RunRouteSnapshot route = RunRouteSnapshot.empty,
}) {
  return CompleteRunResult(
    activityId: activityId,
    summaryId: 'summary-$activityId',
    progressionEventId: 'progression-$activityId',
    summary: RunSummarySnapshot(
      title: title,
      dateLabel: dateLabel,
      timeLabel: '8:10 AM',
      distanceKm: distanceKm,
      avgPace: '6’15”',
      duration: '18:30',
      avgHeartRate: '--',
      calories: '--',
      routeName: 'Current Session Route',
      hasSufficientData: hasSufficientData,
      route: route,
    ),
    xpUpdate: defaultXpUpdateDisplayModel,
  );
}

LocalRunCompletionPayload _syncPayload(
  String clientRunSessionId, {
  bool userConfirmedLowDataSave = false,
}) {
  return LocalRunCompletionPayload(
    clientRunSessionId: clientRunSessionId,
    startedAt: DateTime.utc(2026, 6, 30, 8),
    completedAt: DateTime.utc(2026, 6, 30, 8, 30),
    durationSeconds: 1800,
    distanceMeters: 3000,
    avgPaceSecondsPerKm: 360,
    source: 'mobile',
    routePrivacy: 'private',
    userConfirmedLowDataSave: userConfirmedLowDataSave,
  );
}

RunActivityDisplayModel _displayRun({
  required String activityId,
  required String title,
}) {
  return RunActivityDisplayModel(
    activityId: activityId,
    title: title,
    timeAgoLabel: '12 Jun 2026',
    distanceLabel: '3.20 km',
    distanceMeters: 3200,
    paceLabel: '7’10”',
    durationLabel: '22:56',
    summary: RunSummarySnapshot(
      title: title,
      dateLabel: '12 Jun 2026',
      timeLabel: '7:20 AM',
      distanceKm: '3.20',
      avgPace: '7’10”',
      duration: '22:56',
      avgHeartRate: '--',
      calories: '--',
      routeName: 'Repository Route',
    ),
  );
}

RunRouteSnapshot _sessionRouteFixture() {
  final startedAt = DateTime.utc(2026, 6, 18, 8, 10);

  return RunRouteSnapshot(
    segments: [
      [
        RunLocationSample(
          recordedAt: startedAt,
          latitude: 1.301,
          longitude: 103.801,
        ),
        RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 90)),
          latitude: 1.3018,
          longitude: 103.8021,
        ),
        RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 180)),
          latitude: 1.3025,
          longitude: 103.8016,
        ),
      ],
    ],
    lastKnownLocation: RunLocationSample(
      recordedAt: startedAt.add(const Duration(seconds: 180)),
      latitude: 1.3025,
      longitude: 103.8016,
    ),
  );
}

RunRouteSnapshot _singlePointRouteFixture() {
  final startedAt = DateTime.utc(2026, 6, 18, 8, 10);

  return RunRouteSnapshot(
    segments: [
      [
        RunLocationSample(
          recordedAt: startedAt,
          latitude: 1.301,
          longitude: 103.801,
        ),
      ],
    ],
    lastKnownLocation: RunLocationSample(
      recordedAt: startedAt,
      latitude: 1.301,
      longitude: 103.801,
    ),
  );
}

RunRouteSnapshot _noLocationRouteFixture() {
  return const RunRouteSnapshot();
}

RunRouteSnapshot _stationaryRouteFixture() {
  final startedAt = DateTime.utc(2026, 6, 18, 8, 10);

  return RunRouteSnapshot(
    segments: [
      [
        RunLocationSample(
          recordedAt: startedAt,
          latitude: 1.301,
          longitude: 103.801,
        ),
        RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 1)),
          latitude: 1.30100001,
          longitude: 103.80100001,
        ),
      ],
    ],
    lastKnownLocation: RunLocationSample(
      recordedAt: startedAt.add(const Duration(seconds: 1)),
      latitude: 1.30100001,
      longitude: 103.80100001,
    ),
  );
}

const _transparentPixelPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

class _FakeActivityRouteThumbnailProvider
    implements ActivityRouteThumbnailProvider {
  _FakeActivityRouteThumbnailProvider(this.result);

  final ActivityRouteThumbnailResult result;
  ActivityRouteThumbnailRequest? lastRequest;
  int requestCount = 0;

  @override
  Future<ActivityRouteThumbnailResult> resolve(
    ActivityRouteThumbnailRequest request,
  ) async {
    requestCount += 1;
    lastRequest = request;
    return result;
  }
}

class _CompletingActivityRouteThumbnailProvider
    implements ActivityRouteThumbnailProvider {
  _CompletingActivityRouteThumbnailProvider();

  final Completer<ActivityRouteThumbnailResult> completer =
      Completer<ActivityRouteThumbnailResult>();
  ActivityRouteThumbnailRequest? lastRequest;
  int requestCount = 0;

  @override
  Future<ActivityRouteThumbnailResult> resolve(
    ActivityRouteThumbnailRequest request,
  ) {
    requestCount += 1;
    lastRequest = request;
    return completer.future;
  }
}

void main() {
  void expectDistanceGraph(
    WidgetTester tester, {
    List<double> expectedValues = const [
      2.5,
      5,
      0,
      0,
      3.8,
      5,
      4.5,
      4.09,
      0,
      0,
      0,
      1.1,
    ],
    String axisLabelPattern = r'0 km.*2 km.*5 km',
  }) {
    final graphFinder = find.byKey(
      const ValueKey('you_monthly_distance_graph'),
    );
    expect(graphFinder, findsOneWidget);

    final graph = tester.widget<PastTwelveWeeksDistanceGraph>(graphFinder);
    expect(graph.labels, ['APR', 'MAY', 'JUN']);
    expect(graph.values, hasLength(expectedValues.length));
    for (var index = 0; index < expectedValues.length; index += 1) {
      expect(graph.values[index], closeTo(expectedValues[index], 0.001));
    }
    expect(
      find.bySemanticsLabel(
        RegExp(
          'Past 12 weeks distance graph.*APR.*MAY.*JUN.*$axisLabelPattern',
        ),
      ),
      findsOneWidget,
    );
  }

  testWidgets(
    'current-session single-point route renders snapshot with orange dot only',
    (WidgetTester tester) async {
      final provider = _FakeActivityRouteThumbnailProvider(
        ActivityRouteThumbnailResult.readyImage(
          MemoryImage(Uint8List.fromList(_transparentPixelPng)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActivityRoutePreview(
              route: _singlePointRouteFixture(),
              thumbnailProvider: provider,
              allowExternalStaticMap: true,
              isCurrentSessionRoute: true,
              activityId: 'low-data-one-point',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(provider.requestCount, 1);
      expect(provider.lastRequest!.allowExternalStaticMap, isTrue);
      expect(provider.lastRequest!.isCurrentSessionRoute, isTrue);
      expect(provider.lastRequest!.isTrustedPersistedRoutePreview, isFalse);
      expect(provider.lastRequest!.isDemoRoute, isFalse);
      expect(
        provider.lastRequest!.route.lastKnownLocation?.latitude,
        closeTo(1.301, 0.000001),
      );
      expect(
        find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'activity_route_preview_static_thumbnail_location_dot',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'activity_route_preview_static_thumbnail_route_overlay',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('activity_route_preview_polyline')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('activity_route_preview_fallback')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'current-session single-point route replaces local grid with ready image',
    (WidgetTester tester) async {
      final provider = _CompletingActivityRouteThumbnailProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActivityRoutePreview(
              route: _singlePointRouteFixture(),
              thumbnailProvider: provider,
              allowExternalStaticMap: true,
              isCurrentSessionRoute: true,
              activityId: 'low-data-one-point',
            ),
          ),
        ),
      );

      expect(provider.requestCount, 1);
      expect(
        find.byKey(const ValueKey('activity_route_preview_tiny_route')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
        findsNothing,
      );

      provider.completer.complete(
        ActivityRouteThumbnailResult.readyImage(
          MemoryImage(Uint8List.fromList(_transparentPixelPng)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'activity_route_preview_static_thumbnail_location_dot',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('activity_route_preview_tiny_route')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('activity_route_preview_fallback')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'trusted persisted single-point route requests snapshot without current session',
    (WidgetTester tester) async {
      // Given: a backend-masked persisted preview containing one trusted point.
      final provider = _FakeActivityRouteThumbnailProvider(
        ActivityRouteThumbnailResult.readyImage(
          MemoryImage(Uint8List.fromList(_transparentPixelPng)),
        ),
      );

      // When: the preview renders without a live completion session.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActivityRoutePreview(
              route: _singlePointRouteFixture(),
              thumbnailProvider: provider,
              allowExternalStaticMap: true,
              isTrustedPersistedRoutePreview: true,
              activityId: 'trusted-persisted-one-point',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Then: the trusted preview reaches the provider and retains its actual
      // provenance instead of impersonating a current-session route.
      expect(provider.requestCount, 1);
      expect(provider.lastRequest!.isCurrentSessionRoute, isFalse);
      expect(provider.lastRequest!.isTrustedPersistedRoutePreview, isTrue);
      expect(
        find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'current-session no-location route keeps fallback without provider request',
    (WidgetTester tester) async {
      final provider = _FakeActivityRouteThumbnailProvider(
        ActivityRouteThumbnailResult.readyImage(
          MemoryImage(Uint8List.fromList(_transparentPixelPng)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActivityRoutePreview(
              route: _noLocationRouteFixture(),
              thumbnailProvider: provider,
              allowExternalStaticMap: true,
              isCurrentSessionRoute: true,
              activityId: 'low-data-no-location',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(provider.requestCount, 0);
      expect(
        find.byKey(const ValueKey('activity_route_preview_fallback')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey(
            'activity_route_preview_static_thumbnail_location_dot',
          ),
        ),
        findsNothing,
      );
    },
  );

  test(
    'pace chart display anchors sufficient graph endpoints to final slot',
    () {
      for (final graph in [
        normalEasyRunPaceGraph,
        gpsSpikeRunPaceGraph,
        recoveryJogPaceGraph,
      ]) {
        expect(graph.isAvailable, isTrue);
        expect(graph.points.length, greaterThanOrEqualTo(3));
        expect(
          paceChartDisplayProgressForPoint(
            index: 0,
            pointCount: graph.points.length,
            rawProgressFraction: graph.points.first.progressFraction,
          ),
          0,
        );
        expect(
          paceChartDisplayProgressForPoint(
            index: graph.points.length - 1,
            pointCount: graph.points.length,
            rawProgressFraction: graph.points.last.progressFraction,
          ),
          1,
        );
        expect(
          paceChartDisplayProgressForPoint(
            index: 1,
            pointCount: graph.points.length,
            rawProgressFraction: graph.points[1].progressFraction,
          ),
          graph.points[1].progressFraction,
        );
      }
    },
  );

  test('You static demo snapshots live outside presentation widgets', () {
    // Given: the You feature keeps demo/read-only data behind a data boundary.
    final dataFiles = [
      'lib/features/you/presentation/data/you_overview_demo_snapshots.dart',
      'lib/features/you/presentation/data/activity_history_demo_snapshots.dart',
      'lib/features/you/presentation/data/goal_plan_demo_snapshots.dart',
      'lib/features/you/presentation/data/weekly_workout_demo_snapshots.dart',
    ];

    // Then: each expected snapshot file exists for backend-readiness.
    for (final path in dataFiles) {
      expect(File(path).existsSync(), isTrue, reason: '$path must exist');
    }

    final presentationFiles = {
      'lib/features/you/presentation/you_tab.dart': [
        'const _progressSnapshot =',
        'const _plansSnapshot =',
        'class _YouProgressSnapshot',
        'class _YouPlansSnapshot',
      ],
      'lib/features/you/presentation/activity_history_screen.dart': [
        'const activityHistoryDisplayData =',
        'class _ActivityHistoryMonth',
      ],
      'lib/features/you/presentation/goal_plan_detail_screen.dart': [
        'const goalPlanDisplaySnapshot =',
        'const _sampleDailyPlan =',
      ],
      'lib/features/you/presentation/weekly_workout_detail_screen.dart': [
        'const weeklyWorkoutDetailSnapshot =',
        'const saturdayWeeklyWorkoutDetailSnapshot =',
      ],
    };

    // Then: large presentation widgets no longer own static/demo snapshots.
    for (final entry in presentationFiles.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final forbiddenSnippet in entry.value) {
        expect(
          source,
          isNot(contains(forbiddenSnippet)),
          reason: '${entry.key} still contains $forbiddenSnippet',
        );
      }
    }
  });

  test(
    'Activity History cadence QA fixture carries local cadence analysis',
    () {
      final qaRun = activityHistoryDisplayData
          .expand((month) => month.activities)
          .singleWhere((activity) => activity.title == 'Pace Graph QA Run');

      final cadence = const AdvancedAnalysisSnapshotBuilder()
          .fromRunSummary(qaRun.summary)
          .formCadence;
      final cadenceGraph = cadence.cadenceGraph.value!;

      expect(cadence.averageCadence.valueLabel, '173 spm');
      expect(
        cadence.cadenceGraph.availability,
        AdvancedAnalysisMetricAvailability.available,
      );
      expect(
        cadence.cadenceGraph.source,
        AdvancedAnalysisMetricSource.localGpsDerived,
      );
      expect(cadenceGraph.isAvailable, isTrue);
      expect(cadenceGraph.points.map((point) => point.cadenceSpm), [
        173,
        170,
        172,
        174,
        176,
      ]);
      expect(cadenceGraph.points.map((point) => point.elapsedSeconds), [
        0,
        120,
        240,
        360,
        480,
      ]);
      expect(cadenceGraph.lowestCadencePoint?.cadenceSpm, 170);
      expect(cadenceGraph.highestCadencePoint?.cadenceSpm, 176);
      expect(cadenceGraph.targetLabel, demoCadenceGraphTargetLabel);
      expect(cadenceGraph.targetMinCadenceSpm, demoCadenceGraphTargetMinSpm);
      expect(cadenceGraph.targetMaxCadenceSpm, demoCadenceGraphTargetMaxSpm);
      expect(cadenceGraph.targetKind, CadenceGraphTargetKind.demo);
      expect(cadence.strideConsistency.valueLabel, 'stable');
      expect(cadence.cadenceStatus.valueLabel, 'stable');
      expect(
        cadence.averageCadence.source,
        AdvancedAnalysisMetricSource.localGpsDerived,
      );
    },
  );

  test(
    'Recent Running demo route fixtures expose route previews for every capped card',
    () {
      // Given: Recent Running shows the three newest static/demo activities.
      final recentRuns = youProgressSnapshot.runs.take(3).toList();

      // Then: each capped demo card carries enough route geometry for a
      // route-specific preview instead of the generic fallback drawing.
      expect(recentRuns, hasLength(3));
      expect(recentRuns.map((activity) => activity.title), [
        'Saturday Night Run',
        'Morning Easy Run',
        'Recovery Jog',
      ]);
      for (final activity in recentRuns) {
        expect(
          activity.summary.route.hasRoute,
          isTrue,
          reason: '${activity.title} should render a route-backed preview',
        );
      }
    },
  );

  test(
    'Activity History demo route fixtures distinguish route-backed and fallback previews',
    () {
      final activities = {
        for (final activity in activityHistoryDisplayData.expand(
          (month) => month.activities,
        ))
          activity.title: activity,
      };

      for (final title in const [
        'Pace Graph QA Run',
        'Easy Morning Jog',
        'Sunset Loop',
        'Tuesday Tempo',
        'Park Walk + Run',
        'First 5K Attempt',
        'Gentle Start',
      ]) {
        expect(
          activities[title]?.summary.route.hasRoute,
          isTrue,
          reason: '$title should render a route-backed preview',
        );
      }
      expect(
        activities['Riverside Recovery']?.summary.route.hasRoute,
        isFalse,
        reason: 'Low-data activity should keep the fallback preview',
      );
    },
  );

  testWidgets('You page shows progress overview sections when selected', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester);

    expect(find.text('You'), findsWidgets);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Plans'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Weekly Distance'), findsOneWidget);
    expect(find.text('Monthly Distance'), findsNothing);
    expect(find.text('Past 12 weeks'), findsOneWidget);
    expect(find.text('1.10'), findsOneWidget);
    expectDistanceGraph(tester);
    expect(find.text('3 runs this week'), findsNothing);
    expect(find.text('82% of weekly goal'), findsNothing);
    expect(find.text('This Week'), findsNothing);
    expect(find.text('Consistency Streak'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('Running Calendar'), findsOneWidget);
    expect(find.text('June 2026'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Recent Running'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Recent Running')).dx,
      lessThan(tester.getTopLeft(find.text('See all')).dx),
    );
    expect(find.text('Saturday Night Run'), findsOneWidget);
    expect(find.text('Morning Easy Run'), findsOneWidget);
    expect(find.text('Recovery Jog'), findsOneWidget);
    final recentRunCards = find.byType(CompactRunActivityCard);
    expect(recentRunCards, findsNWidgets(3));
    expect(
      find.descendant(
        of: recentRunCards,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: recentRunCards,
        matching: find.byKey(const ValueKey('activity_route_preview_slot')),
      ),
      findsNWidgets(3),
    );
    expect(
      find.descendant(
        of: recentRunCards,
        matching: find.byKey(const ValueKey('activity_route_preview_polyline')),
      ),
      findsNWidgets(3),
    );
    expect(
      find.descendant(
        of: recentRunCards,
        matching: find.byKey(const ValueKey('activity_route_preview_fallback')),
      ),
      findsNothing,
    );
    final firstRecentCard = find.byKey(
      const ValueKey('recent_running_card_Saturday Night Run'),
    );
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: firstRecentCard,
              matching: find.byKey(const ValueKey('activity_card_content')),
            ),
          )
          .dx,
      greaterThan(
        tester
            .getRect(
              find.descendant(
                of: firstRecentCard,
                matching: find.byKey(
                  const ValueKey('activity_route_preview_slot'),
                ),
              ),
            )
            .right,
      ),
    );
    expect(
      find.descendant(of: recentRunCards, matching: find.text('DISTANCE')),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: recentRunCards, matching: find.text('AVG PACE')),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: recentRunCards, matching: find.text('TIME')),
      findsNWidgets(3),
    );
    expect(
      find.descendant(
        of: recentRunCards,
        matching: find.byType(VerticalDivider),
      ),
      findsNWidgets(6),
    );
    expect(find.text('More Activities'), findsNothing);
    expect(find.byKey(const ValueKey('more_activities_button')), findsNothing);
    expect(find.byKey(const ValueKey('more_activities_chevron')), findsNothing);
    expect(find.text('Run Level'), findsNothing);
    expect(find.text('Level 12 Runner'), findsNothing);
    expect(find.text('Keep showing up at a comfortable pace.'), findsNothing);
  });

  testWidgets('Running Calendar does not mark low-data-only run days', (
    WidgetTester tester,
  ) async {
    final historyStore = CurrentSessionActivityHistoryStore(
      now: () => DateTime(2026, 6, 30),
    );
    addTearDown(historyStore.dispose);

    await _openYouTab(tester, activityHistoryStore: historyStore);

    historyStore.registerCompletedRun(
      _sessionCompletion(
        activityId: 'low-data-calendar-only',
        title: 'Low Data Calendar Run',
        distanceKm: '0.08',
        dateLabel: '29/6/26',
        hasSufficientData: false,
      ),
    );
    historyStore.registerCompletedRun(
      _sessionCompletion(
        activityId: 'sufficient-calendar-run',
        title: 'Sufficient Calendar Run',
        distanceKm: '3.20',
        dateLabel: '28/6/26',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Running Calendar'), findsOneWidget);
    expect(_calendarDayTextColor(tester, '28'), RuniacColors.white);
    expect(_calendarDayTextColor(tester, '29'), isNot(RuniacColors.white));

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('recent_running_card_low-data-calendar-only')),
      findsOneWidget,
    );
  });

  testWidgets('You streak section does not show Pending while progress loads', (
    WidgetTester tester,
  ) async {
    final progressRepository = _HoldingUserProgressRepository();

    await _openYouTab(tester, userProgressRepository: progressRepository);

    expect(find.text('Consistency Streak'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
    expect(find.text('1 day'), findsNothing);

    progressRepository.complete('1 day');
    await tester.pumpAndSettle();

    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
  });

  testWidgets('You shows Activity History loading instead of zero graph', (
    WidgetTester tester,
  ) async {
    await _openYouTab(
      tester,
      activityHistoryRepository: _HoldingActivityHistoryRepository(),
    );

    expect(
      find.byKey(const ValueKey('you_monthly_distance_loading_placeholder')),
      findsOneWidget,
    );
    expect(find.text('Loading your activities'), findsOneWidget);
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('You keeps last official streak while date reload is pending', (
    WidgetTester tester,
  ) async {
    final progressRepository = _DateReloadUserProgressRepository();
    final activityHistoryStore = CurrentSessionActivityHistoryStore();
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    addTearDown(activityHistoryStore.dispose);
    addTearDown(generatedPlanStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CurrentSessionActivityHistoryScope(
          store: activityHistoryStore,
          child: CurrentSessionGeneratedPlanScope(
            store: generatedPlanStore,
            child: YouTab(
              activityHistoryRepository:
                  const StaticActivityHistoryRepository(),
              userProgressRepository: progressRepository,
              authRepository: const NonProductionAuthRepository(),
              enableForegroundGps: false,
              progressToday: DateTime(2026, 6, 30),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('Complete a run to start your streak.'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: CurrentSessionActivityHistoryScope(
          store: activityHistoryStore,
          child: CurrentSessionGeneratedPlanScope(
            store: generatedPlanStore,
            child: YouTab(
              activityHistoryRepository:
                  const StaticActivityHistoryRepository(),
              userProgressRepository: progressRepository,
              authRepository: const NonProductionAuthRepository(),
              enableForegroundGps: false,
              progressToday: DateTime(2026, 7),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('Complete a run to start your streak.'), findsNothing);

    progressRepository.completeReload('5 days');
    await tester.pumpAndSettle();

    expect(find.text('5 days'), findsOneWidget);
    expect(find.text('4 days'), findsNothing);
  });

  testWidgets(
    'You official streak display uses backend label instead of derived value',
    (WidgetTester tester) async {
      // Given: activity history can only derive a 2 day consistency streak,
      // while the backend-produced official read model should display 1 day.
      await _openYouTab(
        tester,
        activityHistoryRepository: const _OfficialStreakBoundaryRepository(),
      );

      // When / Then: the official You streak surface must display the
      // backend-owned label and must not present the UI-derived value as
      // official progress.
      expect(find.text('Consistency Streak'), findsOneWidget);
      expect(
        find.text('1 day'),
        findsOneWidget,
        reason:
            'Official You streak display must use a backend-produced '
            'streak label/read model, not activityHistoryMonths/rest days.',
      );
      expect(
        find.text('2 days'),
        findsNothing,
        reason:
            'The UI-derived consistency count may only be fallback/non-official.',
      );
    },
  );

  testWidgets(
    'mounted You streak refreshes after meaningful remote sync only',
    (WidgetTester tester) async {
      final progressRepository = _MutableUserProgressRepository(
        initialLabel: '1 day',
        refreshedLabel: '2 days',
      );
      late CurrentSessionActivityHistoryStore historyStore;
      historyStore = CurrentSessionActivityHistoryStore(
        ownerUid: 'test-owner',
        persistence: MemoryLocalPendingRunActivityStore(),
        onRemoteRunSynced: progressRepository.refreshUserProgress,
      );
      addTearDown(historyStore.dispose);

      await _openYouTab(
        tester,
        activityHistoryStore: historyStore,
        userProgressRepository: progressRepository,
      );

      expect(find.text('1 day'), findsOneWidget);
      expect(find.text('2 days'), findsNothing);
      historyStore.updateOwnerUid('test-owner');

      await historyStore.saveCompletedRun(
        _sessionCompletion(
          activityId: 'local-progress-refresh',
          title: 'Progress Refresh Run',
          distanceKm: '3.00',
        ),
        payload: _syncPayload('progress-refresh-session'),
      );
      await historyStore.syncPendingRuns(const _RemoteAcceptingRunRepository());
      await tester.pumpAndSettle();

      expect(progressRepository.refreshCount, 1);
      expect(find.text('2 days'), findsOneWidget);
      expect(find.text('1 day'), findsNothing);

      await historyStore.saveCompletedRun(
        _sessionCompletion(
          activityId: 'local-low-data-no-refresh',
          title: 'Low Data Save',
          distanceKm: '0.00',
          hasSufficientData: false,
        ),
        payload: _syncPayload(
          'low-data-no-refresh-session',
          userConfirmedLowDataSave: true,
        ),
      );
      await historyStore.syncPendingRuns(const _RemoteAcceptingRunRepository());
      await tester.pumpAndSettle();

      expect(progressRepository.refreshCount, 1);
      expect(find.text('2 days'), findsOneWidget);
    },
  );

  testWidgets('mounted You ignores stale load after sync refresh', (
    WidgetTester tester,
  ) async {
    final progressRepository = _DelayedLoadUserProgressRepository(
      refreshedLabel: '2 days',
    );
    late CurrentSessionActivityHistoryStore historyStore;
    historyStore = CurrentSessionActivityHistoryStore(
      ownerUid: 'test-owner',
      persistence: MemoryLocalPendingRunActivityStore(),
      onRemoteRunSynced: progressRepository.refreshUserProgress,
    );
    addTearDown(historyStore.dispose);

    await _openYouTab(
      tester,
      activityHistoryStore: historyStore,
      userProgressRepository: progressRepository,
    );
    historyStore.updateOwnerUid('test-owner');

    await historyStore.saveCompletedRun(
      _sessionCompletion(
        activityId: 'local-race-refresh',
        title: 'Race Refresh Run',
        distanceKm: '3.00',
      ),
      payload: _syncPayload('race-refresh-session'),
    );
    await historyStore.syncPendingRuns(const _RemoteAcceptingRunRepository());
    await tester.pumpAndSettle();

    expect(find.text('2 days'), findsOneWidget);

    progressRepository.completeLoad('1 day');
    await tester.pumpAndSettle();

    expect(progressRepository.refreshCount, 1);
    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('1 day'), findsNothing);
  });

  testWidgets('mounted You reloads official streak after auth owner changes', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'owner-1');
    addTearDown(authRepository.dispose);
    final progressRepository = _AuthAwareUserProgressRepository(
      authRepository: authRepository,
      labelsByUid: const <String, String>{
        'signed-out': '1 day',
        'owner-1': '1 day',
        'owner-2': '2 days',
      },
    );

    await _openYouTab(
      tester,
      authRepository: authRepository,
      showAuth: true,
      userProgressRepository: progressRepository,
    );

    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('2 days'), findsNothing);

    authRepository.emitSignedIn(uid: 'owner-2');
    await tester.pumpAndSettle();

    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('1 day'), findsNothing);
  });

  testWidgets('mounted You streak ignores deferred local-result sync refresh', (
    WidgetTester tester,
  ) async {
    final progressRepository = _MutableUserProgressRepository(
      initialLabel: '1 day',
      refreshedLabel: '2 days',
    );
    late CurrentSessionActivityHistoryStore historyStore;
    historyStore = CurrentSessionActivityHistoryStore(
      ownerUid: 'test-owner',
      persistence: MemoryLocalPendingRunActivityStore(),
      onRemoteRunSynced: progressRepository.refreshUserProgress,
    );
    addTearDown(historyStore.dispose);

    await _openYouTab(
      tester,
      activityHistoryStore: historyStore,
      userProgressRepository: progressRepository,
    );
    historyStore.updateOwnerUid('test-owner');

    await historyStore.saveCompletedRun(
      _sessionCompletion(
        activityId: 'local-deferred-no-refresh',
        title: 'Deferred Local Result',
        distanceKm: '3.00',
      ),
      payload: _syncPayload('deferred-no-refresh-session'),
    );
    await historyStore.syncPendingRuns(const _LocalResultRunRepository());
    await tester.pumpAndSettle();

    expect(progressRepository.refreshCount, 0);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('2 days'), findsNothing);
  });

  testWidgets(
    'current-session history keeps fallback cap and dedupes by activity id',
    (WidgetTester tester) async {
      final historyStore = CurrentSessionActivityHistoryStore(
        now: () => DateTime(2026, 6, 18),
      );
      addTearDown(historyStore.dispose);

      await _openYouTab(tester, activityHistoryStore: historyStore);

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();

      expect(find.byType(CompactRunActivityCard), findsNWidgets(3));
      expect(find.text('Saturday Night Run'), findsOneWidget);
      expect(find.text('Morning Easy Run'), findsOneWidget);
      expect(find.text('Recovery Jog'), findsOneWidget);

      historyStore.registerCompletedRun(
        _sessionCompletion(
          activityId: 'session-duplicate',
          title: 'Session First Run',
          distanceKm: '2.40',
        ),
      );
      historyStore.registerCompletedRun(
        _sessionCompletion(
          activityId: 'session-second',
          title: 'Session Second Run',
          distanceKm: '3.10',
          route: _sessionRouteFixture(),
        ),
      );
      historyStore.registerCompletedRun(
        _sessionCompletion(
          activityId: 'session-duplicate',
          title: 'Session Replacement Run',
          distanceKm: '4.20',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CompactRunActivityCard), findsNWidgets(3));
      expect(find.text('Session Replacement Run'), findsOneWidget);
      expect(find.text('Session Second Run'), findsOneWidget);
      expect(find.text('Saturday Night Run'), findsOneWidget);
      expect(find.text('Session First Run'), findsNothing);
      expect(find.text('Morning Easy Run'), findsNothing);
      expect(find.text('Recovery Jog'), findsNothing);

      final replacementCard = find.byKey(
        const ValueKey('recent_running_card_session-duplicate'),
      );
      final secondCard = find.byKey(
        const ValueKey('recent_running_card_session-second'),
      );
      final retainedStaticCard = find.byKey(
        const ValueKey('recent_running_card_Saturday Night Run'),
      );
      expect(replacementCard, findsOneWidget);
      expect(secondCard, findsOneWidget);
      expect(retainedStaticCard, findsOneWidget);
      expect(
        find.descendant(
          of: secondCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: retainedStaticCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(replacementCard).dy,
        lessThan(tester.getTopLeft(secondCard).dy),
      );
      expect(
        tester.getTopLeft(secondCard).dy,
        lessThan(tester.getTopLeft(retainedStaticCard).dy),
      );

      await _tapRecentRunningSeeAll(tester);

      expect(find.text('Current Session'), findsNothing);
      expect(find.text('June 2026'), findsOneWidget);
      final replacementHistoryCard = find.byKey(
        const ValueKey('activity_history_card_session-duplicate'),
      );
      final retainedHistoryCard = find.byKey(
        const ValueKey('activity_history_card_Pace Graph QA Run'),
      );
      expect(replacementHistoryCard, findsOneWidget);
      expect(retainedHistoryCard, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('activity_history_card_session-second'),
          ),
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: retainedHistoryCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(replacementHistoryCard).dy,
        lessThan(tester.getTopLeft(retainedHistoryCard).dy),
      );

      await tester.tap(replacementHistoryCard);
      await tester.pumpAndSettle();

      expect(find.text('Session Replacement Run'), findsOneWidget);
      expect(find.text('Today · 8:10 AM'), findsOneWidget);
      expect(find.text('4.20'), findsOneWidget);
    },
  );

  test('current-session recent fallback fills limit after dedupe', () {
    final historyStore = CurrentSessionActivityHistoryStore(
      now: () => DateTime(2026, 6, 18),
    );
    addTearDown(historyStore.dispose);
    historyStore.registerCompletedRun(
      _sessionCompletion(
        activityId: 'shared-activity',
        title: 'Session Replacement Run',
        distanceKm: '4.20',
      ),
    );

    final recentRuns = historyStore.recentRunsWithFallback(<
      RunActivityDisplayModel
    >[
      _displayRun(activityId: 'shared-activity', title: 'Repository Match'),
      _displayRun(activityId: 'repository-second', title: 'Repository Second'),
      _displayRun(activityId: 'repository-third', title: 'Repository Third'),
    ]);

    expect(recentRuns.map((run) => run.activityId), <String?>[
      'shared-activity',
      'repository-second',
      'repository-third',
    ]);
    expect(recentRuns.map((run) => run.title), <String>[
      'Session Replacement Run',
      'Repository Second',
      'Repository Third',
    ]);
  });

  testWidgets(
    'low-data current-session route previews distinguish route movement',
    (WidgetTester tester) async {
      final historyStore = CurrentSessionActivityHistoryStore(
        now: () => DateTime(2026, 6, 18),
      );
      addTearDown(historyStore.dispose);

      await _openYouTab(tester, activityHistoryStore: historyStore);

      historyStore.registerCompletedRun(
        _sessionCompletion(
          activityId: 'low-data-route',
          title: 'Low Data Route Run',
          distanceKm: '0.08',
          hasSufficientData: false,
          route: _sessionRouteFixture(),
        ),
      );
      historyStore.registerCompletedRun(
        _sessionCompletion(
          activityId: 'low-data-stationary',
          title: 'Low Data Stationary Run',
          distanceKm: '0.00',
          hasSufficientData: false,
          route: _stationaryRouteFixture(),
        ),
      );
      historyStore.registerCompletedRun(
        _sessionCompletion(
          activityId: 'low-data-no-location',
          title: 'Low Data No Location Run',
          distanceKm: '0.03',
          hasSufficientData: false,
          route: _noLocationRouteFixture(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();

      final routeBackedRecentCard = find.byKey(
        const ValueKey('recent_running_card_low-data-route'),
      );
      final stationaryRecentCard = find.byKey(
        const ValueKey('recent_running_card_low-data-stationary'),
      );
      final fallbackRecentCard = find.byKey(
        const ValueKey('recent_running_card_low-data-no-location'),
      );
      expect(routeBackedRecentCard, findsOneWidget);
      expect(stationaryRecentCard, findsOneWidget);
      expect(fallbackRecentCard, findsOneWidget);
      expect(
        find.descendant(
          of: routeBackedRecentCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: routeBackedRecentCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_fallback'),
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: stationaryRecentCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_tiny_route'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stationaryRecentCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: stationaryRecentCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_fallback'),
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: fallbackRecentCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_fallback'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: fallbackRecentCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsNothing,
      );

      await _tapRecentRunningSeeAll(tester);

      final routeBackedHistoryCard = find.byKey(
        const ValueKey('activity_history_card_low-data-route'),
      );
      final stationaryHistoryCard = find.byKey(
        const ValueKey('activity_history_card_low-data-stationary'),
      );
      final fallbackHistoryCard = find.byKey(
        const ValueKey('activity_history_card_low-data-no-location'),
      );
      expect(routeBackedHistoryCard, findsOneWidget);
      expect(stationaryHistoryCard, findsOneWidget);
      expect(fallbackHistoryCard, findsOneWidget);
      expect(
        find.descendant(
          of: routeBackedHistoryCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stationaryHistoryCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_tiny_route'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stationaryHistoryCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: fallbackHistoryCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_fallback'),
          ),
        ),
        findsOneWidget,
      );

      await Scrollable.ensureVisible(
        tester.element(routeBackedHistoryCard),
        alignment: 0.3,
      );
      await tester.pumpAndSettle();
      await tester.tap(routeBackedHistoryCard);
      await tester.pumpAndSettle();

      expect(find.text('Low Data Route Run'), findsOneWidget);
      expect(find.text('More run data needed'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Go to Home'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'View XP Update'), findsNothing);
    },
  );

  testWidgets(
    'You page shows Runiac-styled weekly distance graph in progress overview',
    (WidgetTester tester) async {
      await _openYouTab(tester);

      expect(find.text('Weekly Distance'), findsOneWidget);
      expect(find.text('Monthly Distance'), findsNothing);
      expect(find.text('Past 12 weeks'), findsOneWidget);
      expect(find.text('1.10'), findsOneWidget);
      expect(find.text('km'), findsWidgets);
      expectDistanceGraph(tester);
      expect(find.text('This Week'), findsNothing);
      expect(find.text('3 runs this week'), findsNothing);
      expect(find.text('82% of weekly goal'), findsNothing);
    },
  );

  testWidgets('weekly distance graph exposes floored half-max axis labels', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PastTwelveWeeksDistanceGraph(
            labels: ['APR', 'MAY', 'JUN'],
            values: [0, 8, 15, 25, 30, 45, 50, 62, 70, 81, 92, 100],
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(
        RegExp(
          r'Past 12 weeks distance graph.*APR.*MAY.*JUN.*0 km.*50 km.*100 km',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'\bmiddle\b|\bmax\b', caseSensitive: false),
      ),
      findsNothing,
    );
  });

  testWidgets('weekly distance graph floors odd half-max labels with km', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PastTwelveWeeksDistanceGraph(
            labels: ['APR', 'MAY', 'JUN'],
            values: [0, 3, 5, 6, 7, 9, 11, 12, 13, 14, 15, 0],
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(
        RegExp(
          r'Past 12 weeks distance graph.*APR.*MAY.*JUN.*0 km.*7 km.*15 km',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('weekly distance graph aligns y-axis labels by km right edge', (
    WidgetTester tester,
  ) async {
    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
    const rightEdge = 50.0;
    const top = 0.0;
    const maxWidth = 56.0;

    double labelRightEdge(String value) {
      final offset = axisLabelOffsetFor(
        value: value,
        style: style,
        rightEdge: rightEdge,
        top: top,
        maxWidth: maxWidth,
      );
      final painter = TextPainter(
        text: const TextSpan(style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );
      painter.text = TextSpan(text: value, style: style);
      painter.layout(maxWidth: maxWidth);
      return offset.dx + painter.width;
    }

    expect(labelRightEdge('0 km'), closeTo(rightEdge, 0.001));
    expect(labelRightEdge('7 km'), closeTo(rightEdge, 0.001));
    expect(labelRightEdge('15 km'), closeTo(rightEdge, 0.001));
    expect(labelRightEdge('100 km'), closeTo(rightEdge, 0.001));
  });

  testWidgets(
    'weekly distance graph month labels sit between week boundaries',
    (WidgetTester tester) async {
      final fractions = monthLabelFractionsForGraph(
        labelCount: 3,
        pointCount: 12,
      );

      expect(fractions, hasLength(3));
      expect(fractions[0], closeTo(2.5 / 12, 0.0001));
      expect(fractions[1], closeTo(6.5 / 12, 0.0001));
      expect(fractions[2], closeTo(10.5 / 12, 0.0001));
      for (final fraction in fractions) {
        expect(fraction * 12, isNot(closeTo((fraction * 12).round(), 0.0001)));
      }
    },
  );

  test('weekly distance graph labels the current month and the two before it', () {
    // A new month pushes the oldest label off the left: August retires May.
    final julyMarkers = weeklyDistanceGraphMonthMarkers(DateTime(2026, 7, 31));
    expect(julyMarkers.labels, ['MAY', 'JUN', 'JUL']);
    final augustMarkers = weeklyDistanceGraphMonthMarkers(DateTime(2026, 8));
    expect(augustMarkers.labels, ['JUN', 'JUL', 'AUG']);

    // The label set depends on the month alone, never on the day within it.
    for (var day = 1; day <= 31; day += 1) {
      expect(
        weeklyDistanceGraphMonthMarkers(DateTime(2026, 8, day)).labels,
        ['JUN', 'JUL', 'AUG'],
        reason: 'labels for 2026-08-$day',
      );
    }

    // Year boundaries walk back into the previous year.
    expect(weeklyDistanceGraphMonthMarkers(DateTime(2026)).labels, [
      'NOV',
      'DEC',
      'JAN',
    ]);
    expect(weeklyDistanceGraphMonthMarkers(DateTime(2026, 2, 14)).labels, [
      'DEC',
      'JAN',
      'FEB',
    ]);
  });

  test('weekly distance graph axis advances one month at a time for years', () {
    // Walks four calendar years day by day — 1461 days including the 29
    // February 2024 leap day and three December-to-January rollovers — to prove
    // the axis holds still inside a month and slides exactly one slot left when
    // the month turns, never skipping, repeating or reordering a month.
    List<String>? previousLabels;
    DateTime? previousDay;

    for (var offset = 0; offset < 1461; offset += 1) {
      final today = DateTime(2024, 1, 1 + offset);
      final markers = weeklyDistanceGraphMonthMarkers(today);
      final stamp = today.toIso8601String();

      expect(markers.labels, hasLength(3), reason: 'label count for $stamp');
      expect(markers.weekIndices, [2, 6, 10], reason: 'positions for $stamp');
      expect(
        markers.labels.toSet(),
        hasLength(3),
        reason: 'no month may repeat for $stamp',
      );
      expect(
        markers.labels,
        [
          _monthAbbreviation(DateTime(today.year, today.month - 2).month),
          _monthAbbreviation(DateTime(today.year, today.month - 1).month),
          _monthAbbreviation(today.month),
        ],
        reason: 'the last three months in order for $stamp',
      );

      if (previousLabels != null) {
        if (today.month == previousDay!.month) {
          expect(
            markers.labels,
            previousLabels,
            reason: 'the axis must not change within a month, at $stamp',
          );
        } else {
          expect(
            markers.labels.sublist(0, 2),
            previousLabels.sublist(1),
            reason: 'each label steps exactly one slot left at $stamp',
          );
          expect(
            markers.labels,
            isNot(contains(previousLabels.first)),
            reason: '${previousLabels.first} must retire at $stamp',
          );
        }
      }
      previousLabels = markers.labels;
      previousDay = today;
    }

    // The walk really did cross every boundary it claims to.
    expect(previousDay, DateTime(2027, 12, 31));
  });

  test('weekly distance graph spaces its three month labels evenly', () {
    // Buckets 2, 6 and 10 put each label at the centre of its own four-week
    // block, so the gaps stay identical as the labels slide left month by month.
    for (var month = 1; month <= 12; month += 1) {
      for (final day in const [1, 7, 15, 28]) {
        final today = DateTime(2026, month, day);
        final markers = weeklyDistanceGraphMonthMarkers(today);
        expect(
          markers.weekIndices,
          [2, 6, 10],
          reason: 'week indices for ${today.toIso8601String()}',
        );
        expect(
          markers.labels,
          hasLength(3),
          reason: 'label count for ${today.toIso8601String()}',
        );
        expect(
          markers.labels.last,
          _monthAbbreviation(today.month),
          reason: 'current month is rightmost for ${today.toIso8601String()}',
        );
      }
    }
  });

  test('weekly distance graph paints three evenly spaced labels all year', () {
    // Regression guard for the August 2026 report, where the axis rendered only
    // JUN and JUL: every day of a year must paint all three labels, at equal
    // gaps and inside the chart. Chart width is the screen width minus the 16pt
    // page padding on each side and the graph's 58/12 insets: 291 for a 393pt
    // phone, 328 for a 430pt phone, plus 261 as a narrower-than-any-shipping-
    // device stress.
    const chartWidths = <double>[261, 291, 328];

    for (var offset = 0; offset < 366; offset += 1) {
      final today = DateTime(2026).add(Duration(days: offset));
      final markers = weeklyDistanceGraphMonthMarkers(today);
      final expectedCurrentMonth = _monthAbbreviation(today.month);

      for (final chartWidth in chartWidths) {
        const chartLeft = 58.0;
        final chartRight = chartLeft + chartWidth;
        final visibleLabels = visibleMonthLabelPlacementsForGraph(
          labels: markers.labels,
          labelWeekIndices: markers.weekIndices,
          pointCount: 12,
          chartLeft: chartLeft,
          chartRight: chartRight,
        );
        final context =
            '${today.toIso8601String()} at chart width $chartWidth';

        expect(
          visibleLabels.map((label) => label.label),
          markers.labels,
          reason: 'all three labels must be painted for $context',
        );
        expect(
          visibleLabels.last.label,
          expectedCurrentMonth,
          reason: 'current month must be the rightmost label for $context',
        );
        for (final label in visibleLabels) {
          expect(
            label.left,
            greaterThanOrEqualTo(chartLeft - 0.001),
            reason: '${label.label} must not overrun the left edge for $context',
          );
          expect(
            label.right,
            lessThanOrEqualTo(chartRight + 0.001),
            reason:
                '${label.label} must not overrun the right edge for $context',
          );
        }
        final firstGap = visibleLabels[1].centerX - visibleLabels[0].centerX;
        for (var index = 1; index < visibleLabels.length; index += 1) {
          expect(
            visibleLabels[index].left,
            greaterThanOrEqualTo(visibleLabels[index - 1].right + 4),
            reason: 'labels must not overlap for $context',
          );
          expect(
            visibleLabels[index].centerX - visibleLabels[index - 1].centerX,
            closeTo(firstGap, 0.001),
            reason: 'label gaps must stay equal for $context',
          );
        }
      }
    }
  });

  testWidgets(
    'You distance graph paints three even labels in the laid-out chart',
    (WidgetTester tester) async {
      // Geometry comes from the real widget rather than hard-coded numbers, so
      // a future change to the page padding or the graph insets is caught here
      // instead of silently shrinking the room the labels need.
      const screenWidths = <double>[375, 393, 430];
      final earlyMonthDays = <DateTime>[
        DateTime(2026, 8), // Saturday: the reported case.
        DateTime(2026, 6, 30), // Tuesday: current week starts in June.
        DateTime(2026, 3, 2), // Monday: current week starts on the 1st.
        DateTime(2026, 11, 7), // Sunday: last day of the first full week.
      ];

      for (final screenWidth in screenWidths) {
        for (final today in earlyMonthDays) {
          tester.view.physicalSize = Size(screenWidth * 3, 2400);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: YouProgressSurface(
                    activityHistoryMonths: const [],
                    activityHistoryLoading: false,
                    runs: const [],
                    visibleCalendarMonth: DateTime(today.year, today.month),
                    onPreviousMonth: () {},
                    onNextMonth: () {},
                    onRunSelected: (_) {},
                    onMoreActivities: () {},
                    officialStreakLabel: '0 days',
                    today: today,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final graphSize = tester.getSize(
            find.byKey(const ValueKey('you_monthly_distance_graph')),
          );
          final markers = weeklyDistanceGraphMonthMarkers(today);
          final visibleLabels = visibleMonthLabelPlacementsForGraph(
            labels: markers.labels,
            labelWeekIndices: markers.weekIndices,
            pointCount: 12,
            chartLeft: monthlyDistanceGraphLeftInset,
            chartRight: graphSize.width - monthlyDistanceGraphRightInset,
          );
          final context =
              '${today.toIso8601String()} on a ${screenWidth}pt screen';

          expect(
            visibleLabels.map((label) => label.label),
            markers.labels,
            reason: 'all three labels must be painted for $context',
          );
          expect(
            visibleLabels.last.label,
            _monthAbbreviation(today.month),
            reason: 'current month must be the rightmost label for $context',
          );
          expect(
            visibleLabels[2].centerX - visibleLabels[1].centerX,
            closeTo(visibleLabels[1].centerX - visibleLabels[0].centerX, 0.001),
            reason: 'label gaps must stay equal for $context',
          );
          expect(
            visibleLabels.last.right,
            lessThanOrEqualTo(
              graphSize.width - monthlyDistanceGraphRightInset + 0.001,
            ),
            reason: 'the last label must stay inside the chart for $context',
          );
        }
      }
    },
  );

  test('weekly distance graph paints the reported 1 August 2026 axis', () {
    // The reported screen rendered only JUN and JUL on a 393pt phone.
    final markers = weeklyDistanceGraphMonthMarkers(DateTime(2026, 8));
    expect(markers.labels, ['JUN', 'JUL', 'AUG']);
    expect(markers.weekIndices, [2, 6, 10]);

    final visibleLabels = visibleMonthLabelPlacementsForGraph(
      labels: markers.labels,
      labelWeekIndices: markers.weekIndices,
      pointCount: 12,
      chartLeft: 58,
      chartRight: 349,
    );

    expect(visibleLabels.map((label) => label.label), ['JUN', 'JUL', 'AUG']);
    expect(visibleLabels[0].centerX, closeTo(58 + 291 * 2.5 / 12, 0.001));
    expect(visibleLabels[1].centerX, closeTo(58 + 291 * 6.5 / 12, 0.001));
    expect(visibleLabels[2].centerX, closeTo(58 + 291 * 10.5 / 12, 0.001));
  });

  test(
    'weekly distance graph hides adjacent month labels instead of shifting',
    () {
      final visibleLabels = visibleMonthLabelPlacementsForGraph(
        labels: const ['APR', 'MAY', 'JUN'],
        labelWeekIndices: const [4, 5, 8],
        pointCount: 12,
        chartLeft: 58,
        chartRight: 378,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      );

      expect(visibleLabels.map((label) => label.label), ['APR', 'JUN']);
      for (var index = 1; index < visibleLabels.length; index += 1) {
        expect(
          visibleLabels[index].left,
          greaterThanOrEqualTo(visibleLabels[index - 1].right + 4),
        );
      }
      expect(visibleLabels.first.centerX, closeTo(58 + 320 * 4.5 / 12, 0.001));
      expect(visibleLabels.last.centerX, closeTo(58 + 320 * 8.5 / 12, 0.001));
    },
  );

  test(
    'weekly distance graph clamps edge month labels into the chart',
    () {
      const chartLeft = 72.0;
      const chartRight = 378.0;
      final visibleLabels = visibleMonthLabelPlacementsForGraph(
        labels: const ['APR', 'MAY', 'JUN', 'JUL'],
        labelWeekIndices: const [0, 1, 5, 11],
        pointCount: 12,
        chartLeft: chartLeft,
        chartRight: chartRight,
      );

      // Both edge buckets keep their label; only the crowded neighbour is
      // dropped, and the current month always outranks it.
      expect(visibleLabels.map((label) => label.label), ['APR', 'JUN', 'JUL']);
      expect(visibleLabels.first.left, closeTo(chartLeft, 0.001));
      expect(visibleLabels.last.right, closeTo(chartRight, 0.001));
      // The uncrowded interior label is untouched by clamping.
      final june = visibleLabels.firstWhere((label) => label.label == 'JUN');
      expect(june.centerX, closeTo(chartLeft + 306 * 5.5 / 12, 0.001));
      for (var index = 1; index < visibleLabels.length; index += 1) {
        expect(
          visibleLabels[index].left,
          greaterThanOrEqualTo(visibleLabels[index - 1].right + 4),
        );
      }
    },
  );

  testWidgets('You progress period buttons update only distance summary', (
    WidgetTester tester,
  ) async {
    await _openYouTab(
      tester,
      activityHistoryRepository: const _AggregateProgressRepository(),
    );

    void expectFixedGraphContext() {
      expect(find.text('Past 12 weeks'), findsOneWidget);
      expectDistanceGraph(
        tester,
        expectedValues: const [0, 0, 0, 8.1, 0, 0, 0, 3.5, 0, 0, 0, 4.25],
        axisLabelPattern: r'0 km.*4 km.*8.1 km',
      );
      expect(find.text('This Week'), findsNothing);
      expect(find.text('3 runs this week'), findsNothing);
      expect(find.text('82% of weekly goal'), findsNothing);
    }

    expect(find.text('Weekly Distance'), findsOneWidget);
    expect(find.text('4.25'), findsOneWidget);
    expectFixedGraphContext();

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    expect(find.text('Monthly Distance'), findsOneWidget);
    expect(find.text('7.75'), findsOneWidget);
    expect(find.text('Weekly Distance'), findsNothing);
    expectFixedGraphContext();

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();

    expect(find.text('Yearly Distance'), findsOneWidget);
    expect(find.text('15.85'), findsOneWidget);
    expect(find.text('Monthly Distance'), findsNothing);
    expectFixedGraphContext();

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('Total Distance'), findsOneWidget);
    expect(find.text('16.90'), findsOneWidget);
    expect(find.text('Yearly Distance'), findsNothing);
    expectFixedGraphContext();
  });

  testWidgets('Weekly Distance aggregates Monday through Sunday only', (
    WidgetTester tester,
  ) async {
    await _openYouTab(
      tester,
      activityHistoryRepository: const _WeeklyBoundaryProgressRepository(),
    );

    expect(find.text('Weekly Distance'), findsOneWidget);
    expect(find.text('6.00'), findsOneWidget);
    expect(find.text('10.00'), findsNothing);
    expect(find.text('20.00'), findsNothing);
  });

  testWidgets('Recent Running card opens selected summary with matching data', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    const runs = [
      (
        title: 'Saturday Night Run',
        dateTime: '4/11/26 · 9:18 PM',
        distance: '4.03',
        pace: '6’30”',
        duration: '30:15',
        route: 'East Coast Park Night Loop',
        hasSpikeFilteredGraph: false,
        expectedAxisLabels: ['0:00', '10:00', '20:00', '30:15'],
        forbiddenAxisLabels: ['13:00'],
      ),
      (
        title: 'Morning Easy Run',
        dateTime: '4/11/26 · 6:45 AM',
        distance: '3.20',
        pace: '7’05”',
        duration: '24:10',
        route: 'Neighbourhood Easy Loop',
        hasSpikeFilteredGraph: true,
        expectedAxisLabels: ['0:00', '8:00', '16:00', '24:10'],
        forbiddenAxisLabels: <String>[],
      ),
      (
        title: 'Recovery Jog',
        dateTime: '4/11/26 · 8:10 PM',
        distance: '5.17',
        pace: '7’40”',
        duration: '39:38',
        route: 'Park Connector Recovery Loop',
        hasSpikeFilteredGraph: false,
        expectedAxisLabels: ['0:00', '13:00', '26:00', '39:38'],
        forbiddenAxisLabels: <String>[],
      ),
    ];

    for (final run in runs) {
      final cardButton = find.byKey(
        ValueKey('recent_running_card_${run.title}'),
      );
      expect(cardButton, findsOneWidget);

      await Scrollable.ensureVisible(
        tester.element(cardButton),
        alignment: 0.55,
      );
      await tester.pumpAndSettle();

      await tester.tap(cardButton);
      await tester.pumpAndSettle();

      expect(find.text(run.title), findsOneWidget);
      expect(find.text(run.dateTime), findsOneWidget);
      expect(find.text(run.route), findsNothing);
      expect(find.text(run.distance), findsOneWidget);
      expect(find.text(run.pace), findsOneWidget);
      expect(find.text(run.duration), findsWidgets);
      expect(find.text('Pace Over Time'), findsOneWidget);
      for (final label in run.expectedAxisLabels) {
        expect(find.text(label), findsWidgets);
      }
      final axisLabelCenters = [
        for (var index = 0; index < run.expectedAxisLabels.length; index += 1)
          tester.getCenter(find.byKey(ValueKey('pace_x_axis_label_$index'))).dx,
      ];
      final axisGaps = [
        for (var index = 1; index < axisLabelCenters.length; index += 1)
          axisLabelCenters[index] - axisLabelCenters[index - 1],
      ];
      for (final gap in axisGaps.skip(1)) {
        expect((gap - axisGaps.first).abs(), lessThanOrEqualTo(1));
      }
      for (final label in run.forbiddenAxisLabels) {
        expect(find.text(label), findsNothing);
      }
      expect(find.text('More run data needed'), findsNothing);
      expect(
        find.text('Pace insights will appear after a longer run.'),
        findsNothing,
      );
      if (run.hasSpikeFilteredGraph) {
        expect(find.text('1:20'), findsNothing);
        expect(find.text('45:00'), findsNothing);
      }
      expect(
        find.widgetWithText(OutlinedButton, 'Share Route'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'View XP Update'), findsNothing);

      await tester.tap(find.byTooltip('Back to cool down'));
      await tester.pumpAndSettle();
      expect(find.text('Recent Running'), findsOneWidget);
    }
  });

  testWidgets('Recent Running See all opens Activity History', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester);

    final seeAll = find.byKey(const ValueKey('recent_running_see_all'));
    await Scrollable.ensureVisible(tester.element(seeAll), alignment: 0.55);
    await tester.pumpAndSettle();
    await tester.tap(seeAll);
    await tester.pumpAndSettle();

    expect(find.text('Activity History'), findsOneWidget);
    expect(find.text('All years'), findsOneWidget);
    expect(find.text('All months'), findsOneWidget);
  });

  testWidgets(
    'Recent Running See all opens Activity History with shell navigation preserved',
    (WidgetTester tester) async {
      await _openYouTab(tester);

      await _tapRecentRunningSeeAll(tester);

      expect(find.text('Activity History'), findsOneWidget);
      expect(find.text('Review your runs at your own pace.'), findsNothing);
      expect(find.text('All years'), findsOneWidget);
      expect(find.text('All months'), findsOneWidget);
      expect(find.text('Showing all activities'), findsOneWidget);

      for (final label in const ['Home', 'Feed', 'Run', 'Leaderboard', 'You']) {
        expect(find.byTooltip(label), findsOneWidget);
      }
    },
  );

  testWidgets('Activity History groups mock activities by month', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester);

    await _tapRecentRunningSeeAll(tester);

    expect(find.text('June 2026'), findsOneWidget);
    expect(find.text('May 2026'), findsOneWidget);
    expect(find.text('April 2026'), findsOneWidget);

    for (final title in const [
      'Pace Graph QA Run',
      'Easy Morning Jog',
      'Riverside Recovery',
      'Sunset Loop',
      'Tuesday Tempo',
      'Park Walk + Run',
      'First 5K Attempt',
      'Gentle Start',
    ]) {
      expect(find.text(title), findsOneWidget);
    }

    expect(find.byType(CompactRunActivityCard), findsNWidgets(8));
    expect(find.byType(VerticalDivider), findsNWidgets(16));
    expect(
      find.descendant(
        of: find.byType(CompactRunActivityCard),
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(CompactRunActivityCard),
        matching: find.byKey(const ValueKey('activity_route_preview_slot')),
      ),
      findsNWidgets(8),
    );
  });

  testWidgets(
    'Activity History route previews render polylines for route-backed demos and fallback for low-data demos',
    (WidgetTester tester) async {
      await _openActivityHistoryFromYou(tester);

      for (final title in const [
        'Pace Graph QA Run',
        'Easy Morning Jog',
        'Sunset Loop',
        'Tuesday Tempo',
        'Park Walk + Run',
        'First 5K Attempt',
        'Gentle Start',
      ]) {
        final card = find.byKey(ValueKey('activity_history_card_$title'));
        await Scrollable.ensureVisible(tester.element(card), alignment: 0.55);
        await tester.pumpAndSettle();

        expect(card, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.byKey(
              const ValueKey('activity_route_preview_polyline'),
            ),
          ),
          findsOneWidget,
          reason: '$title should render the route polyline preview',
        );
        expect(
          find.descendant(
            of: card,
            matching: find.byKey(
              const ValueKey('activity_route_preview_fallback'),
            ),
          ),
          findsNothing,
          reason: '$title should not use the fallback preview',
        );
      }

      final fallbackCard = find.byKey(
        const ValueKey('activity_history_card_Riverside Recovery'),
      );
      await Scrollable.ensureVisible(
        tester.element(fallbackCard),
        alignment: 0.55,
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: fallbackCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_fallback'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: fallbackCard,
          matching: find.byKey(
            const ValueKey('activity_route_preview_polyline'),
          ),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('Activity route preview renders injected ready image thumbnail', (
    WidgetTester tester,
  ) async {
    // Given: a provider that has already resolved a static route thumbnail.
    final provider = _FakeActivityRouteThumbnailProvider(
      ActivityRouteThumbnailResult.readyImage(
        MemoryImage(Uint8List.fromList(_transparentPixelPng)),
      ),
    );

    // When: a meaningful route preview is rendered with explicit demo/static
    // thumbnail permission.
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityRoutePreview(
          route: _sessionRouteFixture(),
          thumbnailProvider: provider,
          allowExternalStaticMap: true,
          isDemoRoute: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Then: the non-interactive image thumbnail is used as a background while
    // the exact route remains a local overlay.
    expect(
      find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('activity_route_preview_static_thumbnail_route_overlay'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(
        find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
      ),
      tester.getRect(find.byKey(const ValueKey('activity_route_preview_slot'))),
    );
    expect(provider.requestCount, 1);
    expect(provider.lastRequest!.allowExternalStaticMap, isTrue);
    expect(provider.lastRequest!.isDemoRoute, isTrue);
  });

  testWidgets('Activity route preview area uses the card tap target', (
    WidgetTester tester,
  ) async {
    // Given: an activity card with a route-backed preview.
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactRunActivityCard(
            activity: activityHistoryDisplayData.first.activities.first,
            onTap: () {
              tapCount += 1;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // When: the user taps inside the route preview slot.
    await tester.tap(find.byKey(const ValueKey('activity_route_preview_slot')));
    await tester.pumpAndSettle();

    // Then: the card onTap fires; the preview has no independent tap action.
    expect(tapCount, 1);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('activity_route_preview_slot')),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'Current-session activity card requests a guarded Mapbox thumbnail',
    (WidgetTester tester) async {
      // Given: a current-session completion card with a meaningful route.
      final provider = _FakeActivityRouteThumbnailProvider(
        const ActivityRouteThumbnailResult.unavailable(),
      );
      final completion = _sessionCompletion(
        activityId: 'current-session-mapbox-card',
        title: 'Current Session Mapbox Card',
        distanceKm: '1.20',
        route: _sessionRouteFixture(),
      );
      final activity = RunActivityDisplayModel(
        activityId: completion.activityId,
        title: completion.summary.title,
        timeAgoLabel: 'Just now',
        distanceLabel: '${completion.summary.distanceKm} km',
        distanceMeters: 1200,
        paceLabel: completion.summary.avgPace,
        durationLabel: completion.summary.duration,
        summary: completion.summary,
        completionResult: completion,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompactRunActivityCard(
              activity: activity,
              routeThumbnailProvider: provider,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Then: the card keeps the preview non-interactive while only the
      // current-session route is allowed through the provider boundary.
      expect(provider.requestCount, 1);
      expect(provider.lastRequest!.activityId, 'current-session-mapbox-card');
      expect(provider.lastRequest!.allowExternalStaticMap, isTrue);
      expect(provider.lastRequest!.isCurrentSessionRoute, isTrue);
      expect(provider.lastRequest!.isTrustedPersistedRoutePreview, isFalse);
      expect(provider.lastRequest!.isDemoRoute, isFalse);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('activity_route_preview_slot')),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Activity route preview falls back when provider has no ready image',
    (WidgetTester tester) async {
      for (final result in const [
        ActivityRouteThumbnailResult.privacyDisabled(),
        ActivityRouteThumbnailResult.tokenMissing(),
        ActivityRouteThumbnailResult.requestFailed(),
        ActivityRouteThumbnailResult.timedOut(),
        ActivityRouteThumbnailResult.unavailable(),
      ]) {
        // Given: a provider state that cannot supply a safe ready image.
        final provider = _FakeActivityRouteThumbnailProvider(result);

        // When: a meaningful route preview is rendered.
        await tester.pumpWidget(
          MaterialApp(
            home: ActivityRoutePreview(
              route: _sessionRouteFixture(),
              thumbnailProvider: provider,
              allowExternalStaticMap: true,
              isDemoRoute: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Then: the existing CustomPaint route preview remains the fallback.
        expect(
          find.byKey(const ValueKey('activity_route_preview_polyline')),
          findsOneWidget,
          reason: '${result.state} should preserve the polyline fallback',
        );
        expect(
          find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
          findsNothing,
        );
      }
    },
  );

  testWidgets('Activity route preview handles stationary and missing routes', (
    WidgetTester tester,
  ) async {
    // Given: a provider that could render an image for meaningful routes.
    final provider = _FakeActivityRouteThumbnailProvider(
      ActivityRouteThumbnailResult.readyImage(
        MemoryImage(Uint8List.fromList(_transparentPixelPng)),
      ),
    );

    // When: a stationary route is rendered.
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityRoutePreview(
          route: _stationaryRouteFixture(),
          thumbnailProvider: provider,
          allowExternalStaticMap: true,
          isDemoRoute: false,
          isCurrentSessionRoute: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Then: stationary current-session routes can use a map background with a
    // single local marker, not a fake route line.
    expect(
      find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('activity_route_preview_static_thumbnail_location_dot'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('activity_route_preview_static_thumbnail_route_overlay'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('activity_route_preview_polyline')),
      findsNothing,
    );
    expect(provider.requestCount, 1);

    // When: a missing route is rendered.
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityRoutePreview(
          route: RunRouteSnapshot.empty,
          thumbnailProvider: provider,
          allowExternalStaticMap: true,
          isDemoRoute: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Then: the no-route fallback remains available.
    expect(
      find.byKey(const ValueKey('activity_route_preview_fallback')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity_route_preview_static_thumbnail')),
      findsNothing,
    );
    expect(provider.requestCount, 1);
  });

  testWidgets('Activity History shows source labels', (
    WidgetTester tester,
  ) async {
    await _openActivityHistoryFromYou(tester);

    expect(find.text('Pace Graph QA Run'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('activity_history_card_Pace Graph QA Run'),
        ),
        matching: find.text('Runiac GPS'),
      ),
      findsOneWidget,
    );
    expect(find.text('Easy Morning Jog'), findsOneWidget);
    expect(find.text('Garmin via Health'), findsOneWidget);

    await tester.ensureVisible(find.text('Riverside Recovery'));
    await tester.pumpAndSettle();

    expect(find.text('Riverside Recovery'), findsOneWidget);
    expect(find.text('Health Connect'), findsOneWidget);
  });

  testWidgets(
    'Activity History summaries cover normal, spike-filtered, and low-data pace graph states',
    (WidgetTester tester) async {
      await _openActivityHistoryFromYou(tester);

      expect(find.byType(CompactRunActivityCard), findsNWidgets(8));

      Future<void> openHistorySummary(String title) async {
        final card = find.byKey(ValueKey('activity_history_card_$title'));
        expect(card, findsOneWidget);

        await Scrollable.ensureVisible(tester.element(card), alignment: 0.55);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await tester.pumpAndSettle();
      }

      await openHistorySummary('Pace Graph QA Run');

      expect(find.text('Pace Graph QA Run'), findsOneWidget);
      expect(find.text('Today · Manual QA'), findsOneWidget);
      expect(find.text('1.10'), findsOneWidget);
      expect(find.text('7\'16"'), findsOneWidget);
      expect(find.text('8:00'), findsWidgets);
      expect(find.text('Pace Over Time'), findsOneWidget);
      expect(find.text('7:00'), findsOneWidget);
      expect(find.text('7:30'), findsOneWidget);
      expect(find.text('8:00'), findsWidgets);
      expect(find.text('More run data needed'), findsNothing);
      expect(
        find.text('Pace insights will appear after a longer run.'),
        findsNothing,
      );
      expect(find.widgetWithText(FilledButton, 'View XP Update'), findsNothing);

      await tester.tap(find.byTooltip('Back to cool down'));
      await tester.pumpAndSettle();

      await openHistorySummary('Easy Morning Jog');

      expect(find.text('Easy Morning Jog'), findsOneWidget);
      expect(find.text('4 Jun 2026 · 6:45 AM'), findsOneWidget);
      expect(find.text('Pace Over Time'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);
      expect(find.text('30:15'), findsWidgets);
      expect(find.text('More run data needed'), findsNothing);
      expect(find.text('1:20'), findsNothing);
      expect(find.text('45:00'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'View XP Update'), findsNothing);

      await tester.tap(find.byTooltip('Back to cool down'));
      await tester.pumpAndSettle();

      await openHistorySummary('Riverside Recovery');

      expect(find.text('Riverside Recovery'), findsOneWidget);
      expect(find.text('1 Jun 2026 · 7:05 PM'), findsOneWidget);
      expect(find.text('0.06'), findsOneWidget);
      expect(find.text('--'), findsWidgets);
      expect(find.text('00:38'), findsOneWidget);
      expect(find.text('Pace Over Time'), findsOneWidget);
      expect(find.text('More run data needed'), findsWidgets);
      expect(
        find.text('Pace insights will appear after a longer run.'),
        findsWidgets,
      );
      expect(find.widgetWithText(FilledButton, 'Go to Home'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'View XP Update'), findsNothing);
    },
  );

  testWidgets(
    'Pace Graph QA run opens Advanced Analysis with local GPS pace graph',
    (WidgetTester tester) async {
      await _openActivityHistoryFromYou(tester, premiumAccount: true);

      final card = find.byKey(
        const ValueKey('activity_history_card_Pace Graph QA Run'),
      );
      expect(card, findsOneWidget);

      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(find.text('Pace Graph QA Run'), findsOneWidget);
      expect(find.text('Runiac GPS'), findsOneWidget);

      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'More Details'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'More Details'));
      await tester.pumpAndSettle();

      final advancedAnalysis = tester.widget<AdvancedAnalysisScreen>(
        find.byType(AdvancedAnalysisScreen),
      );
      final snapshot = advancedAnalysis.analysisSnapshot;
      final paceGraph = snapshot!.pace.paceGraph;
      final cadence = snapshot.formCadence;
      final elevation = snapshot.elevation;

      expect(snapshot, isNotNull);
      expect(
        paceGraph.availability,
        AdvancedAnalysisMetricAvailability.available,
      );
      expect(paceGraph.source, AdvancedAnalysisMetricSource.localGpsDerived);
      expect(paceGraph.value, isNotNull);
      expect(paceGraph.value!.isAvailable, isTrue);
      expect(paceGraph.value!.points.length, greaterThanOrEqualTo(8));
      expect(paceGraph.value!.distanceAxisLabels, ['0 km', '0.5 km', '1.1 km']);
      expect(paceGraph.value!.xAxisLabels, contains('0:00'));
      expect(
        find.byKey(const ValueKey('advanced_analysis_pace_graph_unavailable')),
        findsNothing,
      );
      expect(find.text('Pace Over Distance'), findsOneWidget);
      expect(
        snapshot.performance.scoreMode,
        AdvancedAnalysisScoreSourceMode.mobileOnly,
      );
      expect(snapshot.performance.scoreConfidenceLabel, 'Phone data');
      final hiddenBadgeCount = snapshot.performance.badges.length - 4;
      expect(hiddenBadgeCount, greaterThan(0));
      expect(find.text('Controlled HR'), findsNothing);
      expect(find.text('Easy Effort'), findsNothing);
      expect(find.text('More +$hiddenBadgeCount'), findsOneWidget);

      final moreBadges = find.text('More +$hiddenBadgeCount');
      await Scrollable.ensureVisible(
        tester.element(moreBadges),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(moreBadges);
      await tester.pump(const Duration(milliseconds: 220));

      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('Controlled HR'), findsNothing);
      expect(find.text('Easy Effort'), findsNothing);
      // Heart rate is presentation-only: Runiac records no heart-rate signal,
      // so the section always renders its guarded "not recorded" state.
      await tester.ensureVisible(find.text('Heart Rate Analysis'));
      expect(find.text('AVG HEART RATE'), findsOneWidget);
      expect(find.text('MAX HEART RATE'), findsOneWidget);
      expect(find.text('Target Zone'), findsNothing);
      expect(find.text('Time in Zone'), findsNothing);
      expect(find.text('Zone Distribution'), findsNothing);
      expect(
        find.text('Heart rate was not recorded for this run.'),
        findsOneWidget,
      );
      expect(elevation.elevationGraph.isAvailable, isTrue);
      expect(
        elevation.elevationGraph.source,
        AdvancedAnalysisMetricSource.localGpsDerived,
      );
      expect(elevation.elevationGraph.value!.points.length, 5);
      expect(elevation.totalGain.valueLabel, '+2 m');
      expect(elevation.highestPoint.valueLabel, '8 m');
      expect(elevation.lowestPoint.valueLabel, '4 m');
      expect(elevation.routeDifficulty.valueLabel, 'Mostly Flat');
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('+12'), findsNothing);
      expect(find.text('11'), findsNothing);
      expect(
        find.byKey(
          const ValueKey('advanced_analysis_elevation_graph_unavailable'),
        ),
        findsNothing,
      );

      final pacePainters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<AdvancedAnalysisPaceChartPainter>();
      final elevationPainters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<AdvancedAnalysisElevationChartPainter>();

      expect(
        pacePainters.any(
          (painter) => identical(painter.graph, paceGraph.value),
        ),
        isTrue,
      );
      final pacePainter = pacePainters.singleWhere(
        (painter) => identical(painter.graph, paceGraph.value),
      );
      expect(pacePainters.any((painter) => painter.graph == null), isFalse);
      expect(pacePainter.snapshotXAxisLabels, ['0 km', '0.5 km', '1.1 km']);
      expect(
        elevationPainters.single.graph,
        same(elevation.elevationGraph.value),
      );
      for (final elapsedLabel in const [
        '0:00',
        '2:00',
        '4:00',
        '6:00',
        '8:00',
      ]) {
        expect(pacePainter.snapshotXAxisLabels, isNot(contains(elapsedLabel)));
      }
      expect(pacePainter.snapshotXProgressFractions.first, 0);
      expect(pacePainter.snapshotXProgressFractions.last, 1);
      expect(
        pacePainter.snapshotXProgressFractions,
        isNot(
          equals(
            paceGraph.value!.points
                .map((point) => point.progressFraction)
                .toList(),
          ),
        ),
      );

      expect(cadence.averageCadence.valueLabel, '173 spm');
      expect(
        cadence.cadenceGraph.value!.points.map((point) => point.cadenceSpm),
        [173, 170, 172, 174, 176],
      );
      expect(cadence.cadenceGraph.value!.points.first.elapsedSeconds, 0);
      expect(cadence.cadenceGraph.value!.points.first.progressFraction, 0);
      expect(cadence.cadenceGraph.value!.lowestCadencePoint?.cadenceSpm, 170);
      expect(cadence.cadenceGraph.value!.highestCadencePoint?.cadenceSpm, 176);
      expect(
        cadence.cadenceGraph.value!.targetLabel,
        demoCadenceGraphTargetLabel,
      );
      expect(
        cadence.cadenceGraph.value!.targetMinCadenceSpm,
        demoCadenceGraphTargetMinSpm,
      );
      expect(
        cadence.cadenceGraph.value!.targetMaxCadenceSpm,
        demoCadenceGraphTargetMaxSpm,
      );
      expect(
        cadence.cadenceGraph.value!.targetKind,
        CadenceGraphTargetKind.demo,
      );
      expect(cadence.strideConsistency.valueLabel, 'stable');
      expect(cadence.cadenceStatus.valueLabel, 'stable');
      await tester.ensureVisible(find.text('Running Form / Cadence'));
      expect(find.text('AVERAGE CADENCE'), findsOneWidget);
      expect(find.text('LOWEST'), findsOneWidget);
      expect(find.text('HIGHEST'), findsOneWidget);
      expect(find.text('TREND'), findsOneWidget);
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
          (painter) => identical(painter.graph, cadence.cadenceGraph.value),
        ),
        isTrue,
      );
      expect(cadencePainters.any((painter) => painter.graph == null), isFalse);
    },
  );

  testWidgets('You page shows static plans overview when Plans is selected', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester);

    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();

    expect(find.text('Current Goal'), findsOneWidget);
    expect(find.text('10K Preparation'), findsOneWidget);
    expect(find.text('Week 3 of 8'), findsOneWidget);
    expect(find.text('43% completed'), findsOneWidget);
    expect(find.text('43%'), findsOneWidget);
    expect(find.text('Next Milestone'), findsOneWidget);
    expect(find.text('Complete 6 km comfortably'), findsOneWidget);
    expect(find.text('View Goal Plan'), findsOneWidget);
    expect(find.text("This Week's Plan"), findsOneWidget);
    expect(find.text("This Week's 10K Preparation Plan"), findsNothing);
    expect(find.text('Week 3 of 8 · 10K Plan'), findsNothing);
    expect(find.text('2 of 3 done'), findsOneWidget);
    expect(find.text('Planned Runs'), findsNothing);
    expect(find.text('Remaining'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'3\s+Planned Runs')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'2\s+Completed')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'1\s+Remaining')), findsNothing);
    expect(
      find.text('Take each easy run as a steady step forward.'),
      findsNothing,
    );
    expect(find.text('Running Calendar'), findsNothing);
    expect(find.text('Recent Running'), findsNothing);

    for (final text in [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
      'Rest Day',
      '15 min walk-run',
      '20 min easy run',
      'Upcoming · 7:30 AM',
    ]) {
      expect(find.text(text), findsWidgets);
    }
    expect(find.text('Rest Day'), findsNWidgets(4));
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('Upcoming · 7:30 AM'), findsOneWidget);
    expect(find.text('Scheduled · 8:00 AM'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('premium-upsell-section')));
    await tester.pumpAndSettle();

    // The Strava-style premium upsell closes the Plans surface.
    expect(find.byKey(const Key('premium-upsell-section')), findsOneWidget);
    expect(find.text('Unlock your full potential'), findsOneWidget);
    expect(
      find.text('Go deeper on every run with Runiac Premium.'),
      findsOneWidget,
    );
    expect(find.text('Advanced run analysis'), findsOneWidget);
    // The static challenge-tier teaser is always appended after the
    // admin-driven feature rows (challenge entitlement lives in
    // config/challengeAccess, outside the feature-access catalog).
    expect(
      find.byKey(const Key('premium-upsell-feature-challengeTiers')),
      findsOneWidget,
    );
    expect(find.text('Premium challenge tiers'), findsOneWidget);
  });

  testWidgets('premium upsell section is absent for premium runners', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester, premiumAccount: true);

    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('premium-upsell-section')), findsNothing);
    expect(find.text('Unlock your full potential'), findsNothing);
  });

  testWidgets('You page keeps plans controls visual only and backend safe', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester);

    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();

    // 'premium' and 'subscription' were removed from this forbidden list:
    // the Plans surface now intentionally carries the Runiac Premium upsell
    // section for Basic runners. ('locked' stays — it does not match the
    // upsell's "Unlock" headline.)
    for (final forbidden in <Pattern>[
      RegExp('locked', caseSensitive: false),
      RegExp(r'\bXP\b', caseSensitive: false),
      RegExp('rank', caseSensitive: false),
      RegExp('leaderboard', caseSensitive: false),
      RegExp('published', caseSensitive: false),
      RegExp('approved', caseSensitive: false),
      RegExp('missed', caseSensitive: false),
      RegExp('entitlement', caseSensitive: false),
      RegExp('eligible', caseSensitive: false),
      RegExp('publication', caseSensitive: false),
      RegExp('approval', caseSensitive: false),
      RegExp('admin review', caseSensitive: false),
    ]) {
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.textContaining(forbidden),
        ),
        findsNothing,
      );
    }

    await tester.tap(find.text('View Goal Plan'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('10K Goal Plan'), findsOneWidget);
    expect(find.text('10K Preparation'), findsWidgets);

    await tester.tap(find.byTooltip('Back to Plans'));
    await tester.pumpAndSettle();
    expect(find.text("This Week's Plan"), findsOneWidget);

    await Scrollable.ensureVisible(
      tester.element(find.text('15 min walk-run')),
      alignment: 0.45,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 min walk-run'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('15 min walk-run'), findsOneWidget);

    // The premium upsell opens the paywall sheet — display + navigation
    // only, still backend safe. Bounded pumps (never pumpAndSettle) while
    // the sheet is open: its feature-highlight timer would keep the tree
    // from settling.
    await tester.ensureVisible(find.byKey(const Key('premium-upsell-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('premium-upsell-section')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('paywall-title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('paywall-close-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paywall-title')), findsNothing);
    expect(find.text("This Week's Plan"), findsOneWidget);
  });

  testWidgets(
    'goal plan detail matches Plan Preview header and timeline alignment',
    (WidgetTester tester) async {
      // Given: the static Goal Plan Detail screen is open from You > Plans.
      await _openYouTab(tester);
      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Goal Plan'));
      await tester.pumpAndSettle();

      // Then: the header follows the Plan Preview fixed-header pattern.
      final backButton = find.byTooltip('Back to Plans');
      expect(backButton, findsOneWidget);
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.text('10K Goal Plan'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('10K Goal Plan')).dx,
        greaterThan(
          tester.getTopLeft(find.byIcon(Icons.chevron_left_rounded)).dx,
        ),
      );

      // Then: a long blue/orange content accent strip starts the scroll body.
      final accentStrip = find.byKey(
        const ValueKey('goal_plan_detail_header_accent_strip'),
      );
      expect(accentStrip, findsOneWidget);
      expect(tester.getSize(accentStrip).width, greaterThan(650));
      expect(
        tester.getTopLeft(accentStrip).dy,
        greaterThan(tester.getBottomLeft(backButton).dy),
      );
      expect(
        tester.getTopLeft(accentStrip).dy,
        lessThan(tester.getTopLeft(find.text('10K Preparation').first).dy),
      );

      // Then: timeline markers align with each Week label row.
      for (final week in const ['Week 1', 'Week 3', 'Week 8']) {
        final marker = find.byKey(ValueKey('goal_plan_detail_marker_$week'));
        expect(marker, findsOneWidget);

        final markerCenter = tester.getCenter(marker).dy;
        final weekCenter = tester.getCenter(find.text(week)).dy;
        expect((markerCenter - weekCenter).abs(), lessThanOrEqualTo(1.0));
      }

      // Then: progress state is visual-only on week rows.
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Current'), findsNothing);
      expect(find.text('Upcoming'), findsNothing);
      expect(find.byIcon(Icons.check), findsWidgets);
      for (final summary in const [
        '4 days · 8 km',
        '4 days · 10 km',
        '4 days · 12 km',
        '4 days · 14 km',
        '4 days · 16 km',
        '4 days · 18 km',
        '4 days · 20 km',
        '4 days · 10K',
      ]) {
        expect(find.text(summary), findsNothing);
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('goal_plan_detail_marker_Week 3')),
          matching: find.byIcon(Icons.directions_run),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('goal_plan_detail_marker_Week 4')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopRight(
              find.byKey(
                const ValueKey('goal_plan_detail_chevron_Week 3_collapsed'),
              ),
            )
            .dx,
        greaterThan(tester.getTopRight(find.text('Base Endurance').first).dx),
      );

      // Then: the current week highlight spans the whole row surface.
      final currentHighlight = find.byKey(
        const ValueKey('goal_plan_detail_current_week_highlight'),
      );
      expect(currentHighlight, findsOneWidget);
      expect(tester.getSize(currentHighlight).width, greaterThan(650));

      // Then: all weekly dropdown plans are initially collapsed.
      expect(
        find.byKey(const ValueKey('goal_plan_detail_daily_plan_Week 3')),
        findsNothing,
      );
      for (final day in const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ]) {
        expect(find.text(day), findsNothing);
      }

      // When: the current week is expanded.
      await tester.tap(
        find.byKey(const ValueKey('goal_plan_detail_week_toggle_Week 3')),
      );
      await tester.pumpAndSettle();

      // Then: the sample onboarding run/rest mapping is visible in order.
      final weekThreePlan = find.byKey(
        const ValueKey('goal_plan_detail_daily_plan_Week 3'),
      );
      expect(weekThreePlan, findsOneWidget);
      for (final day in const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ]) {
        expect(
          find.byKey(ValueKey('goal_plan_detail_day_Week 3_$day')),
          findsOneWidget,
        );
      }
      expect(find.text('Easy Run'), findsNWidgets(2));
      expect(find.text('Tempo Run'), findsOneWidget);
      expect(find.text('Long Run'), findsOneWidget);
      expect(find.text('Rest'), findsNWidgets(3));
      expect(find.text('3 km'), findsOneWidget);
      expect(find.text('25 min'), findsOneWidget);
      expect(find.text('4 km'), findsOneWidget);
      expect(find.text('5 km'), findsOneWidget);
      expect(find.text('0 min'), findsNWidgets(3));
      expect(find.text('4 days · 12 km'), findsNothing);
      expect(
        find.byKey(const ValueKey('goal_plan_detail_chevron_Week 3_expanded')),
        findsOneWidget,
      );

      // When: the same week is tapped again.
      await tester.tap(
        find.byKey(const ValueKey('goal_plan_detail_week_toggle_Week 3')),
      );
      await tester.pumpAndSettle();

      // Then: it collapses back to the static week-list state.
      expect(weekThreePlan, findsNothing);
      expect(find.text('Monday'), findsNothing);
      expect(
        find.byKey(const ValueKey('goal_plan_detail_chevron_Week 3_collapsed')),
        findsOneWidget,
      );

      // When: the detail content scrolls.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
      await tester.pumpAndSettle();

      // Then: the header remains available, while the accent strip is not sticky.
      expect(find.text('10K Goal Plan'), findsOneWidget);
      expect(backButton, findsOneWidget);
      expect(
        tester.getTopLeft(accentStrip).dy,
        lessThan(tester.getTopLeft(backButton).dy),
      );
    },
  );

  testWidgets('Upcoming weekly workout opens static workout detail only', (
    WidgetTester tester,
  ) async {
    // Given: the static Plans weekly schedule is visible.
    await _openYouTab(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();

    // When: the upcoming Thu workout row is tapped.
    await Scrollable.ensureVisible(
      tester.element(find.text('Upcoming · 7:30 AM')),
      alignment: 0.45,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming · 7:30 AM'));
    await tester.pumpAndSettle();

    // Then: the static workout instruction detail is shown.
    expect(find.text('Workout detail'), findsOneWidget);
    expect(find.text('Thursday · Easy Run'), findsOneWidget);
    expect(find.text('20 min easy run'), findsOneWidget);
    expect(find.text('A gentle 20 minutes.'), findsNothing);
    expect(
      find.text('You should be able to chat the whole way through.'),
      findsNothing,
    );
    expect(find.text('No race — just rhythm.'), findsNothing);
    expect(find.text('Suggested pace'), findsOneWidget);
    expect(find.text('Warm-up'), findsOneWidget);
    expect(find.text('Easy run'), findsOneWidget);
    expect(find.text('Cool-down'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Workout detail'), findsOneWidget);
    expect(find.byTooltip('Edit schedule'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('edit_schedule_icon_action')),
      findsOneWidget,
    );
    expect(find.text('Edit schedule'), findsNothing);
    expect(find.byTooltip('Back to Plans'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Workout detail')).dy, greaterThan(0));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('edit_schedule_icon_action')))
          .dy,
      greaterThan(0),
    );
    expect(find.text('Start This Run'), findsOneWidget);
  });

  testWidgets('Saturday weekly workout opens matching instruction preview', (
    WidgetTester tester,
  ) async {
    // Given: the static Plans weekly schedule is visible.
    await _openYouTab(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();

    // When: the Saturday easy-run row is tapped.
    await Scrollable.ensureVisible(
      tester.element(find.text('Sat')),
      alignment: 0.45,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sat'));
    await tester.pumpAndSettle();

    // Then: the same static instruction sheet opens with Saturday labeling.
    expect(find.text('Workout detail'), findsOneWidget);
    expect(find.text('Saturday · Easy Run'), findsOneWidget);
    expect(find.text('Thursday · Easy Run'), findsNothing);
    expect(find.text('20 min easy run'), findsOneWidget);
    expect(find.text('A gentle 20 minutes.'), findsNothing);
    expect(find.text('Suggested pace'), findsOneWidget);
    expect(find.text('Warm-up'), findsOneWidget);
    expect(find.text('Easy run'), findsOneWidget);
    expect(find.text('Cool-down'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Current schedule'), findsOneWidget);
    expect(find.text('Saturday'), findsOneWidget);
    expect(find.text('Sat · 7:30 AM'), findsNothing);
    expect(find.text('Saturday · 7:30 AM'), findsNothing);
  });

  testWidgets('Only available workout instruction rows show tap affordance', (
    WidgetTester tester,
  ) async {
    // Given: the static Plans weekly schedule is visible.
    await _openYouTab(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();

    // Then: Thu and Sat expose detail chevrons, while completed and rest rows do not.
    expect(
      find.byKey(const ValueKey('weekly_workout_detail_chevron')),
      findsNWidgets(2),
    );
  });

  testWidgets(
    'Weekly plan rows keep day column aligned across affordance states',
    (WidgetTester tester) async {
      // Given: the static Plans weekly schedule is visible.
      await _openYouTab(tester);
      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();

      // Then: tappable workout rows use the same day-column grid as rest/completed rows.
      final monLeft = tester.getTopLeft(find.text('Mon')).dx;
      final tueLeft = tester.getTopLeft(find.text('Tue')).dx;
      final thuLeft = tester.getTopLeft(find.text('Thu')).dx;
      final satLeft = tester.getTopLeft(find.text('Sat')).dx;

      expect(tueLeft, monLeft);
      expect(thuLeft, monLeft);
      expect(satLeft, monLeft);
    },
  );

  testWidgets('Rest and completed weekly rows do not open workout detail', (
    WidgetTester tester,
  ) async {
    // Given: the static Plans weekly schedule is visible.
    await _openYouTab(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();

    // Then: only available instruction previews expose detail chevrons.
    expect(
      find.byKey(const ValueKey('weekly_workout_detail_chevron')),
      findsNWidgets(2),
    );

    // When: a completed workout row is tapped.
    await Scrollable.ensureVisible(
      tester.element(find.text('15 min walk-run')),
      alignment: 0.45,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 min walk-run'));
    await tester.pumpAndSettle();

    // Then: no completed-workout detail flow is introduced.
    expect(find.text('Workout detail'), findsNothing);
    expect(find.text('15 min walk-run'), findsOneWidget);

    // When: a Rest Day row is tapped.
    await tester.tap(find.text('Mon'));
    await tester.pumpAndSettle();

    // Then: no Rest Day detail flow is introduced.
    expect(find.text('Workout detail'), findsNothing);
    expect(find.text('Rest Day'), findsWidgets);
  });

  testWidgets('Workout detail edit schedule uses custom time only', (
    WidgetTester tester,
  ) async {
    // Given: the static Workout detail screen is open.
    await _openYouTab(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Upcoming · 7:30 AM')),
      alignment: 0.45,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming · 7:30 AM'));
    await tester.pumpAndSettle();

    // When: the Edit schedule action is opened.
    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();

    // Then: the bottom sheet presents an actionable day/time picker without
    // suggested time chips or preview-only copy.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('edit_schedule_drag_handle')),
      findsOneWidget,
    );
    expect(find.text('Edit schedule'), findsWidgets);
    final handleBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('edit_schedule_drag_handle')))
        .dy;
    final titleTop = tester.getTopLeft(find.text('Edit schedule').last).dy;
    expect(handleBottom, lessThan(titleTop));
    expect(
      find.byKey(const ValueKey('edit_schedule_brand_accent')),
      findsOneWidget,
    );
    expect(
      find.text('Preview only — changes are not saved yet.'),
      findsNothing,
    );
    expect(find.text('Current schedule'), findsOneWidget);
    expect(find.text('Thu · 7:30 AM'), findsOneWidget);
    expect(find.text('New schedule'), findsOneWidget);
    expect(find.text('Select a day and time'), findsOneWidget);
    expect(find.text('Suggested time previews'), findsNothing);
    expect(
      find.byKey(const ValueKey('edit_schedule_suggested_preview_row')),
      findsNothing,
    );
    expect(find.text('Tonight · 6:30 PM'), findsNothing);
    expect(find.text('Tomorrow morning · 7:30 AM'), findsNothing);
    expect(find.text('Weekend morning · 8:00 AM'), findsNothing);
    expect(find.text('Advanced preview'), findsNothing);
    expect(find.text('These options are examples only.'), findsNothing);
    expect(find.text('Select day'), findsOneWidget);
    for (final text in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      expect(find.text(text), findsWidgets);
    }
    for (final text in ['07:00 AM', '08:00 AM', '06:30 PM', '07:30 PM']) {
      expect(find.text(text), findsNothing);
    }
    expect(find.text('Select time'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('edit_schedule_time_preview_grid')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('edit_schedule_time_selector')),
      findsOneWidget,
    );
    expect(find.text('Choose time'), findsOneWidget);
    expect(find.text('Use 06:45 AM'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('edit_schedule_time_selector')));
    await tester.pumpAndSettle();
    expect(find.text('Select time'), findsWidgets);
    expect(
      find.byKey(const ValueKey('edit_schedule_time_hour_picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('edit_schedule_time_minute_picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('edit_schedule_time_period_picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('edit_schedule_time_option_0645')),
      findsNothing,
    );
    await tester.timedDrag(
      find.byKey(const ValueKey('edit_schedule_time_minute_picker')),
      const Offset(0, -38),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('7:01 PM'), findsOneWidget);
    expect(find.text('Why might you move it later?'), findsNothing);
    for (final reason in [
      'Busy at original time',
      'Feeling tired',
      'Bad weather',
      'Injury / discomfort',
      'Prefer another time',
      'Other',
    ]) {
      expect(find.text(reason), findsNothing);
    }
    expect(
      find.text(
        'You’ll be able to add a reason when schedule changes are enabled.',
      ),
      findsNothing,
    );
    expect(
      find.text('Saving schedule changes will be available later.'),
      findsNothing,
    );
    final saveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save New Schedule'),
    );
    expect(saveButton.onPressed, isNull);
    expect(find.text('Close'), findsOneWidget);

    await Scrollable.ensureVisible(tester.element(find.text('Close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('Workout detail disables overscroll stretch locally', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Given: the static Workout detail screen is open on a constrained viewport.
    await _openYouTab(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Upcoming · 7:30 AM')),
      alignment: 0.45,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming · 7:30 AM'));
    await tester.pumpAndSettle();

    // Then: the detail scroll surface disables overscroll stretch locally.
    expect(
      find.byKey(const ValueKey('workout_detail_no_overscroll')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();

    // And: the preview-only sheet uses the same no-stretch boundary locally.
    expect(
      find.byKey(const ValueKey('edit_schedule_no_overscroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Workout detail keeps Suggested pace metric compact', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Given: the static Workout detail screen is open on a narrow viewport.
    await _openYouTab(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Upcoming · 7:30 AM')),
      alignment: 0.45,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming · 7:30 AM'));
    await tester.pumpAndSettle();

    final headerTitle = tester.widget<Text>(
      find.byKey(const ValueKey('workout_detail_header_title')),
    );
    final headerTitleSize = tester.getSize(
      find.byKey(const ValueKey('workout_detail_header_title')),
    );
    final suggestedPaceLabel = tester.widget<Text>(
      find.byKey(const ValueKey('suggested_pace_metric_label')),
    );

    // Then: the centered header title renders without ellipsis, and the
    // schedule action is icon-only while remaining accessible.
    expect(headerTitle.data, 'Workout detail');
    expect(headerTitle.maxLines, 2);
    expect(headerTitle.overflow, TextOverflow.visible);
    expect(headerTitle.style?.fontFamily, isNull);
    expect(headerTitle.style?.decoration, isNot(TextDecoration.underline));
    expect(headerTitleSize.width, greaterThan(92));
    expect(find.byTooltip('Edit schedule'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('edit_schedule_icon_action')),
      findsOneWidget,
    );
    expect(find.text('Edit schedule'), findsNothing);

    final dayLabel = tester.widget<Text>(find.text('Thursday · Easy Run'));
    final planTitle = tester.widget<Text>(find.text('20 min easy run'));
    expect(dayLabel.style?.fontFamily, isNull);
    expect(dayLabel.style?.decoration, isNot(TextDecoration.underline));
    expect(planTitle.style?.fontFamily, isNull);
    expect(planTitle.style?.decoration, isNot(TextDecoration.underline));

    // Then: the long metric label remains a compact single-line label.
    expect(suggestedPaceLabel.data, 'Suggested pace');
    expect(suggestedPaceLabel.maxLines, 1);
    expect(suggestedPaceLabel.softWrap, isFalse);
    expect(find.text('7:30 /km'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Workout detail start action opens run launch screen', (
    WidgetTester tester,
  ) async {
    // Given: the static Workout detail screen is open.
    await _openYouTab(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Upcoming · 7:30 AM')),
      alignment: 0.45,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming · 7:30 AM'));
    await tester.pumpAndSettle();

    // When: Start This Run is tapped.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start This Run'));
    await tester.pumpAndSettle();

    // Then: it routes only to the existing frontend run launch screen.
    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('Waiting for GPS'), findsNothing);
    expect(find.text('Start run'), findsOneWidget);
    expect(find.text('Start This Run'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    for (final forbidden in <Pattern>[
      RegExp(r'\bXP\b', caseSensitive: false),
      RegExp('streak', caseSensitive: false),
      RegExp('rank', caseSensitive: false),
      RegExp('leaderboard', caseSensitive: false),
      RegExp('completed', caseSensitive: false),
      RegExp('saved', caseSensitive: false),
    ]) {
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.textContaining(forbidden),
        ),
        findsNothing,
      );
    }
  });

  testWidgets('Workout detail run uses app-level active session coordinator', (
    WidgetTester tester,
  ) async {
    final activeRunSessionCoordinator = _testActiveRunSessionCoordinator(
      tester,
    );
    await _openYouTab(
      tester,
      activeRunSessionCoordinator: activeRunSessionCoordinator,
    );
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Upcoming · 7:30 AM')),
      alignment: 0.45,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming · 7:30 AM'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start This Run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start run'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Start run'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    expect(find.text('Start run'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'View Goal Plan opens static goal detail with bottom nav visible',
    (WidgetTester tester) async {
      // Given: the user is viewing the static Plans section in the You tab.
      await _openYouTab(tester);
      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();

      // When: the user opens the current goal plan detail.
      await tester.tap(find.text('View Goal Plan'));
      await tester.pumpAndSettle();

      // Then: the static detail snapshot is shown without leaving the app shell.
      expect(find.text('10K Goal Plan'), findsOneWidget);
      expect(find.text('10K Preparation'), findsWidgets);
      expect(find.text('Week 3 of 8'), findsOneWidget);
      expect(find.text('43% completed'), findsOneWidget);
      expect(find.text('Current Phase'), findsOneWidget);
      expect(find.text('Base Endurance'), findsWidgets);
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Feed'), findsOneWidget);
      expect(find.byTooltip('Run'), findsOneWidget);
      expect(find.byTooltip('Leaderboard'), findsOneWidget);
      expect(find.byTooltip('You'), findsOneWidget);
    },
  );

  testWidgets('Goal Plan Detail renders static timeline rows only', (
    WidgetTester tester,
  ) async {
    // Given: the static Goal Plan Detail screen is open.
    await _openYouTab(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Goal Plan'));
    await tester.pumpAndSettle();

    // Then: every accepted static week row is rendered from the snapshot.
    for (final text in [
      'Week 1',
      'Build Routine',
      'Week 2',
      'Easy Distance',
      'Week 3',
      'Base Endurance',
      'Week 4',
      '6 km Milestone',
      'Week 5',
      'Longer Effort',
      'Week 6',
      '8 km Progression',
      'Week 7',
      '10K Preparation',
      'Week 8',
      '10K Attempt',
    ]) {
      expect(find.text(text), findsWidgets);
    }
    for (final label in ['Completed', 'Current', 'Upcoming', 'Goal Week']) {
      expect(find.text(label), findsNothing);
    }
    for (final summary in const [
      '4 days · 8 km',
      '4 days · 10 km',
      '4 days · 12 km',
      '4 days · 14 km',
      '4 days · 16 km',
      '4 days · 18 km',
      '4 days · 20 km',
      '4 days · 10K',
    ]) {
      expect(find.text(summary), findsNothing);
    }
    expect(find.byIcon(Icons.check), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('goal_plan_detail_marker_Week 3')),
        matching: find.byIcon(Icons.directions_run),
      ),
      findsOneWidget,
    );
    expect(find.text('Monday'), findsNothing);

    // When: a week row is tapped.
    await tester.tap(
      find.byKey(const ValueKey('goal_plan_detail_week_toggle_Week 4')),
    );
    await tester.pumpAndSettle();

    // Then: only the static preview dropdown opens; no modal behavior appears.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('10K Goal Plan'), findsOneWidget);
    expect(find.text('6 km Milestone'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Sunday'), findsOneWidget);
    expect(find.text('Rest'), findsNWidgets(3));
    expect(find.text('0 min'), findsNWidgets(3));
    expect(find.text('4 days · 14 km'), findsNothing);
  });

  testWidgets(
    'Goal Plan Detail back returns to Plans without Home entry point',
    (WidgetTester tester) async {
      // Given: Home does not expose the Goal Plan Detail entry point.
      await tester.pumpWidget(
        const RuniacApp(showSplash: false, enableForegroundGps: false),
      );
      expect(find.text('View Goal Plan'), findsNothing);

      // And: the user opens the detail from the You tab Plans section.
      await tester.tap(find.byTooltip('You'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Goal Plan'));
      await tester.pumpAndSettle();
      expect(find.text('10K Goal Plan'), findsOneWidget);

      // When: the detail back button is tapped.
      await tester.tap(find.byTooltip('Back to Plans'));
      await tester.pumpAndSettle();

      // Then: the previous Plans screen is restored.
      expect(find.text('10K Goal Plan'), findsNothing);
      expect(find.text('View Goal Plan'), findsOneWidget);
      expect(find.text("This Week's Plan"), findsOneWidget);
    },
  );

  testWidgets('You page preserves shell navigation around adjacent tabs', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester);

    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Feed'), findsOneWidget);
    expect(find.byTooltip('Run'), findsOneWidget);
    expect(find.byTooltip('Leaderboard'), findsOneWidget);
    expect(find.byTooltip('You'), findsOneWidget);
    expect(find.text('You'), findsWidgets);
    expect(find.text('Weekly Distance'), findsOneWidget);

    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();

    expect(find.text('Your journey map is waiting'), findsOneWidget);
    expect(find.text('Weekly Distance'), findsNothing);
  });

  testWidgets('You graph keeps loaded history after returning from Home', (
    WidgetTester tester,
  ) async {
    final activityHistoryRepository = _DelayedSecondActivityHistoryRepository();

    await _openYouTab(
      tester,
      activityHistoryRepository: activityHistoryRepository,
    );

    expect(activityHistoryRepository.loadCount, 1);
    expectDistanceGraph(
      tester,
      expectedValues: const [0, 0, 0, 8.1, 0, 0, 0, 3.5, 0, 0, 0, 4.25],
      axisLabelPattern: r'0 km.*4 km.*8.1 km',
    );

    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('You'));
    await tester.pump();

    expect(activityHistoryRepository.loadCount, 1);
    expectDistanceGraph(
      tester,
      expectedValues: const [0, 0, 0, 8.1, 0, 0, 0, 3.5, 0, 0, 0, 4.25],
      axisLabelPattern: r'0 km.*4 km.*8.1 km',
    );
  });

  testWidgets('Run launch from You hides the You header once settled', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester);

    expect(find.text('You'), findsWidgets);
    expect(find.text('Weekly Distance'), findsOneWidget);

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('You').hitTestable(), findsNothing);
    expect(find.text('Weekly Distance').hitTestable(), findsNothing);
  });

  testWidgets('Run close from You reveals the You page during transition', (
    WidgetTester tester,
  ) async {
    await _openYouTab(tester);

    await tester.tap(find.byTooltip('Run'));
    await tester.pumpAndSettle();

    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('You').hitTestable(), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('run_launch_transition_cover')),
      findsNothing,
    );
    expect(find.text('You', skipOffstage: false), findsWidgets);

    await tester.pump(const Duration(milliseconds: 100));
  });
}

Color? _calendarDayTextColor(WidgetTester tester, String dayLabel) {
  final text = tester.widget<Text>(find.text(dayLabel));
  return text.style?.color;
}

String _monthAbbreviation(int month) {
  const names = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return names[month - 1];
}
