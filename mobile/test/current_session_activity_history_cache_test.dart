import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/you/domain/models/activity_history_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/activity_history_repository.dart';
import 'package:runiac_app/features/you/presentation/activity_history_display_controller.dart';
import 'package:runiac_app/features/you/presentation/current_session_activity_history.dart';

void main() {
  test(
    'retains last-good remote graph when Activity History refresh fails',
    () async {
      final repository = _OneGoodThenFailingActivityHistoryRepository(
        _historyWithMonth('June 2026'),
      );
      final controller = ActivityHistoryDisplayController(
        repository: repository,
      );
      addTearDown(controller.dispose);
      final store = CurrentSessionActivityHistoryStore(ownerUid: 'owner-1');
      addTearDown(store.dispose);

      await controller.load();
      expect(
        controller.months(store).map((month) => month.label),
        contains('June 2026'),
      );

      await controller.load();

      expect(controller.loadFailed, isTrue);
      expect(
        controller.months(store).map((month) => month.label),
        contains('June 2026'),
        reason:
            'A retryable refresh failure should keep the last-good remote '
            'Activity History graph/read model instead of erasing it.',
      );
    },
  );
}

ActivityHistoryReadModel _historyWithMonth(String label) {
  return ActivityHistoryReadModel(
    recentRuns: const <ActivityHistoryItemReadModel>[],
    months: <ActivityHistoryMonthReadModel>[
      ActivityHistoryMonthReadModel(
        label: label,
        activities: const <ActivityHistoryItemReadModel>[
          ActivityHistoryItemReadModel(
            activityId: 'remote-run-1',
            title: 'Remote run',
            completedAtLabel: '14/6/26',
            distanceLabel: '5.00 km',
            distanceMeters: 5000,
            paceLabel: '6:00/km',
            durationLabel: '30:00',
          ),
        ],
      ),
    ],
  );
}

class _OneGoodThenFailingActivityHistoryRepository
    implements ActivityHistoryRepository {
  _OneGoodThenFailingActivityHistoryRepository(this._history);

  final ActivityHistoryReadModel _history;
  var _calls = 0;

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    _calls += 1;
    if (_calls == 1) {
      return _history;
    }
    throw StateError('refresh failed');
  }
}
