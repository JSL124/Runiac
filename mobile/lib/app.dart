import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/characters/local_selected_runner_character_storage.dart';
import 'core/characters/runner_character.dart';
import 'core/haptics/runiac_haptics.dart';
import 'core/haptics/runiac_haptics_scope.dart';
import 'core/observability/error_screen_tracker.dart';
import 'core/theme/runiac_theme.dart';
import 'features/profile/data/static_user_profile_repository.dart';
import 'features/profile/domain/models/user_profile_read_model.dart';
import 'features/profile/domain/repositories/runner_public_profile_repository.dart';
import 'features/profile/domain/repositories/user_account_repository.dart';
import 'features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'features/profile/domain/repositories/user_profile_repository.dart';
import 'features/profile/presentation/current_session_user_account.dart';
import 'features/profile/presentation/runner_public_profile_scope.dart';
import 'features/profile/presentation/personal_profile_collection_screen.dart';
import 'features/auth/data/non_production_auth_repository.dart';
import 'features/auth/domain/runiac_auth_service.dart';
import 'features/auth/presentation/runiac_auth_gate.dart';
import 'features/auth/presentation/runiac_profile_setup_gate.dart';
import 'features/challenge/data/static_challenge_repository.dart';
import 'features/challenge/domain/repositories/challenge_repository.dart';
import 'features/challenge/presentation/challenge_result_presentation_controller.dart';
import 'features/feed/data/static_feed_repository.dart';
import 'features/feed/domain/repositories/feed_repository.dart';
import 'features/feed/presentation/current_session_feed.dart';
import 'features/friends/data/static_friends_repository.dart';
import 'features/friends/domain/repositories/friends_repository.dart';
import 'features/home/domain/guide/home_guide_agent.dart';
import 'features/home/domain/guide/home_guide_consent.dart';
import 'features/home/domain/guide/rule_based_home_guide_agent.dart';
import 'features/onboarding/domain/models/local_onboarding_draft.dart';
import 'features/notifications/domain/models/notification_inbox_item.dart';
import 'features/notifications/domain/repositories/notification_inbox_repository.dart';
import 'features/notifications/domain/repositories/notification_preference_mirror.dart';
import 'features/notifications/domain/services/notification_registration_service.dart';
import 'features/paywall/domain/repositories/character_access_repository.dart';
import 'features/paywall/domain/repositories/feature_access_repository.dart';
import 'features/paywall/domain/repositories/paywall_config_repository.dart';
import 'features/paywall/presentation/current_session_character_access.dart';
import 'features/paywall/presentation/premium_character_entitlement.dart';
import 'features/paywall/presentation/current_session_feature_access.dart';
import 'features/paywall/presentation/current_session_paywall_config.dart';
import 'features/leaderboard/data/static_leaderboard_repository.dart';
import 'features/leaderboard/domain/repositories/leaderboard_repository.dart';
import 'features/plan/domain/models/adaptive_plan_estimate_read_model.dart';
import 'features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'features/plan/domain/models/plan_progress_read_model.dart';
import 'features/plan/domain/plan_completion_seen_store.dart';
import 'features/plan/domain/repositories/adaptive_plan_estimate_repository.dart';
import 'features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'features/plan/domain/repositories/plan_progress_repository.dart';
import 'features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'features/plan/presentation/current_session_generated_plan.dart';
import 'features/plan/presentation/plan_completion_celebration_scope.dart';
import 'features/run/data/static_run_repository.dart';
import 'features/run/domain/repositories/run_repository.dart';
import 'features/run/presentation/active_run_session_coordinator.dart';
import 'features/run/presentation/run_open_intent.dart';
import 'features/run/presentation/run_repository_scope.dart';
import 'features/settings/data/shared_preferences_app_settings_repository.dart';
import 'features/tutorial/domain/app_tour_seen_store.dart';
import 'features/you/data/local_user_progress_cache_store.dart';
import 'features/you/data/static_activity_history_repository.dart';
import 'features/you/data/local_pending_run_activity_store.dart';
import 'features/you/domain/models/user_progress_read_model.dart';
import 'features/you/domain/repositories/activity_history_repository.dart';
import 'features/you/domain/repositories/user_progress_repository.dart';
import 'features/onboarding/presentation/runiac_character_selection_gate.dart';
import 'features/onboarding/presentation/runiac_onboarding_gate.dart';
import 'features/shell/runiac_shell.dart';
import 'features/splash/presentation/runiac_splash_tokens.dart';
import 'features/splash/presentation/runiac_startup_gate.dart';
import 'features/you/presentation/current_session_activity_history.dart';
import 'features/you/presentation/current_session_user_progress.dart';
import 'features/you/presentation/widgets/activity_route_snapshot_thumbnail_cache.dart';

export 'features/run/presentation/run_open_intent.dart';

