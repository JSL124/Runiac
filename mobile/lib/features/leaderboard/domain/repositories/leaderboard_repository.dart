import '../models/leaderboard_read_model.dart';

abstract interface class LeaderboardRepository {
  Future<LeaderboardReadModel> loadLeaderboard();

  Future<LeaderboardReadModel> loadRegion({required String regionId});
}

abstract interface class LiveLeaderboardRepository
    implements LeaderboardRepository {
  Stream<LeaderboardReadModel> watchLeaderboard();
}
