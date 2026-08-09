import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/you/domain/models/activity_history_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/activity_history_repository.dart';

void main() {
  testWidgets('RuniacApp accepts injected activity history repository', (
    tester,
  ) async {
    final repository = _RecordingActivityHistoryRepository();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        enableForegroundGps: false,
        activityHistoryRepository: repository,
      ),
    );

    await tester.tap(find.byTooltip('You'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('You'), findsOneWidget);
    expect(repository.loadCount, 1);
  });
}

class _RecordingActivityHistoryRepository implements ActivityHistoryRepository {
  var loadCount = 0;

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    loadCount += 1;
    return ActivityHistoryReadModel(
      recentRuns: const <ActivityHistoryItemReadModel>[],
    );
  }
}
