import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics/runiac_haptics_scope.dart';
import '../../core/theme/runiac_colors.dart';
import '../profile/domain/models/user_profile_read_model.dart';
import '../profile/domain/repositories/user_profile_repository.dart';
import '../profile/domain/repositories/user_profile_persistence_repository.dart';
import '../auth/domain/runiac_auth_service.dart';
import '../challenge/data/static_challenge_repository.dart';
import '../challenge/domain/repositories/challenge_repository.dart';
import '../challenge/presentation/challenge_result_presentation_controller.dart';
import '../feed/domain/models/feed_display_models.dart';
import '../feed/domain/repositories/feed_repository.dart';
import '../feed/presentation/current_session_feed.dart';
import '../feed/presentation/feed_comment_intent_controller.dart';
import '../friends/data/static_friends_repository.dart';
import '../friends/domain/repositories/friends_repository.dart';
import '../home/domain/guide/home_guide_agent.dart';
import '../home/domain/guide/home_guide_consent.dart';
import '../home/domain/guide/rule_based_home_guide_agent.dart';
import '../home/presentation/home_recenter_intent_controller.dart';
import '../home/presentation/home_tab.dart';
import '../home/presentation/stage_map/home_stage_map_model.dart';
import '../leaderboard/data/static_leaderboard_repository.dart';
import '../leaderboard/domain/repositories/leaderboard_repository.dart';
import '../leaderboard/presentation/leaderboard_tab.dart';
import '../notifications/data/method_channel_plan_notification_scheduler.dart';
import '../notifications/data/shared_preferences_notification_center_settings_repository.dart';
import '../notifications/data/shared_preferences_notification_inbox_cleanup_store.dart';
import '../notifications/data/shared_preferences_plan_notification_ledger.dart';
import '../notifications/domain/models/plan_notification_schedule.dart';
import '../notifications/domain/repositories/notification_inbox_repository.dart';
import '../notifications/domain/repositories/notification_preference_mirror.dart';
import '../notifications/domain/services/notification_inbox_legacy_cleanup.dart';
import '../notifications/domain/services/notification_preference_mirror_service.dart';
import '../notifications/domain/services/plan_notification_delivery_materializer.dart';
import '../notifications/domain/services/plan_notification_sync_service.dart';
import '../plan/domain/models/adaptive_plan_estimate_read_model.dart';
import '../plan/domain/plan_completion_seen_store.dart';
import '../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import '../plan/domain/repositories/generated_plan_persistence_repository.dart';
import '../plan/domain/models/plan_progress_read_model.dart';
import '../plan/presentation/current_session_generated_plan.dart';
import '../plan/presentation/plan_completion_celebration_scope.dart';
import '../run/domain/models/run_location_sample.dart';
import '../run/presentation/active_run_session_coordinator.dart';
import '../run/presentation/models/planned_run_context.dart';
import '../run/presentation/run_launch_screen.dart';
import '../run/presentation/run_open_intent.dart';
import '../tutorial/domain/app_tour_seen_store.dart';
import '../tutorial/domain/models/tutorial_step.dart';
import '../tutorial/presentation/app_tour_controller.dart';
import '../tutorial/presentation/app_tour_host.dart';
import '../tutorial/presentation/tutorial_anchor_registry.dart';
import '../you/data/static_activity_history_repository.dart';
import '../you/domain/models/user_progress_read_model.dart';
import '../you/domain/repositories/activity_history_repository.dart';
import '../you/domain/repositories/user_progress_repository.dart';
import '../you/presentation/adapters/generated_plan_you_display_adapter.dart';
import '../you/presentation/current_session_activity_history.dart';
import '../you/presentation/current_session_user_progress.dart';
import '../you/presentation/you_tab.dart';
import 'current_day_rollover.dart';

class RuniacShell extends StatefulWidget {
  const RuniacShell({
    required this.authRepository,
    required this.feedRepository,
    this.activityHistoryRepository = const StaticActivityHistoryRepository(),
    this.userProgressRepository = const StaticUserProgressRepository(),
    this.leaderboardRepository = const StaticLeaderboardRepository(),
    this.friendsRepository = const StaticFriendsRepository(),
    this.challengeRepository = const StaticChallengeRepository(),
    this.challengeResultPresenter,
    required this.profileRepository,
    required this.profilePersistenceRepository,
    this.generatedPlanPersistenceRepository =
        const NoopGeneratedPlanPersistenceRepository(),
    this.notificationInboxRepository =
        const StaticNotificationInboxRepository(),
    this.notificationPreferenceMirror =
        const NoopNotificationPreferenceMirror(),
    this.planProgress,
    this.planCompletionSeenStore,
    this.appTourSeenStore,
    this.appTourAutoStartArmed = false,
    this.adaptivePlanEstimate,
    this.homeGuideAgent = const RuleBasedHomeGuideAgent(),
    this.homeGuideConsentRepository =
        const AlwaysGrantedHomeGuideConsentRepository(),
    super.key,
    this.enableForegroundGps = true,
    this.activeRunSessionCoordinator,
    this.initialRunOpenIntent,
    this.youProgressToday,
    this.enableLocalPlanNotifications = false,
    this.currentDayRolloverController,
  });

