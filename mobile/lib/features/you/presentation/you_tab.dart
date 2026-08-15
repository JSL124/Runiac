import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../auth/domain/runiac_auth_service.dart';
import '../../plan/domain/models/adaptive_plan_estimate_read_model.dart';
import '../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import '../../plan/domain/repositories/generated_plan_persistence_repository.dart';
import '../../run/domain/models/run_activity_display_model.dart';
import '../../run/presentation/active_run_session_coordinator.dart';
import '../../run/presentation/view_summary_screen.dart';
import '../../tutorial/domain/models/tutorial_step.dart';
import '../../tutorial/presentation/tutorial_anchor_registry.dart';
import '../data/static_activity_history_repository.dart';
import '../domain/models/user_progress_read_model.dart';
import '../domain/repositories/activity_history_repository.dart';
import '../domain/repositories/user_progress_repository.dart';
import '../../plan/presentation/current_session_generated_plan.dart';
import 'activity_history_display_controller.dart';
import 'activity_history_screen.dart';
import 'current_session_activity_history.dart';
import 'current_session_user_progress.dart';
import 'adapters/generated_plan_you_display_adapter.dart';
import 'data/goal_plan_demo_snapshots.dart';
import 'data/weekly_workout_demo_snapshots.dart';
import 'goal_plan_detail_screen.dart';
import 'weekly_workout_detail_screen.dart';
import 'widgets/you_header_overlay.dart';
import 'widgets/you_plans_surface.dart';
import 'widgets/you_progress_surface.dart';
import 'widgets/you_segmented_control.dart';

/// The You tab — the runner's own progress: level and XP, streak, weekly
/// distance, activity history and the remaining sessions of their plan.
///
/// Everything numeric here is read-only by design. XP, level, streak and rank
/// are owned by the backend and rejected on client write by `firestore.rules`,
/// so this tab displays progression state and never computes it. Starting a
/// planned session hands off to the run flow, which is the only path that can
/// cause those numbers to change.
class YouTab extends StatefulWidget {
  const YouTab({
    super.key,
    this.activityHistoryRepository = const StaticActivityHistoryRepository(),
    this.userProgressRepository = const StaticUserProgressRepository(),
    this.authRepository,
    this.generatedPlanPersistenceRepository =
        const NoopGeneratedPlanPersistenceRepository(),
    this.enableForegroundGps = true,
    this.activeRunSessionCoordinator,
    this.progressToday,
    this.generatedPlanProgress,
    this.adaptivePlanEstimate,
  });

  final ActivityHistoryRepository activityHistoryRepository;
  final UserProgressRepository userProgressRepository;
  final RuniacAuthRepository? authRepository;
  final GeneratedPlanPersistenceRepository generatedPlanPersistenceRepository;
  final bool enableForegroundGps;
  final ActiveRunSessionCoordinator? activeRunSessionCoordinator;
  final DateTime? progressToday;
  final GeneratedPlanProgressDisplay? generatedPlanProgress;
  final AdaptivePlanEstimateReadModel? adaptivePlanEstimate;

  @override
  State<YouTab> createState() => _YouTabState();
}

class _YouTabState extends State<YouTab> {
  var _plans = false;
  var _goalPlanDetailVisible = false;
  var _workoutDetailVisible = false;
  var _activityHistoryVisible = false;
  late ActivityHistoryDisplayController _activityHistoryController;
  var _workoutDetailSnapshot = weeklyWorkoutDetailSnapshot;
  GeneratedYouPlanDisplay? _editedGeneratedPlanDisplay;
  late DateTime _visibleCalendarMonth;
  UserProgressReadModel? _userProgress;
  var _userProgressLoaded = false;
  int? _observedUserProgressRefreshRevision;
  var _userProgressLoadSerial = 0;
  String? _observedActivityHistoryOwnerUid;
  String? _observedUserProgressOwnerUid;