class RuniacApp extends StatefulWidget {
  const RuniacApp({
    super.key,
    this.showSplash = true,
    this.showAuth = false,
    this.showOnboarding = false,
    this.splashDuration = RuniacSplashTokens.minVisibleDuration,
    this.authRepository = const NonProductionAuthRepository(),
    this.runRepository = const StaticRunRepository(),
    this.activityHistoryRepository = const StaticActivityHistoryRepository(),
    this.userProgressRepository = const StaticUserProgressRepository(),
    this.leaderboardRepository = const StaticLeaderboardRepository(),
    this.runnerPublicProfileRepository =
        const UnavailableRunnerPublicProfileRepository(),
    this.friendsRepository = const StaticFriendsRepository(),
    this.challengeRepository = const StaticChallengeRepository(),
    this.challengeResultPresenter,
    this.profileRepository = const StaticUserProfileRepository(),
    this.userAccountRepository = const StaticUserAccountRepository(),
    this.paywallConfigRepository = const StaticPaywallConfigRepository(),
    this.featureAccessRepository = const StaticFeatureAccessRepository(),
    this.characterAccessRepository = const StaticCharacterAccessRepository(),
    this.profilePersistenceRepository =
        const NoopUserProfilePersistenceRepository(),
    this.generatedPlanPersistenceRepository =
        const NoopGeneratedPlanPersistenceRepository(),
    this.planProgressRepository = const NoopPlanProgressRepository(),
    this.planCompletionSeenStore,
    this.appTourSeenStore,
    this.adaptivePlanEstimateRepository =
        const NoopAdaptivePlanEstimateRepository(),
    this.notificationInboxRepository =
        const StaticNotificationInboxRepository(),
    this.notificationPreferenceMirror =
        const NoopNotificationPreferenceMirror(),
    this.notificationRegistrationService,
    this.homeGuideAgent = const RuleBasedHomeGuideAgent(),
    this.homeGuideConsentRepository =
        const AlwaysGrantedHomeGuideConsentRepository(),
    this.enableForegroundGps = true,
    this.activeRunSessionCoordinator,
    this.initialRunOpenIntent,
    this.currentSessionActivityHistoryStore,
    this.currentSessionFeedStore,
    this.feedRepository,
    this.currentSessionGeneratedPlanStore,
    this.initialPersonalProfileDraft,
    this.onOnboardingCompleted,
    this.youProgressToday,
  });

  final bool showSplash;
  final bool showAuth;
  final bool showOnboarding;
  final Duration splashDuration;
  final RuniacAuthRepository authRepository;
  final RunRepository runRepository;
  final ActivityHistoryRepository activityHistoryRepository;
  final UserProgressRepository userProgressRepository;
  final LeaderboardRepository leaderboardRepository;

  /// Backend source for another runner's public profile, opened from a
  /// leaderboard rank row.
  final RunnerPublicProfileRepository runnerPublicProfileRepository;
  final FriendsRepository friendsRepository;

  /// Challenge distance-system repository seam, threaded through
  /// `RuniacShell` to `HomeTab` (and the Account badge case) so physical runs
  /// use trusted data. Defaults to the static source for previews/tests.
  final ChallengeRepository challengeRepository;

  /// One-shot foreground Result presenter, threaded to `HomeTab`. `null`
  /// (previews/tests/no-Firebase) disables auto-presentation.
  final ChallengeResultPresentationController? challengeResultPresenter;
  final UserProfileRepository profileRepository;

  /// Read-only seam for the trusted `users/{uid}` account document. A
  /// [LiveUserAccountRepository] makes admin-side subscription changes appear
  /// without an app restart; the static default reports the Basic tier.
  final UserAccountRepository userAccountRepository;

  /// Read-only seam for the admin-published `config/paywall` display copy.
  /// The static default reports the built-in paywall defaults instantly.
  final PaywallConfigRepository paywallConfigRepository;

  /// Read-only seam for the admin-published `config/featureAccess` premium
  /// feature checklist shown by the upsell section.
  final FeatureAccessRepository featureAccessRepository;

  /// Read-only seam for the admin-published `config/characterAccess` premium
  /// guide-character list the picker locks for Basic runners.
  final CharacterAccessRepository characterAccessRepository;
  final UserProfilePersistenceRepository profilePersistenceRepository;
  final GeneratedPlanPersistenceRepository generatedPlanPersistenceRepository;
  final PlanProgressRepository planProgressRepository;

  /// Local one-shot marker for the plan-completion ceremony, forwarded to the
  /// shell. `null` (previews/tests) disables the celebration.
  final PlanCompletionSeenStore? planCompletionSeenStore;

  /// Local, device-only record of whether the one-time app tour is armed and
  /// completed, forwarded to the shell. `null` (previews/tests) disables the
  /// tour entirely.
  final AppTourSeenStore? appTourSeenStore;
  final AdaptivePlanEstimateRepository adaptivePlanEstimateRepository;
  final NotificationInboxRepository notificationInboxRepository;

  /// Best-effort mirror of the derived Social-activity boolean into
  /// `notificationPreferences/{uid}`, forwarded to `RuniacShell`.
  final NotificationPreferenceMirror notificationPreferenceMirror;
  final NotificationRegistrationService? notificationRegistrationService;

  /// Guide seam forwarded down to `HomeTab`'s stage-map speech bubble.
  final HomeGuideAgent homeGuideAgent;
  final HomeGuideConsentRepository homeGuideConsentRepository;
  final bool enableForegroundGps;
  final ActiveRunSessionCoordinator? activeRunSessionCoordinator;
  final RunOpenIntent? initialRunOpenIntent;
  final CurrentSessionActivityHistoryStore? currentSessionActivityHistoryStore;
  final CurrentSessionFeedStore? currentSessionFeedStore;
  final FeedRepository? feedRepository;
  final CurrentSessionGeneratedPlanStore? currentSessionGeneratedPlanStore;
  final PersonalProfileDraft? initialPersonalProfileDraft;
  final ValueChanged<LocalOnboardingDraft>? onOnboardingCompleted;
  final DateTime? youProgressToday;

  @override
  State<RuniacApp> createState() => _RuniacAppState();
}

class _RuniacAppState extends State<RuniacApp> {
  late final CurrentSessionActivityHistoryStore _activityHistoryStore;
  late final bool _ownsActivityHistoryStore;
  late final CurrentSessionUserProgress _userProgressStore;
  late final CurrentSessionUserAccount _userAccountStore;
  late final CurrentSessionPaywallConfig _paywallConfigStore;
  late final CurrentSessionFeatureAccess _featureAccessStore;
  late final CurrentSessionCharacterAccess _characterAccessStore;
  late final CurrentSessionFeedStore _feedStore;
  late final bool _ownsFeedStore;
  late FeedRepository _feedRepository;
  var _ownsFeedRepository = false;
  late final CurrentSessionGeneratedPlanStore _generatedPlanStore;
  late final bool _ownsGeneratedPlanStore;
  RuniacAuthCompletion? _authCompletion;
  PersonalProfileDraft? _personalProfileDraft;
  String? _generatedPlanOwnerUid;
  String? _generatedPlanHydrationProbeUid;
  PlanProgressReadModel? _planProgress;
  var _planProgressLoadSerial = 0;