  final RuniacAuthRepository authRepository;
  final FeedRepository feedRepository;
  final ActivityHistoryRepository activityHistoryRepository;
  final UserProgressRepository userProgressRepository;
  final LeaderboardRepository leaderboardRepository;
  final FriendsRepository friendsRepository;

  /// Server-owned Challenge source threaded to [HomeTab] and the Account badge
  /// case. Defaults to the static source for previews/tests.
  final ChallengeRepository challengeRepository;

  /// One-shot foreground Result presenter threaded to [HomeTab]. `null`
  /// disables auto-presentation.
  final ChallengeResultPresentationController? challengeResultPresenter;
  final UserProfileRepository profileRepository;
  final UserProfilePersistenceRepository profilePersistenceRepository;
  final GeneratedPlanPersistenceRepository generatedPlanPersistenceRepository;
  final NotificationInboxRepository notificationInboxRepository;

  /// Best-effort mirror of the derived Social-activity boolean into
  /// `notificationPreferences/{uid}`. Defaults to a no-op so previews/tests
  /// need no Firestore.
  final NotificationPreferenceMirror notificationPreferenceMirror;
  final PlanProgressReadModel? planProgress;

  /// One-shot marker forwarded to [HomeTab] for the plan-completion ceremony.
  /// `null` (previews/tests) disables the celebration.
  final PlanCompletionSeenStore? planCompletionSeenStore;

  /// Local, device-only record of whether the one-time app tour is armed and
  /// completed. `null` (previews/tests, and the default) disables the tour
  /// entirely: the overlay never builds and no store call is ever made.
  final AppTourSeenStore? appTourSeenStore;

  /// Session-only accelerator forwarded to `AppTourHost.autoStartArmed`; it
  /// can hasten an auto-start the durable [appTourSeenStore] already permits
  /// but can never gate or block one. Has no effect when [appTourSeenStore]
  /// is `null`. See `AppTourHost.autoStartArmed` for the full contract.
  final bool appTourAutoStartArmed;
  final AdaptivePlanEstimateReadModel? adaptivePlanEstimate;

  /// Guide seam forwarded to [HomeTab]'s stage-map speech bubble. See
  /// `HomeTab.homeGuideAgent` for the trust-boundary contract.
  final HomeGuideAgent homeGuideAgent;
  final HomeGuideConsentRepository homeGuideConsentRepository;
  final bool enableForegroundGps;
  final ActiveRunSessionCoordinator? activeRunSessionCoordinator;
  final RunOpenIntent? initialRunOpenIntent;
  final DateTime? youProgressToday;
  final bool enableLocalPlanNotifications;
  final CurrentDayRolloverController? currentDayRolloverController;

  @override
  State<RuniacShell> createState() => _RuniacShellState();
}

class _RuniacShellState extends State<RuniacShell> with WidgetsBindingObserver {
  static const _localNotificationSmokeTestEnabled = bool.fromEnvironment(
    'RUNIAC_LOCAL_NOTIFICATION_SMOKE_TEST',
  );
  static const _localNotificationSmokeTestDelaySeconds = int.fromEnvironment(
    'RUNIAC_LOCAL_NOTIFICATION_SMOKE_TEST_DELAY_SECONDS',
    defaultValue: 60,
  );
  static const _localNotificationDebugLogs = bool.fromEnvironment(
    'RUNIAC_LOCAL_NOTIFICATION_DEBUG_LOGS',
  );

  int _selectedIndex = 0;
  final Set<int> _visitedTabIndexes = <int>{0};
  PlanCompletionCelebrationRouter? _planCompletionCelebrationRouter;
  late final bool _ownsActiveRunSessionCoordinator =
      widget.activeRunSessionCoordinator == null;
  late final ActiveRunSessionCoordinator _activeRunSessionCoordinator =
      widget.activeRunSessionCoordinator ?? ActiveRunSessionCoordinator();
  bool _handledInitialRunOpenIntent = false;
  bool _runLaunchRouteOpen = false;
  String? _lastPlanNotificationSyncSignature;
  var _planNotificationSyncInFlight = false;
  var _pendingPlanNotificationSync = false;
  var _localNotificationSmokeTestScheduled = false;
  var _dayRolloverProgressRefreshSerial = 0;
  late final CurrentDayRolloverController _currentDayController;
  late final bool _ownsCurrentDayController =
      widget.currentDayRolloverController == null;
  late final AppTourController _appTourController = AppTourController(
    onRequestTab: _selectTab,
  );

  /// Owns the "open this post's comment sheet" request a tapped feed-
  /// engagement notification makes. Requested from [HomeTab] via
  /// [_openFeedPostComments], consumed by the Feed tab's `CurrentSessionFeed`.
  final FeedCommentIntentController _feedCommentIntent =
      FeedCommentIntentController();

