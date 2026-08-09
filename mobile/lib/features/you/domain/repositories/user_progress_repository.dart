import '../models/user_progress_read_model.dart';

abstract interface class UserProgressRepository {
  Future<UserProgressReadModel> loadUserProgress();

  Future<UserProgressReadModel> refreshUserProgress();
}

abstract interface class LiveUserProgressRepository
    implements UserProgressRepository {
  Stream<UserProgressReadModel> watchUserProgress();
}

class StaticUserProgressRepository implements UserProgressRepository {
  const StaticUserProgressRepository();

  @override
  Future<UserProgressReadModel> loadUserProgress() async {
    return const UserProgressReadModel(
      userId: 'static_you_progress',
      officialStreakLabel: '',
      levelLabel: 'Level 0',
      totalXpLabel: '0 XP',
      weeklyXpLabel: '',
      monthlyXpLabel: '0 XP',
      weeklyDistanceLabel: '12.4 km',
      goalProgressLabel: '43%',
      longestStreakLabel: '12 days',
      totalDistanceLabel: '148.6 km',
    );
  }

  @override
  Future<UserProgressReadModel> refreshUserProgress() {
    return loadUserProgress();
  }
}
