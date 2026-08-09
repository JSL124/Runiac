import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/profile/data/firestore_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/onboarding_flow_test_helpers.dart';
import 'support/plan_family_test_drafts.dart';

void main() {
  testWidgets(
    'eligible onboarding completion activates generated running plan session',
    (tester) async {
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
          currentSessionGeneratedPlanStore: generatedPlanStore,
        ),
      );

      await completeOnboardingToFourSessionPreview(tester);
      await tapText(tester, 'Continue with this plan');

      expect(find.byTooltip('Home'), findsOneWidget);
      expect(generatedPlanStore.activePlan, isNotNull);
      expect(generatedPlanStore.activePlan!.title, '10K Performance Build');
      expect(generatedPlanStore.currentWeekRunningSessionCount, 4);
    },
  );

  testWidgets(
    'signed-in onboarding completion saves and activates plan start date',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final generatedPlanRepository =
          _RecordingGeneratedPlanPersistenceRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          currentSessionGeneratedPlanStore: generatedPlanStore,
          generatedPlanPersistenceRepository: generatedPlanRepository,
          youProgressToday: DateTime(2026, 7, 6),
        ),
      );

      await completeOnboardingToFourSessionPreview(tester);
      await tapText(tester, 'Continue with this plan');

      expect(generatedPlanRepository.savedUid, 'test-auth-user-1');
      expect(generatedPlanRepository.savedPlan?.startsOnDate, '2026-07-06');
      expect(generatedPlanStore.activePlan?.startsOnDate, '2026-07-06');
    },
  );

  testWidgets(
    'starter onboarding completion activates generated movement plan session',
    (tester) async {
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
          currentSessionGeneratedPlanStore: generatedPlanStore,
        ),
      );

      await completeOnboardingToPreview(tester);
      await tapText(tester, 'Continue with this plan');

      expect(find.byTooltip('Home'), findsOneWidget);
      expect(generatedPlanStore.activePlan, isNotNull);
      expect(generatedPlanStore.activePlan!.title, 'Return to Movement');
      expect(generatedPlanStore.currentWeekRunningSessionCount, 3);
    },
  );

  testWidgets(
    'signed-in saved onboarding profile hydrates generated plan after restart',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          showOnboarding: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          currentSessionGeneratedPlanStore: generatedPlanStore,
          profileRepository: FirestoreUserProfileRepository(
            authRepository: authRepository,
            reader: const _SavedOnboardingProfileDocumentReader(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(generatedPlanStore.activePlan, isNotNull);
      expect(generatedPlanStore.activePlan!.title, '10K Performance Build');
      expect(generatedPlanStore.currentWeekRunningSessionCount, 4);
      expect(find.byTooltip('Home'), findsOneWidget);
    },
  );

  testWidgets(
    'signed-in saved generated plan hydrates before regenerating from profile',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final persistedPlan = const BeginnerAdaptivePlanGenerator().generate(
        planFamilyStarterDraft(),
      );
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          showOnboarding: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          currentSessionGeneratedPlanStore: generatedPlanStore,
          generatedPlanPersistenceRepository:
              _RecordingGeneratedPlanPersistenceRepository(
                loadedPlan: persistedPlan,
              ),
          profileRepository: FirestoreUserProfileRepository(
            authRepository: authRepository,
            reader: const _SavedOnboardingProfileDocumentReader(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(generatedPlanStore.activePlan, isNotNull);
      expect(generatedPlanStore.activePlan!.title, persistedPlan.title);
      expect(
        generatedPlanStore
            .activePlan!
            .weeks
            .first
            .workouts
            .first
            .detail
            .breakdown
            .first
            .title,
        isNotEmpty,
      );
    },
  );

  testWidgets(
    'in-flight generated plan hydration does not activate after sign-out',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final repository = _HoldingGeneratedPlanPersistenceRepository();
      final persistedPlan = const BeginnerAdaptivePlanGenerator().generate(
        planFamilyStarterDraft(),
      );
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          showOnboarding: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          currentSessionGeneratedPlanStore: generatedPlanStore,
          generatedPlanPersistenceRepository: repository,
          profileRepository: FirestoreUserProfileRepository(
            authRepository: authRepository,
            reader: const _SavedOnboardingProfileDocumentReader(),
          ),
        ),
      );
      await repository.loadStarted.future;

      authRepository.emitSignedOut();
      await tester.pump();
      repository.completeLoad(persistedPlan);
      await tester.pumpAndSettle();

      expect(repository.loadedUid, 'test-auth-user-1');
      expect(generatedPlanStore.activePlan, isNull);
    },
  );

  testWidgets('active generated plan clears after sign-out', (tester) async {
    final authRepository = FakeRuniacAuthRepository();
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    final persistedPlan = const BeginnerAdaptivePlanGenerator().generate(
      planFamilyStarterDraft(),
    );
    addTearDown(authRepository.dispose);
    authRepository.emitSignedIn();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: authRepository,
        currentSessionGeneratedPlanStore: generatedPlanStore,
        generatedPlanPersistenceRepository:
            _RecordingGeneratedPlanPersistenceRepository(
              loadedPlan: persistedPlan,
            ),
        profileRepository: FirestoreUserProfileRepository(
          authRepository: authRepository,
          reader: const _SavedOnboardingProfileDocumentReader(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(generatedPlanStore.activePlan?.title, persistedPlan.title);

    authRepository.emitSignedOut();
    await tester.pumpAndSettle();

    expect(generatedPlanStore.activePlan, isNull);
  });

  testWidgets('signed-in onboarding completion persists safe profile fields', (
    tester,
  ) async {
    final authRepository = FakeRuniacAuthRepository();
    final profileRepository = _RecordingUserProfilePersistenceRepository();
    final generatedPlanRepository =
        _RecordingGeneratedPlanPersistenceRepository();
    addTearDown(authRepository.dispose);
    authRepository.emitSignedIn();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: authRepository,
        profilePersistenceRepository: profileRepository,
        generatedPlanPersistenceRepository: generatedPlanRepository,
        initialPersonalProfileDraft: PersonalProfileDraft(
          fullName: 'Maya Tan',
          nickname: 'Maya',
          dateOfBirthIso: '2002-06-28',
          weightKg: 58.5,
          locationLabel: 'Queenstown, Singapore',
        ),
      ),
    );

    await completeOnboardingToPreview(tester);
    await tapText(tester, 'Continue with this plan');

    expect(find.byTooltip('Home'), findsOneWidget);
    expect(profileRepository.uid, 'test-auth-user-1');
    expect(profileRepository.profile?.displayName, 'Maya');
    expect(profileRepository.profile?.fullName, 'Maya Tan');
    expect(profileRepository.profile?.nickname, 'Maya');
    expect(profileRepository.profile?.avatarInitials, 'M');
    expect(profileRepository.profile?.dateOfBirthIso, '2002-06-28');
    expect(profileRepository.profile?.ageYears, 24);
    expect(profileRepository.profile?.weightKg, 58.5);
    expect(profileRepository.profile?.locationLabel, 'Queenstown, Singapore');
    expect(profileRepository.profile?.fitnessLevel, 'new');
    expect(profileRepository.profile?.goals, <String>['habit']);
    expect(profileRepository.profile?.availability, <String, Object>{
      'weeklySessions': '3',
      'preferredDays': <String>['Mon', 'Wed', 'Fri'],
      'preferredTime': 'morning',
      'sessionLengthMinutes': '20',
    });
    expect(profileRepository.profile?.planCautiousness, 'balanced');
    expect(profileRepository.profile?.healthSafetyReadiness, <String, Object>{
      'comfort': 'ready',
      'activitySymptoms': <String>['none'],
      'recentRunningConsistency': 'none',
      'currentWeeklyRunFrequency': '0',
      'continuousRunCapacity': 'walk',
      'runningPlace': 'park',
      'motivationStyle': 'reminders',
    });
    expect(generatedPlanRepository.savedUid, 'test-auth-user-1');
    expect(generatedPlanRepository.savedPlan?.title, 'Return to Movement');
    expect(
      generatedPlanRepository
          .savedPlan
          ?.weeks
          .first
          .workouts
          .first
          .detail
          .metrics
          .map((metric) => metric.label),
      <String>['Duration', 'Type', 'Effort'],
    );
  });

  testWidgets(
    'signed-in onboarding completion waits when generated plan persistence fails',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      final profileRepository = _RecordingUserProfilePersistenceRepository();
      final generatedPlanRepository =
          _RecordingGeneratedPlanPersistenceRepository()..failNextSave = true;
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          profilePersistenceRepository: profileRepository,
          generatedPlanPersistenceRepository: generatedPlanRepository,
          currentSessionGeneratedPlanStore: generatedPlanStore,
          initialPersonalProfileDraft: PersonalProfileDraft(
            fullName: 'Maya Tan',
            nickname: 'Maya',
            dateOfBirthIso: '2002-06-28',
            weightKg: 58.5,
            locationLabel: 'Queenstown, Singapore',
          ),
        ),
      );

      await completeOnboardingToPreview(tester);
      await tapText(tester, 'Continue with this plan');
      await tester.pumpAndSettle();
      final reportedError = tester.takeException();

      expect(find.text('Good to see you'), findsNothing);
      expect(profileRepository.uid, 'test-auth-user-1');
      expect(generatedPlanRepository.saveCalls, 1);
      expect(generatedPlanStore.activePlan, isNull);
      expect(
        find.text('We could not save your profile. Try again.'),
        findsOneWidget,
      );
      expect(reportedError, isA<StateError>());
    },
  );

  testWidgets(
    'signed-in onboarding completion waits when profile persistence fails',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      final profileRepository = _RecordingUserProfilePersistenceRepository()
        ..failNextSave = true;
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          profilePersistenceRepository: profileRepository,
          initialPersonalProfileDraft: PersonalProfileDraft(
            fullName: 'Maya Tan',
            nickname: 'Maya',
            dateOfBirthIso: '2002-06-28',
            weightKg: 58.5,
            locationLabel: 'Queenstown, Singapore',
          ),
        ),
      );

      await completeOnboardingToPreview(tester);
      await tapText(tester, 'Continue with this plan');

      expect(find.text('Good to see you'), findsNothing);
      expect(find.text('Continue with this plan'), findsOneWidget);
      expect(find.textContaining('profile'), findsWidgets);

      await tapText(tester, 'Continue with this plan');

      expect(find.byTooltip('Home'), findsOneWidget);
      expect(profileRepository.saveCalls, 2);
    },
  );

  testWidgets(
    'body concern onboarding completion activates recovery plan session',
    (tester) async {
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showOnboarding: true,
          enableForegroundGps: false,
          currentSessionGeneratedPlanStore: generatedPlanStore,
        ),
      );

      await completeOnboardingToBodyConcernPreview(tester);
      await tapText(tester, 'Continue with this plan');

      expect(find.byTooltip('Home'), findsOneWidget);
      expect(generatedPlanStore.activePlan, isNotNull);
      expect(generatedPlanStore.activePlan!.title, 'Return to Movement');
      expect(generatedPlanStore.currentWeekRunningSessionCount, 3);
    },
  );

  testWidgets('needs clearance completion retains safety readiness display', (
    tester,
  ) async {
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
        currentSessionGeneratedPlanStore: generatedPlanStore,
      ),
    );

    await completeOnboardingToNeedsClearancePreview(tester);

    expect(find.text('Safety-first setup'), findsOneWidget);
    expect(find.text('Safety Readiness Plan'), findsOneWidget);
    expect(
      find.textContaining('qualified professional guidance'),
      findsWidgets,
    );
    expect(find.text('First week preview'), findsNothing);
    expect(find.text('Suggested starting plan'), findsNothing);
    expect(find.textContaining(' min'), findsNothing);
    expect(find.textContaining('km'), findsNothing);
    expect(find.textContaining('pace'), findsNothing);
    expect(find.textContaining('Start Run'), findsNothing);
    expect(find.textContaining('continue anyway'), findsNothing);

    await tapText(tester, 'Finish for now');

    expect(find.byTooltip('Home'), findsOneWidget);
    expect(generatedPlanStore.activePlan, isNotNull);
    expect(generatedPlanStore.activePlan!.isSafetyReadinessDisplay, isTrue);
    expect(generatedPlanStore.activePlan!.canStartPlannedRun, isFalse);
    expect(
      isEligibleCurrentSessionGeneratedPlan(generatedPlanStore.activePlan!),
      isFalse,
    );
    expect(generatedPlanStore.currentWeekRunningSessionCount, 0);
  });

  testWidgets('needs clearance completion replaces stale generated plan', (
    tester,
  ) async {
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    final stalePlan = const BeginnerAdaptivePlanGenerator().generate(
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
    expect(generatedPlanStore.setActivePlan(stalePlan), isTrue);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showOnboarding: true,
        enableForegroundGps: false,
        currentSessionGeneratedPlanStore: generatedPlanStore,
      ),
    );

    await completeOnboardingToNeedsClearancePreview(tester);

    expect(find.text('Safety-first setup'), findsOneWidget);
    expect(find.text('Safety Readiness Plan'), findsOneWidget);
    expect(find.text('Continue with this plan'), findsNothing);
    expect(find.text('Finish for now'), findsOneWidget);

    await tapText(tester, 'Finish for now');

    expect(find.byTooltip('Home'), findsOneWidget);
    expect(generatedPlanStore.activePlan, isNotNull);
    expect(generatedPlanStore.activePlan, isNot(same(stalePlan)));
    expect(generatedPlanStore.activePlan!.isSafetyReadinessDisplay, isTrue);
    expect(
      isEligibleCurrentSessionGeneratedPlan(generatedPlanStore.activePlan!),
      isFalse,
    );
    expect(generatedPlanStore.currentWeekRunningSessionCount, 0);
  });
}

