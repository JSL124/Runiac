import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/shell/current_day_rollover.dart';
import 'package:runiac_app/features/shell/runiac_shell.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/user_progress_repository.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  test('refresh advances the shell date after local midnight', () {
    var now = DateTime(2026, 7, 10, 23, 59);
    final controller = CurrentDayRolloverController(now: () => now);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    expect(controller.today, DateTime(2026, 7, 10));

    now = DateTime(2026, 7, 11);
    controller.refresh();

    expect(controller.today, DateTime(2026, 7, 11));
    expect(notifications, 1);
  });

  test('next refresh delay targets the next local midnight', () {
    expect(
      nextLocalDayRefreshDelay(DateTime(2026, 7, 10, 23, 59, 30)),
      const Duration(seconds: 30),
    );
  });

  testWidgets('shell refreshes backend-owned progress on local midnight', (
    tester,
  ) async {
    var now = DateTime(2026, 7, 10, 23, 59);
    final controller = CurrentDayRolloverController(now: () => now);
    final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
    final progressRepository = _CountingUserProgressRepository();
    final activityHistoryStore = CurrentSessionActivityHistoryStore(
      ownerUid: 'test-auth-user-1',
    );
    addTearDown(authRepository.dispose);
    addTearDown(activityHistoryStore.dispose);

    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    addTearDown(generatedPlanStore.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CurrentSessionActivityHistoryScope(
          store: activityHistoryStore,
          child: CurrentSessionGeneratedPlanScope(
            store: generatedPlanStore,
            child: RuniacShell(
              authRepository: authRepository,
              feedRepository: const StaticFeedRepository(),
              userProgressRepository: progressRepository,
              profileRepository: const StaticUserProfileRepository(),
              profilePersistenceRepository:
                  const NoopUserProfilePersistenceRepository(),
              enableForegroundGps: false,
              currentDayRolloverController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Feed'));
    await tester.pumpAndSettle();

    expect(progressRepository.refreshCalls, 0);

    now = DateTime(2026, 7, 11);
    controller.refresh();
    await tester.pumpAndSettle();

    expect(progressRepository.refreshCalls, 1);
    expect(
      activityHistoryStore.latestUserProgressRefresh?.officialStreakLabel,
      '4 days',
    );
    expect(activityHistoryStore.userProgressRefreshRevision, 1);
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'shell keeps Home progress and profile visible when returning from Feed',
    (tester) async {
      final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
      final progressRepository = _DelayedCountingUserProgressRepository();
      final profileRepository = _DelayedCountingUserProfileRepository();
      final activityHistoryStore = CurrentSessionActivityHistoryStore(
        ownerUid: 'test-auth-user-1',
      );
      addTearDown(authRepository.dispose);
      addTearDown(activityHistoryStore.dispose);

      final generatedPlanStore = CurrentSessionGeneratedPlanStore();
      addTearDown(generatedPlanStore.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CurrentSessionActivityHistoryScope(
            store: activityHistoryStore,
            child: CurrentSessionGeneratedPlanScope(
              store: generatedPlanStore,
              child: RuniacShell(
                authRepository: authRepository,
                feedRepository: const StaticFeedRepository(),
                userProgressRepository: progressRepository,
                profileRepository: profileRepository,
                profilePersistenceRepository:
                    const NoopUserProfilePersistenceRepository(),
                enableForegroundGps: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      progressRepository.completePending(_profileProgress);
      profileRepository.completePending(_profile);
      await tester.pumpAndSettle();

      expect(find.text('Lv.6'), findsOneWidget);
      expect(find.text('ZX'), findsOneWidget);
      final initialProgressLoads = progressRepository.loadCalls;
      final initialProfileLoads = profileRepository.loadCalls;

      await tester.tap(find.byTooltip('Feed'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Home'));
      await tester.pump();

      expect(progressRepository.loadCalls, initialProgressLoads);
      expect(profileRepository.loadCalls, initialProfileLoads);
      expect(find.text('Lv.6'), findsOneWidget);
      expect(find.text('ZX'), findsOneWidget);
      expect(find.text('Lv.0'), findsNothing);
      expect(find.text('R'), findsNothing);

      // The streak now lives in the Menu panel; opening it must still show the
      // carried-over value without triggering a refetch.
      await tester.tap(find.byKey(const ValueKey('homeMenuTrigger')));
      await tester.pumpAndSettle();
      expect(find.text('7 day streak'), findsOneWidget);
      expect(progressRepository.loadCalls, initialProgressLoads);
      await tester.tap(find.byKey(const ValueKey('homeMenuBarrier')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _CountingUserProgressRepository implements UserProgressRepository {
  int loadCalls = 0;
  int refreshCalls = 0;

  @override
  Future<UserProgressReadModel> loadUserProgress() async {
    loadCalls += 1;
    return _progress;
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() async {
    refreshCalls += 1;
    return _progress;
  }
}

const _progress = UserProgressReadModel(
  userId: 'test-auth-user-1',
  officialStreakLabel: '4 days',
  levelLabel: 'Level 4',
  totalXpLabel: '400 XP',
  weeklyXpLabel: '',
  monthlyXpLabel: '',
  weeklyDistanceLabel: '',
  goalProgressLabel: '',
);

const _profileProgress = UserProgressReadModel(
  userId: 'test-auth-user-1',
  officialStreakLabel: '7 days',
  officialStreakCount: 7,
  level: 6,
  levelLabel: 'Level 6',
  totalXpLabel: '600 XP',
  weeklyXpLabel: '',
  monthlyXpLabel: '',
  weeklyDistanceLabel: '',
  goalProgressLabel: '',
);

final _profile = UserProfileReadModel(
  userId: 'test-auth-user-1',
  displayName: 'Zoe X',
  avatarInitials: 'ZX',
  locationLabel: 'Jurong East, Singapore',
);

class _DelayedCountingUserProgressRepository implements UserProgressRepository {
  final List<Completer<UserProgressReadModel>> _pendingLoads =
      <Completer<UserProgressReadModel>>[];
  int loadCalls = 0;
  int refreshCalls = 0;

  @override
  Future<UserProgressReadModel> loadUserProgress() {
    loadCalls += 1;
    final completer = Completer<UserProgressReadModel>();
    _pendingLoads.add(completer);
    return completer.future;
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() async {
    refreshCalls += 1;
    return _profileProgress;
  }

  void completePending(UserProgressReadModel progress) {
    for (final completer in List<Completer<UserProgressReadModel>>.of(
      _pendingLoads,
    )) {
      if (!completer.isCompleted) {
        completer.complete(progress);
      }
    }
    _pendingLoads.clear();
  }
}

class _DelayedCountingUserProfileRepository implements UserProfileRepository {
  final List<Completer<UserProfileReadModel>> _pendingLoads =
      <Completer<UserProfileReadModel>>[];
  int loadCalls = 0;

  @override
  Future<UserProfileReadModel> loadUserProfile() {
    loadCalls += 1;
    final completer = Completer<UserProfileReadModel>();
    _pendingLoads.add(completer);
    return completer.future;
  }

  void completePending(UserProfileReadModel profile) {
    for (final completer in List<Completer<UserProfileReadModel>>.of(
      _pendingLoads,
    )) {
      if (!completer.isCompleted) {
        completer.complete(profile);
      }
    }
    _pendingLoads.clear();
  }
}
