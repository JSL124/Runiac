import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../features/profile/data/cloud_functions_runner_public_profile_repository.dart';
import '../../features/profile/data/firestore_user_account_repository.dart';
import '../../features/profile/data/firestore_user_profile_persistence_repository.dart';
import '../../features/profile/data/firestore_user_profile_repository.dart';
import '../../features/profile/data/static_user_profile_repository.dart';
import '../../features/profile/domain/repositories/runner_public_profile_repository.dart';
import '../../features/profile/domain/repositories/user_account_repository.dart';
import '../../features/profile/domain/repositories/user_profile_persistence_repository.dart';
import '../../features/profile/domain/repositories/user_profile_repository.dart';
import '../../features/auth/data/firebase_runiac_auth_repository.dart';
import '../../features/auth/data/non_production_auth_repository.dart';
import '../../features/auth/domain/runiac_auth_service.dart';
import '../../features/challenge/data/durable_challenge_result_seen_store.dart';
import '../../features/challenge/data/firebase_challenge_repository.dart';
import '../../features/challenge/data/firestore_challenge_read_store.dart';
import '../../features/challenge/data/firestore_challenge_result_seen_store.dart';
import '../../features/challenge/data/shared_preferences_challenge_result_seen_store.dart';
import '../../features/challenge/data/static_challenge_repository.dart';
import '../../features/challenge/domain/repositories/challenge_repository.dart';
import '../../features/challenge/presentation/challenge_result_presentation_controller.dart';
import '../../features/feed/data/firebase_feed_repository/firebase_feed_data_port.dart';
import '../../features/feed/data/firebase_feed_repository/firebase_feed_repository.dart';
import '../../features/feed/data/static_feed_repository.dart';
import '../../features/feed/domain/repositories/feed_repository.dart';
import '../../features/friends/data/firebase_friends_repository.dart';
import '../../features/friends/data/static_friends_repository.dart';
import '../../features/friends/domain/repositories/friends_repository.dart';
import '../../features/home/data/home_guide_agent_factory.dart';
import '../../features/home/data/cloud_function_home_guide_consent_repository.dart';
import '../../features/home/domain/guide/home_guide_consent.dart';
import '../../features/home/domain/guide/home_guide_agent.dart';
import '../../features/leaderboard/data/firestore_leaderboard_repository.dart';
import '../../features/leaderboard/data/static_leaderboard_repository.dart';
import '../../features/leaderboard/domain/repositories/leaderboard_repository.dart';
import '../../features/notifications/data/cloud_firestore_notification_inbox_document_store.dart';
import '../../features/notifications/data/cloud_functions_notification_device_callable.dart';
import '../../features/notifications/data/firebase_messaging_push_notification_client.dart';
import '../../features/notifications/data/firestore_notification_inbox_repository.dart';
import '../../features/notifications/data/firestore_notification_preference_mirror.dart';
import '../../features/notifications/domain/repositories/notification_inbox_repository.dart';
import '../../features/notifications/domain/repositories/notification_preference_mirror.dart';
import '../../features/notifications/domain/services/notification_registration_service.dart';
import '../../features/paywall/data/firestore_character_access_repository.dart';
import '../../features/paywall/data/firestore_feature_access_repository.dart';
import '../../features/paywall/data/firestore_paywall_config_repository.dart';
import '../../features/paywall/domain/repositories/character_access_repository.dart';
import '../../features/paywall/domain/repositories/feature_access_repository.dart';
import '../../features/paywall/domain/repositories/paywall_config_repository.dart';
import '../../features/plan/data/firestore_adaptive_plan_estimate_repository.dart';
import '../../features/plan/data/firestore_generated_plan_persistence_repository.dart';
import '../../features/plan/data/firestore_plan_progress_repository.dart';
import '../../features/plan/data/shared_preferences_plan_completion_seen_store.dart';
import '../../features/plan/domain/plan_completion_seen_store.dart';
import '../../features/plan/domain/repositories/adaptive_plan_estimate_repository.dart';
import '../../features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import '../../features/plan/domain/repositories/plan_progress_repository.dart';
import '../../features/run/data/run_repository_factory.dart';
import '../../features/run/domain/repositories/run_repository.dart';
import '../../features/tutorial/data/shared_preferences_app_tour_seen_store.dart';
import '../../features/tutorial/domain/app_tour_seen_store.dart';
import '../../features/you/data/firestore_activity_history_repository.dart';
import '../../features/you/data/firestore_user_progress_repository.dart';
import '../../features/you/data/user_streak_refresh_service.dart';
import '../../features/you/data/static_activity_history_repository.dart';
import '../../features/you/domain/repositories/activity_history_repository.dart';
import '../../features/you/domain/repositories/user_progress_repository.dart';
import 'runiac_firestore_gateway.dart';

