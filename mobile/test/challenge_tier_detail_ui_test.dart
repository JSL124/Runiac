import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_tier.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_lobby_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_tier_detail_screen.dart';

import 'support/fake_challenge_repository.dart';

ChallengeTier _tier({
  required ChallengeTierId tierId,
  required String difficulty,
  required int durationDays,
  required int maxParticipants,
  required int maxInvitedFriends,
  required int targetMeters,
  required int personalMinimumMeters,
}) {
  return ChallengeTier(
    tierId: tierId,
    catalogVersion: 'challenge-distance-v1',
    difficultyLabel: difficulty,
    durationDays: durationDays,
    maxParticipants: maxParticipants,
    maxInvitedFriends: maxInvitedFriends,
    targetMeters: targetMeters,
    personalMinimumMeters: personalMinimumMeters,
  );
}

final _tier10k = _tier(
  tierId: ChallengeTierId.k10,
  difficulty: 'Beginner',
  durationDays: 7,
  maxParticipants: 2,
  maxInvitedFriends: 1,
  targetMeters: 10000,
  personalMinimumMeters: 3000,
);

final _tier100k = _tier(
  tierId: ChallengeTierId.k100,
  difficulty: 'Challenging',
  durationDays: 28,
  maxParticipants: 4,
  maxInvitedFriends: 3,
  targetMeters: 100000,
  personalMinimumMeters: 13000,
);

final _tier1000k = _tier(
  tierId: ChallengeTierId.k1000,
  difficulty: 'Legend',
  durationDays: 98,
  maxParticipants: 8,
  maxInvitedFriends: 7,
  targetMeters: 1000000,
  personalMinimumMeters: 63000,
);

Widget _harness({
  required ChallengeTier tier,
  bool slotHeld = false,
  bool earned = false,
  FakeChallengeRepository? repository,
}) {
  return MaterialApp(
    home: ChallengeTierDetailScreen(
      tier: tier,
      repository: repository ?? FakeChallengeRepository(),
      slotHeld: slotHeld,
      earned: earned,
      onBack: () {},
    ),
  );
}

void main() {
  testWidgets('10K rules card shows the exact locked copy', (tester) async {
    await tester.pumpWidget(_harness(tier: _tier10k));
    await tester.pumpAndSettle();

    expect(find.text('10.0 km'), findsOneWidget);
    expect(find.text('1 week'), findsOneWidget);
    expect(find.text('Up to 2 runners'), findsOneWidget);
    expect(
      find.text('Each runner must run at least 3.0 km'),
      findsOneWidget,
    );
    expect(
      find.text("The team's combined distance must reach the target"),
      findsOneWidget,
    );
    expect(
      find.text("Running solo? You'll run the full 10.0 km yourself."),
      findsOneWidget,
    );
  });

  testWidgets('100K rules card shows the exact locked copy', (tester) async {
    await tester.pumpWidget(_harness(tier: _tier100k));
    await tester.pumpAndSettle();

    expect(find.text('100.0 km'), findsOneWidget);
    expect(find.text('4 weeks'), findsOneWidget);
    expect(find.text('Up to 4 runners'), findsOneWidget);
    expect(
      find.text('Each runner must run at least 13.0 km'),
      findsOneWidget,
    );
    expect(
      find.text("Running solo? You'll run the full 100.0 km yourself."),
      findsOneWidget,
    );
  });

  testWidgets('1000K rules card shows the exact locked copy', (tester) async {
    await tester.pumpWidget(_harness(tier: _tier1000k));
    await tester.pumpAndSettle();

    expect(find.text('1000.0 km'), findsOneWidget);
    expect(find.text('14 weeks'), findsOneWidget);
    expect(find.text('Up to 8 runners'), findsOneWidget);
    expect(
      find.text('Each runner must run at least 63.0 km'),
      findsOneWidget,
    );
    expect(
      find.text("Running solo? You'll run the full 1000.0 km yourself."),
      findsOneWidget,
    );
  });

  testWidgets('Create challenge creates a lobby and navigates', (tester) async {
    final repository = FakeChallengeRepository();
    await tester.pumpWidget(_harness(tier: _tier10k, repository: repository));
    await tester.pumpAndSettle();

    final createButton = find.widgetWithText(FilledButton, 'Create challenge');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(repository.createdTiers, <ChallengeTierId>[ChallengeTierId.k10]);
    expect(find.byType(ChallengeLobbyScreen), findsOneWidget);
  });

  testWidgets('slot-held detail disables Create and offers view link', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(tier: _tier10k, slotHeld: true));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create challenge'),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('You already have a challenge in progress'),
      findsOneWidget,
    );
  });

  testWidgets('earned tier shows the Earned chip', (tester) async {
    await tester.pumpWidget(_harness(tier: _tier10k, earned: true));
    await tester.pumpAndSettle();

    expect(find.text('Earned'), findsOneWidget);
  });

  testWidgets('lays out at 360px width and textScale 1.3 without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: ChallengeTierDetailScreen(
            tier: _tier100k,
            repository: FakeChallengeRepository(),
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('100.0 km'), findsOneWidget);
  });
}
