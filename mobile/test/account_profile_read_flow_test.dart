import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';
import 'package:runiac_app/core/widgets/runiac_level_profile_badge.dart';
import 'package:runiac_app/features/profile/data/firestore_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/leaderboard/domain/models/leaderboard_read_model.dart';
import 'package:runiac_app/features/leaderboard/domain/repositories/leaderboard_repository.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/user_progress_repository.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/onboarding_flow_test_helpers.dart';

void main() {
  testWidgets(
    'Account profile displays saved profile values from the repository',
    (tester) async {
      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: _SingleProfileRepository(
            UserProfileReadModel(
              userId: 'test-auth-user-1',
              displayName: 'Maya Tan',
              fullName: 'Maya Tan',
              nickname: 'Maya',
              avatarInitials: 'MT',
              ageYears: 24,
              weightKg: 58.5,
              locationLabel: 'Queenstown, Singapore',
              previewLevelBadge: '',
              previewNote: '',
              setupSectionLabel: 'RUNNING SETUP',
              manageSectionLabel: 'MANAGE',
              footerCaption: 'Runiac · Preview build · Built for new runners',
              setupItems: const <UserProfileInfoItemReadModel>[
                UserProfileInfoItemReadModel(
                  title: 'Current goal',
                  value: 'First relaxed 5K',
                ),
                UserProfileInfoItemReadModel(
                  title: 'Weekly rhythm',
                  value: '4 sessions / week',
                ),
                UserProfileInfoItemReadModel(
                  title: 'Experience',
                  value: 'Returning runner',
                ),
              ],
              manageRows: const <UserProfileManageRowReadModel>[
                UserProfileManageRowReadModel(
                  title: 'Edit profile',
                  subtitle: 'Email, personal details, and onboarding',
                  snackBarMessage: '',
                  action: UserProfileManageAction.editProfile,
                ),
              ],
            ),
          ),
          userProgressRepository: const _SingleUserProgressRepository(
            UserProgressReadModel(
              userId: 'test-auth-user-1',
              officialStreakLabel: '3 days',
              level: 6,
              levelProgressFraction: 0.2,
              totalXp: 520,
              nextLevelXp: 600,
              xpToNextLevel: 80,
              levelLabel: 'Level 6',
              totalXpLabel: '520 XP',
              weeklyXpLabel: '',
              monthlyXpLabel: '520 XP',
              weeklyDistanceLabel: '',
              goalProgressLabel: '',
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Maya'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-profile-level-badge')),
        findsOneWidget,
      );
      expect(find.byType(RuniacLevelProfileBadge), findsWidgets);
      expect(find.text('Queenstown, Singapore'), findsOneWidget);
      // Shown once on the profile badge and once on the level-up gauge.
      expect(find.text('Lv.6'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('account-level-up-gauge')),
        findsOneWidget,
      );
      expect(find.text('Lv.7'), findsOneWidget);
      expect(find.text('80 XP to level up'), findsOneWidget);
      expect(find.text('520 / 600 XP'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-division-badge-tier_02')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Bronze division'), findsOneWidget);
      expect(find.text('First relaxed 5K'), findsOneWidget);
      expect(find.text('4 sessions / week'), findsOneWidget);
      expect(find.text('Returning runner'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-subscription-status-badge')),
        findsOneWidget,
      );
      expect(find.text('BASIC'), findsOneWidget);
    },
  );

  testWidgets(
    'Account profile renders an empty division badge for an unranked runner',
    (tester) async {
      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: _SingleProfileRepository(_savedProfile()),
          leaderboardRepository: _SingleLeaderboardRepository(
            LeaderboardReadModel(
              status: LeaderboardReadStatus.unranked,
              regionLabel: 'Queenstown, Singapore',
              divisionKey: '',
              divisionLabel: 'Unranked',
              currentRunnerRankLabel: '',
              entries: const [],
            ),
          ),
          userProgressRepository: const _SingleUserProgressRepository(
            UserProgressReadModel(
              userId: 'test-auth-user-1',
              officialStreakLabel: '',
              level: 0,
              levelLabel: 'Level 0',
              totalXpLabel: '0 XP',
              weeklyXpLabel: '',
              monthlyXpLabel: '0 XP',
              weeklyDistanceLabel: '',
              goalProgressLabel: '',
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      // Shown once on the profile badge and once on the level-up gauge.
      expect(find.text('Lv.0'), findsNWidgets(2));
      // No backend XP value yet, so the gauge shows no XP caption.
      expect(find.textContaining('XP to level up'), findsNothing);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Unranked'), findsNothing);
      expect(
        find.byKey(const ValueKey('account-division-badge-unranked')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Unranked division'), findsOneWidget);
    },
  );

  testWidgets(
    'Account profile shows backend progression division even when leaderboard is unranked',
    (tester) async {
      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: _SingleProfileRepository(_savedProfile()),
          leaderboardRepository: _SingleLeaderboardRepository(
            LeaderboardReadModel(
              status: LeaderboardReadStatus.unranked,
              regionLabel: 'Queenstown, Singapore',
              divisionKey: '',
              divisionLabel: 'Unranked',
              currentRunnerRankLabel: '',
              entries: const [],
            ),
          ),
          userProgressRepository: const _SingleUserProgressRepository(
            UserProgressReadModel(
              userId: 'test-auth-user-1',
              officialStreakLabel: '',
              level: 1,
              levelProgressFraction: 0.5,
              divisionKey: 'tier_01',
              divisionLabel: 'Iron League',
              totalXp: 50,
              nextLevelXp: 100,
              xpToNextLevel: 50,
              levelLabel: 'Level 1',
              totalXpLabel: '50 XP',
              weeklyXpLabel: '',
              monthlyXpLabel: '50 XP',
              weeklyDistanceLabel: '',
              goalProgressLabel: '',
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Lv.1'), findsNWidgets(2));
      expect(find.text('50 / 100 XP'), findsOneWidget);
      expect(
        tester
            .widget<RuniacLevelProfileBadge>(
              find.byKey(const ValueKey('account-profile-level-badge')),
            )
            .progressFraction,
        0.5,
      );
      expect(
        find.byKey(const ValueKey('account-division-badge-tier_01')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Iron League division'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-division-badge-unranked')),
        findsNothing,
      );
    },
  );

  for (final tier in <(int, String, String)>[
    (1, 'tier_01', 'Iron League'),
    (11, 'tier_02', 'Bronze League'),
    (21, 'tier_03', 'Silver League'),
    (31, 'tier_04', 'Gold League'),
    (41, 'tier_05', 'Platinum League'),
    (51, 'tier_06', 'Emerald League'),
    (61, 'tier_07', 'Diamond League'),
    (71, 'tier_08', 'Master League'),
    (81, 'tier_09', 'Grandmaster League'),
    (100, 'tier_10', 'Challenger League'),
  ]) {
    testWidgets(
      'Account profile renders backend progression badge ${tier.$2} at level ${tier.$1}',
      (tester) async {
        await tester.pumpWidget(
          RuniacApp(
            showSplash: false,
            enableForegroundGps: false,
            profileRepository: _SingleProfileRepository(_savedProfile()),
            leaderboardRepository: _SingleLeaderboardRepository(
              LeaderboardReadModel(
                status: LeaderboardReadStatus.unranked,
                regionLabel: 'Queenstown, Singapore',
                divisionKey: '',
                divisionLabel: 'Unranked',
                currentRunnerRankLabel: '',
                entries: const [],
              ),
            ),
            userProgressRepository: _SingleUserProgressRepository(
              UserProgressReadModel(
                userId: 'test-auth-user-1',
                officialStreakLabel: '',
                level: tier.$1,
                levelProgressFraction: 0.25,
                divisionKey: tier.$2,
                divisionLabel: tier.$3,
                levelLabel: 'Level ${tier.$1}',
                totalXpLabel: '${tier.$1 * 100} XP',
                weeklyXpLabel: '',
                monthlyXpLabel: '${tier.$1 * 100} XP',
                weeklyDistanceLabel: '',
                goalProgressLabel: '',
              ),
            ),
          ),
        );

        await tester.tap(find.bySemanticsLabel('Profile'));
        await tester.pumpAndSettle();

        expect(find.text('Lv.${tier.$1}'), findsNWidgets(2));
        expect(
          find.byKey(ValueKey('account-division-badge-${tier.$2}')),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('${tier.$3} division'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Account profile level-up gauge reports max level from the backend',
    (tester) async {
      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: _SingleProfileRepository(_savedProfile()),
          userProgressRepository: const _SingleUserProgressRepository(
            UserProgressReadModel(
              userId: 'test-auth-user-1',
              officialStreakLabel: '',
              level: 50,
              levelProgressFraction: 1,
              totalXp: 99000,
              isMaxLevel: true,
              levelLabel: 'Level 50',
              totalXpLabel: '99,000 XP',
              weeklyXpLabel: '',
              monthlyXpLabel: '1,200 XP',
              weeklyDistanceLabel: '',
              goalProgressLabel: '',
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('account-level-up-gauge')),
        findsOneWidget,
      );
      expect(find.text('Max level reached'), findsOneWidget);
      expect(find.text('Lv.51'), findsNothing);
      expect(find.text('99,000 XP'), findsOneWidget);
    },
  );

  testWidgets(
    'Account profile shows email verification prompt for unverified user and resends successfully',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn(emailVerified: false);

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          profileRepository: _SingleProfileRepository(_savedProfile()),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('Resend email'), findsOneWidget);

      await tester.tap(find.text('Resend email'));
      await tester.pumpAndSettle();

      expect(authRepository.sendEmailVerificationCalls, 1);
      expect(find.text('Verification email sent.'), findsWidgets);
    },
  );

  testWidgets('Account profile shows auth error when resend fails', (
    tester,
  ) async {
    final authRepository = FakeRuniacAuthRepository(
      emailVerificationError: const RuniacAuthException(
        code: RuniacAuthErrorCode.tooManyRequests,
        userMessage: 'Too many attempts. Please wait a moment and try again.',
      ),
    );
    addTearDown(authRepository.dispose);
    authRepository.emitSignedIn(emailVerified: false);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        enableForegroundGps: false,
        authRepository: authRepository,
        profileRepository: _SingleProfileRepository(_savedProfile()),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resend email'));
    await tester.pumpAndSettle();

    expect(authRepository.sendEmailVerificationCalls, 1);
    expect(
      find.text('Too many attempts. Please wait a moment and try again.'),
      findsWidgets,
    );
  });

  testWidgets(
    'Edit profile shows read-only email and editable personal fields',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final profileRepository = _MutableProfileRepository(
        UserProfileReadModel(
          userId: 'test-auth-user-1',
          displayName: 'Maya',
          fullName: 'Maya Tan',
          nickname: 'Maya',
          avatarInitials: 'M',
          dateOfBirthIso: '2000-01-01',
          ageYears: 24,
          weightKg: 58.5,
          locationLabel: 'Queenstown',
          setupItems: const <UserProfileInfoItemReadModel>[
            UserProfileInfoItemReadModel(title: 'Current goal', value: 'habit'),
            UserProfileInfoItemReadModel(
              title: 'Weekly rhythm',
              value: '3 sessions / week',
            ),
            UserProfileInfoItemReadModel(title: 'Experience', value: 'new'),
          ],
          manageRows: const <UserProfileManageRowReadModel>[
            UserProfileManageRowReadModel(
              title: 'Edit profile',
              subtitle: 'Email, personal details, and onboarding',
              snackBarMessage: '',
              action: UserProfileManageAction.editProfile,
            ),
          ],
        ),
      );
      final persistenceRepository = _RecordingUserProfilePersistenceRepository(
        onSaveOnboardingProfile: (profile) {
          profileRepository.profile = UserProfileReadModel(
            userId: 'test-auth-user-1',
            displayName: profile.displayName,
            fullName: profile.fullName,
            nickname: profile.nickname,
            avatarInitials: profile.avatarInitials,
            dateOfBirthIso: profile.dateOfBirthIso,
            ageYears: profile.ageYears,
            weightKg: profile.weightKg,
            locationLabel: profile.locationLabel,
            previewNote: '',
            setupSectionLabel: 'RUNNING SETUP',
            manageSectionLabel: 'MANAGE',
            footerCaption: 'Runiac · Preview build · Built for new runners',
            setupItems: <UserProfileInfoItemReadModel>[
              UserProfileInfoItemReadModel(
                title: 'Current goal',
                value: profile.goals.join(', '),
              ),
              UserProfileInfoItemReadModel(
                title: 'Weekly rhythm',
                value:
                    '${profile.availability['weeklySessions']} sessions / week',
              ),
              UserProfileInfoItemReadModel(
                title: 'Experience',
                value: profile.fitnessLevel,
              ),
            ],
            manageRows: const <UserProfileManageRowReadModel>[
              UserProfileManageRowReadModel(
                title: 'Edit profile',
                subtitle: 'Email, personal details, and onboarding',
                snackBarMessage: '',
                action: UserProfileManageAction.editProfile,
              ),
            ],
          );
        },
      );
      final generatedPlanPersistenceRepository =
          _RecordingGeneratedPlanPersistenceRepository();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          profilePersistenceRepository: persistenceRepository,
          generatedPlanPersistenceRepository:
              generatedPlanPersistenceRepository,
          currentSessionGeneratedPlanStore: generatedPlanStore,
          profileRepository: profileRepository,
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit profile'));
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();

      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('runner@runiac.app'), findsOneWidget);
      expect(find.text('Personal details'), findsOneWidget);
      expect(find.text('Your training profile'), findsOneWidget);
      expect(find.text('Retake onboarding'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('Nickname'), 'May');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Nickname is available.'), findsOneWidget);
      expect(
        _textColor(tester, 'Nickname is available.'),
        RuniacColors.successGreen,
      );
      expect(find.text('Date of birth'), findsOneWidget);
      expect(find.text('Age'), findsOneWidget);
      await tester.enterText(
        find.bySemanticsLabel('Weight in kilograms'),
        '59',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      await tester.ensureVisible(find.bySemanticsLabel('Region'));
      await tester.tap(find.bySemanticsLabel('Region'));
      await tester.pumpAndSettle();
      expect(find.text('Bedok, Singapore'), findsOneWidget);
      await tapText(tester, 'Bedok, Singapore');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Retake onboarding'));
      await tester.tap(find.text('Retake onboarding'));
      await tester.pumpAndSettle();
      await confirmOnboardingRetake(tester);
      await completeOnboardingToFourSessionPreview(tester);
      await tapText(tester, 'Continue with this plan');
      await tester.pumpAndSettle();

      expect(persistenceRepository.onboardingProfile?.nickname, 'May');
      expect(
        persistenceRepository.onboardingProfile?.dateOfBirthIso,
        '2000-01-01',
      );
      expect(persistenceRepository.onboardingProfile?.ageYears, 26);
      expect(persistenceRepository.onboardingProfile?.weightKg, 59);
      expect(
        persistenceRepository.onboardingProfile?.locationLabel,
        'Bedok, Singapore',
      );
      expect(
        persistenceRepository.onboardingProfile?.planCautiousness,
        'performance',
      );
      expect(generatedPlanStore.activePlan?.title, '10K Performance Build');
      expect(generatedPlanPersistenceRepository.savedUid, 'test-auth-user-1');
      expect(
        generatedPlanPersistenceRepository.savedPlan?.title,
        '10K Performance Build',
      );
      expect(
        generatedPlanPersistenceRepository
            .savedPlan
            ?.weeks
            .first
            .workouts
            .first
            .detail
            .coachNotes,
        isNotEmpty,
      );
      // Initial shell/Home profile reads plus Account reload after saving.
      expect(profileRepository.loadCount, 4);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('4 sessions / week'), findsOneWidget);
      expect(find.text('3 sessions / week'), findsNothing);
    },
  );

  testWidgets('Edit profile refreshes Account after saving personal fields', (
    tester,
  ) async {
    final authRepository = FakeRuniacAuthRepository();
    addTearDown(authRepository.dispose);
    authRepository.emitSignedIn();
    final profileRepository = _MutableProfileRepository(
      UserProfileReadModel(
        userId: 'test-auth-user-1',
        displayName: 'Maya',
        fullName: 'Maya Tan',
        nickname: 'Maya',
        avatarInitials: 'M',
        dateOfBirthIso: '2000-01-01',
        ageYears: 24,
        weightKg: 58.5,
        locationLabel: 'Queenstown, Singapore',
        manageRows: const <UserProfileManageRowReadModel>[
          UserProfileManageRowReadModel(
            title: 'Edit profile',
            subtitle: 'Email, personal details, and onboarding',
            snackBarMessage: '',
            action: UserProfileManageAction.editProfile,
          ),
        ],
      ),
    );
    final persistenceRepository = _RecordingUserProfilePersistenceRepository(
      onSavePersonalProfile: (profile) {
        profileRepository.profile = UserProfileReadModel(
          userId: 'test-auth-user-1',
          displayName: profile.displayName,
          fullName: profile.fullName,
          nickname: profile.nickname,
          avatarInitials: profile.avatarInitials,
          dateOfBirthIso: profile.dateOfBirthIso,
          ageYears: profile.ageYears,
          weightKg: profile.weightKg,
          locationLabel: profile.locationLabel,
          previewNote: '',
          setupSectionLabel: 'RUNNING SETUP',
          manageSectionLabel: 'MANAGE',
          footerCaption: 'Runiac · Preview build · Built for new runners',
          manageRows: const <UserProfileManageRowReadModel>[
            UserProfileManageRowReadModel(
              title: 'Edit profile',
              subtitle: 'Email, personal details, and onboarding',
              snackBarMessage: '',
              action: UserProfileManageAction.editProfile,
            ),
          ],
        );
      },
    );

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        enableForegroundGps: false,
        authRepository: authRepository,
        profileRepository: profileRepository,
        profilePersistenceRepository: persistenceRepository,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Maya'), findsOneWidget);
    await tester.ensureVisible(find.text('Edit profile'));
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    await tester.enterText(find.bySemanticsLabel('Name'), 'Jess Lee');
    await tester.enterText(find.bySemanticsLabel('Nickname'), 'Jess');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.bySemanticsLabel('Weight in kilograms'), '61');
    await tester.ensureVisible(find.bySemanticsLabel('Region'));
    await tester.tap(find.bySemanticsLabel('Region'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Orchard, Singapore');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Jess'), findsOneWidget);
    expect(find.text('Maya'), findsNothing);
    expect(find.text('Orchard, Singapore'), findsOneWidget);
    // Initial shell/Home profile reads plus Account reload after saving.
    expect(profileRepository.loadCount, 4);
  });

  testWidgets('Edit profile blocks duplicate nickname before saving', (
    tester,
  ) async {
    final authRepository = FakeRuniacAuthRepository();
    addTearDown(authRepository.dispose);
    authRepository.emitSignedIn();
    final persistenceRepository = _RecordingUserProfilePersistenceRepository(
      nicknameAvailable: false,
    );

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        enableForegroundGps: false,
        authRepository: authRepository,
        profilePersistenceRepository: persistenceRepository,
        profileRepository: _SingleProfileRepository(
          UserProfileReadModel(
            userId: 'test-auth-user-1',
            displayName: 'Maya',
            fullName: 'Maya Tan',
            nickname: 'Maya',
            avatarInitials: 'M',
            dateOfBirthIso: '2000-01-01',
            ageYears: 24,
            weightKg: 58.5,
            locationLabel: 'Queenstown, Singapore',
            manageRows: const <UserProfileManageRowReadModel>[
              UserProfileManageRowReadModel(
                title: 'Edit profile',
                subtitle: 'Email, personal details, and onboarding',
                snackBarMessage: '',
                action: UserProfileManageAction.editProfile,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit profile'));
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    await tester.enterText(find.bySemanticsLabel('Nickname'), 'TakenRunner');
    await tester.pump(const Duration(milliseconds: 500));
    expect(persistenceRepository.checkedNickname, 'TakenRunner');
    expect(find.text('Nickname is already taken.'), findsOneWidget);
    expect(
      _textColor(tester, 'Nickname is already taken.'),
      RuniacColors.errorRed,
    );
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Nickname is already taken.'), findsOneWidget);
    expect(persistenceRepository.personalProfile, isNull);
  });

  testWidgets('Edit profile explains when nickname rules block checking', (
    tester,
  ) async {
    final authRepository = FakeRuniacAuthRepository();
    addTearDown(authRepository.dispose);
    authRepository.emitSignedIn();
    final persistenceRepository = _RecordingUserProfilePersistenceRepository(
      nicknameCheckError: const NicknameAvailabilityCheckException(
        NicknameAvailabilityFailureReason.rulesUnavailable,
      ),
    );

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        enableForegroundGps: false,
        authRepository: authRepository,
        profilePersistenceRepository: persistenceRepository,
        profileRepository: _SingleProfileRepository(
          UserProfileReadModel(
            userId: 'test-auth-user-1',
            displayName: 'Maya',
            fullName: 'Maya Tan',
            nickname: 'Maya',
            avatarInitials: 'M',
            dateOfBirthIso: '2000-01-01',
            ageYears: 24,
            weightKg: 58.5,
            locationLabel: 'Queenstown, Singapore',
            manageRows: const <UserProfileManageRowReadModel>[
              UserProfileManageRowReadModel(
                title: 'Edit profile',
                subtitle: 'Email, personal details, and onboarding',
                snackBarMessage: '',
                action: UserProfileManageAction.editProfile,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit profile'));
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    await tester.enterText(find.bySemanticsLabel('Nickname'), 'Jinseo Lee');
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text(
        'Nickname check is blocked by Firestore rules. Deploy the updated rules or use the emulator.',
      ),
      findsOneWidget,
    );
    expect(persistenceRepository.personalProfile, isNull);
  });

  testWidgets(
    'Account profile shows recovery UI when authenticated profile is missing',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          profileRepository: FirestoreUserProfileRepository(
            authRepository: authRepository,
            reader: const _MissingUserProfileDocumentReader(),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Profile setup was not found'), findsOneWidget);
      expect(find.text('Set up profile'), findsOneWidget);
      expect(find.text('Runiac Runner'), findsNothing);

      await tester.tap(find.text('Set up profile'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Profile recovery setup requires completing signup/onboarding again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('Account profile shows loading state while profile is loading', (
    tester,
  ) async {
    final profileCompleter = Completer<UserProfileReadModel>();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        profileRepository: _CompletingProfileRepository(
          profileCompleter.future,
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading profile...'), findsOneWidget);
    expect(find.text('Runiac Runner'), findsNothing);

    profileCompleter.complete(_savedProfile());
    await tester.pumpAndSettle();

    expect(find.text('Loading profile...'), findsNothing);
    expect(find.text('Maya'), findsOneWidget);
  });

  testWidgets(
    'Edit profile retake waits when generated plan persistence fails',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();
      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      final profileRepository = _MutableProfileRepository(_savedProfile());
      final persistenceRepository = _RecordingUserProfilePersistenceRepository(
        onSaveOnboardingProfile: (profile) {
          profileRepository.profile = UserProfileReadModel(
            userId: 'test-auth-user-1',
            displayName: profile.displayName,
            fullName: profile.fullName,
            nickname: profile.nickname,
            avatarInitials: profile.avatarInitials,
            ageYears: profile.ageYears,
            weightKg: profile.weightKg,
            locationLabel: profile.locationLabel,
            setupItems: <UserProfileInfoItemReadModel>[
              UserProfileInfoItemReadModel(
                title: 'Weekly rhythm',
                value:
                    '${profile.availability['weeklySessions']} sessions / week',
              ),
            ],
            manageRows: const <UserProfileManageRowReadModel>[
              UserProfileManageRowReadModel(
                title: 'Edit profile',
                subtitle: 'Email, personal details, and onboarding',
                snackBarMessage: '',
                action: UserProfileManageAction.editProfile,
              ),
            ],
          );
        },
      );
      final generatedPlanPersistenceRepository =
          _RecordingGeneratedPlanPersistenceRepository()..failNextSave = true;

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          profilePersistenceRepository: persistenceRepository,
          generatedPlanPersistenceRepository:
              generatedPlanPersistenceRepository,
          currentSessionGeneratedPlanStore: generatedPlanStore,
          profileRepository: profileRepository,
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit profile'));
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retake onboarding'));
      await tester.tap(find.text('Retake onboarding'));
      await tester.pumpAndSettle();
      await confirmOnboardingRetake(tester);
      await completeOnboardingToPreview(tester);
      await tapText(tester, 'Continue with this plan');
      await tester.pumpAndSettle();
      final reportedError = tester.takeException();

      expect(find.text('Profile'), findsNothing);
      expect(generatedPlanStore.activePlan, isNull);
      expect(persistenceRepository.onboardingProfile, isNotNull);
      expect(generatedPlanPersistenceRepository.saveCalls, 1);
      expect(
        find.text('We could not save your onboarding result. Try again.'),
        findsOneWidget,
      );
      expect(reportedError, isA<StateError>());
    },
  );

  testWidgets('Account profile falls back to the demo profile snapshot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Runiac Runner'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('account-profile-level-badge')),
      findsOneWidget,
    );
    expect(find.text('Jurong East, Singapore'), findsOneWidget);
    // Trusted, backend-owned regional rank rendered in front of the region.
    expect(find.byKey(const ValueKey('account-regional-rank')), findsOneWidget);
    expect(find.text('#18'), findsOneWidget);
    // Shown once on the profile badge and once on the level-up gauge.
    expect(find.text('Lv.0'), findsNWidgets(2));
    expect(find.text('Work toward a 10K'), findsOneWidget);
    // The no-Firebase static preview keeps its demo lifetime stats.
    expect(find.text('12 days'), findsOneWidget);
    expect(find.text('148.6 km'), findsOneWidget);
  });

  testWidgets(
    'Account profile passes the stored avatarUrl to the level profile badge',
    (tester) async {
      final profile = UserProfileReadModel(
        userId: 'test-auth-user-1',
        displayName: 'Maya Tan',
        fullName: 'Maya Tan',
        nickname: 'Maya',
        avatarInitials: 'MT',
        avatarUrl:
            'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok',
        ageYears: 24,
        weightKg: 58.5,
        locationLabel: 'Queenstown, Singapore',
        previewNote: '',
        setupSectionLabel: 'RUNNING SETUP',
        manageSectionLabel: 'MANAGE',
        footerCaption: 'Runiac · Preview build · Built for new runners',
        setupItems: const <UserProfileInfoItemReadModel>[],
        manageRows: const <UserProfileManageRowReadModel>[],
      );

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: _SingleProfileRepository(profile),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<RuniacLevelProfileBadge>(
              find.byKey(const ValueKey('account-profile-level-badge')),
            )
            .photoUrl,
        'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok',
      );
    },
  );

  testWidgets(
    'Account profile shows em-dash lifetime stats for a real runner with no runs',
    (tester) async {
      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: _SingleProfileRepository(_savedProfile()),
          userProgressRepository: const _SingleUserProgressRepository(
            UserProgressReadModel(
              userId: 'test-auth-user-1',
              officialStreakLabel: '',
              level: 0,
              levelLabel: 'Level 0',
              totalXpLabel: '0 XP',
              weeklyXpLabel: '',
              monthlyXpLabel: '0 XP',
              weeklyDistanceLabel: '',
              goalProgressLabel: '',
              // Backend has not published lifetime stats for this fresh account.
              longestStreakLabel: '',
              totalDistanceLabel: '',
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('account-stat-max-streak')))
            .data,
        '—',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('account-stat-total-distance')),
            )
            .data,
        '—',
      );
      // No fabricated demo values leak into the real-runner path.
      expect(find.text('12 days'), findsNothing);
      expect(find.text('148.6 km'), findsNothing);
    },
  );
}

Color? _textColor(WidgetTester tester, String text) {
  return tester.widget<Text>(find.text(text)).style?.color;
}

UserProfileReadModel _savedProfile() {
  return UserProfileReadModel(
    userId: 'test-auth-user-1',
    displayName: 'Maya Tan',
    fullName: 'Maya Tan',
    nickname: 'Maya',
    avatarInitials: 'MT',
    dateOfBirthIso: '2002-06-28',
    ageYears: 24,
    weightKg: 58.5,
    locationLabel: 'Queenstown, Singapore',
    previewNote: '',
    setupSectionLabel: 'RUNNING SETUP',
    manageSectionLabel: 'MANAGE',
    footerCaption: 'Runiac · Preview build · Built for new runners',
    setupItems: const <UserProfileInfoItemReadModel>[
      UserProfileInfoItemReadModel(
        title: 'Current goal',
        value: 'First relaxed 5K',
      ),
    ],
    manageRows: const <UserProfileManageRowReadModel>[
      UserProfileManageRowReadModel(
        title: 'Edit profile',
        subtitle: 'Email, personal details, and onboarding',
        snackBarMessage: '',
        action: UserProfileManageAction.editProfile,
      ),
    ],
  );
}

class _SingleProfileRepository implements UserProfileRepository {
  const _SingleProfileRepository(this.profile);

  final UserProfileReadModel profile;

  @override
  Future<UserProfileReadModel> loadUserProfile() async => profile;
}

class _SingleUserProgressRepository implements UserProgressRepository {
  const _SingleUserProgressRepository(this.progress);

  final UserProgressReadModel progress;

  @override
  Future<UserProgressReadModel> loadUserProgress() async => progress;

  @override
  Future<UserProgressReadModel> refreshUserProgress() async => progress;
}

class _SingleLeaderboardRepository implements LeaderboardRepository {
  const _SingleLeaderboardRepository(this.leaderboard);

  final LeaderboardReadModel leaderboard;

  @override
  Future<LeaderboardReadModel> loadLeaderboard() async => leaderboard;

  @override
  Future<LeaderboardReadModel> loadRegion({required String regionId}) async =>
      leaderboard;
}

class _CompletingProfileRepository implements UserProfileRepository {
  const _CompletingProfileRepository(this.profile);

  final Future<UserProfileReadModel> profile;

  @override
  Future<UserProfileReadModel> loadUserProfile() => profile;
}

class _MissingUserProfileDocumentReader implements UserProfileDocumentReader {
  const _MissingUserProfileDocumentReader();

  @override
  Future<UserProfileDocumentReadResult> readUserProfile({
    required String uid,
  }) async {
    return const UserProfileDocumentReadResult.missing();
  }
}

class _MutableProfileRepository implements UserProfileRepository {
  _MutableProfileRepository(this.profile);

  UserProfileReadModel profile;
  int loadCount = 0;

  @override
  Future<UserProfileReadModel> loadUserProfile() async {
    loadCount += 1;
    return profile;
  }
}

class _RecordingGeneratedPlanPersistenceRepository
    implements GeneratedPlanPersistenceRepository {
  String? savedUid;
  BeginnerAdaptivePlanSnapshot? savedPlan;
  bool failNextSave = false;
  int saveCalls = 0;

  @override
  Future<BeginnerAdaptivePlanSnapshot?> loadGeneratedPlan({
    required String uid,
  }) async {
    return null;
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

class _RecordingUserProfilePersistenceRepository
    implements UserProfilePersistenceRepository {
  _RecordingUserProfilePersistenceRepository({
    this.nicknameAvailable = true,
    this.nicknameCheckError,
    this.onSaveOnboardingProfile,
    this.onSavePersonalProfile,
  });

  final bool nicknameAvailable;
  final NicknameAvailabilityCheckException? nicknameCheckError;
  final ValueChanged<UserProfileOnboardingSnapshot>? onSaveOnboardingProfile;
  final ValueChanged<UserProfilePersonalSnapshot>? onSavePersonalProfile;
  String? uid;
  String? checkedNickname;
  UserProfilePersonalSnapshot? personalProfile;
  UserProfileOnboardingSnapshot? onboardingProfile;

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async {
    checkedNickname = nickname;
    if (nicknameCheckError != null) {
      throw nicknameCheckError!;
    }
    return nicknameAvailable;
  }

  @override
  Future<void> saveOnboardingProfile({
    required String uid,
    required UserProfileOnboardingSnapshot profile,
  }) async {
    this.uid = uid;
    onboardingProfile = profile;
    onSaveOnboardingProfile?.call(profile);
  }

  @override
  Future<void> savePersonalProfile({
    required String uid,
    required UserProfilePersonalSnapshot profile,
  }) async {
    this.uid = uid;
    personalProfile = profile;
    onSavePersonalProfile?.call(profile);
  }
}