  @override
  void initState() {
    super.initState();
    final today = widget.progressToday ?? DateTime.now();
    _visibleCalendarMonth = DateTime(today.year, today.month);
    _observedActivityHistoryOwnerUid = _currentActivityHistoryOwnerUid;
    _activityHistoryController = ActivityHistoryDisplayController(
      repository: widget.activityHistoryRepository,
    )..addListener(_handleActivityHistoryChanged);
    _activityHistoryController.load();
    _observedUserProgressOwnerUid = _currentUserProgressOwnerUid;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activityHistoryStore = CurrentSessionActivityHistoryScope.of(context);
    final scopedSessionUserProgress = CurrentSessionUserProgressScope.maybeOf(
      context,
    );
    final sessionUserProgress =
        scopedSessionUserProgress?.snapshot.ownerUid == null
        ? null
        : scopedSessionUserProgress;
    _activityHistoryController.attachActivityHistoryStore(activityHistoryStore);
    _syncActivityHistoryOwner(activityHistoryStore);
    if (sessionUserProgress == null) {
      _syncUserProgressOwner();
      if (!_userProgressLoaded && _userProgress == null) {
        unawaited(_loadUserProgress());
      }
    } else {
      _syncSessionUserProgress(sessionUserProgress);
    }
    final revision = activityHistoryStore.userProgressRefreshRevision;
    final observedRevision = _observedUserProgressRefreshRevision;
    _observedUserProgressRefreshRevision = revision;
    if (observedRevision != null && revision != observedRevision) {
      final refreshedProgress = activityHistoryStore.latestUserProgressRefresh;
      if (refreshedProgress != null) {
        _userProgressLoadSerial += 1;
        setState(() {
          _userProgress = refreshedProgress;
          _userProgressLoaded = true;
        });
      } else {
        unawaited(_loadUserProgress());
      }
    }
  }