class _RecordingGeneratedPlanPersistenceRepository
    implements GeneratedPlanPersistenceRepository {
  _RecordingGeneratedPlanPersistenceRepository({this.loadedPlan});

  final BeginnerAdaptivePlanSnapshot? loadedPlan;
  String? savedUid;
  BeginnerAdaptivePlanSnapshot? savedPlan;
  bool failNextSave = false;
  int saveCalls = 0;

  @override
  Future<BeginnerAdaptivePlanSnapshot?> loadGeneratedPlan({
    required String uid,
  }) async {
    return loadedPlan;
  }

  @override
  Future<void> saveGeneratedPlan({
    required String uid,
    required BeginnerAdaptivePlanSnapshot plan,
    bool resetCreatedAt = false,
  }) async {
    saveCalls += 1;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('generated plan save failed');
    }
    savedUid = uid;
    savedPlan = plan;
  }
}

class _HoldingGeneratedPlanPersistenceRepository
    implements GeneratedPlanPersistenceRepository {
  final Completer<void> loadStarted = Completer<void>();
  final Completer<BeginnerAdaptivePlanSnapshot?> _loadCompleter =
      Completer<BeginnerAdaptivePlanSnapshot?>();
  String? loadedUid;

  void completeLoad(BeginnerAdaptivePlanSnapshot? plan) {
    if (!_loadCompleter.isCompleted) {
      _loadCompleter.complete(plan);
    }
  }

  @override
  Future<BeginnerAdaptivePlanSnapshot?> loadGeneratedPlan({
    required String uid,
  }) {
    loadedUid = uid;
    if (!loadStarted.isCompleted) {
      loadStarted.complete();
    }
    return _loadCompleter.future;
  }

  @override
  Future<void> saveGeneratedPlan({
    required String uid,
    required BeginnerAdaptivePlanSnapshot plan,
    bool resetCreatedAt = false,
  }) async {}
}