class RuniacFirebaseBootstrap {
  const RuniacFirebaseBootstrap._();

  static const emulatorFirebaseOptions = FirebaseOptions(
    apiKey: 'AIzaSyA00000000000000000000000000000000',
    appId: '1:000000000000:ios:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-runiac-feed',
    storageBucket: 'demo-runiac-feed.appspot.com',
  );

  static Future<RuniacFirebaseBootstrapResult> initialize({
    RuniacFirebaseRuntimeConfig? config,
    bool enableAnonymousEmulatorSignIn = true,
    RuniacFirestoreConnector? firestoreConnector,
  }) async {
    final runtimeConfig =
        config ?? RuniacFirebaseRuntimeConfig.fromEnvironment();
    if (!runtimeConfig.useFirebaseEmulator) {
      final productionOptions = _productionOptionsFor(runtimeConfig);
      if (productionOptions == null) {
        return RuniacFirebaseBootstrapResult(
          runRepository: RunRepositoryFactory.create(config: runtimeConfig),
          homeGuideAgent: HomeGuideAgentFactory.create(config: runtimeConfig),
          homeGuideConsentRepository:
              const AlwaysGrantedHomeGuideConsentRepository(),
          authRepository: const NonProductionAuthRepository(),
          activityHistoryRepository: const StaticActivityHistoryRepository(),
          userProgressRepository: const StaticUserProgressRepository(),
          leaderboardRepository: const StaticLeaderboardRepository(),
          friendsRepository: const StaticFriendsRepository(),
          profileRepository: const StaticUserProfileRepository(),
          userAccountRepository: const StaticUserAccountRepository(),
          runnerPublicProfileRepository:
              const UnavailableRunnerPublicProfileRepository(),
          paywallConfigRepository: const StaticPaywallConfigRepository(),
          featureAccessRepository: const StaticFeatureAccessRepository(),
          characterAccessRepository: const StaticCharacterAccessRepository(),
          profilePersistenceRepository:
              const NoopUserProfilePersistenceRepository(),
          generatedPlanPersistenceRepository:
              const NoopGeneratedPlanPersistenceRepository(),
          planProgressRepository: const NoopPlanProgressRepository(),
          planCompletionSeenStore: null,
          appTourSeenStore: null,
          adaptivePlanEstimateRepository:
              const NoopAdaptivePlanEstimateRepository(),
          feedRepository: const StaticFeedRepository(),
          notificationInboxRepository:
              const StaticNotificationInboxRepository(),
          notificationPreferenceMirror:
              const NoopNotificationPreferenceMirror(),
          notificationRegistrationService: null,
          challengeRepository: const StaticChallengeRepository(),
          challengeResultPresenter: null,
          firestoreGateway: RuniacFirestoreGateway.configure(
            useFirebaseEmulator: runtimeConfig.useFirebaseEmulator,
            emulatorHost: runtimeConfig.emulatorHost,
            connector: firestoreConnector,
          ),
        );
      }
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: productionOptions);
      }
      final firebaseAuth = FirebaseAuth.instance;
      final authRepository = FirebaseRuniacAuthRepository(
        firebaseAuth: firebaseAuth,
      );
      final firestoreGateway = RuniacFirestoreGateway.configure(
        useFirebaseEmulator: runtimeConfig.useFirebaseEmulator,
        emulatorHost: runtimeConfig.emulatorHost,
        connector: firestoreConnector,
      );
      final challengeRepository = _firebaseChallengeRepository(authRepository);
      return RuniacFirebaseBootstrapResult(
        runRepository: RunRepositoryFactory.create(config: runtimeConfig),
        homeGuideAgent: HomeGuideAgentFactory.create(config: runtimeConfig),
        homeGuideConsentRepository: CloudFunctionHomeGuideConsentRepository(),
        authRepository: authRepository,
        challengeRepository: challengeRepository,
        challengeResultPresenter: _challengeResultPresenter(
          challengeRepository,
          authRepository,
        ),
        activityHistoryRepository: FirestoreActivityHistoryRepository(
          authRepository: authRepository,
        ),
        userProgressRepository: FirestoreUserProgressRepository(
          authRepository: authRepository,
          streakRefreshService: CloudFunctionUserStreakRefreshService(),
        ),
        leaderboardRepository: FirestoreLeaderboardRepository(
          authRepository: authRepository,
        ),
        friendsRepository: FirebaseFriendsRepository(
          authRepository: authRepository,
        ),
        profileRepository: FirestoreUserProfileRepository(
          authRepository: authRepository,
        ),
        userAccountRepository: FirestoreUserAccountRepository(
          authRepository: authRepository,
        ),
        runnerPublicProfileRepository:
            CloudFunctionsRunnerPublicProfileRepository(),
        paywallConfigRepository: FirestorePaywallConfigRepository(),
        featureAccessRepository: FirestoreFeatureAccessRepository(),
        characterAccessRepository: FirestoreCharacterAccessRepository(),
        profilePersistenceRepository:
            FirestoreUserProfilePersistenceRepository(),
        generatedPlanPersistenceRepository:
            FirestoreGeneratedPlanPersistenceRepository(),
        planProgressRepository: FirestorePlanProgressRepository(),
        planCompletionSeenStore: SharedPreferencesPlanCompletionSeenStore(
          uidProvider: () => authRepository.currentUser?.uid,
        ),
        appTourSeenStore: const SharedPreferencesAppTourSeenStore(),
        adaptivePlanEstimateRepository:
            FirestoreAdaptivePlanEstimateRepository(),
        feedRepository: FirebaseFeedRepository(port: FirebaseFeedDataPort()),
        notificationInboxRepository: FirestoreNotificationInboxRepository(
          ownerUidProvider: () => authRepository.currentUser?.uid,
          documentStore: CloudFirestoreNotificationInboxDocumentStore(),
        ),
        notificationPreferenceMirror: FirestoreNotificationPreferenceMirror(),
        notificationRegistrationService: NotificationRegistrationService(
          client: FirebaseMessagingPushNotificationClient(),
          callable: CloudFunctionsNotificationDeviceCallable(),
          ownerUidProvider: () => authRepository.currentUser?.uid,
          applePushRegistrationEnabled:
              runtimeConfig.enableIosPushNotifications,
        ),
        firestoreGateway: firestoreGateway,
      );
    }

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: firebaseOptionsForEmulator(runtimeConfig),
      );
    }

    final firebaseAuth = FirebaseAuth.instance;
    await _useAuthEmulator(firebaseAuth, runtimeConfig);
    FirebaseFunctions.instanceFor(
      region: 'asia-southeast1',
    ).useFunctionsEmulator(runtimeConfig.emulatorHost, 5001);
    FirebaseStorage.instance.useStorageEmulator(
      runtimeConfig.emulatorHost,
      9199,
    );
    final firestoreGateway = RuniacFirestoreGateway.configure(
      useFirebaseEmulator: runtimeConfig.useFirebaseEmulator,
      emulatorHost: runtimeConfig.emulatorHost,
      connector: firestoreConnector,
    );

    if (enableAnonymousEmulatorSignIn && firebaseAuth.currentUser == null) {
      await firebaseAuth.signInAnonymously();
    }

    final authRepository = FirebaseRuniacAuthRepository(
      firebaseAuth: firebaseAuth,
    );
    final challengeRepository = _firebaseChallengeRepository(authRepository);

    return RuniacFirebaseBootstrapResult(
      runRepository: RunRepositoryFactory.create(config: runtimeConfig),
      homeGuideAgent: HomeGuideAgentFactory.create(config: runtimeConfig),
      homeGuideConsentRepository: CloudFunctionHomeGuideConsentRepository(),
      authRepository: authRepository,
      challengeRepository: challengeRepository,
      challengeResultPresenter: _challengeResultPresenter(
        challengeRepository,
        authRepository,
      ),
      activityHistoryRepository: FirestoreActivityHistoryRepository(
        authRepository: authRepository,
      ),
      userProgressRepository: FirestoreUserProgressRepository(
        authRepository: authRepository,
        streakRefreshService: CloudFunctionUserStreakRefreshService(),
      ),
      leaderboardRepository: FirestoreLeaderboardRepository(
        authRepository: authRepository,
      ),
      friendsRepository: FirebaseFriendsRepository(
        authRepository: authRepository,
      ),
      profileRepository: FirestoreUserProfileRepository(
        authRepository: authRepository,
      ),
      userAccountRepository: FirestoreUserAccountRepository(
        authRepository: authRepository,
      ),
      runnerPublicProfileRepository:
          CloudFunctionsRunnerPublicProfileRepository(),
      paywallConfigRepository: FirestorePaywallConfigRepository(),
      featureAccessRepository: FirestoreFeatureAccessRepository(),
      characterAccessRepository: FirestoreCharacterAccessRepository(),
      profilePersistenceRepository: FirestoreUserProfilePersistenceRepository(),
      generatedPlanPersistenceRepository:
          FirestoreGeneratedPlanPersistenceRepository(),
      planProgressRepository: FirestorePlanProgressRepository(),
      planCompletionSeenStore: SharedPreferencesPlanCompletionSeenStore(
        uidProvider: () => authRepository.currentUser?.uid,
      ),
      appTourSeenStore: const SharedPreferencesAppTourSeenStore(),
      adaptivePlanEstimateRepository: FirestoreAdaptivePlanEstimateRepository(),
      feedRepository: FirebaseFeedRepository(port: FirebaseFeedDataPort()),
      notificationInboxRepository: FirestoreNotificationInboxRepository(
        ownerUidProvider: () => authRepository.currentUser?.uid,
        documentStore: CloudFirestoreNotificationInboxDocumentStore(),
      ),
      notificationPreferenceMirror: FirestoreNotificationPreferenceMirror(),
      notificationRegistrationService: NotificationRegistrationService(
        client: FirebaseMessagingPushNotificationClient(),
        callable: CloudFunctionsNotificationDeviceCallable(),
        ownerUidProvider: () => authRepository.currentUser?.uid,
        applePushRegistrationEnabled: runtimeConfig.enableIosPushNotifications,
      ),
      firestoreGateway: firestoreGateway,
    );
  }

  /// Callable-backed Challenge repository with the member-scoped Firestore read
  /// store for the two read paths (history, badges) that have no callable.
  static ChallengeRepository _firebaseChallengeRepository(
    RuniacAuthRepository authRepository,
  ) {
    return FirebaseChallengeRepository(
      currentUid: () => authRepository.currentUser?.uid,
      readStore: FirestoreChallengeReadStore(),
    );
  }

  /// One-shot foreground Result presenter with an account-scoped seen-marker
  /// mirrored into device preferences.
  ///
  /// The marker used to be local only, which made "presented exactly once" a
  /// per-installation promise: deleting and reinstalling the app dropped it and
  /// replayed the badge ceremony for any result still inside the presenter's
  /// recency window. The account copy is now authoritative; the local mirror
  /// keeps the check instant and correct offline.
  static ChallengeResultPresentationController _challengeResultPresenter(
    ChallengeRepository challengeRepository,
    RuniacAuthRepository authRepository,
  ) {
    return ChallengeResultPresentationController(
      repository: challengeRepository,
      seenStore: DurableChallengeResultSeenStore(
        remote: FirestoreChallengeResultSeenStore(
          uidProvider: () => authRepository.currentUser?.uid,
        ),
        local: SharedPreferencesChallengeResultSeenStore(
          uidProvider: () => authRepository.currentUser?.uid,
        ),
      ),
    );
  }

  static Future<void> _useAuthEmulator(
    FirebaseAuth firebaseAuth,
    RuniacFirebaseRuntimeConfig runtimeConfig,
  ) {
    return firebaseAuth.useAuthEmulator(runtimeConfig.emulatorHost, 9099);
  }

  /// The Firebase app identity an emulator run should use.
  ///
  /// Prefers the real project's options when they are supplied, because
  /// App Check is the one component that never talks to the emulator: it
  /// exchanges a token with the real `firebaseappcheck.googleapis.com`. With
  /// the placeholder project that exchange can only fail, and the iOS
  /// Firestore SDK turns an App Check failure into a watch-stream error and
  /// never opens its connection — every emulator read then fails with
  /// "client is offline". Real options + the registered debug token make the
  /// exchange succeed; all data traffic still goes to the emulator hosts
  /// configured right below.
  static FirebaseOptions firebaseOptionsForEmulator(
    RuniacFirebaseRuntimeConfig runtimeConfig,
  ) {
    return _productionOptionsFor(runtimeConfig) ?? emulatorFirebaseOptions;
  }

  static FirebaseOptions? _productionOptionsFor(
    RuniacFirebaseRuntimeConfig runtimeConfig,
  ) {
    if (!runtimeConfig.useProductionFirebase) {
      return null;
    }

    if (runtimeConfig.productionApiKey.isEmpty ||
        runtimeConfig.productionAppId.isEmpty ||
        runtimeConfig.productionMessagingSenderId.isEmpty ||
        runtimeConfig.productionProjectId.isEmpty) {
      throw StateError(
        'Production Firebase requires RUNIAC_FIREBASE_API_KEY, '
        'RUNIAC_FIREBASE_APP_ID, RUNIAC_FIREBASE_MESSAGING_SENDER_ID, and '
        'RUNIAC_FIREBASE_PROJECT_ID dart-defines.',
      );
    }

    return FirebaseOptions(
      apiKey: runtimeConfig.productionApiKey,
      appId: runtimeConfig.productionAppId,
      messagingSenderId: runtimeConfig.productionMessagingSenderId,
      projectId: runtimeConfig.productionProjectId,
      storageBucket: runtimeConfig.productionStorageBucket.isEmpty
          ? null
          : runtimeConfig.productionStorageBucket,
    );
  }
}