  /// Owns the "take me back to the character" request the bottom bar's Home
  /// item makes. Fired from [_handleNavigationTap], consumed by the Home tab's
  /// stage map.
  final HomeRecenterIntentController _homeRecenterIntent =
      HomeRecenterIntentController();
  BeginnerAdaptivePlanSnapshot? _pendingPlanNotificationPlan;
  GeneratedPlanProgressDisplay? _pendingPlanNotificationProgress;
  late Future<FeedAuthorProfileSnapshot> _feedAuthorProfileFuture;
  String? _feedAuthorProfileOwnerUid;
  FeedAuthorProfileSnapshot? _lastFeedAuthorProfile;
  String? _notificationInboxMaintenanceOwnerUid;
  var _notificationInboxMaintenanceInFlight = false;
  late final MethodChannelPlanNotificationScheduler _planNotificationScheduler =
      MethodChannelPlanNotificationScheduler();
  late final SharedPreferencesPlanNotificationLedger _planNotificationLedger =
      SharedPreferencesPlanNotificationLedger(
        uidProvider: _notificationOwnerUid,
      );
  late final PlanNotificationSyncService _planNotificationSyncService =
      PlanNotificationSyncService(
        settingsRepository:
            const SharedPreferencesNotificationCenterSettingsRepository(),
        scheduler: _planNotificationScheduler,
        ledger: _planNotificationLedger,
        debugLog: _localNotificationDebugLogs
            ? _logLocalNotificationDebug
            : null,
      );
  late final PlanNotificationDeliveryMaterializer
  _planNotificationMaterializer = PlanNotificationDeliveryMaterializer(
    ledger: _planNotificationLedger,
    deliveryReader: _planNotificationScheduler,
    inboxRepository: widget.notificationInboxRepository,
    ownerUidProvider: _notificationOwnerUid,
    debugLog: _localNotificationDebugLogs ? _logLocalNotificationDebug : null,
  );
  late final NotificationInboxLegacyCleanup _notificationInboxLegacyCleanup =
      NotificationInboxLegacyCleanup(
        inboxRepository: widget.notificationInboxRepository,
        cleanupStore: SharedPreferencesNotificationInboxCleanupStore(
          uidProvider: _notificationOwnerUid,
        ),
        ownerUidProvider: _notificationOwnerUid,
        debugLog: _localNotificationDebugLogs
            ? _logLocalNotificationDebug
            : null,
      );
  late final NotificationPreferenceMirrorService
  _notificationPreferenceMirrorService = NotificationPreferenceMirrorService(
    settingsRepository: const SharedPreferencesNotificationCenterSettingsRepository(),
    mirror: widget.notificationPreferenceMirror,
    ownerUidProvider: _notificationOwnerUid,
  );
  String? _socialActivityMirrorOwnerUid;

  String? _notificationOwnerUid() => widget.authRepository.currentUser?.uid;

  static void _logLocalNotificationDebug(String message) {
    debugPrint('[RuniacLocalNotifications][Dart] $message');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentDayController =
        (widget.currentDayRolloverController ?? CurrentDayRolloverController())
          ..addListener(_handleCurrentDayChanged);
    _setFeedAuthorProfileFuture();
    if (widget.youProgressToday == null) {
      _currentDayController.start();
    }
    _scheduleInitialRunOpenIntent();
    _scheduleLocalNotificationSmokeTestIfEnabled();
    if (widget.enableLocalPlanNotifications) {
      _planNotificationScheduler.onDelivered = _handlePlanNotificationDelivered;
    }
    _scheduleNotificationInboxMaintenance();
    _scheduleSocialActivityMirrorSync();
  }

  void _handlePlanNotificationDelivered() {
    if (!mounted) {
      return;
    }
    unawaited(_runNotificationInboxMaintenance());
  }