  /// Read by the run flow's "Home" action so a plan finished on this run lands
  /// the runner on the Home dashboard, where the ceremony is held. Owned here
  /// because this state holds both inputs — the backend-recorded completion and
  /// the one-shot seen marker.
  late final PlanCompletionCelebrationRouter _planCompletionCelebrationRouter =
      PlanCompletionCelebrationRouter(
        isCelebrationPending: _planCompletionCelebrationPending,
      );
  AdaptivePlanEstimateReadModel? _adaptivePlanEstimate;
  var _adaptivePlanEstimateLoadSerial = 0;

  /// Whether onboarding has just finished this session and the app tour is
  /// therefore owed to this user. Forwarded to `RuniacShell` as
  /// `appTourAutoStartArmed` — a session-only accelerator, not a gate: the
  /// durable per-uid "armed"/"completed" markers in `appTourSeenStore` are
  /// the sole authority on whether auto-start is allowed (`armed &&
  /// !completed`), so an existing runner who reinstalls the app (skipping
  /// onboarding, with wiped preferences, hence `armed == false`) is never
  /// ambushed by the tour, and a runner who kills the app mid-tour (this
  /// flag resets to `false` on every restart) still gets it replayed on the
  /// next launch because the durable `armed` flag alone is enough.
  bool _appTourArmed = false;
  String? _authStateError;
  bool _showMissingProfileSignupPrompt = false;

  /// The signed-in account owns no profile document, so onboarding has never
  /// completed for it — an account created on the Runiac website, or an app
  /// signup that was killed before onboarding finished. It takes the same
  /// "Tell us about you" → onboarding path a fresh in-app signup takes, which
  /// is what finally writes that profile document.
  ///
  /// Kept separate from `_authCompletion` on purpose: these runners signed
  /// *in*, and only `RuniacProfileSetupGate` can tell that their setup is
  /// unfinished.
  bool _needsOnboardingSetup = false;
  StreamSubscription<PushNotificationMessage>? _pushNotificationSubscription;
  final SelectedRunnerCharacterStore _selectedCharacterStore =
      SelectedRunnerCharacterStore();
  final LocalSelectedRunnerCharacterStorage _selectedCharacterStorage =
      const SharedPreferencesSelectedRunnerCharacterStorage();
  late final PremiumCharacterEntitlement _characterEntitlement;
  late final ActivityRouteSnapshotThumbnailArtifactLifecycle
  _thumbnailArtifactLifecycle;
  late final SystemRuniacHaptics _haptics = SystemRuniacHaptics();

  @override
  void initState() {
    super.initState();
    _ownsActivityHistoryStore =
        widget.currentSessionActivityHistoryStore == null;
    _activityHistoryStore =
        widget.currentSessionActivityHistoryStore ??
        CurrentSessionActivityHistoryStore(
          ownerUid: widget.authRepository.currentUser?.uid,
          persistence: const SharedPreferencesLocalPendingRunActivityStore(),
          onRemoteRunSynced: _refreshUserProgressAfterRunSync,
        );
    final initialOwnerUid = widget.authRepository.currentUser?.uid;
    _userProgressStore = CurrentSessionUserProgress(
      ownerUid: initialOwnerUid,
      repository: widget.userProgressRepository,
      cacheStore: const SharedPreferencesLocalUserProgressCacheStore(),
      clock: () => widget.youProgressToday ?? DateTime.now(),
    );
    if (initialOwnerUid != null) {
      _scheduleUserProgressLoad(initialOwnerUid);
    }
    _userAccountStore = CurrentSessionUserAccount(
      ownerUid: initialOwnerUid,
      repository: widget.userAccountRepository,
    );
    _paywallConfigStore = CurrentSessionPaywallConfig(
      repository: widget.paywallConfigRepository,
    );
    _featureAccessStore = CurrentSessionFeatureAccess(
      repository: widget.featureAccessRepository,
    );
    _characterAccessStore = CurrentSessionCharacterAccess(
      repository: widget.characterAccessRepository,
    );
    // Watches the live account tier so a lapsed subscription drops a
    // premium-only guide back to a free one without a restart.
    _characterEntitlement = PremiumCharacterEntitlement(
      account: _userAccountStore,
      paywallConfig: _paywallConfigStore,
      characterAccess: _characterAccessStore,
      selectedCharacter: _selectedCharacterStore,
      onReverted: _persistSelectedCharacter,
    )..start();
    _thumbnailArtifactLifecycle =
        ActivityRouteSnapshotThumbnailArtifactLifecycle(
          initialOwnerUid: initialOwnerUid,
        );
    _ownsFeedStore = widget.currentSessionFeedStore == null;
    _feedStore =
        widget.currentSessionFeedStore ??
        CurrentSessionFeedStore(ownerUid: initialOwnerUid);
    if (!_ownsFeedStore) {
      _feedStore.syncOwner(initialOwnerUid);
    }
    _configureFeedRepository(widget.feedRepository);
    if (initialOwnerUid != null) {
      unawaited(_restoreAndSyncPendingRuns(ownerUid: initialOwnerUid));
    }
    _ownsGeneratedPlanStore = widget.currentSessionGeneratedPlanStore == null;
    _generatedPlanStore =
        widget.currentSessionGeneratedPlanStore ??
        CurrentSessionGeneratedPlanStore();
    _personalProfileDraft = widget.initialPersonalProfileDraft;
    _startPushNotificationsForCurrentUser();
    unawaited(
      _restoreSelectedCharacter(widget.authRepository.currentUser?.uid),
    );
    unawaited(_restoreHapticsSetting());
  }

