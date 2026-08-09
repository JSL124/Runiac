import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';
import 'package:runiac_app/features/leaderboard/domain/models/leaderboard_read_model.dart';
import 'package:runiac_app/features/leaderboard/domain/repositories/leaderboard_repository.dart';
import 'package:runiac_app/features/leaderboard/presentation/leaderboard_tab.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/user_progress_repository.dart';

void main() {
  testWidgets(
    'Leaderboard automatically shows the promoted division from its live repository',
    (tester) async {
      final repository = _LiveLeaderboardRepository(_leaderboard('tier_01'));
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LeaderboardTab(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Iron'), findsOneWidget);

      repository.publish(_leaderboard('tier_02'));
      await tester.pumpAndSettle();

      expect(find.text('Bronze'), findsOneWidget);
      expect(find.text('Iron'), findsNothing);
    },
  );

  testWidgets(
    'Account automatically changes its division badge after a promoted progress update',
    (tester) async {
      final progress = _LiveUserProgressRepository(_progress('tier_01'));
      addTearDown(progress.dispose);

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          enableForegroundGps: false,
          profileRepository: const _ProfileRepository(),
          userProgressRepository: progress,
          leaderboardRepository: _LiveLeaderboardRepository(
            _leaderboard('tier_01'),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Profile'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-division-badge-tier_01')),
        findsOneWidget,
      );

      progress.publish(_progress('tier_02'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('account-division-badge-tier_02')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('account-division-badge-tier_01')),
        findsNothing,
      );
    },
  );
}

LeaderboardReadModel _leaderboard(String divisionKey) {
  final isBronze = divisionKey == 'tier_02';
  return LeaderboardReadModel(
    status: LeaderboardReadStatus.data,
    regionId: 'jurong-east',
    homeRegionId: 'jurong-east',
    regionLabel: 'Jurong East',
    divisionKey: divisionKey,
    divisionLabel: isBronze ? 'Bronze League' : 'Iron League',
    currentRunnerRankLabel: '#1',
    entries: const [],
  );
}

UserProgressReadModel _progress(String divisionKey) {
  final isBronze = divisionKey == 'tier_02';
  return UserProgressReadModel(
    userId: 'test-auth-user-1',
    officialStreakLabel: '',
    level: isBronze ? 11 : 10,
    levelProgressFraction: 0,
    divisionKey: divisionKey,
    divisionLabel: isBronze ? 'Bronze League' : 'Iron League',
    totalXp: isBronze ? 1050 : 990,
    nextLevelXp: isBronze ? 1200 : 1050,
    xpToNextLevel: 150,
    levelLabel: isBronze ? 'Level 11' : 'Level 10',
    totalXpLabel: isBronze ? '1,050 XP' : '990 XP',
    weeklyXpLabel: '',
    monthlyXpLabel: '',
    weeklyDistanceLabel: '',
    goalProgressLabel: '',
  );
}

class _LiveLeaderboardRepository implements LiveLeaderboardRepository {
  _LiveLeaderboardRepository(this._current);

  final StreamController<LeaderboardReadModel> _controller =
      StreamController<LeaderboardReadModel>.broadcast();
  LeaderboardReadModel _current;

  @override
  Future<LeaderboardReadModel> loadLeaderboard() async => _current;

  @override
  Future<LeaderboardReadModel> loadRegion({required String regionId}) async =>
      _current;

  @override
  Stream<LeaderboardReadModel> watchLeaderboard() => _controller.stream;

  void publish(LeaderboardReadModel value) {
    _current = value;
    _controller.add(value);
  }

  Future<void> dispose() => _controller.close();
}

class _LiveUserProgressRepository implements LiveUserProgressRepository {
  _LiveUserProgressRepository(this._current);

  final StreamController<UserProgressReadModel> _controller =
      StreamController<UserProgressReadModel>.broadcast();
  UserProgressReadModel _current;

  @override
  Future<UserProgressReadModel> loadUserProgress() async => _current;

  @override
  Future<UserProgressReadModel> refreshUserProgress() async => _current;

  @override
  Stream<UserProgressReadModel> watchUserProgress() => _controller.stream;

  void publish(UserProgressReadModel value) {
    _current = value;
    _controller.add(value);
  }

  Future<void> dispose() => _controller.close();
}

class _ProfileRepository implements UserProfileRepository {
  const _ProfileRepository();

  @override
  Future<UserProfileReadModel> loadUserProfile() async => UserProfileReadModel(
    userId: 'test-auth-user-1',
    displayName: 'League Runner',
    fullName: '',
    nickname: 'League Runner',
    dateOfBirthIso: '',
    avatarInitials: 'LR',
    ageYears: null,
    weightKg: null,
    locationLabel: 'Jurong East, Singapore',
    previewLevelBadge: '',
    previewNote: '',
    setupSectionLabel: 'RUNNING SETUP',
    manageSectionLabel: 'MANAGE',
    footerCaption: '',
    onboardingDraft: null,
    setupItems: [],
    manageRows: [],
  );
}
