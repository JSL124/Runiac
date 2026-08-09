import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/run/presentation/view_summary_screen.dart';
import 'package:runiac_app/features/you/domain/models/activity_history_read_model.dart';
import 'package:runiac_app/features/you/domain/repositories/activity_history_repository.dart';

void main() {
  group('Running Activity History user-link', () {
    testWidgets(
      'You tab renders authenticated activity history repository rows',
      (tester) async {
        final repository = _FakeActivityHistoryRepository.authenticated();

        await _openYouTab(tester, activityHistoryRepository: repository);

        expect(repository.loadCount, 1);
        expect(find.text('Authenticated Recovery Run'), findsOneWidget);
        expect(find.text('12 Jun 2026'), findsOneWidget);
        expect(find.text('3.20 km'), findsOneWidget);
        expect(find.text('7\'10"'), findsOneWidget);
        expect(find.text('22:56'), findsOneWidget);
        expect(find.text('Easy Morning Jog'), findsNothing);
      },
    );

    testWidgets('Activity History renders authenticated repository rows', (
      tester,
    ) async {
      final repository = _FakeActivityHistoryRepository.authenticated();

      await _openActivityHistoryFromYou(
        tester,
        activityHistoryRepository: repository,
      );

      expect(repository.loadCount, 1);
      expect(find.text('Authenticated Recovery Run'), findsOneWidget);
      expect(find.text('12 Jun 2026'), findsOneWidget);
      expect(find.text('3.20 km'), findsOneWidget);
      expect(find.text('7\'10"'), findsOneWidget);
      expect(find.text('22:56'), findsOneWidget);
    });

    testWidgets('Authenticated empty history does not show demo activity rows', (
      tester,
    ) async {
      final repository = _FakeActivityHistoryRepository.empty();

      await _openYouTab(tester, activityHistoryRepository: repository);

      final seeAll = find.byKey(const ValueKey('recent_running_see_all'));
      await Scrollable.ensureVisible(tester.element(seeAll), alignment: 0.55);
      await tester.pumpAndSettle();

      expect(repository.loadCount, 1);
      expect(find.text('Recent Running'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recent_running_empty_state')),
        findsOneWidget,
      );
      expect(find.text('Start your first run'), findsOneWidget);
      expect(
        find.text(
          "Start a run when you're ready. Your recent activities will appear here.",
        ),
        findsOneWidget,
      );
      expect(find.text('More Activities'), findsNothing);
      expect(find.text('Authenticated Recovery Run'), findsNothing);
      expect(find.text('Easy Morning Jog'), findsNothing);
      expect(
        find.text('We could not load your activity history.'),
        findsNothing,
      );

      await tester.tap(seeAll);
      await tester.pumpAndSettle();

      expect(find.text('Activity History'), findsOneWidget);
    });

    testWidgets(
      'Authenticated Activity History summary keeps XP update hidden',
      (tester) async {
        final repository = _FakeActivityHistoryRepository.authenticated();

        await _openActivityHistoryFromYou(
          tester,
          activityHistoryRepository: repository,
        );
        await tester.tap(find.text('Authenticated Recovery Run'));
        await tester.pumpAndSettle();

        expect(find.text('Authenticated Recovery Run'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'View XP Update'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'remote Activity History forwards its stable id to the summary cache',
      (tester) async {
        final repository = _FakeActivityHistoryRepository.authenticated();

        await _openActivityHistoryFromYou(
          tester,
          activityHistoryRepository: repository,
        );
        await tester.tap(find.text('Authenticated Recovery Run'));
        await tester.pumpAndSettle();

        final summaryScreen = tester.widget<ViewSummaryScreen>(
          find.byType(ViewSummaryScreen),
        );
        expect(
          summaryScreen.activityFeedbackCacheIdentity,
          'activity-authenticated-recovery',
        );
      },
    );

    testWidgets(
      'You tab keeps activity history usable when repository load fails',
      (tester) async {
        final repository = _FakeActivityHistoryRepository.failing();

        await _openActivityHistoryFromYou(
          tester,
          activityHistoryRepository: repository,
        );

        expect(repository.loadCount, 1);
        expect(find.text('Activity History'), findsOneWidget);
        expect(
          find.text('We could not load your activity history.'),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
      },
    );

    testWidgets('Activity History retry loads repository rows after failure', (
      tester,
    ) async {
      final repository =
          _RetryingActivityHistoryRepository.failOnceThenAuthenticated();

      await _openActivityHistoryFromYou(
        tester,
        activityHistoryRepository: repository,
      );

      expect(repository.loadCount, 1);
      expect(
        find.text('We could not load your activity history.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(repository.loadCount, 2);
      expect(
        find.text('We could not load your activity history.'),
        findsNothing,
      );
      expect(find.text('Authenticated Recovery Run'), findsOneWidget);
    });
  });
}

Future<void> _openYouTab(
  WidgetTester tester, {
  required ActivityHistoryRepository activityHistoryRepository,
}) async {
  await tester.pumpWidget(
    RuniacApp(
      showSplash: false,
      enableForegroundGps: false,
      activityHistoryRepository: activityHistoryRepository,
    ),
  );
  await tester.tap(find.byTooltip('You'));
  await tester.pumpAndSettle();
}

Future<void> _openActivityHistoryFromYou(
  WidgetTester tester, {
  required ActivityHistoryRepository activityHistoryRepository,
}) async {
  await _openYouTab(
    tester,
    activityHistoryRepository: activityHistoryRepository,
  );
  final seeAll = find.byKey(const ValueKey('recent_running_see_all'));
  await Scrollable.ensureVisible(tester.element(seeAll), alignment: 0.55);
  await tester.pumpAndSettle();
  await tester.tap(seeAll);
  await tester.pumpAndSettle();
}

class _FakeActivityHistoryRepository implements ActivityHistoryRepository {
  _FakeActivityHistoryRepository.authenticated()
    : _history = _authenticatedActivityHistory(),
      _failure = null;

  _FakeActivityHistoryRepository.empty()
    : _history = _emptyActivityHistory(),
      _failure = null;

  _FakeActivityHistoryRepository.failing()
    : _history = null,
      _failure = StateError('authenticated activity history unavailable');

  final ActivityHistoryReadModel? _history;
  final Object? _failure;
  int loadCount = 0;

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    loadCount += 1;
    final failure = _failure;
    if (failure != null) {
      throw failure;
    }
    return _history!;
  }
}

class _RetryingActivityHistoryRepository implements ActivityHistoryRepository {
  _RetryingActivityHistoryRepository.failOnceThenAuthenticated()
    : _remainingFailures = 1;

  int _remainingFailures;
  int loadCount = 0;

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    loadCount += 1;
    if (_remainingFailures > 0) {
      _remainingFailures -= 1;
      throw StateError('authenticated activity history unavailable');
    }
    return _authenticatedActivityHistory();
  }
}

ActivityHistoryReadModel _authenticatedActivityHistory() {
  const activity = ActivityHistoryItemReadModel(
    activityId: 'activity-authenticated-recovery',
    title: 'Authenticated Recovery Run',
    completedAtLabel: '12 Jun 2026',
    distanceLabel: '3.20 km',
    distanceMeters: 3200,
    paceLabel: '7\'10"',
    durationLabel: '22:56',
    routeNameLabel: 'Private route',
  );

  return ActivityHistoryReadModel(
    recentRuns: const <ActivityHistoryItemReadModel>[activity],
    months: <ActivityHistoryMonthReadModel>[
      ActivityHistoryMonthReadModel(
        label: 'June 2026',
        activities: const <ActivityHistoryItemReadModel>[activity],
      ),
    ],
  );
}

ActivityHistoryReadModel _emptyActivityHistory() {
  return ActivityHistoryReadModel(
    recentRuns: const <ActivityHistoryItemReadModel>[],
    months: const <ActivityHistoryMonthReadModel>[],
  );
}
