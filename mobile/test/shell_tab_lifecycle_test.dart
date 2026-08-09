import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/data/static_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/plan/presentation/current_session_generated_plan.dart';
import 'package:runiac_app/features/shell/runiac_shell.dart';
import 'package:runiac_app/features/you/domain/models/activity_history_read_model.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/activity_history_repository.dart';
import 'package:runiac_app/features/you/domain/repositories/user_progress_repository.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  testWidgets('shell keeps You tab alive across Home round trips', (
    tester,
  ) async {
    final authRepository = FakeRuniacAuthRepository()..emitSignedIn();
    final activityHistoryRepository = _CountingActivityHistoryRepository();
    final userProgressRepository = _CountingUserProgressRepository();
    final activityHistoryStore = CurrentSessionActivityHistoryStore(
      ownerUid: 'test-auth-user-1',
    );
    final generatedPlanStore = CurrentSessionGeneratedPlanStore();
    addTearDown(authRepository.dispose);
    addTearDown(activityHistoryStore.dispose);
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
              activityHistoryRepository: activityHistoryRepository,
              userProgressRepository: userProgressRepository,
              profileRepository: const StaticUserProfileRepository(),
              profilePersistenceRepository:
                  const NoopUserProfilePersistenceRepository(),
              enableForegroundGps: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(activityHistoryRepository.loadCalls, 0);

    await tester.tap(find.byTooltip('You'));
    await tester.pumpAndSettle();

    expect(activityHistoryRepository.loadCalls, 1);

    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('You'));
    await tester.pumpAndSettle();

    expect(activityHistoryRepository.loadCalls, 1);
  });
}

class _CountingActivityHistoryRepository implements ActivityHistoryRepository {
  int loadCalls = 0;

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    loadCalls += 1;
    return ActivityHistoryReadModel(recentRuns: const []);
  }
}

class _CountingUserProgressRepository implements UserProgressRepository {
  @override
  Future<UserProgressReadModel> loadUserProgress() async => _progress;

  @override
  Future<UserProgressReadModel> refreshUserProgress() async => _progress;
}

const _progress = UserProgressReadModel(
  userId: 'test-auth-user-1',
  officialStreakLabel: '4 days',
  levelLabel: 'Level 4',
  totalXpLabel: '400 XP',
  weeklyXpLabel: '',
  monthlyXpLabel: '',
  weeklyDistanceLabel: '',
  goalProgressLabel: '43%',
  level: 4,
  totalXp: 400,
);
