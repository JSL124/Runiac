import '../models/activity_history_read_model.dart';

abstract interface class ActivityHistoryRepository {
  Future<ActivityHistoryReadModel> loadActivityHistory();
}