class _SavedOnboardingProfileDocumentReader
    implements UserProfileDocumentReader {
  const _SavedOnboardingProfileDocumentReader();

  @override
  Future<UserProfileDocumentReadResult> readUserProfile({
    required String uid,
  }) async {
    return const UserProfileDocumentReadResult.exists(<String, Object?>{
      'displayName': 'Maya',
      'fullName': 'Maya Tan',
      'nickname': 'Maya',
      'avatarInitials': 'M',
      'dateOfBirth': '2002-06-28',
      'ageYears': 24,
      'weightKg': 58.5,
      'locationLabel': 'Queenstown, Singapore',
      'fitnessLevel': 'run30',
      'goals': <String>['10k'],
      'availability': <String, Object?>{
        'weeklySessions': '4',
        'preferredDays': <String>['Mon', 'Tue', 'Wed', 'Thu'],
        'preferredTime': 'morning',
        'sessionLengthMinutes': '30',
      },
      'planCautiousness': 'performance',
      'healthSafetyReadiness': <String, Object?>{
        'comfort': 'ready',
        'activitySymptoms': <String>['none'],
        'recentRunningConsistency': '3-6m',
        'currentWeeklyRunFrequency': '4',
        'continuousRunCapacity': '45plus',
        'runningPlace': 'park',
        'motivationStyle': 'reminders',
      },
    });
  }
}

class _RecordingUserProfilePersistenceRepository
    implements UserProfilePersistenceRepository {
  String? uid;
  UserProfileOnboardingSnapshot? profile;
  bool failNextSave = false;
  int saveCalls = 0;

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async {
    return true;
  }

  @override
  Future<void> saveOnboardingProfile({
    required String uid,
    required UserProfileOnboardingSnapshot profile,
  }) async {
    saveCalls += 1;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('profile save failed');
    }
    this.uid = uid;
    this.profile = profile;
  }

  @override
  Future<void> savePersonalProfile({
    required String uid,
    required UserProfilePersonalSnapshot profile,
  }) async {}
}
