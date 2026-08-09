import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/leaderboard/domain/models/leaderboard_read_model.dart';
import 'package:runiac_app/features/leaderboard/domain/repositories/leaderboard_repository.dart';
import 'package:runiac_app/features/leaderboard/presentation/leaderboard_status_copy.dart';
import 'package:runiac_app/features/leaderboard/presentation/leaderboard_tab.dart';
import 'package:runiac_app/features/leaderboard/presentation/widgets/leaderboard_ranking_screen.dart';

// Generic error strings the tab renders only on a thrown exception. None of the
// friendly backend statuses below should surface these.
const _initialErrorText = 'Leaderboard could not be loaded.';
const _bannerErrorText = 'Leaderboard could not be refreshed.';

LeaderboardReadModel _model({
  required LeaderboardReadStatus status,
  List<LeaderboardRowReadModel> entries = const [],
  List<LeaderboardRowReadModel> nearbyEntries = const [],
  String currentRunnerRankLabel = '',
}) {
  return LeaderboardReadModel(
    status: status,
    regionId: 'jurong-east',
    homeRegionId: 'jurong-east',
    regionLabel: 'Jurong East',
    divisionKey: 'tier_02',
    divisionLabel: 'Bronze League',
    currentRunnerRankLabel: currentRunnerRankLabel,
    entries: entries,
    nearbyEntries: nearbyEntries,
    periodLabel: 'July 2026',
    refreshLabel: 'Refreshes soon',
  );
}

const _sampleBoard = [
  LeaderboardRowReadModel(
    userId: 'runner-1',
    displayName: 'Ari S.',
    rankLabel: '#1',
    scoreLabel: '1,480 XP',
    levelLabel: 'Level 19',
    divisionLabel: 'Bronze',
    regionLabel: 'Jurong East',
  ),
  LeaderboardRowReadModel(
    userId: 'runner-2',
    displayName: 'Maya L.',
    rankLabel: '#2',
    scoreLabel: '1,320 XP',
    levelLabel: 'Level 18',
    divisionLabel: 'Bronze',
    regionLabel: 'Jurong East',
  ),
];

Future<void> _pumpTab(WidgetTester tester, LeaderboardReadModel model) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LeaderboardTab(repository: _FakeLeaderboardRepository(model)),
    ),
  );
  await tester.pumpAndSettle();
}

// Distance between the bottom of the actions row and the bottom of the sheet.
// It must stay equal to the sheet's own bottom padding in every status: any
// more than that is dead space the sheet is holding open for content it is not
// showing.
double _slackBelowActions(WidgetTester tester) {
  return tester
          .getRect(find.byKey(const Key('leaderboard_sheet_surface')))
          .bottom -
      tester
          .getRect(find.byKey(const Key('leaderboard_view_more_ranking_button')))
          .bottom;
}

double _sheetHeight(WidgetTester tester) {
  return tester
      .getSize(find.byKey(const Key('leaderboard_sheet_surface')))
      .height;
}

void _expectNoErrorCopy() {
  expect(find.text(_initialErrorText), findsNothing);
  expect(find.text(_bannerErrorText), findsNothing);
}

void main() {
  testWidgets('empty status shows friendly empty copy without an error', (
    tester,
  ) async {
    await _pumpTab(tester, _model(status: LeaderboardReadStatus.empty));

    expect(find.text(leaderboardEmptyStateTitle), findsOneWidget);
    expect(find.text(leaderboardEmptyStateBody('Jurong East')), findsOneWidget);
    _expectNoErrorCopy();
  });

  testWidgets('empty status View More Ranking still pushes the ranking page', (
    tester,
  ) async {
    await _pumpTab(tester, _model(status: LeaderboardReadStatus.empty));

    expect(find.byType(LeaderboardRankingScreen), findsNothing);

    await tester.tap(
      find.byKey(const Key('leaderboard_view_more_ranking_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LeaderboardRankingScreen), findsOneWidget);
  });

  testWidgets('unranked status shows encouragement copy without an error', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      _model(status: LeaderboardReadStatus.unranked, entries: _sampleBoard),
    );

    expect(find.text(leaderboardUnrankedBody), findsOneWidget);
    // The real board must stay visible for an unranked runner — the
    // encouragement copy supplements the rows, it never replaces them.
    expect(find.text('Ari S.'), findsOneWidget);
    expect(find.text('Maya L.'), findsOneWidget);
    expect(
      find.byKey(const Key('leaderboard_view_more_ranking_button')),
      findsOneWidget,
    );
    _expectNoErrorCopy();
  });

  testWidgets('unranked home region ranking page shows Ranks near you', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      _model(status: LeaderboardReadStatus.unranked, entries: _sampleBoard),
    );

    await tester.tap(
      find.byKey(const Key('leaderboard_view_more_ranking_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LeaderboardRankingScreen), findsOneWidget);
    expect(find.text('RANKS NEAR YOU'), findsOneWidget);
    expect(find.text('Top runners'), findsNothing);
    expect(find.text(leaderboardUnrankedBody), findsOneWidget);
  });

  testWidgets('updating status shows preparing copy without an error', (
    tester,
  ) async {
    await _pumpTab(tester, _model(status: LeaderboardReadStatus.updating));

    expect(find.text(leaderboardUpdatingBody), findsOneWidget);
    expect(
      find.byKey(const Key('leaderboard_view_more_ranking_button')),
      findsOneWidget,
    );
    _expectNoErrorCopy();
  });

  testWidgets('ineligible status shows unavailable copy without an error', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      _model(status: LeaderboardReadStatus.ineligiblePremium),
    );

    expect(find.text(leaderboardIneligibleBody), findsOneWidget);
    _expectNoErrorCopy();
  });

  testWidgets('sheet height tracks the content each status renders', (
    tester,
  ) async {
    const sheetBottomPadding = 14.0;

    // A one-line message card carries far less content than a full board plus
    // the My Rank Preview section, so no single constant height can close both
    // without leaving dead space under the actions in one of them.
    await _pumpTab(
      tester,
      _model(status: LeaderboardReadStatus.ineligiblePremium),
    );
    final messageStateHeight = _sheetHeight(tester);
    expect(_slackBelowActions(tester), closeTo(sheetBottomPadding, 0.5));

    await _pumpTab(tester, _model(status: LeaderboardReadStatus.empty));
    final emptyStateHeight = _sheetHeight(tester);
    expect(_slackBelowActions(tester), closeTo(sheetBottomPadding, 0.5));

    await _pumpTab(
      tester,
      _model(
        status: LeaderboardReadStatus.data,
        entries: _sampleBoard,
        nearbyEntries: _sampleBoard,
        currentRunnerRankLabel: '#2',
      ),
    );
    final rankedStateHeight = _sheetHeight(tester);
    expect(_slackBelowActions(tester), closeTo(sheetBottomPadding, 0.5));

    expect(messageStateHeight, lessThan(emptyStateHeight));
    expect(emptyStateHeight, lessThan(rankedStateHeight));
  });
}

class _FakeLeaderboardRepository implements LeaderboardRepository {
  const _FakeLeaderboardRepository(this.model);

  final LeaderboardReadModel model;

  @override
  Future<LeaderboardReadModel> loadLeaderboard() async => model;

  @override
  Future<LeaderboardReadModel> loadRegion({required String regionId}) async =>
      model;
}
