import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/data/static_challenge_repository.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_badge_ownership.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/repositories/challenge_repository.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_explore_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_tier_detail_screen.dart';

import 'support/fake_challenge_repository.dart';

const _tierOrder = <String>[
  '10K',
  '20K',
  '42K',
  '100K',
  '200K',
  '250K',
  '300K',
  '500K',
  '1000K',
];

Widget _harness(Widget child) => MaterialApp(home: child);

Finder _tile(String tier) =>
    find.byKey(ValueKey<String>('challenge-tier-$tier'));

void main() {
  testWidgets('renders nine tier tiles in catalog order', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeExploreScreen(
          repository: FakeChallengeRepository(),
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final tier in _tierOrder) {
      expect(_tile(tier), findsOneWidget, reason: tier);
    }

    // Ordered top-to-bottom, left-to-right across the 3x3 grid.
    double previousKey = -1;
    for (final tier in _tierOrder) {
      final centre = tester.getCenter(_tile(tier));
      final ordinal = centre.dy * 1000 + centre.dx;
      expect(ordinal, greaterThan(previousKey), reason: tier);
      previousKey = ordinal;
    }
  });

  testWidgets('tapping a tile opens the tier detail', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeExploreScreen(
          repository: FakeChallengeRepository(),
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_tile('10K'));
    await tester.pumpAndSettle();

    expect(find.byType(ChallengeTierDetailScreen), findsOneWidget);
    expect(find.text('Target distance'), findsOneWidget);
  });

  testWidgets('shows the slot banner and marks the in-progress tier', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        ChallengeExploreScreen(
          repository: FakeChallengeRepository(
            seed: ChallengeScenarioSeed.recruiting,
          ),
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('You already have a challenge in progress'),
      findsOneWidget,
    );
    expect(find.text('View current challenge'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('slot-held tier detail disables Create challenge', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeExploreScreen(
          repository: FakeChallengeRepository(
            seed: ChallengeScenarioSeed.recruiting,
          ),
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The in-progress tier is 10K in the recruiting seed.
    await tester.tap(_tile('10K'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create challenge'),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('You already have a challenge in progress'),
      findsWidgets,
    );
  });

  testWidgets('renders the pending-invitations count badge', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeExploreScreen(
          repository: FakeChallengeRepository(),
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Invitations, 1 pending'),
      findsOneWidget,
    );
  });

  testWidgets('marks an earned tier with a success check', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeExploreScreen(
          repository: FakeChallengeRepository(
            ownedBadgesOverride: ChallengeBadgeOwnership(
              ownedTierIds: <ChallengeTierId>{ChallengeTierId.k20},
            ),
          ),
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('degrades gracefully when badge ownership is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        ChallengeExploreScreen(
          repository: FakeChallengeRepository(
            ownedBadgesFailure: const ChallengeFailure(
              reason: ChallengeFailure.unavailableReason,
            ),
          ),
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The grid still renders; no earned marks appear.
    expect(_tile('10K'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  testWidgets('shows the loading state before data resolves', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeExploreScreen(
          repository: FakeChallengeRepository(blockCatalog: true),
          onBack: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading challenges…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows an error state and recovers on retry', (tester) async {
    final repository = FakeChallengeRepository()..catalogFailuresRemaining = 1;
    await tester.pumpWidget(
      _harness(
        ChallengeExploreScreen(repository: repository, onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(_tile('10K'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(_tile('10K'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('lays out at 360px width and textScale 1.3 without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: ChallengeExploreScreen(
            repository: FakeChallengeRepository(),
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_tile('1000K'), findsOneWidget);
  });
}
