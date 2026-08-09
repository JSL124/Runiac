import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runiac_app/app.dart';
import 'package:runiac_app/core/widgets/runiac_level_profile_badge.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/home/presentation/home_tab.dart';
import 'package:runiac_app/features/home/presentation/data/home_dashboard_demo_snapshots.dart';
import 'package:runiac_app/features/home/presentation/widgets/home_progress_insight_section.dart';
import 'package:runiac_app/features/home/presentation/widgets/today_plan_card.dart';
import 'package:runiac_app/features/plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import 'package:runiac_app/features/plan/domain/services/beginner_adaptive_plan_generator.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/notifications/domain/models/notification_inbox_item.dart';
import 'package:runiac_app/features/notifications/domain/repositories/notification_inbox_repository.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/user_progress_repository.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

import 'support/fake_runiac_auth_repository.dart';
import 'support/plan_family_test_drafts.dart';

final _forbiddenTrustedStateCopy = RegExp(
  r'leaderboard score|saved count|popularity|owned|territory owned|'
  r'route completed|activity saved|synced|premium|subscription|'
  r'validated|eligible|enrolled|official',
  caseSensitive: false,
);

Finder _nearestDecoratedBoxContaining(String text) {
  return find
      .ancestor(of: find.text(text), matching: find.byType(DecoratedBox))
      .last;
}

RuniacLevelProfileBadge _homeBadge(WidgetTester tester) {
  return tester.widget<RuniacLevelProfileBadge>(
    find.byWidgetPredicate(
      (widget) =>
          widget is RuniacLevelProfileBadge &&
          widget.size == 54 &&
          widget.badgeHeight == 17,
    ),
  );
}
class _SingleUserProgressRepository implements UserProgressRepository {
  const _SingleUserProgressRepository(this.progress);

  final UserProgressReadModel progress;

  @override
  Future<UserProgressReadModel> loadUserProgress() async => progress;

  @override
  Future<UserProgressReadModel> refreshUserProgress() async => progress;
}

class _SingleUserProfileRepository implements UserProfileRepository {
  const _SingleUserProfileRepository(this.profile);

  final UserProfileReadModel profile;

  @override
  Future<UserProfileReadModel> loadUserProfile() async => profile;
}

class _HeldUserProfileRepository implements UserProfileRepository {
  final Completer<UserProfileReadModel> _completer =
      Completer<UserProfileReadModel>();

  @override
  Future<UserProfileReadModel> loadUserProfile() => _completer.future;
}

class _CountingUserProgressRepository implements UserProgressRepository {
  _CountingUserProgressRepository(this.progress);

  final UserProgressReadModel progress;
  int loadCalls = 0;
  int refreshCalls = 0;

  @override
  Future<UserProgressReadModel> loadUserProgress() async {
    loadCalls += 1;
    return progress;
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() async {
    refreshCalls += 1;
    return progress;
  }
}

class _HeldUserProgressRepository implements UserProgressRepository {
  final Completer<UserProgressReadModel> _completer =
      Completer<UserProgressReadModel>();
  int loadCalls = 0;
  int refreshCalls = 0;

  @override
  Future<UserProgressReadModel> loadUserProgress() {
    loadCalls += 1;
    return _completer.future;
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() {
    refreshCalls += 1;
    return _completer.future;
  }
}

class _AuthAwareUserProgressRepository implements UserProgressRepository {
  _AuthAwareUserProgressRepository({
    required this.authRepository,
    required this.progressByUid,
  });

  final FakeRuniacAuthRepository authRepository;
  final Map<String, UserProgressReadModel> progressByUid;
  int loadCalls = 0;

