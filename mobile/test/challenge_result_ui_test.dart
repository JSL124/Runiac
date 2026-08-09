import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_history.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_result_screen.dart';
import 'package:runiac_app/features/challenge/presentation/widgets/challenge_badge_image.dart';

ChallengeResult _result({
  required ChallengeParticipantStatus outcome,
  ChallengeTerminalReason? terminalReason,
  ChallengeTierId tierId = ChallengeTierId.k10,
  int creditedMeters = 2000,
  int teamMeters = 10000,
  int targetMeters = 10000,
  int personalMinimumMeters = 3000,
}) {
  return ChallengeResult(
    challengeId: 'challenge-1',
    tierId: tierId,
    mode: ChallengeMode.group,
    role: ChallengeParticipantRole.member,
    outcome: outcome,
    terminalReason: terminalReason,
    creditedMeters: creditedMeters,
    teamMeters: teamMeters,
    targetMeters: targetMeters,
    personalMinimumMeters: personalMinimumMeters,
    startedAtMs: 0,
    endedAtMs: 1000,
  );
}

Widget _harness(
  Widget child, {
  double textScale = 1.0,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child,
        );
      },
    ),
  );
}

ChallengeBadgeImage _badge(WidgetTester tester) {
  return tester.widget<ChallengeBadgeImage>(
    find.byType(ChallengeBadgeImage),
  );
}

void main() {
  testWidgets('SUCCEEDED shows the earned headline, full-colour badge, and '
      'both buttons', (tester) async {
    var viewedCollection = false;
    var closed = false;
    await tester.pumpWidget(
      _harness(
        ChallengeResultScreen(
          result: _result(
            outcome: ChallengeParticipantStatus.succeeded,
            terminalReason: ChallengeTerminalReason.targetReached,
          ),
          onClose: () => closed = true,
          onViewBadgeCollection: () => viewedCollection = true,
        ),
      ),
    );
    // The earned ceremony runs a continuous ambient/fireworks loop that never
    // settles, so drive a bounded number of frames instead of pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('You earned the 10K badge!'), findsOneWidget);
    expect(_badge(tester).dimmed, isFalse);
    expect(find.text('View badge collection'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('View badge collection'));
    expect(viewedCollection, isTrue);
    await tester.tap(find.text('Done'));
    expect(closed, isTrue);
  });

  testWidgets('INELIGIBLE shows the personal-minimum chip, desaturated badge, '
      'and supportive copy', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeResultScreen(
          result: _result(
            outcome: ChallengeParticipantStatus.ineligible,
            terminalReason: ChallengeTerminalReason.targetReached,
            creditedMeters: 2000,
            teamMeters: 10000,
            targetMeters: 10000,
            personalMinimumMeters: 3000,
          ),
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal minimum not reached'), findsOneWidget);
    expect(find.text('Team goal reached'), findsOneWidget);
    expect(
      find.text(
        'The team reached 10.0 km — but your 2.0 km '
        "didn't reach the 3.0 km personal minimum, so no badge this time.",
      ),
      findsOneWidget,
    );
    expect(find.text('You still added 2.0 km to the team.'), findsOneWidget);
    expect(_badge(tester).dimmed, isTrue);
    // No badge-collection action for a non-earned outcome.
    expect(find.text('View badge collection'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('FAILED shows the deadline copy and a desaturated badge',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeResultScreen(
          result: _result(
            outcome: ChallengeParticipantStatus.failed,
            terminalReason: ChallengeTerminalReason.deadlineFailed,
            teamMeters: 6400,
            targetMeters: 20000,
          ),
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Time ran out at 6.4 km of 20.0 km. No badges this time.'),
      findsOneWidget,
    );
    expect(_badge(tester).dimmed, isTrue);
    expect(find.text('View badge collection'), findsNothing);
  });

  testWidgets('CANCELLED shows neutral informational copy', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeResultScreen(
          result: _result(
            outcome: ChallengeParticipantStatus.cancelled,
            terminalReason: ChallengeTerminalReason.ownerAbandoned,
          ),
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Challenge cancelled'), findsOneWidget);
    expect(
      find.text(
        'The owner cancelled this challenge before it finished. '
        'No badges this time.',
      ),
      findsOneWidget,
    );
    expect(_badge(tester).dimmed, isTrue);
  });

  testWidgets('LEFT confirms retained contribution and no badge',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeResultScreen(
          result: _result(
            outcome: ChallengeParticipantStatus.left,
            creditedMeters: 2000,
          ),
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You left the challenge'), findsOneWidget);
    expect(
      find.text(
        'You left the challenge. Your 2.0 km stayed with the team, '
        'and no badge was awarded.',
      ),
      findsOneWidget,
    );
    expect(_badge(tester).dimmed, isTrue);
  });

  testWidgets('badge-earned variant renders under reduced motion without a '
      'pending animation', (tester) async {
    await tester.pumpWidget(
      _harness(
        ChallengeResultScreen(
          result: _result(
            outcome: ChallengeParticipantStatus.succeeded,
            terminalReason: ChallengeTerminalReason.targetReached,
          ),
          onClose: () {},
          onViewBadgeCollection: () {},
        ),
        reduceMotion: true,
      ),
    );
    // A single pump (no settle) must already show the final state because the
    // celebration is skipped when animations are disabled.
    await tester.pump();

    expect(find.text('You earned the 10K badge!'), findsOneWidget);
    expect(_badge(tester).dimmed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders on a 360px viewport at textScale 1.3 without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _harness(
        ChallengeResultScreen(
          result: _result(
            outcome: ChallengeParticipantStatus.ineligible,
            terminalReason: ChallengeTerminalReason.targetReached,
          ),
          onClose: () {},
        ),
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Personal minimum not reached'), findsOneWidget);
  });
}