  @override
  void didUpdateWidget(covariant YouTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activityHistoryRepository !=
        widget.activityHistoryRepository) {
      _observedActivityHistoryOwnerUid = _currentActivityHistoryOwnerUid;
      _replaceActivityHistoryController(
        CurrentSessionActivityHistoryScope.of(context),
      );
    } else {
      _syncActivityHistoryOwner(CurrentSessionActivityHistoryScope.of(context));
    }
    if (oldWidget.userProgressRepository != widget.userProgressRepository) {
      if (_activeSessionUserProgress(context) == null) {
        _resetAndLoadUserProgress();
      }
    } else if (!_isSameDate(oldWidget.progressToday, widget.progressToday)) {
      final sessionUserProgress = _activeSessionUserProgress(context);
      if (sessionUserProgress == null) {
        unawaited(_loadUserProgress());
      } else {
        unawaited(sessionUserProgress.refresh());
      }
    }
    if (oldWidget.authRepository != widget.authRepository) {
      _syncActivityHistoryOwner(CurrentSessionActivityHistoryScope.of(context));
      if (_activeSessionUserProgress(context) == null) {
        _syncUserProgressOwner();
      }
    }
  }

  @override
  void dispose() {
    _activityHistoryController
      ..removeListener(_handleActivityHistoryChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scopedSessionUserProgress = CurrentSessionUserProgressScope.maybeOf(
      context,
    );
    final sessionUserProgress =
        scopedSessionUserProgress?.snapshot.ownerUid == null
        ? null
        : scopedSessionUserProgress;
    final sessionProgressSnapshot = sessionUserProgress?.snapshot;
    final displayedProgress =
        sessionProgressSnapshot?.progress ?? _userProgress;
    final progressLoaded = sessionUserProgress == null
        ? _userProgressLoaded
        : displayedProgress != null ||
              sessionProgressSnapshot?.status ==
                  CurrentSessionUserProgressStatus.failure;
    final activityHistoryStore = CurrentSessionActivityHistoryScope.of(context);
    final recentRuns = _activityHistoryController.recentRuns(
      activityHistoryStore,
    );
    final activityHistoryMonths = _activityHistoryController.months(
      activityHistoryStore,
    );
    final activityHistoryLoading =
        _activityHistoryController.initialLoadPending &&
        activityHistoryMonths.isEmpty &&
        recentRuns.isEmpty;
    final generatedPlanStore = CurrentSessionGeneratedPlanScope.of(context);
    final activeGeneratedPlan = generatedPlanStore.activePlan;
    final generatedPlanProgress = _generatedPlanProgress(
      activityHistoryStore,
      activeGeneratedPlan,
    );
    final generatedPlanDisplay =
        _editedGeneratedPlanDisplay ??
        generatedYouPlanDisplayFromSnapshot(
          activeGeneratedPlan,
          planProgress: generatedPlanProgress,
          currentDate: widget.progressToday,
          adaptiveEstimate: widget.adaptivePlanEstimate,
        );
    // Derived from the plan itself, not from `_editedGeneratedPlanDisplay`: the
    // full-plan view is laid out in plan weeks while that display is a calendar
    // week, and a reschedule already writes back through `setActivePlan`.
    final generatedGoalPlanDetail = generatedGoalPlanDisplayFromSnapshot(
      activeGeneratedPlan,
      currentDate: widget.progressToday,
    );
    final safetyReadinessDisplay = safetyReadinessYouPlanDisplayFromSnapshot(
      activeGeneratedPlan,
    );

    if (_activityHistoryVisible) {
      return ActivityHistoryScreen(
        activityHistoryMonths: activityHistoryMonths,
        loadFailed: _activityHistoryController.loadFailed,
        onRetryLoad: () {
          _activityHistoryController.load();
        },
        onBack: () {
          setState(() => _activityHistoryVisible = false);
        },
        onActivitySelected: _showRunSummary,
      );
    }

    if (_workoutDetailVisible) {
      return WeeklyWorkoutDetailScreen(
        snapshot: _workoutDetailSnapshot,
        onBack: () {
          setState(() => _workoutDetailVisible = false);
        },
        enableForegroundGps: widget.enableForegroundGps,
        activeRunSessionCoordinator: widget.activeRunSessionCoordinator,
        onScheduleChanged: _handleWorkoutScheduleChanged,
      );
    }

    if (_goalPlanDetailVisible) {
      return GoalPlanDetailScreen(
        snapshot: generatedGoalPlanDetail ?? goalPlanDisplaySnapshot,
        onWorkoutSelected: _showWorkoutDetail,
        onBack: () {
          setState(() => _goalPlanDetailVisible = false);
        },
      );
    }

    final topPadding = MediaQuery.paddingOf(context).top;
    final headerHeight = topPadding + kToolbarHeight;

    return ColoredBox(
      color: RuniacColors.background,
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(overscroll: false),
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, headerHeight + 8, 16, 28),
              children: [
                TutorialAnchor(
                  id: TutorialAnchorId.youSegmentedControl,
                  child: YouSegmentedControl(
                    labels: const ['Progress', 'Plans'],
                    selected: _plans ? 1 : 0,
                    onTap: (index) {
                      setState(() => _plans = index == 1);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (_plans)
                  YouPlansSurface(
                    generatedPlan: generatedPlanDisplay,
                    safetyReadinessPlan: safetyReadinessDisplay,
                    onViewGoalPlan: _showGoalPlanDetail,
                    onViewWorkout: _showWorkoutDetail,
                  )
                else
                  YouProgressSurface(
                    activityHistoryMonths: activityHistoryMonths,
                    activityHistoryLoading: activityHistoryLoading,
                    runs: recentRuns,
                    visibleCalendarMonth: _visibleCalendarMonth,
                    onPreviousMonth: _showPreviousCalendarMonth,
                    onNextMonth: _showNextCalendarMonth,
                    onRunSelected: _showRunSummary,
                    onMoreActivities: _showActivityHistory,
                    officialStreakLabel:
                        displayedProgress?.officialStreakLabel ?? '',
                    officialStreakLoading: !progressLoaded,
                    today: widget.progressToday,
                  ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerHeight,
            child: const YouHeaderOverlay(),
          ),
        ],
      ),
    );
  }

  GeneratedPlanProgressDisplay? _generatedPlanProgress(
    CurrentSessionActivityHistoryStore activityHistoryStore,
    BeginnerAdaptivePlanSnapshot? activeGeneratedPlan,
  ) {
    final completedIds = <String>{
      if (widget.generatedPlanProgress != null)
        ...widget.generatedPlanProgress!.completedScheduledWorkoutIds,
      ...activityHistoryStore.completedScheduledWorkoutIdsForPlan(
        activeGeneratedPlan?.id ?? '',
      ),
    };
    if (completedIds.isEmpty) {
      return null;
    }
    return GeneratedPlanProgressDisplay(
      completedScheduledWorkoutIds: completedIds,
    );
  }

  void _showPreviousCalendarMonth() {
    setState(() {
      _visibleCalendarMonth = DateTime(
        _visibleCalendarMonth.year,
        _visibleCalendarMonth.month - 1,
      );
    });
  }

  void _showNextCalendarMonth() {
    setState(() {
      _visibleCalendarMonth = DateTime(
        _visibleCalendarMonth.year,
        _visibleCalendarMonth.month + 1,
      );
    });
  }

  String? get _currentActivityHistoryOwnerUid =>
      widget.authRepository?.currentUser?.uid;

  void _syncActivityHistoryOwner(CurrentSessionActivityHistoryStore store) {
    final ownerUid = _currentActivityHistoryOwnerUid;
    if (_observedActivityHistoryOwnerUid == ownerUid) {
      return;
    }
    _observedActivityHistoryOwnerUid = ownerUid;
    _replaceActivityHistoryController(store);
  }

  void _replaceActivityHistoryController(
    CurrentSessionActivityHistoryStore store,
  ) {
    _activityHistoryController
      ..removeListener(_handleActivityHistoryChanged)
      ..dispose();
    _activityHistoryController = ActivityHistoryDisplayController(
      repository: widget.activityHistoryRepository,
    )..addListener(_handleActivityHistoryChanged);
    _activityHistoryController.attachActivityHistoryStore(store);
    _activityHistoryController.load();
  }

  void _showGoalPlanDetail() {
    setState(() => _goalPlanDetailVisible = true);
  }

  void _showWorkoutDetail(WeeklyWorkoutDetailSnapshot snapshot) {
    setState(() {
      _workoutDetailSnapshot = snapshot;
      _workoutDetailVisible = true;
    });
  }

  void _handleWorkoutScheduleChanged(WorkoutScheduleEditSelection selection) {
    final generatedPlanStore = CurrentSessionGeneratedPlanScope.of(context);
    final activityHistoryStore = CurrentSessionActivityHistoryScope.of(context);
    final activePlan = generatedPlanStore.activePlan;
    final generatedPlanProgress = _generatedPlanProgress(
      activityHistoryStore,
      activePlan,
    );
    final updatedPlan = activePlan == null
        ? null
        : rescheduleGeneratedPlanSnapshot(
            activePlan,
            _workoutDetailSnapshot,
            selection,
            currentDate: widget.progressToday,
          );
    setState(() {
      final currentGeneratedPlan =
          _editedGeneratedPlanDisplay ??
          generatedYouPlanDisplayFromSnapshot(
            activePlan,
            currentDate: widget.progressToday,
            planProgress: generatedPlanProgress,
            adaptiveEstimate: widget.adaptivePlanEstimate,
          );
      _editedGeneratedPlanDisplay = currentGeneratedPlan?.rescheduleWorkout(
        _workoutDetailSnapshot,
        selection,
      );
      _workoutDetailSnapshot = selection.updatedDetail(_workoutDetailSnapshot);
    });
    if (updatedPlan == null) {
      return;
    }

    generatedPlanStore.setActivePlan(updatedPlan);
    final uid = widget.authRepository?.currentUser?.uid;
    if (uid == null) {
      return;
    }
    unawaited(_saveGeneratedPlanSchedule(uid, updatedPlan));
  }

  Future<void> _saveGeneratedPlanSchedule(
    String uid,
    BeginnerAdaptivePlanSnapshot plan,
  ) async {
    try {
      await widget.generatedPlanPersistenceRepository.saveGeneratedPlan(
        uid: uid,
        plan: plan,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac',
          context: ErrorDescription('saving generated plan schedule edit'),
        ),
      );
    }
  }

  void _showActivityHistory() {
    setState(() => _activityHistoryVisible = true);
  }

  void _showRunSummary(RunActivityDisplayModel run) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ViewSummaryScreen(
          completionResult: run.completionResult,
          summary: run.summary,
          feedPublishSource: run.feedPublishSource,
          activityFeedbackCacheIdentity: _activityFeedbackCacheIdentityFor(run),
          showXpUpdateAction: false,
          showLowDataSaveAction: false,
        ),
      ),
    );
  }

  String? _activityFeedbackCacheIdentityFor(RunActivityDisplayModel run) {
    for (final identity in <String?>[run.activityId, run.clientRunSessionId]) {
      final normalized = identity?.trim();
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  void _handleActivityHistoryChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  String? get _currentUserProgressOwnerUid =>
      widget.authRepository?.currentUser?.uid;

  CurrentSessionUserProgress? _activeSessionUserProgress(BuildContext context) {
    final session = CurrentSessionUserProgressScope.maybeRead(context);
    return session?.snapshot.ownerUid == null ? null : session;
  }

  void _syncUserProgressOwner() {
    final ownerUid = _currentUserProgressOwnerUid;
    if (_observedUserProgressOwnerUid == ownerUid) {
      return;
    }
    _observedUserProgressOwnerUid = ownerUid;
    _resetAndLoadUserProgress();
  }

  void _syncSessionUserProgress(CurrentSessionUserProgress session) {
    final snapshot = session.snapshot;
    final progress = snapshot.progress;
    if (progress != null) {
      _userProgressLoadSerial += 1;
      _userProgress = progress;
      _userProgressLoaded = true;
      return;
    }
    if (snapshot.status == CurrentSessionUserProgressStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            session.snapshot.status != CurrentSessionUserProgressStatus.idle) {
          return;
        }
        unawaited(session.load());
      });
    } else if (snapshot.status == CurrentSessionUserProgressStatus.failure) {
      _userProgressLoaded = true;
      if (_userProgress == null) {
        unawaited(_loadUserProgress());
      }
    }
  }

  void _resetAndLoadUserProgress() {
    _userProgressLoadSerial += 1;
    setState(() {
      _userProgress = null;
      _userProgressLoaded = false;
    });
    unawaited(_loadUserProgress());
  }

  Future<void> _loadUserProgress() async {
    final loadSerial = _userProgressLoadSerial + 1;
    _userProgressLoadSerial = loadSerial;
    try {
      final progress = await widget.userProgressRepository.loadUserProgress();
      if (!mounted || loadSerial != _userProgressLoadSerial) {
        return;
      }
      setState(() {
        _userProgress = progress;
        _userProgressLoaded = true;
      });
    } catch (error, stackTrace) {
      if (!mounted || loadSerial != _userProgressLoadSerial) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac',
          context: ErrorDescription('loading user progress for You tab'),
        ),
      );
      setState(() {
        _userProgressLoaded = true;
      });
    }
  }
}

bool _isSameDate(DateTime? left, DateTime? right) {
  return left?.year == right?.year &&
      left?.month == right?.month &&
      left?.day == right?.day;
}