  Future<void> _restoreHapticsSetting() async {
    try {
      final settings = await const SharedPreferencesAppSettingsRepository()
          .loadSettings();
      if (!mounted) {
        return;
      }
      _haptics.setEnabled(settings.hapticFeedbackEnabled);
    } catch (_) {
      // Leave the default (enabled) haptics setting in place; this is a
      // non-critical comfort preference and must never block startup.
    }
  }

  Future<void> _restoreSelectedCharacter(String? uid) async {
    final stored = await _selectedCharacterStorage.readSelectedCharacter(
      uid: uid,
    );
    if (!mounted) {
      return;
    }
    if (stored != null) {
      _selectedCharacterStore.select(stored);
    } else {
      _selectedCharacterStore.clear();
    }
  }

  void _persistSelectedCharacter(RunnerCharacter character) {
    unawaited(
      _selectedCharacterStorage.writeSelectedCharacter(
        uid: widget.authRepository.currentUser?.uid,
        character: character,
      ),
    );
  }

  bool get _shouldShowCharacterSelection =>
      widget.showAuth && _shouldShowOnboarding;

  @override
  void didUpdateWidget(covariant RuniacApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authRepository != widget.authRepository ||
        oldWidget.profileRepository != widget.profileRepository) {
      _authCompletion = null;
      _personalProfileDraft = widget.initialPersonalProfileDraft;
      _needsOnboardingSetup = false;
      final nextOwnerUid = widget.authRepository.currentUser?.uid;
      _thumbnailArtifactLifecycle.syncOwner(nextOwnerUid);
      _syncUserProgressOwner(nextOwnerUid);
      _userAccountStore.updateOwnerUid(nextOwnerUid);
      _scheduleActivityHistoryOwnerSync(nextOwnerUid);
      _feedStore.syncOwner(nextOwnerUid);
    }
    if (oldWidget.feedRepository != widget.feedRepository) {
      _configureFeedRepository(widget.feedRepository);
    }
    if (oldWidget.planProgressRepository != widget.planProgressRepository) {
      final ownerUid = _generatedPlanOwnerUid;
      final activePlan = _generatedPlanStore.activePlan;
      if (ownerUid != null && activePlan != null) {
        unawaited(_loadPlanProgress(ownerUid, activePlan.id));
      }
    }
    if (oldWidget.adaptivePlanEstimateRepository !=
        widget.adaptivePlanEstimateRepository) {
      final ownerUid = _generatedPlanOwnerUid;
      final activePlan = _generatedPlanStore.activePlan;
      if (ownerUid != null && activePlan != null) {
        unawaited(_loadAdaptivePlanEstimate(ownerUid, activePlan.id));
      }
    }
    if (oldWidget.notificationRegistrationService !=
        widget.notificationRegistrationService) {
      unawaited(_cancelPushNotificationSubscription());
      _startPushNotificationsForCurrentUser();
    }
  }

  @override
  void dispose() {
    if (_ownsActivityHistoryStore) {
      _activityHistoryStore.dispose();
    }
    if (_ownsFeedStore) {
      _feedStore.dispose();
    }
    _disposeOwnedFeedRepository();
    if (_ownsGeneratedPlanStore) {
      _generatedPlanStore.dispose();
    }
    // Detaches from the four stores before any of them is disposed.
    _characterEntitlement.dispose();
    _userProgressStore.dispose();
    _userAccountStore.dispose();
    _paywallConfigStore.dispose();
    _featureAccessStore.dispose();
    _characterAccessStore.dispose();
    unawaited(_cancelPushNotificationSubscription());
    unawaited(widget.notificationRegistrationService?.dispose());
    _selectedCharacterStore.dispose();
    super.dispose();
  }

  void _configureFeedRepository(FeedRepository? repository) {
    _disposeOwnedFeedRepository();
    _ownsFeedRepository = repository == null;
    _feedRepository = repository ?? const StaticFeedRepository();
  }

  void _disposeOwnedFeedRepository() {
    if (_ownsFeedRepository && _feedRepository is FeedTimelineRepository) {
      (_feedRepository as FeedTimelineRepository).dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlanCompletionCelebrationScope(
      router: _planCompletionCelebrationRouter,
      child: RuniacHapticsScope(
        haptics: _haptics,
        child: CurrentSessionUserProgressScope(
          store: _userProgressStore,
          child: CurrentSessionUserAccountScope(
            store: _userAccountStore,
            child: PaywallConfigScope(
              store: _paywallConfigStore,
              child: FeatureAccessScope(
                store: _featureAccessStore,
                child: CharacterAccessScope(
                  store: _characterAccessStore,
                  child: CurrentSessionFeedScope(
                    store: _feedStore,
                    child: SelectedRunnerCharacterScope(
                      store: _selectedCharacterStore,
                      child: CurrentSessionActivityHistoryScope(
                        store: _activityHistoryStore,
                        child: CurrentSessionGeneratedPlanScope(
                          store: _generatedPlanStore,
                          child: RunRepositoryScope(
                            repository: widget.runRepository,
                            child: RunnerPublicProfileScope(
                              repository: widget.runnerPublicProfileRepository,
                              child: MaterialApp(
                                debugShowCheckedModeBanner: false,
                                title: 'Runiac',
                                theme: buildRuniacTheme(),
                                navigatorObservers: [runiacErrorScreenTracker],
                                home: RuniacStartupGate(
                                  showSplash: widget.showSplash,
                                  splashDuration: widget.splashDuration,
                                  child: RuniacAuthGate(
                                    authRepository: widget.authRepository,
                                    showAuth: widget.showAuth,
                                    onAuthenticated: (completion) {
                                      final ownerUid =
                                          widget.authRepository.currentUser?.uid;
                                      _syncUserProgressOwner(ownerUid);
                                      _userAccountStore.updateOwnerUid(ownerUid);
                                      _syncFeatureAccessOwner(ownerUid);
                                      setState(() {
                                        _authCompletion = completion;
                                        _authStateError = null;
                                        _showMissingProfileSignupPrompt = false;
                                        _needsOnboardingSetup = false;
                                      });
                                      _startPushNotificationsForCurrentUser();
                                      unawaited(
                                        _restoreSelectedCharacter(ownerUid),
                                      );
                                    },
                                    onAuthStateChanged: (user) {
                                      _thumbnailArtifactLifecycle.syncOwner(
                                        user?.uid,
                                      );
                                      _syncUserProgressOwner(user?.uid);
                                      _userAccountStore.updateOwnerUid(user?.uid);
                                      _syncFeatureAccessOwner(user?.uid);
                                      if (user == null) {
                                        unawaited(
                                          _cancelPushNotificationSubscription(),
                                        );
                                        unawaited(
                                          widget.notificationRegistrationService
                                              ?.unregisterCurrentDevice(),
                                        );
                                        // A sign-out must drop the outgoing
                                        // account's post-auth completion state,
                                        // or the next signup in this same app
                                        // process inherits it: `_authCompletion`
                                        // would already read `signup` and
                                        // `_personalProfileDraft` would already
                                        // be non-null, so `_shouldShowPersonalProfile`
                                        // (which requires a null draft) is false
                                        // from the first frame and the new
                                        // account's "Tell us about you" step is
                                        // skipped entirely.
                                        //
                                        // `RuniacAuthGate` reposts this
                                        // callback on every rebuild, not just
                                        // on a change, so the reset must be a
                                        // no-op once already applied or this
                                        // becomes an unconditional setState
                                        // loop that never lets the widget tree
                                        // settle.
                                        if (_authCompletion != null ||
                                            _personalProfileDraft != null ||
                                            _needsOnboardingSetup) {
                                          setState(() {
                                            _authCompletion = null;
                                            _personalProfileDraft = null;
                                            _needsOnboardingSetup = false;
                                          });
                                        }
                                      }
                                      _scheduleActivityHistoryOwnerSync(
                                        user?.uid,
                                      );
                                      _feedStore.syncOwner(user?.uid);
                                      _clearGeneratedPlanForAuthChange(user?.uid);
                                      unawaited(
                                        _restoreSelectedCharacter(user?.uid),
                                      );
                                    },
                                    recoveryPrompt:
                                        _showMissingProfileSignupPrompt
                                        ? const RuniacAuthRecoveryPrompt.signup(
                                            message:
                                                'No Runiac account setup exists for this account. Sign up to create your profile and start onboarding.',
                                          )
                                        : null,
                                    childBuilder: (_) => _buildPostAuthFlow(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _syncUserProgressOwner(String? ownerUid) {
    _userProgressStore.updateOwnerUid(ownerUid);
    if (ownerUid != null) {
      _scheduleUserProgressLoad(ownerUid);
    }
  }

  /// Loads the admin's `config/featureAccess` policy as soon as a runner is
  /// signed in, and drops it on sign-out.
  ///
  /// The document is signed-in-readable only, and the premium gates
  /// (`interceptWithPaywallIfGated`) consult it synchronously on tap — so the
  /// read has to be in flight before the runner reaches a gated surface,
  /// rather than waiting for the You tab's upsell to mount.
  void _syncFeatureAccessOwner(String? ownerUid) {
    if (ownerUid == null) {
      _featureAccessStore.reset();
      return;
    }
    unawaited(_featureAccessStore.ensureLoaded());
  }

  void _scheduleUserProgressOwnerSync(String? ownerUid) {
    if (_userProgressStore.snapshot.ownerUid == ownerUid) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userProgressStore.snapshot.ownerUid == ownerUid) {
        return;
      }
      _syncUserProgressOwner(ownerUid);
    });
  }

  void _scheduleUserProgressLoad(String ownerUid) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.authRepository.currentUser?.uid != ownerUid) {
        return;
      }
      unawaited(_userProgressStore.load());
    });
  }

  void _clearGeneratedPlanForAuthChange(String? nextOwnerUid) {
    final currentPlanOwnerUid = _generatedPlanOwnerUid;
    final probeUid = _generatedPlanHydrationProbeUid;
    if (currentPlanOwnerUid == nextOwnerUid &&
        (probeUid == null || probeUid == nextOwnerUid)) {
      return;
    }
    _generatedPlanOwnerUid = null;
    _generatedPlanHydrationProbeUid = null;
    _planProgress = null;
    _planProgressLoadSerial += 1;
    _adaptivePlanEstimate = null;
    _adaptivePlanEstimateLoadSerial += 1;
    _generatedPlanStore.clear();
  }

  void _startPushNotificationsForCurrentUser() {
    final service = widget.notificationRegistrationService;
    if (widget.authRepository.currentUser == null || service == null) {
      return;
    }
    _pushNotificationSubscription ??= service.messages.listen(
      _saveReceivedPushNotification,
    );
    unawaited(service.start());
  }

  Future<void> _cancelPushNotificationSubscription() async {
    final subscription = _pushNotificationSubscription;
    _pushNotificationSubscription = null;
    await subscription?.cancel();
  }

  void _saveReceivedPushNotification(PushNotificationMessage message) {
    final title = message.title?.trim();
    final body = message.body?.trim();
    if (message.id.isEmpty || title == null || title.isEmpty) {
      return;
    }

    unawaited(
      widget.notificationInboxRepository
          .saveInboxItem(
            NotificationInboxItem(
              id: message.id,
              title: title,
              body: body == null || body.isEmpty ? title : body,
              createdAt: DateTime.now(),
              data: message.data,
            ),
          )
          .catchError((Object error, StackTrace stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'runiac app',
                context: ErrorDescription(
                  'saving received push notification to inbox',
                ),
              ),
            );
          }),
    );
  }

  Future<void> _restoreAndSyncPendingRuns({required String ownerUid}) async {
    try {
      if (_activityHistoryStore.ownerUid != ownerUid) {
        return;
      }
      await _activityHistoryStore.restoreSavedActivities();
      if (_activityHistoryStore.ownerUid != ownerUid) {
        return;
      }
      await _activityHistoryStore.syncPendingRuns(widget.runRepository);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac app',
          context: ErrorDescription('restoring and syncing pending runs'),
        ),
      );
    }
  }

  Future<UserProgressReadModel> _refreshUserProgressAfterRunSync() async {
    // The synced run may have completed the plan's final scheduled workout,
    // which the backend records on `planProgress/{uid}`. Refresh that too, or
    // a runner finishing their plan with the app already open would keep the
    // stale pre-run value and see no ceremony until the next launch.
    // Deliberately fire-and-forget and ordered first, so it still happens when
    // the user-progress refresh below throws and rethrows.
    _refreshPlanProgressAfterRunSync();
    try {
      final progress = await widget.userProgressRepository
          .refreshUserProgress();
      _userProgressStore.recordRemoteProgress(progress);
      return progress;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac app',
          context: ErrorDescription('refreshing user progress after run sync'),
        ),
      );
      rethrow;
    }
  }

  /// Re-reads backend plan progress after a run syncs. `_loadPlanProgress`
  /// already guards itself with a load serial and swallows its own errors, so
  /// a failure here can never break run syncing.
  void _refreshPlanProgressAfterRunSync() {
    final ownerUid = _generatedPlanOwnerUid;
    final activePlanId = _generatedPlanStore.activePlan?.id;
    if (ownerUid == null || activePlanId == null) {
      return;
    }
    unawaited(_loadPlanProgress(ownerUid, activePlanId));
  }

  Widget _buildPostAuthFlow() {
    final currentUser = widget.authRepository.currentUser;
    _scheduleUserProgressOwnerSync(currentUser?.uid);
    _scheduleActivityHistoryOwnerSync(currentUser?.uid);

    if (_shouldShowPersonalProfile) {
      if (currentUser == null) {
        return _AuthStateErrorScreen(
          message:
              _authStateError ??
              'We could not confirm your account. Please try signing in again.',
        );
      }
      return _buildPersonalProfileCollection(currentUser);
    }

    if (_shouldProbeSignedInProfileSetup(currentUser)) {
      return RuniacProfileSetupGate(
        authRepository: widget.authRepository,
        profileRepository: widget.profileRepository,
        currentUser: currentUser!,
        onLoadedProfile: (profile) {
          unawaited(_hydrateGeneratedPlanFromProfile(profile));
        },
        onProfileSetupIncomplete: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _needsOnboardingSetup = true;
            _showMissingProfileSignupPrompt = false;
          });
        },
        onRecoverableProfileMissing: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _authCompletion = null;
            _personalProfileDraft = null;
            _showMissingProfileSignupPrompt = true;
          });
        },
        child: _buildOnboardingAndShell(),
      );
    }

    if (currentUser != null) {
      _scheduleGeneratedPlanRepositoryHydration(currentUser.uid);
    }

    return _buildOnboardingAndShell();
  }

  void _scheduleGeneratedPlanRepositoryHydration(String ownerUid) {
    if (_generatedPlanHydrationProbeUid == ownerUid ||
        _generatedPlanOwnerUid == ownerUid) {
      return;
    }
    _generatedPlanHydrationProbeUid = ownerUid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_restoreGeneratedPlanForOwner(ownerUid));
      }
    });
  }

  Future<void> _restoreGeneratedPlanForOwner(String ownerUid) async {
    BeginnerAdaptivePlanSnapshot? persistedPlan;
    try {
      persistedPlan = await widget.generatedPlanPersistenceRepository
          .loadGeneratedPlan(uid: ownerUid);
    } catch (_) {
      persistedPlan = null;
    }
    final stillCurrentUser = widget.authRepository.currentUser;
    if (!mounted ||
        stillCurrentUser?.uid != ownerUid ||
        persistedPlan == null) {
      return;
    }
    _setActiveGeneratedPlan(persistedPlan, ownerUid: ownerUid);
  }

  void _scheduleActivityHistoryOwnerSync(String? ownerUid) {
    if (_activityHistoryStore.ownerUid == ownerUid) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_activityHistoryStore.ownerUid == ownerUid) {
        return;
      }
      _activityHistoryStore.updateOwnerUid(ownerUid);
      if (ownerUid != null) {
        unawaited(_restoreAndSyncPendingRuns(ownerUid: ownerUid));
      }
    });
  }

  Widget _buildOnboardingAndShell() {
    return RuniacCharacterSelectionGate(
      active: _shouldShowCharacterSelection,
      store: _selectedCharacterStore,
      onCharacterConfirmed: _persistSelectedCharacter,
      child: RuniacOnboardingGate(
        showOnboarding: _shouldShowOnboarding,
        onCompletedDraft: _completeOnboarding,
        child: RuniacShell(
          authRepository: widget.authRepository,
          activityHistoryRepository: widget.activityHistoryRepository,
          feedRepository: _feedRepository,
          userProgressRepository: widget.userProgressRepository,
          leaderboardRepository: widget.leaderboardRepository,
          friendsRepository: widget.friendsRepository,
          challengeRepository: widget.challengeRepository,
          challengeResultPresenter: widget.challengeResultPresenter,
          profileRepository: widget.profileRepository,
          profilePersistenceRepository: widget.profilePersistenceRepository,
          generatedPlanPersistenceRepository:
              widget.generatedPlanPersistenceRepository,
          notificationInboxRepository: widget.notificationInboxRepository,
          notificationPreferenceMirror: widget.notificationPreferenceMirror,
          planProgress: _planProgress,
          planCompletionSeenStore: widget.planCompletionSeenStore,
          appTourSeenStore: widget.appTourSeenStore,
          appTourAutoStartArmed: _appTourArmed,
          adaptivePlanEstimate: _adaptivePlanEstimate,
          homeGuideAgent: widget.homeGuideAgent,
          homeGuideConsentRepository: widget.homeGuideConsentRepository,
          enableForegroundGps: widget.enableForegroundGps,
          activeRunSessionCoordinator: widget.activeRunSessionCoordinator,
          initialRunOpenIntent: widget.initialRunOpenIntent,
          youProgressToday: widget.youProgressToday,
          enableLocalPlanNotifications:
              defaultTargetPlatform == TargetPlatform.iOS,
        ),
      ),
    );
  }

  Widget _buildPersonalProfileCollection(RuniacAuthUser currentUser) {
    return PersonalProfileCollectionScreen(
      uid: currentUser.uid,
      emailLabel: currentUser.email ?? 'Email unavailable',
      persistenceRepository: widget.profilePersistenceRepository,
      onComplete: (draft) {
        setState(() {
          _personalProfileDraft = draft;
        });
      },
    );
  }

  Future<void> _hydrateGeneratedPlanFromProfile(
    UserProfileReadModel profile,
  ) async {
    final currentUser = widget.authRepository.currentUser;
    if (currentUser != null) {
      final hydratedUid = currentUser.uid;
      BeginnerAdaptivePlanSnapshot? persistedPlan;
      try {
        persistedPlan = await widget.generatedPlanPersistenceRepository
            .loadGeneratedPlan(uid: hydratedUid);
      } catch (_) {
        persistedPlan = null;
      }
      final stillCurrentUser = widget.authRepository.currentUser;
      if (!mounted || stillCurrentUser?.uid != hydratedUid) {
        return;
      }
      if (persistedPlan != null) {
        _setActiveGeneratedPlan(persistedPlan, ownerUid: hydratedUid);
        return;
      }
    }

    final draft = profile.onboardingDraft;
    if (draft == null) {
      return;
    }
    final snapshot = const BeginnerAdaptivePlanGenerator()
        .generate(draft)
        .withStartsOnDate(generatedPlanDateLabel(DateTime.now()));
    _setActiveGeneratedPlan(snapshot, ownerUid: currentUser?.uid);
  }

  Future<bool> _completeOnboarding(LocalOnboardingDraft draft) async {
    final snapshot = const BeginnerAdaptivePlanGenerator()
        .generate(draft)
        .withStartsOnDate(generatedPlanDateLabel(_generatedPlanStartDate()));
    final currentUser = widget.authRepository.currentUser;
    if (currentUser != null) {
      final saved = await _saveOnboardingProfile(currentUser.uid, draft);
      if (!saved) {
        return false;
      }
      final savedPlan = await _saveGeneratedPlan(currentUser.uid, snapshot);
      if (!savedPlan) {
        return false;
      }
    }
    _setActiveGeneratedPlan(snapshot, ownerUid: currentUser?.uid);
    widget.onOnboardingCompleted?.call(draft);
    // `armed` is the durable "onboarding just finished, tour still owed"
    // marker. This is fire-and-forget: a missing store or a write failure
    // must never block, delay, or fail onboarding completion.
    unawaited(
      widget.appTourSeenStore
          ?.setArmed(uid: currentUser?.uid, armed: true)
          .catchError((_) {}),
    );
    if (mounted) {
      setState(() => _appTourArmed = true);
    }
    return true;
  }

  DateTime _generatedPlanStartDate() {
    final currentDate = widget.youProgressToday;
    if (currentDate != null) {
      return DateTime(currentDate.year, currentDate.month, currentDate.day);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _setActiveGeneratedPlan(
    BeginnerAdaptivePlanSnapshot snapshot, {
    required String? ownerUid,
  }) {
    _generatedPlanOwnerUid = ownerUid;
    if (!_generatedPlanStore.setActivePlan(snapshot)) {
      _generatedPlanOwnerUid = null;
      _planProgress = null;
      _planProgressLoadSerial += 1;
      _adaptivePlanEstimate = null;
      _adaptivePlanEstimateLoadSerial += 1;
      _generatedPlanStore.clear();
      return;
    }
    if (ownerUid == null) {
      _planProgress = null;
      _planProgressLoadSerial += 1;
      _adaptivePlanEstimate = null;
      _adaptivePlanEstimateLoadSerial += 1;
      return;
    }
    unawaited(_loadPlanProgress(ownerUid, snapshot.id));
    unawaited(_loadAdaptivePlanEstimate(ownerUid, snapshot.id));
  }

  Future<void> _loadPlanProgress(
    String ownerUid,
    String activeGeneratedPlanId,
  ) async {
    final loadSerial = _planProgressLoadSerial + 1;
    _planProgressLoadSerial = loadSerial;
    final progress = await widget.planProgressRepository.loadPlanProgress(
      uid: ownerUid,
      activeGeneratedPlanId: activeGeneratedPlanId,
    );
    if (!mounted ||
        loadSerial != _planProgressLoadSerial ||
        _generatedPlanOwnerUid != ownerUid ||
        _generatedPlanStore.activePlan?.id != activeGeneratedPlanId) {
      return;
    }
    setState(() {
      // A completion is retained even with no per-workout ids, so the
      // plan-completion signal is never collapsed away by the "no progress
      // worth showing" shortcut.
      _planProgress =
          progress.completedScheduledWorkoutIds.isEmpty &&
              progress.planCompletedAt == null
          ? null
          : progress;
    });
  }

  /// Mirrors `HomeTab`'s own guard: a completion the backend has recorded for
  /// the active plan, which the local one-shot marker has not yet spent. The
  /// marker is deliberately not advanced here — `HomeTab` spends it, and only
  /// once the overlay is actually being opened.
  Future<bool> _planCompletionCelebrationPending() async {
    final seenStore = widget.planCompletionSeenStore;
    final completedAt = _planProgress?.planCompletedAt;
    if (seenStore == null || completedAt == null) {
      return false;
    }
    final lastSeenMs = await seenStore.lastSeenPlanCompletedAtMs();
    return lastSeenMs == null ||
        completedAt.millisecondsSinceEpoch > lastSeenMs;
  }

  Future<void> _loadAdaptivePlanEstimate(
    String ownerUid,
    String activeGeneratedPlanId,
  ) async {
    final loadSerial = _adaptivePlanEstimateLoadSerial + 1;
    _adaptivePlanEstimateLoadSerial = loadSerial;
    final estimate = await widget.adaptivePlanEstimateRepository
        .loadAdaptivePlanEstimate(uid: ownerUid);
    if (!mounted ||
        loadSerial != _adaptivePlanEstimateLoadSerial ||
        _generatedPlanOwnerUid != ownerUid ||
        _generatedPlanStore.activePlan?.id != activeGeneratedPlanId) {
      return;
    }
    setState(() {
      _adaptivePlanEstimate = estimate.isUsableForPlannedRun ? estimate : null;
    });
  }

  Future<bool> _saveOnboardingProfile(
    String uid,
    LocalOnboardingDraft draft,
  ) async {
    try {
      await widget.profilePersistenceRepository.saveOnboardingProfile(
        uid: uid,
        profile: _profileSnapshotFromDraft(draft),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _saveGeneratedPlan(
    String uid,
    BeginnerAdaptivePlanSnapshot snapshot,
  ) async {
    try {
      await widget.generatedPlanPersistenceRepository.saveGeneratedPlan(
        uid: uid,
        plan: snapshot,
        resetCreatedAt: true,
      );
      return true;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac app',
          context: ErrorDescription('saving generated onboarding plan'),
        ),
      );
      return false;
    }
  }

  UserProfileOnboardingSnapshot _profileSnapshotFromDraft(
    LocalOnboardingDraft draft,
  ) {
    final personalProfile = _personalProfileDraft;
    final displayName = personalProfile?.displayName ?? 'Runiac Runner';
    final fullName = personalProfile?.fullName ?? 'Runiac Runner';
    final nickname = personalProfile?.nickname ?? 'Runiac Runner';
    final avatarInitials = personalProfile?.avatarInitials ?? 'RR';
    final dateOfBirthIso = personalProfile?.dateOfBirthIso ?? '2008-01-01';
    final ageYears = personalProfile?.ageYears ?? 18;
    final weightKg = personalProfile?.weightKg ?? 60;
    final locationLabel = personalProfile?.locationLabel ?? 'Not set yet';
    return UserProfileOnboardingSnapshot(
      displayName: displayName,
      fullName: fullName,
      nickname: nickname,
      avatarInitials: avatarInitials,
      dateOfBirthIso: dateOfBirthIso,
      ageYears: ageYears,
      weightKg: weightKg,
      locationLabel: locationLabel,
      fitnessLevel: draft.experience.value,
      goals: <String>[draft.goal.value],
      availability: <String, Object>{
        'weeklySessions': draft.availability.value,
        'preferredDays': draft.preferredDays
            .map((day) => day.value)
            .toList(growable: false),
        'preferredTime': draft.preferredTime.value,
        'sessionLengthMinutes': draft.sessionLength.value,
      },
      planCautiousness: draft.planStyle.value,
      healthSafetyReadiness: <String, Object>{
        'comfort': draft.healthComfort.value,
        'activitySymptoms': draft.activitySymptoms
            .map((symptom) => symptom.value)
            .toList(growable: false),
        'recentRunningConsistency': draft.recentRunningConsistency.value,
        'currentWeeklyRunFrequency': draft.currentWeeklyRunFrequency.value,
        'continuousRunCapacity': draft.continuousRunCapacity.value,
        'runningPlace': draft.runningPlace.value,
        'motivationStyle': draft.motivationStyle.value,
      },
    );
  }

  /// Whether this session still owes the account its one-time setup: a fresh
  /// in-app signup, or a sign-in the profile-setup gate found to have no
  /// profile document (website signup, or an abandoned in-app signup).
  bool get _accountNeedsProfileSetup =>
      _authCompletion == RuniacAuthCompletion.signup || _needsOnboardingSetup;

  bool get _shouldShowOnboarding {
    if (!widget.showOnboarding) {
      return false;
    }
    if (!widget.showAuth) {
      return true;
    }
    return _accountNeedsProfileSetup && _personalProfileDraft != null;
  }

  bool get _shouldShowPersonalProfile {
    return widget.showAuth &&
        widget.showOnboarding &&
        _accountNeedsProfileSetup &&
        _personalProfileDraft == null;
  }

  bool _shouldProbeSignedInProfileSetup(RuniacAuthUser? currentUser) {
    return widget.showAuth &&
        widget.showOnboarding &&
        currentUser != null &&
        !_accountNeedsProfileSetup &&
        _personalProfileDraft == null;
  }
}

class _AuthStateErrorScreen extends StatelessWidget {
  const _AuthStateErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