class RuniacFirebaseBootstrapResult {
  const RuniacFirebaseBootstrapResult({
    required this.runRepository,
    required this.homeGuideAgent,
    required this.homeGuideConsentRepository,
    required this.authRepository,
    required this.activityHistoryRepository,
    required this.userProgressRepository,
    required this.leaderboardRepository,
    required this.friendsRepository,
    required this.profileRepository,
    required this.userAccountRepository,
    required this.runnerPublicProfileRepository,
    required this.paywallConfigRepository,
    required this.featureAccessRepository,
    required this.characterAccessRepository,
    required this.profilePersistenceRepository,
    required this.generatedPlanPersistenceRepository,
    required this.planProgressRepository,
    required this.planCompletionSeenStore,
    required this.appTourSeenStore,
    required this.adaptivePlanEstimateRepository,
    required this.feedRepository,
    required this.notificationInboxRepository,
    required this.notificationPreferenceMirror,
    required this.notificationRegistrationService,
    required this.challengeRepository,
    required this.challengeResultPresenter,
    required this.firestoreGateway,
  });

  final RunRepository runRepository;
  final HomeGuideAgent homeGuideAgent;
  final HomeGuideConsentRepository homeGuideConsentRepository;
  final RuniacAuthRepository authRepository;
  final ActivityHistoryRepository activityHistoryRepository;
  final UserProgressRepository userProgressRepository;
  final LeaderboardRepository leaderboardRepository;
  final FriendsRepository friendsRepository;
  final UserProfileRepository profileRepository;