  @override
  Future<UserProgressReadModel> loadUserProgress() async {
    loadCalls += 1;
    return _progressForCurrentUser();
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() async {
    return _progressForCurrentUser();
  }

  UserProgressReadModel _progressForCurrentUser() {
    final uid = authRepository.currentUser?.uid;
    return progressByUid[uid] ??
        const UserProgressReadModel(
          userId: 'fallback',
          officialStreakLabel: '',
          levelLabel: 'Level 0',
          totalXpLabel: '0 XP',
          weeklyXpLabel: '',
          monthlyXpLabel: '0 XP',
          weeklyDistanceLabel: '',
          goalProgressLabel: '',
        );
  }
}

Future<void> _pumpHomeTab(
  WidgetTester tester, {
  required FakeRuniacAuthRepository authRepository,
  required UserProgressRepository userProgressRepository,
  UserProfileRepository profileRepository = const StaticUserProfileRepository(),
  CurrentSessionActivityHistoryStore? activityHistoryStore,
}) async {
  final homeTab = HomeTab(
    authRepository: authRepository,
    profileRepository: profileRepository,
    profilePersistenceRepository: const NoopUserProfilePersistenceRepository(),
    userProgressRepository: userProgressRepository,
    enableForegroundGps: false,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: activityHistoryStore == null
          ? homeTab
          : CurrentSessionActivityHistoryScope(
              store: activityHistoryStore,
              child: homeTab,
            ),
    ),
  );
}

const _longXpHomeSnapshot = HomeDashboardDemoSnapshot(
  todayPlan: homeTodayPlanDemoSnapshot,
  goal: HomeGoalProgressDemoSnapshot(
    title: 'First 10K Preparation',
    weekLabel: 'Week 3 of 8',
    progressLabel: '43%',
    milestoneLabel: 'Next Milestone',
    milestoneValue: 'Complete 6 km comfortably',
  ),
  streak: HomeMetricDemoSnapshot(
    title: 'Streak',
    value: '6 days',
    caption: 'Keep it going!',
  ),
  xp: HomeMetricDemoSnapshot(
    title: 'XP',
    value: '100,000 xp',
    caption: '360 XP to Lv.13',
  ),
  insight: HomeInsightDemoSnapshot(
    title: 'Advanced Insight',
    rows: [
      HomeInsightRowDemoSnapshot(
        icon: Icons.show_chart_rounded,
        label: 'Pace rhythm',
        value: 'Improved',
      ),
      HomeInsightRowDemoSnapshot(
        icon: Icons.bar_chart_rounded,
        label: 'Effort balance',
        value: 'Balanced',
      ),
      HomeInsightRowDemoSnapshot(
        icon: Icons.track_changes_rounded,
        label: 'Goal progress',
        value: 'On track',
      ),
    ],
    chartLabels: ['May 6', 'May 13', 'May 20', 'May 27', 'Jun 3'],
    chartValues: [0.42, 0.33, 0.18, 0.36, 0.55, 0.62, 0.72],
  ),
  exploreRoutes: homeExploreRouteDemoSnapshots,
);

/// A generated beginner plan whose active week has run sessions on Mon–Thu, so
/// the stage map renders a tappable "today" stage when today is that Monday.
BeginnerAdaptivePlanSnapshot _generatedRunPlan(DateTime startDate) {
  final plan = const BeginnerAdaptivePlanGenerator().generate(
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
  return plan.withStartsOnDate(generatedPlanDateLabel(startDate));
}

int _stageAssetCount(WidgetTester tester, String assetName) {
  return tester
      .widgetList<Image>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == assetName,
        ),
      )
      .length;
}

void main() {
  testWidgets('Home profile badge matches the account profile source', (
    WidgetTester tester,
  ) async {
    final profileRepository = _SingleUserProfileRepository(
      UserProfileReadModel(
        userId: 'runner-profile',
        displayName: 'Lee Runner',
        nickname: 'Lee Runner',
        avatarInitials: 'LR',
        locationLabel: 'Tampines, Singapore',
      ),
    );
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'runner-profile');

    await _pumpHomeTab(
      tester,
      authRepository: authRepository,
      userProgressRepository: const StaticUserProgressRepository(),
      profileRepository: profileRepository,
    );
    await tester.pumpAndSettle();

    expect(find.text('LR'), findsOneWidget);
    final homeInitials = tester.widget<Text>(find.text('LR'));
    expect(homeInitials.textAlign, TextAlign.center);
    expect(
      find.ancestor(of: find.text('LR'), matching: find.byType(FittedBox)),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Lee Runner'), findsOneWidget);
    expect(find.text('Tampines, Singapore'), findsOneWidget);
    expect(find.text('LR'), findsOneWidget);
  });

  testWidgets(
    'Home profile XP ring follows the latest backend progress refresh',
    (WidgetTester tester) async {
      final historyStore = CurrentSessionActivityHistoryStore(
        ownerUid: 'runner-progress',
      );
      final authRepository = FakeRuniacAuthRepository()
        ..emitSignedIn(uid: 'runner-progress');
      final progressRepository = _SingleUserProgressRepository(
        const UserProgressReadModel(
          userId: 'runner-progress',
          officialStreakLabel: '',
          level: 1,
          levelProgressFraction: 0.66,
          levelLabel: 'Level 1',
          totalXpLabel: '66 XP',
          weeklyXpLabel: '',
          monthlyXpLabel: '66 XP',
          weeklyDistanceLabel: '',
          goalProgressLabel: '',
        ),
      );

      await _pumpHomeTab(
        tester,
        authRepository: authRepository,
        userProgressRepository: progressRepository,
        activityHistoryStore: historyStore,
      );
      await tester.pumpAndSettle();

      expect(_homeBadge(tester).progressFraction, 0.66);

      historyStore.recordUserProgressRefresh(
        const UserProgressReadModel(
          userId: 'runner-progress',
          officialStreakLabel: '',
          level: 1,
          levelProgressFraction: 0.5,
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
      );
      await tester.pump();

      expect(_homeBadge(tester).progressFraction, 0.5);
    },
  );

  testWidgets(
    'Home stage map shows the empty journey state and a live header',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const RuniacApp(showSplash: false, enableForegroundGps: false),
      );
      await tester.pumpAndSettle();

      // The default app has no active plan, so the stage map shows its friendly
      // empty state instead of the retired dashboard cards.
      expect(find.text('Your journey map is waiting'), findsOneWidget);
      expect(find.text('Good to see you'), findsNothing);
      expect(find.text('Today\'s Plan'), findsNothing);
      expect(find.text('Quick Start'), findsNothing);
      expect(find.text('View Plan'), findsNothing);
      expect(find.text('Advanced Insight'), findsNothing);
      expect(find.byType(TodayPlanCard), findsNothing);
      expect(find.byType(HomeProgressInsightSection), findsNothing);

      // Streak and notifications moved into the Menu panel, so the header
      // itself carries only the profile and the Menu trigger.
      expect(find.byIcon(Icons.local_fire_department), findsNothing);
      expect(find.bySemanticsLabel('Notifications'), findsNothing);
      expect(find.bySemanticsLabel('Menu'), findsOneWidget);
      expect(find.bySemanticsLabel('Profile'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();

      // The streak readout stays the backend-owned number (0 with no
      // progress) and never a fabricated "days" label.
      expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
      expect(find.text('0 day streak'), findsOneWidget);
      expect(find.textContaining('days'), findsNothing);

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('No notifications yet'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Runiac'), findsNothing);
      expect(find.text('Runiac Runner'), findsOneWidget);
      final displayName = tester.widget<Text>(find.text('Runiac Runner'));
      expect(displayName.maxLines, 2);
      expect(displayName.overflow, TextOverflow.ellipsis);
      expect(find.text('Jurong East, Singapore'), findsOneWidget);
      expect(find.text('Lv.0'), findsWidgets);
      expect(find.text('Preview only'), findsNothing);
      expect(find.text('Goal'), findsNothing);
      expect(find.text('Lv. 1'), findsNothing);
      expect(find.text('Beginner 10K preparation'), findsNothing);
      expect(find.text('Building consistency'), findsNothing);
      expect(
        find.text('Account changes are not saved in this prototype.'),
        findsOneWidget,
      );
      expect(find.text('YOUR TRAINING PROFILE'), findsOneWidget);
      expect(find.text('Current goal'), findsOneWidget);
      expect(find.text('Work toward a 10K'), findsOneWidget);
      expect(find.text('Starting point'), findsOneWidget);
      expect(find.text('Getting started'), findsOneWidget);
      expect(find.text('Plan style'), findsOneWidget);
      expect(find.text('Balanced progression'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
      expect(find.text('3 sessions / week · Mon · Wed · Sat'), findsOneWidget);
      expect(find.text('Session length'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('Safety'), findsOneWidget);
      expect(find.text('Cleared to start'), findsOneWidget);
      expect(
        find.text(
          'Based on how often you run now and the days you can commit to.',
        ),
        findsOneWidget,
      );
      // Settings now lives in the Home stage-map Menu, not the Manage list.
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Privacy & Safety'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      // Health import is not implemented, so the Manage list must not offer
      // a watch or health-app entry point at all.
      expect(find.text('Watch & Health Apps'), findsNothing);
      expect(find.text('Connect watch runs and health apps'), findsNothing);
      expect(find.text('About Runiac'), findsOneWidget);
      expect(find.text('Connect watch runs later'), findsNothing);
      expect(
        find.text('Profile settings preview is coming soon.'),
        findsNothing,
      );
      for (final forbiddenCopy in <String>[
        'Synced',
        'HealthKit',
        'Connected',
        'logout',
        'delete account',
        'Firebase',
        'Auth',
        'Signed in',
        'signed in',
        'verified account',
        'location permission',
        'GPS',
        'subscription',
        'entitlement',
        'XP',
        // 'streak' intentionally allowed: the profile screen now surfaces the
        // backend-owned Max streak stat beneath the progression bar.
        'level',
        'Level',
        'rank',
        'leaderboard',
        'published',
        'approved',
        'expert publication',
        'admin review',
      ]) {
        expect(find.textContaining(forbiddenCopy), findsNothing);
      }

      await tester.tap(find.bySemanticsLabel('Back to Home'));
      await tester.pumpAndSettle();

      expect(find.text('Your journey map is waiting'), findsOneWidget);
      expect(find.text('Profile'), findsNothing);

      expect(find.text('This Week\'s Plan'), findsNothing);
      expect(find.text('Last Run'), findsNothing);
      expect(find.text('Post-run Feedback'), findsNothing);
      expect(find.text('Complete a run to see your summary.'), findsNothing);
      expect(
        find.text('Feedback will appear after a completed run.'),
        findsNothing,
      );
      expect(find.text('View Details'), findsNothing);
      expect(find.text('Ready for an easy run?'), findsNothing);
      expect(find.text('Start small and keep it comfortable.'), findsNothing);
      expect(find.textContaining(_forbiddenTrustedStateCopy), findsNothing);
    },
  );

  testWidgets('Home profile badge reads backend-owned level progress', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        userProgressRepository: _SingleUserProgressRepository(
          UserProgressReadModel(
            userId: 'runner-42',
            officialStreakLabel: '3 days',
            level: 6,
            levelProgressFraction: 0.2,
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

    await tester.pumpAndSettle();

    expect(find.text('Lv.6'), findsOneWidget);
    expect(find.text('Lv.0'), findsNothing);
    expect(find.text('Lv.12'), findsNothing);
  });

  testWidgets('Home shows loading placeholder instead of default progress', (
    WidgetTester tester,
  ) async {
    final progressRepository = _HeldUserProgressRepository();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        userProgressRepository: progressRepository,
      ),
    );
    await tester.pump();

    expect(find.text('Lv.0'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RuniacLevelProfileBadge &&
            widget.size == 54 &&
            widget.badgeHeight == 17,
      ),
      findsNothing,
    );
    expect(progressRepository.refreshCalls, 0);
  });

  testWidgets('Home hides profile badge while profile is still loading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        profileRepository: _HeldUserProfileRepository(),
        userProgressRepository: const _SingleUserProgressRepository(
          UserProgressReadModel(
            userId: 'runner-42',
            officialStreakLabel: '4 days',
            level: 4,
            levelProgressFraction: 0.42,
            levelLabel: 'Level 4',
            totalXpLabel: '1,240 XP',
            weeklyXpLabel: '180 XP',
            monthlyXpLabel: '620 XP',
            weeklyDistanceLabel: '12.4 km',
            goalProgressLabel: '43%',
            officialStreakCount: 4,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Lv.4'), findsNothing);
    expect(find.text('Lv.0'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RuniacLevelProfileBadge &&
            widget.size == 54 &&
            widget.badgeHeight == 17,
      ),
      findsNothing,
    );
  });

  testWidgets('Home profile progress load is not repeated by inbox updates', (
    WidgetTester tester,
  ) async {
    final progressRepository = _CountingUserProgressRepository(
      const UserProgressReadModel(
        userId: 'runner-42',
        officialStreakLabel: '3 days',
        level: 6,
        levelProgressFraction: 0.2,
        levelLabel: 'Level 6',
        totalXpLabel: '520 XP',
        weeklyXpLabel: '',
        monthlyXpLabel: '520 XP',
        weeklyDistanceLabel: '',
        goalProgressLabel: '',
      ),
    );
    final notificationRepository = InMemoryNotificationInboxRepository();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        userProgressRepository: progressRepository,
        notificationInboxRepository: notificationRepository,
      ),
    );
    await tester.pumpAndSettle();

    // The shell syncs the feed-author profile once and Home reads its own
    // profile progress once; inbox changes must not add another progress read.
    expect(progressRepository.loadCalls, 2);
    expect(progressRepository.refreshCalls, 0);

    await notificationRepository.saveInboxItem(
      NotificationInboxItem(
        id: 'profile-cache-notification',
        title: 'Plan reminder',
        body: 'Your gentle run is ready.',
        createdAt: DateTime.utc(2026, 7, 8, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lv.6'), findsOneWidget);
    expect(progressRepository.loadCalls, 2);
    expect(progressRepository.refreshCalls, 0);
  });

  testWidgets('Home profile progress refreshes after returning from Account', (
    WidgetTester tester,
  ) async {
    final progressRepository = _CountingUserProgressRepository(
      const UserProgressReadModel(
        userId: 'runner-42',
        officialStreakLabel: '3 days',
        level: 6,
        levelProgressFraction: 0.2,
        levelLabel: 'Level 6',
        totalXpLabel: '520 XP',
        weeklyXpLabel: '',
        monthlyXpLabel: '520 XP',
        weeklyDistanceLabel: '',
        goalProgressLabel: '',
      ),
    );

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        userProgressRepository: progressRepository,
      ),
    );
    await tester.pumpAndSettle();

    // The shell syncs the feed-author profile once and Home reads its own
    // profile progress once before the Account round trip.
    expect(progressRepository.loadCalls, 2);
    expect(progressRepository.refreshCalls, 0);

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back to Home'));
    await tester.pumpAndSettle();

    expect(find.text('Your journey map is waiting'), findsOneWidget);
    // Two reads on the way back: Home refreshes its own progress, and the
    // shell re-reads the feed-author profile because an Account edit can have
    // renamed the runner, and every Feed surface labels them by that name.
    expect(progressRepository.loadCalls, 4);
    expect(progressRepository.refreshCalls, 1);
  });

  testWidgets('Home profile progress cache follows auth user changes', (
    WidgetTester tester,
  ) async {
    final authRepository = FakeRuniacAuthRepository()
      ..emitSignedIn(uid: 'runner-a');
    final progressRepository = _AuthAwareUserProgressRepository(
      authRepository: authRepository,
      progressByUid: const {
        'runner-a': UserProgressReadModel(
          userId: 'runner-a',
          officialStreakLabel: '3 days',
          level: 6,
          levelProgressFraction: 0.2,
          levelLabel: 'Level 6',
          totalXpLabel: '520 XP',
          weeklyXpLabel: '',
          monthlyXpLabel: '520 XP',
          weeklyDistanceLabel: '',
          goalProgressLabel: '',
        ),
        'runner-b': UserProgressReadModel(
          userId: 'runner-b',
          officialStreakLabel: '4 days',
          level: 9,
          levelProgressFraction: 0.5,
          levelLabel: 'Level 9',
          totalXpLabel: '900 XP',
          weeklyXpLabel: '',
          monthlyXpLabel: '900 XP',
          weeklyDistanceLabel: '',
          goalProgressLabel: '',
        ),
      },
    );

    await _pumpHomeTab(
      tester,
      authRepository: authRepository,
      userProgressRepository: progressRepository,
    );
    await tester.pumpAndSettle();

    expect(find.text('Lv.6'), findsOneWidget);
    expect(progressRepository.loadCalls, 1);

    authRepository.emitSignedIn(uid: 'runner-b');
    await _pumpHomeTab(
      tester,
      authRepository: authRepository,
      userProgressRepository: progressRepository,
    );
    await tester.pumpAndSettle();

    expect(find.text('Lv.9'), findsOneWidget);
    expect(find.text('Lv.6'), findsNothing);
    expect(progressRepository.loadCalls, 2);
  });

  testWidgets('Account Settings and About rows open their screens', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'Runiac',
      packageName: 'app.runiac',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);

    // Settings is reached from the Home stage-map Menu, not from the Profile
    // screen, so step back out to Home first.
    await tester.tap(find.bySemanticsLabel('Back to Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_menu_settings')));
    await tester.pumpAndSettle();

    expect(find.text('Distance units'), findsOneWidget);
    expect(find.text('APP COMFORT'), findsOneWidget);
    expect(find.text('PROFILE VISIBILITY'), findsOneWidget);

    // Settings was pushed from Home, so backing out lands on Home; re-enter
    // Profile for the About Runiac half of this test.
    await tester.tap(find.byTooltip('Back to Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('About Runiac'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('About Runiac'));
    await tester.pumpAndSettle();

    expect(find.text('Built for new runners'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);

    expect(find.text('Settings preview is coming soon.'), findsNothing);
    expect(find.text('About Runiac preview is coming soon.'), findsNothing);
  });

  testWidgets('Account opens Privacy & Safety guide consent from Manage', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Privacy & Safety'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy & Safety'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('privacySafetyGuideConsentSwitch')),
      findsOneWidget,
    );
    expect(find.text('Personalized guide'), findsOneWidget);
  });

  testWidgets('Account profile preview fits a narrow mobile surface', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Runiac'), findsNothing);
    expect(find.text('Runiac Runner'), findsOneWidget);
    expect(find.text('Jurong East, Singapore'), findsOneWidget);
    expect(find.text('Lv.0'), findsWidgets);
    expect(find.text('Preview only'), findsNothing);
    expect(find.text('Goal'), findsNothing);
    expect(find.text('Lv. 1'), findsNothing);
    expect(find.text('Beginner 10K preparation'), findsNothing);
    expect(find.text('Building consistency'), findsNothing);
    // Settings moved to the Home stage-map Menu, so the Profile body carries
    // the row no longer.
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Privacy & Safety'), findsOneWidget);
    expect(find.bySemanticsLabel('Back to Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home stage map fits a narrow surface and shows the streak in the Menu',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          userProgressRepository: _SingleUserProgressRepository(
            UserProgressReadModel(
              userId: 'runner-7',
              officialStreakLabel: '5 days',
              officialStreakCount: 5,
              level: 4,
              levelProgressFraction: 0.4,
              levelLabel: 'Level 4',
              totalXpLabel: '410 XP',
              weeklyXpLabel: '',
              monthlyXpLabel: '410 XP',
              weeklyDistanceLabel: '',
              goalProgressLabel: '',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The empty-state map lays out on a narrow device without overflowing.
      expect(find.text('Your journey map is waiting'), findsOneWidget);
      expect(find.text('Lv.4'), findsOneWidget);
      expect(find.text('Streak'), findsNothing);
      expect(find.text('Advanced Insight'), findsNothing);

      // The Menu panel fits the narrow surface and shows the backend-owned
      // streak count, never the raw "5 days" label.
      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('5 day streak'), findsOneWidget);
      expect(find.text('5 days'), findsNothing);
      expect(find.textContaining('days'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home goal progress percentage is vertically centered', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: HomeProgressInsightSection(),
          ),
        ),
      ),
    );

    final progressLabelRect = tester.getRect(find.text('43%'));
    final progressBarRect = tester.getRect(
      find.ancestor(of: find.text('43%'), matching: find.byType(Stack)).last,
    );

    expect(
      (progressLabelRect.center.dy - progressBarRect.center.dy).abs(),
      lessThanOrEqualTo(0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home stage map removes the retired dashboard sections', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const RuniacApp(showSplash: false, enableForegroundGps: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your journey map is waiting'), findsOneWidget);
    for (final removed in <String>[
      'Explore Routes',
      'Recommended Routes',
      'Community routes will appear here.',
      'View All',
      'Haneul Park Trail',
      'First 10K Preparation',
      'Next Milestone',
      'Route explorer preview',
    ]) {
      expect(find.text(removed), findsNothing);
    }
    expect(
      find.byKey(const ValueKey('home_explore_routes_carousel')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home XP mini card fits a long display value', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: HomeProgressInsightSection(snapshot: _longXpHomeSnapshot),
          ),
        ),
      ),
    );

    expect(find.text('Streak'), findsOneWidget);
    expect(find.text('6 days'), findsOneWidget);
    expect(find.text('XP'), findsOneWidget);
    expect(find.text('100,000 xp'), findsOneWidget);
    expect(find.text('360 XP to Lv.13'), findsOneWidget);

    final streakTitleRect = tester.getRect(find.text('Streak'));
    final xpTitleRect = tester.getRect(find.text('XP'));
    final longXpValueRect = tester.getRect(find.text('100,000 xp'));
    final xpCardRect = tester.getRect(_nearestDecoratedBoxContaining('XP'));

    expect(streakTitleRect.center.dx, lessThan(xpTitleRect.center.dx));
    expect(longXpValueRect.left, greaterThanOrEqualTo(xpCardRect.left));
    expect(longXpValueRect.right, lessThanOrEqualTo(xpCardRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home today plan hero keeps runner image and fills a narrow mobile surface',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodayPlanCard(onViewPlan: () {}, onQuickStart: () {}),
          ),
        ),
      );

      expect(find.text('Today\'s Plan'), findsOneWidget);
      expect(find.text('20 min easy run'), findsOneWidget);
      expect(find.text('Goal Mode: First 5K'), findsOneWidget);
      expect(
        find.text('Build consistency with an easy, comfortable effort.'),
        findsOneWidget,
      );
      expect(find.text('View Plan'), findsOneWidget);
      expect(find.text('Quick Start'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today_plan_hero_image')),
        findsOneWidget,
      );
      final heroClipFinder = find.ancestor(
        of: find.text('Today\'s Plan'),
        matching: find.byType(ClipRRect),
      );
      expect(heroClipFinder, findsNothing);
      final heroRect = tester.getRect(find.byType(TodayPlanCard));
      expect(heroRect.left, equals(0));
      expect(heroRect.right, equals(tester.view.physicalSize.width));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home stage map renders run and rest stones for an active plan', (
    WidgetTester tester,
  ) async {
    final monday = DateTime(2026, 6, 22); // a Monday
    final store = CurrentSessionGeneratedPlanStore();
    expect(store.setActivePlan(_generatedRunPlan(monday)), isTrue);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        youProgressToday: monday,
        currentSessionGeneratedPlanStore: store,
      ),
    );
    // Do not settle: today's stage runs a gentle repeating pulse.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Your journey map is waiting'), findsNothing);
    expect(
      _stageAssetCount(
        tester,
        'assets/images/home/stages/dashboard_stage_run.png',
      ),
      greaterThan(0),
    );
    expect(
      _stageAssetCount(
        tester,
        'assets/images/home/stages/dashboard_stage_rest.png',
      ),
      greaterThan(0),
    );
    expect(find.bySemanticsLabel("Today's stage"), findsOneWidget);
  });

  testWidgets('Home stage map advances to week 2 on the next Monday', (
    WidgetTester tester,
  ) async {
    final startMonday = DateTime(2026, 7, 6);
    final nextMonday = DateTime(2026, 7, 13);
    final store = CurrentSessionGeneratedPlanStore();
    expect(store.setActivePlan(_generatedRunPlan(startMonday)), isTrue);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        youProgressToday: nextMonday,
        currentSessionGeneratedPlanStore: store,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey<String>('homeStageStone-2-0')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel("Today's stage"), findsOneWidget);
  });

  testWidgets('Home stage map advances every week through week 8', (
    WidgetTester tester,
  ) async {
    final startMonday = DateTime(2026, 7, 6);

    for (var week = 1; week <= 8; week += 1) {
      final store = CurrentSessionGeneratedPlanStore();
      expect(store.setActivePlan(_generatedRunPlan(startMonday)), isTrue);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          youProgressToday: startMonday.add(Duration(days: 7 * (week - 1))),
          currentSessionGeneratedPlanStore: store,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(ValueKey<String>('homeStageStone-$week-0')),
        findsOneWidget,
        reason: 'Home should show week $week as the active Monday stage',
      );
      expect(find.bySemanticsLabel("Today's stage"), findsOneWidget);
    }
  });

  testWidgets('Home today stage opens the workout detail without editing', (
    WidgetTester tester,
  ) async {
    final monday = DateTime(2026, 6, 22); // a Monday
    final store = CurrentSessionGeneratedPlanStore();
    expect(store.setActivePlan(_generatedRunPlan(monday)), isTrue);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        youProgressToday: monday,
        currentSessionGeneratedPlanStore: store,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final todayStage = find.bySemanticsLabel("Today's stage");
    expect(todayStage, findsOneWidget);

    await tester.tap(todayStage);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Workout detail'), findsOneWidget);
    expect(find.text('Edit schedule'), findsNothing);

    final headerTitle = tester.widget<Text>(
      find.byKey(const ValueKey('workout_detail_header_title')),
    );
    expect(headerTitle.style?.fontSize, 20);
    expect(headerTitle.style?.decoration, isNot(TextDecoration.underline));
  });
}