  /// Sweeps the legacy backlog once, then turns any fired-but-unrecorded plan
  /// notification into an inbox item.
  ///
  /// Ordering matters: the sweep soft-deletes every client-written item, so a
  /// notification materialized first would be wiped by it on the same launch.
  void _scheduleNotificationInboxMaintenance() {
    final ownerUid = _notificationOwnerUid();
    if (ownerUid == null ||
        ownerUid.isEmpty ||
        ownerUid == _notificationInboxMaintenanceOwnerUid) {
      return;
    }
    _notificationInboxMaintenanceOwnerUid = ownerUid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_runNotificationInboxMaintenance(cleanFirst: true));
    });
  }

  /// Reconciles the Firestore Social-activity mirror once per signed-in
  /// owner, so a pre-existing install (or an offline toggle that never made
  /// it out) catches up on the next cold start rather than staying stale
  /// until the user happens to revisit Notification Center.
  void _scheduleSocialActivityMirrorSync() {
    final ownerUid = _notificationOwnerUid();
    if (ownerUid == null ||
        ownerUid.isEmpty ||
        ownerUid == _socialActivityMirrorOwnerUid) {
      return;
    }
    _socialActivityMirrorOwnerUid = ownerUid;
    unawaited(_notificationPreferenceMirrorService.syncSocialActivity());
  }

  Future<void> _runNotificationInboxMaintenance({
    bool cleanFirst = false,
  }) async {
    if (_notificationInboxMaintenanceInFlight) {
      return;
    }
    _notificationInboxMaintenanceInFlight = true;
    try {
      if (cleanFirst) {
        await _notificationInboxLegacyCleanup.runOnce();
      }
      await _planNotificationMaterializer.materializeDeliveries();
    } catch (_) {
      // Inbox maintenance must not block the primary app shell.
    } finally {
      _notificationInboxMaintenanceInFlight = false;
    }
  }

  @override
  void didUpdateWidget(covariant RuniacShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRunOpenIntent != widget.initialRunOpenIntent) {
      _handledInitialRunOpenIntent = false;
      _scheduleInitialRunOpenIntent();
    }
    if (oldWidget.profileRepository != widget.profileRepository ||
        oldWidget.userProgressRepository != widget.userProgressRepository ||
        widget.authRepository.currentUser?.uid != _feedAuthorProfileOwnerUid) {
      _setFeedAuthorProfileFuture();
    }
  }

  void _setFeedAuthorProfileFuture() {
    final ownerUid = widget.authRepository.currentUser?.uid;
    if (ownerUid != _feedAuthorProfileOwnerUid) {
      _lastFeedAuthorProfile = null;
    }
    _feedAuthorProfileOwnerUid = ownerUid;
    _feedAuthorProfileFuture = _loadFeedAuthorProfile(ownerUid);
  }

  Future<FeedAuthorProfileSnapshot> _loadFeedAuthorProfile(
    String? ownerUid,
  ) async {
    try {
      final scopedUserProgressStore = CurrentSessionUserProgressScope.maybeRead(
        context,
      );
      final userProgressStore =
          scopedUserProgressStore?.snapshot.ownerUid == null
          ? null
          : scopedUserProgressStore;
      final (profile, progress) = await (
        widget.profileRepository.loadUserProfile(),
        userProgressStore == null
            ? widget.userProgressRepository.loadUserProgress()
            : _loadFeedAuthorProgress(userProgressStore),
      ).wait;
      final snapshot = _feedAuthorProfileFrom(
        ownerUid: ownerUid,
        profile: profile,
        progress: progress,
      );
      if (_feedAuthorProfileOwnerUid == ownerUid) {
        _lastFeedAuthorProfile = snapshot;
      }
      return snapshot;
    } catch (_) {
      return _lastFeedAuthorProfile ??
          FeedAuthorProfileSnapshot.fallback(userId: ownerUid ?? '');
    }
  }

  Future<UserProgressReadModel> _loadFeedAuthorProgress(
    CurrentSessionUserProgress userProgressStore,
  ) async {
    await WidgetsBinding.instance.endOfFrame;
    await userProgressStore.load();
    return userProgressStore.snapshot.progress ??
        await widget.userProgressRepository.loadUserProgress();
  }

  void _scheduleFeedAuthorProfileStoreSync(FeedAuthorProfileSnapshot profile) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      CurrentSessionFeedScope.maybeRead(context)?.updateAuthorProfile(profile);
    });
  }

  void _scheduleInitialRunOpenIntent() {
    if (widget.initialRunOpenIntent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialRunIntent();
      });
    }
  }

  void _scheduleLocalNotificationSmokeTestIfEnabled() {
    if (!widget.enableLocalPlanNotifications ||
        !_localNotificationSmokeTestEnabled ||
        _localNotificationSmokeTestScheduled) {
      return;
    }
    _localNotificationSmokeTestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _planNotificationSyncService.scheduleSmokeTestNotification(
          now: widget.youProgressToday ?? DateTime.now(),
          delay: Duration(seconds: _localNotificationSmokeTestDelaySeconds),
        );
      } catch (error, stackTrace) {
        // QA smoke notification must not block the app shell.
        if (_localNotificationDebugLogs) {
          debugPrint(
            '[RuniacLocalNotifications][Dart] '
            'scheduleSmokeTestNotification failed: $error',
          );
          debugPrint(stackTrace.toString());
        }
      }
    });
  }

  /// Selects the Home dashboard on behalf of the run flow's "Home" action, so a
  /// plan finished on this run is celebrated where the ceremony lives.
  void _showHomeDashboard() => _selectTab(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = PlanCompletionCelebrationScope.maybeOf(context);
    if (identical(router, _planCompletionCelebrationRouter)) {
      return;
    }
    _planCompletionCelebrationRouter?.detachHomeDashboard(_showHomeDashboard);
    _planCompletionCelebrationRouter = router;
    router?.attachHomeDashboard(_showHomeDashboard);
  }

  @override
  void dispose() {
    _planCompletionCelebrationRouter?.detachHomeDashboard(_showHomeDashboard);
    WidgetsBinding.instance.removeObserver(this);
    _planNotificationScheduler.onDelivered = null;
    _currentDayController.removeListener(_handleCurrentDayChanged);
    if (_ownsCurrentDayController) {
      _currentDayController.dispose();
    }
    if (_ownsActiveRunSessionCoordinator) {
      _activeRunSessionCoordinator.dispose();
    }
    _appTourController.dispose();
    _feedCommentIntent.dispose();
    _homeRecenterIntent.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _currentDayController.refresh();
      _openActiveRunFromSystemReturn();
      // Anything that fired while the app was away is only discoverable now.
      unawaited(_runNotificationInboxMaintenance());
    }
  }

  void _handleCurrentDayChanged() {
    _refreshUserProgressAfterDayRollover();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshUserProgressAfterDayRollover() async {
    final serial = _dayRolloverProgressRefreshSerial + 1;
    _dayRolloverProgressRefreshSerial = serial;
    try {
      final scopedUserProgressStore = CurrentSessionUserProgressScope.maybeRead(
        context,
      );
      final userProgressStore =
          scopedUserProgressStore?.snapshot.ownerUid == null
          ? null
          : scopedUserProgressStore;
      final progress =
          await userProgressStore?.refresh() ??
          await widget.userProgressRepository.refreshUserProgress();
      if (!mounted || serial != _dayRolloverProgressRefreshSerial) {
        return;
      }
      CurrentSessionActivityHistoryScope.maybeRead(
        context,
      )?.recordUserProgressRefresh(progress);
      _setFeedAuthorProfileFuture();
      setState(() {});
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac shell',
          context: ErrorDescription(
            'refreshing user progress after local day rollover',
          ),
        ),
      );
    }
  }

  Future<void> _handleNavigationTap(int index) async {
    // Same weight as the Home stage-map menu trigger: a selection tick.
    RuniacHapticsScope.maybeOf(context)?.selection();

    if (index == 2) {
      final initialPreviewCurrentPosition =
          await prewarmRunLaunchPreviewCurrentPosition(
            enableForegroundGps: widget.enableForegroundGps,
          );
      if (!mounted) {
        return;
      }
      _pushRunLaunchRoute(
        initialPreviewCurrentPosition: initialPreviewCurrentPosition,
        plannedWorkout: _todayPlannedRunContext(),
      );
      return;
    }

    _selectTab(index);

    // Home is the runner's map, so its bar item means "take me to my
    // character", not merely "show the Home tab". The tab keeps its scroll
    // offset across a tab switch, so this is fired on every Home tap —
    // whether Home was already selected and scrolled away, or is being
    // returned to from another tab. The map ignores it when already there.
    if (index == 0) {
      _homeRecenterIntent.request();
    }
  }

  void _selectTab(int index) {
    assert(index != 2, 'Run is a route, not a tab');
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      _visitedTabIndexes.add(index);
    });
  }

  /// Switches to the Feed tab and requests [postId]'s comment sheet. Goes
  /// through [_selectTab], never [_handleNavigationTap] — the latter is
  /// wired to launch a run for index 2 and asserts against it, neither of
  /// which applies here.
  void _openFeedPostComments(String postId) {
    _selectTab(1);
    _feedCommentIntent.request(postId);
  }

  void _openInitialRunIntent() {
    if (!mounted ||
        _handledInitialRunOpenIntent ||
        !_activeRunSessionCoordinator.hasOpenRun) {
      return;
    }

    _handledInitialRunOpenIntent = true;
    _activeRunSessionCoordinator.syncNow();
    _pushRunLaunchRoute(plannedWorkout: _todayPlannedRunContext());
  }

  void _openActiveRunFromSystemReturn() {
    if (!mounted ||
        _runLaunchRouteOpen ||
        !_activeRunSessionCoordinator.hasOpenRun) {
      return;
    }

    _activeRunSessionCoordinator.syncNow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _runLaunchRouteOpen ||
          !_activeRunSessionCoordinator.hasOpenRun) {
        return;
      }
      _pushRunLaunchRoute(plannedWorkout: _todayPlannedRunContext());
    });
  }

  void _pushRunLaunchRoute({
    RunLocationSample? initialPreviewCurrentPosition,
    PlannedRunContext? plannedWorkout,
  }) {
    _runLaunchRouteOpen = true;
    Navigator.of(context)
        .push(
          _buildRunLaunchRoute(
            initialPreviewCurrentPosition: initialPreviewCurrentPosition,
            plannedWorkout: plannedWorkout,
          ),
        )
        .whenComplete(() {
          _runLaunchRouteOpen = false;
        });
  }

  PageRouteBuilder<void> _buildRunLaunchRoute({
    RunLocationSample? initialPreviewCurrentPosition,
    PlannedRunContext? plannedWorkout,
  }) {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) {
        return RunLaunchScreen(
          enableForegroundGps: widget.enableForegroundGps,
          initialPreviewCurrentPosition: initialPreviewCurrentPosition,
          activeRunSessionCoordinator: _activeRunSessionCoordinator,
          plannedWorkout: plannedWorkout,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final offsetAnimation =
            Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );

        return SlideTransition(position: offsetAnimation, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentDate = widget.youProgressToday ?? _currentDayController.today;
    final activeGeneratedPlan = CurrentSessionGeneratedPlanScope.of(
      context,
    ).activePlan;
    final scopedUserProgressStore = CurrentSessionUserProgressScope.maybeRead(
      context,
    );
    final userProgressStore = scopedUserProgressStore?.snapshot.ownerUid == null
        ? null
        : scopedUserProgressStore;
    final generatedPlanProgress = _generatedPlanProgress(activeGeneratedPlan);
    final homeRestDaySignal = _homeTodayIsRestDay(
      activeGeneratedPlan,
      currentDate,
      generatedPlanProgress,
    );
    final todayWorkoutDetail = todayGeneratedWorkoutDetailFromSnapshot(
      activeGeneratedPlan,
      currentDate: currentDate,
      planProgress: generatedPlanProgress,
      adaptiveEstimate: widget.adaptivePlanEstimate,
    );
    final todayPlannedRunContext = todayPlannedRunContextFromSnapshot(
      activeGeneratedPlan,
      currentDate: currentDate,
      planProgress: generatedPlanProgress,
      adaptiveEstimate: widget.adaptivePlanEstimate,
    );
    _syncGeneratedPlanNotifications(
      activeGeneratedPlan,
      generatedPlanProgress,
      userProgressStore: userProgressStore,
      force: false,
    );
    _scheduleNotificationInboxMaintenance();
    _scheduleSocialActivityMirrorSync();
    final feedAuthorProfile =
        _lastFeedAuthorProfile ??
        FeedAuthorProfileSnapshot.fallback(
          userId: widget.authRepository.currentUser?.uid ?? '',
        );
    _scheduleFeedAuthorProfileStoreSync(feedAuthorProfile);
    final tabs = <int, Widget>{
      if (_visitedTabIndexes.contains(0))
        0: HomeTab(
          key: const ValueKey<String>('runiac-shell-tab-home'),
          authRepository: widget.authRepository,
          profileRepository: widget.profileRepository,
          profilePersistenceRepository: widget.profilePersistenceRepository,
          generatedPlanPersistenceRepository:
              widget.generatedPlanPersistenceRepository,
          notificationInboxRepository: widget.notificationInboxRepository,
          userProgressRepository: widget.userProgressRepository,
          leaderboardRepository: widget.leaderboardRepository,
          friendsRepository: widget.friendsRepository,
          challengeRepository: widget.challengeRepository,
          challengeResultPresenter: widget.challengeResultPresenter,
          todayWorkoutDetailSnapshot: todayWorkoutDetail,
          todayPlannedRunContext: todayPlannedRunContext,
          generatedPlanProgress: generatedPlanProgress,
          planCompletedAt: widget.planProgress?.planCompletedAt,
          planCompletionSeenStore: widget.planCompletionSeenStore,
          currentDate: currentDate,
          homeGuideAgent: widget.homeGuideAgent,
          homeGuideConsentRepository: widget.homeGuideConsentRepository,
          enableForegroundGps: widget.enableForegroundGps,
          activeRunSessionCoordinator: _activeRunSessionCoordinator,
          onAccountProfileChanged: () {
            if (mounted) {
              setState(_setFeedAuthorProfileFuture);
            }
          },
          onNotificationSettingsChanged: () {
            _syncGeneratedPlanNotifications(
              activeGeneratedPlan,
              generatedPlanProgress,
              userProgressStore: userProgressStore,
              force: true,
            );
            unawaited(_notificationPreferenceMirrorService.syncSocialActivity());
          },
          onOpenFeedPostComments: _openFeedPostComments,
          recenterIntent: _homeRecenterIntent,
        ),
      if (_visitedTabIndexes.contains(1))
        1: CurrentSessionFeed(
          key: const ValueKey<String>('runiac-shell-tab-feed'),
          repository: widget.feedRepository,
          viewerContext: _feedViewerContext,
          currentAuthorProfile: feedAuthorProfile,
          commentIntent: _feedCommentIntent,
        ),
      if (_visitedTabIndexes.contains(3))
        3: LeaderboardTab(
          key: const ValueKey<String>('runiac-shell-tab-leaderboard'),
          repository: widget.leaderboardRepository,
        ),
      if (_visitedTabIndexes.contains(4))
        4: YouTab(
          key: const ValueKey<String>('runiac-shell-tab-you'),
          activityHistoryRepository: widget.activityHistoryRepository,
          userProgressRepository: widget.userProgressRepository,
          authRepository: widget.authRepository,
          generatedPlanPersistenceRepository:
              widget.generatedPlanPersistenceRepository,
          enableForegroundGps: widget.enableForegroundGps,
          activeRunSessionCoordinator: _activeRunSessionCoordinator,
          progressToday: currentDate,
          generatedPlanProgress: generatedPlanProgress,
          adaptivePlanEstimate: widget.adaptivePlanEstimate,
        ),
    };

    return FutureBuilder<FeedAuthorProfileSnapshot>(
      future: _feedAuthorProfileFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != _lastFeedAuthorProfile) {
          _lastFeedAuthorProfile = snapshot.data;
          _scheduleFeedAuthorProfileStoreSync(snapshot.data!);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
        return AppTourHost(
          controller: _appTourController,
          seenStore: widget.appTourSeenStore,
          autoStartArmed: widget.appTourAutoStartArmed,
          ownerUid: widget.authRepository.currentUser?.uid,
          homeRestDaySignal: homeRestDaySignal,
          child: Scaffold(
            appBar:
                _selectedIndex == 0 ||
                    _selectedIndex == 1 ||
                    _selectedIndex == 3 ||
                    _selectedIndex == 4
                ? null
                : AppBar(title: const Text('Runiac')),
            body: Stack(
              fit: StackFit.expand,
              children: [
                for (final entry in tabs.entries)
                  Offstage(
                    key: ValueKey<String>('runiac-shell-slot-${entry.key}'),
                    offstage: entry.key != _selectedIndex,
                    child: TickerMode(
                      enabled: entry.key == _selectedIndex,
                      child: entry.value,
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: TutorialAnchor(
              id: TutorialAnchorId.bottomNavBar,
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                type: BottomNavigationBarType.fixed,
                onTap: _handleNavigationTap,
                backgroundColor: RuniacColors.white,
                selectedItemColor: RuniacColors.primaryBlue,
                unselectedItemColor: RuniacColors.textSecondary,
                showSelectedLabels: false,
                showUnselectedLabels: false,
                selectedFontSize: 0,
                unselectedFontSize: 0,
                selectedIconTheme: const IconThemeData(size: 32),
                unselectedIconTheme: const IconThemeData(size: 30),
                selectedLabelStyle: const TextStyle(fontSize: 0, height: 0),
                unselectedLabelStyle: const TextStyle(fontSize: 0, height: 0),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home),
                    label: '',
                    tooltip: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dynamic_feed),
                    label: '',
                    tooltip: 'Feed',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.directions_run),
                    label: '',
                    tooltip: 'Run',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.leaderboard),
                    label: '',
                    tooltip: 'Leaderboard',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person),
                    label: '',
                    tooltip: 'You',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  FeedViewerContext? get _feedViewerContext {
    final viewer = widget.authRepository.currentUser;
    return viewer == null
        ? null
        : FeedViewerContext(
            currentUserId: viewer.uid,
            acceptedFriendUserIds: const <String>{},
          );
  }

  PlannedRunContext? _todayPlannedRunContext() {
    final generatedPlanStore = CurrentSessionGeneratedPlanScope.maybeOf(
      context,
    );
    return todayPlannedRunContextFromSnapshot(
      generatedPlanStore?.activePlan,
      currentDate: widget.youProgressToday,
      planProgress: _generatedPlanProgress(generatedPlanStore?.activePlan),
      adaptiveEstimate: widget.adaptivePlanEstimate,
    );
  }

  GeneratedPlanProgressDisplay? _generatedPlanProgress(
    BeginnerAdaptivePlanSnapshot? activePlan,
  ) {
    final completedIds = <String>{
      if (widget.planProgress != null)
        ...widget.planProgress!.completedScheduledWorkoutIds,
      ...?CurrentSessionActivityHistoryScope.maybeRead(
        context,
      )?.completedScheduledWorkoutIdsForPlan(activePlan?.id ?? ''),
    };
    if (completedIds.isEmpty) {
      return null;
    }
    return GeneratedPlanProgressDisplay(
      completedScheduledWorkoutIds: completedIds,
    );
  }

  /// Whether today is a scheduled rest day on [activePlan], for the app tour
  /// only (see `AppTourHost.homeRestDaySignal`).
  ///
  /// Deliberately calls the exact same production derivation `home_tab.dart`
  /// uses for its own guide bubble — `buildHomeStageMapModel`'s
  /// `todayDayIndex` stone, checked for `HomeStageStoneKind.rest` — rather
  /// than re-deriving rest-day-ness independently, so the tour can never
  /// disagree with what the Home guide bubble is showing. `backgroundSequence`
  /// is passed empty because it only selects cosmetic per-week art, never the
  /// stone kind at `todayDayIndex`. Returns null (unknown) whenever
  /// `home_tab.dart` itself would have no stage-map model to show: no plan,
  /// an ineligible plan, or no resolvable "today" stone.
  bool? _homeTodayIsRestDay(
    BeginnerAdaptivePlanSnapshot? activePlan,
    DateTime currentDate,
    GeneratedPlanProgressDisplay? generatedPlanProgress,
  ) {
    if (activePlan == null ||
        !isEligibleCurrentSessionGeneratedPlan(activePlan)) {
      return null;
    }
    final activeWeek = activeGeneratedPlanWeekFor(
      activePlan,
      currentDate: currentDate,
    );
    final activeWeekNumber =
        activeWeek?.weekNumber ?? activePlan.weeks.first.weekNumber;
    final activeWeekdayIndex = activeGeneratedPlanWeekdayFor(
      activePlan,
      currentDate: currentDate,
    );
    final model = buildHomeStageMapModel(
      plan: activePlan,
      completedScheduledWorkoutIds:
          generatedPlanProgress?.completedScheduledWorkoutIds ??
          const <String>{},
      activeWeekNumber: activeWeekNumber,
      currentWeekdayIndex: activeWeekdayIndex,
      backgroundSequence: const <String>[],
    );
    final weekIndex = model.currentWeekIndex;
    final dayIndex = model.todayDayIndex;
    if (weekIndex == null ||
        dayIndex == null ||
        weekIndex >= model.sections.length) {
      return null;
    }
    final stones = model.sections[weekIndex].stones;
    if (dayIndex >= stones.length) {
      return null;
    }
    return !stones[dayIndex].isRun;
  }

  void _syncGeneratedPlanNotifications(
    BeginnerAdaptivePlanSnapshot? activeGeneratedPlan,
    GeneratedPlanProgressDisplay? generatedPlanProgress, {
    required CurrentSessionUserProgress? userProgressStore,
    required bool force,
  }) {
    if (!widget.enableLocalPlanNotifications) {
      return;
    }
    final signature = _planNotificationSyncSignature(
      activeGeneratedPlan,
      generatedPlanProgress,
    );
    if (!force && signature == _lastPlanNotificationSyncSignature) {
      return;
    }
    if (_planNotificationSyncInFlight) {
      _pendingPlanNotificationSync = true;
      _pendingPlanNotificationPlan = activeGeneratedPlan;
      _pendingPlanNotificationProgress = generatedPlanProgress;
      return;
    }
    _lastPlanNotificationSyncSignature = signature;
    _planNotificationSyncInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final now = widget.youProgressToday ?? DateTime.now();
        await _planNotificationSyncService.syncGeneratedPlan(
          activeGeneratedPlan,
          now: now,
          completedScheduledWorkoutIds:
              generatedPlanProgress?.completedScheduledWorkoutIds ??
              const <String>{},
          streakRisk: await _streakRiskInputForPlan(
            activeGeneratedPlan,
            userProgressStore: userProgressStore,
            now: now,
          ),
        );
      } catch (_) {
        // Notification sync should not block the primary app shell.
      } finally {
        _planNotificationSyncInFlight = false;
        if (_pendingPlanNotificationSync && mounted) {
          final pendingPlan = _pendingPlanNotificationPlan;
          final pendingProgress = _pendingPlanNotificationProgress;
          _pendingPlanNotificationSync = false;
          _pendingPlanNotificationPlan = null;
          _pendingPlanNotificationProgress = null;
          _syncGeneratedPlanNotifications(
            pendingPlan,
            pendingProgress,
            userProgressStore: userProgressStore,
            force: true,
          );
        }
      }
    });
  }

  String _planNotificationSyncSignature(
    BeginnerAdaptivePlanSnapshot? activeGeneratedPlan,
    GeneratedPlanProgressDisplay? generatedPlanProgress,
  ) {
    final completedIds = [
      ...?generatedPlanProgress?.completedScheduledWorkoutIds,
    ]..sort();
    final currentDate = widget.youProgressToday;
    final dayKey = currentDate == null
        ? 'today'
        : '${currentDate.year}-${currentDate.month}-${currentDate.day}';
    return [
      activeGeneratedPlan?.id ?? 'none',
      activeGeneratedPlan?.startsOnDate ?? 'no-start',
      dayKey,
      ...completedIds,
    ].join('|');
  }

  Future<StreakRiskNotificationInput?> _streakRiskInputForPlan(
    BeginnerAdaptivePlanSnapshot? activeGeneratedPlan, {
    required CurrentSessionUserProgress? userProgressStore,
    required DateTime now,
  }) async {
    if (activeGeneratedPlan == null) {
      return null;
    }
    final progress = await _loadProgressForShell(userProgressStore);
    if (!_isStreakAtRisk(progress, now: now)) {
      return null;
    }
    return StreakRiskNotificationInput(
      planId: activeGeneratedPlan.id,
      riskDate: now,
      streakWouldBreakWithoutValidatedRun: true,
    );
  }

  Future<UserProgressReadModel> _loadProgressForShell(
    CurrentSessionUserProgress? userProgressStore,
  ) async {
    if (userProgressStore == null) {
      return widget.userProgressRepository.loadUserProgress();
    }
    await WidgetsBinding.instance.endOfFrame;
    await userProgressStore.load();
    return userProgressStore.snapshot.progress ??
        await widget.userProgressRepository.loadUserProgress();
  }

  bool _isStreakAtRisk(
    UserProgressReadModel progress, {
    required DateTime now,
  }) {
    final streakCount = progress.officialStreakCount;
    if (streakCount == null || streakCount <= 0) {
      return false;
    }
    return progress.lastStreakRunDate != _dateKey(now);
  }

  String _dateKey(DateTime date) {
    return [
      date.year.toString().padLeft(4, '0'),
      date.month.toString().padLeft(2, '0'),
      date.day.toString().padLeft(2, '0'),
    ].join('-');
  }
}

FeedAuthorProfileSnapshot _feedAuthorProfileFrom({
  required String? ownerUid,
  required UserProfileReadModel profile,
  required UserProgressReadModel progress,
}) {
  final displayName = profile.displayName.trim();
  final initials = profile.avatarInitials.trim();
  final levelLabel = progress.levelLabel.trim();
  return FeedAuthorProfileSnapshot(
    userId: ownerUid ?? profile.userId,
    displayName: displayName.isEmpty ? 'You' : displayName,
    avatarInitials: initials.isEmpty ? 'R' : initials,
    avatarUrl: profile.avatarUrl.trim(),
    levelLabel: levelLabel.isEmpty ? progress.levelBadgeLabel : levelLabel,
    levelProgressFraction: progress.levelProgressFraction,
  );
}