  /// Read-only trusted `users/{uid}` account seam backing the app-level
  /// subscription-status stream.
  final UserAccountRepository userAccountRepository;

  /// Read-only callable seam for another runner's public profile, opened from
  /// a leaderboard rank row.
  final RunnerPublicProfileRepository runnerPublicProfileRepository;

  /// Read-only seam for the admin-published `config/paywall` display copy.
  final PaywallConfigRepository paywallConfigRepository;

  /// Read-only seam for the admin-published `config/featureAccess` premium
  /// feature checklist (upsell display only).
  final FeatureAccessRepository featureAccessRepository;

  /// Read-only seam for the admin-published `config/characterAccess` premium
  /// guide-character list (picker lock display only).
  final CharacterAccessRepository characterAccessRepository;
  final UserProfilePersistenceRepository profilePersistenceRepository;
  final GeneratedPlanPersistenceRepository generatedPlanPersistenceRepository;
  final PlanProgressRepository planProgressRepository;

  /// Durable one-shot marker for the plan-completion ceremony; non-null only
  /// on Firebase-active paths, null for the static/no-config path.
  final PlanCompletionSeenStore? planCompletionSeenStore;

  /// Local, device-only record of whether the one-time app tour is armed and
  /// completed; non-null only on Firebase-active paths, null for the
  /// static/no-config path (keeps the tour inert there).
  final AppTourSeenStore? appTourSeenStore;
  final AdaptivePlanEstimateRepository adaptivePlanEstimateRepository;
  final FeedRepository feedRepository;
  final NotificationInboxRepository notificationInboxRepository;

  /// Best-effort mirror of the derived Social-activity boolean into
  /// `notificationPreferences/{uid}`. The static/no-config path supplies the
  /// no-op implementation.
  final NotificationPreferenceMirror notificationPreferenceMirror;
  final NotificationRegistrationService? notificationRegistrationService;

  /// Server-owned Challenge distance-system source. Firebase-active paths supply
  /// the callable-backed repository with a member-scoped Firestore read store;
  /// the no-Firebase path keeps the deterministic static source.
  final ChallengeRepository challengeRepository;

  /// One-shot foreground Result presenter; non-null only on Firebase-active
  /// paths (durable local seen-marker), null for the static/no-config path.
  final ChallengeResultPresentationController? challengeResultPresenter;
  final RuniacFirestoreGateway firestoreGateway;
}
