import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_history.dart';
import 'package:runiac_app/features/challenge/domain/repositories/challenge_repository.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_history_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_result_screen.dart';

import 'support/fake_challenge_repository.dart';

ChallengeHistoryEntry _entry({
  required String challengeId,
  required ChallengeTierId tierId,
  required ChallengeParticipantStatus outcome,
  ChallengeTerminalReason? terminalReason,
  int endedAtMs = 1000,
}) {
  return ChallengeHistoryEntry(
    challengeId: challengeId,
    tierId: tierId,
    mode: ChallengeMode.group,
    role: ChallengeParticipantRole.member,
    outcome: outcome,
    terminalReason: terminalReason,
    teamMeters: 10000,
    personalMeters: 2000,
    targetMeters: 10000,
    personalMinimumMeters: 3000,
    startedAtMs: 0,
    endedAtMs: endedAtMs,
  );
}

Widget _harness(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows loading, then rows with an outcome chip each',
      (tester) async {
    final repository = FakeChallengeRepository(
      historyOverride: <ChallengeHistoryEntry>[
        _entry(
          challengeId: 'c-succeeded',
          tierId: ChallengeTierId.k10,
          outcome: ChallengeParticipantStatus.succeeded,
          terminalReason: ChallengeTerminalReason.targetReached,
        ),
        _entry(
          challengeId: 'c-ineligible',
          tierId: ChallengeTierId.k20,
          outcome: ChallengeParticipantStatus.ineligible,
          terminalReason: ChallengeTerminalReason.targetReached,
        ),
        _entry(
          challengeId: 'c-failed',
          tierId: ChallengeTierId.k42,
          outcome: ChallengeParticipantStatus.failed,
          terminalReason: ChallengeTerminalReason.deadlineFailed,
        ),
        _entry(
          challengeId: 'c-cancelled',
          tierId: ChallengeTierId.k100,
          outcome: ChallengeParticipantStatus.cancelled,
          terminalReason: ChallengeTerminalReason.ownerAbandoned,
        ),
        _entry(
          challengeId: 'c-left',
          tierId: ChallengeTierId.k200,
          outcome: ChallengeParticipantStatus.left,
        ),
      ],
    );

    await tester.pumpWidget(
      _harness(
        ChallengeHistoryScreen(repository: repository, onBack: () {}),
      ),
    );
    // First frame: still loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('challenge-history-c-succeeded')),
      findsOneWidget,
    );
    expect(find.text('Badge earned'), findsOneWidget);
    expect(find.text('Minimum missed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
  });

  testWidgets('tapping a row reopens the full result screen for that entry',
      (tester) async {
    final repository = FakeChallengeRepository(
      historyOverride: <ChallengeHistoryEntry>[
        _entry(
          challengeId: 'c-succeeded',
          tierId: ChallengeTierId.k10,
          outcome: ChallengeParticipantStatus.succeeded,
          terminalReason: ChallengeTerminalReason.targetReached,
        ),
      ],
    );

    await tester.pumpWidget(
      _harness(
        ChallengeHistoryScreen(repository: repository, onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('challenge-history-c-succeeded')),
    );
    // The earned ceremony loops forever (ambient glow + fireworks), so the
    // route never settles — drive a bounded number of frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(ChallengeResultScreen), findsOneWidget);
    expect(find.text('You earned the 10K badge!'), findsOneWidget);
  });

  testWidgets('shows the empty state when there is no history', (tester) async {
    final repository = FakeChallengeRepository(
      historyOverride: const <ChallengeHistoryEntry>[],
    );

    await tester.pumpWidget(
      _harness(
        ChallengeHistoryScreen(repository: repository, onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No finished challenges yet'), findsOneWidget);
  });

  testWidgets('shows an error state with retry that reloads', (tester) async {
    final repository = FakeChallengeRepository(
      historyFailure: const ChallengeFailure(reason: 'CHALLENGE_UNAVAILABLE'),
    );

    await tester.pumpWidget(
      _harness(
        ChallengeHistoryScreen(repository: repository, onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    final callsBeforeRetry = repository.historyCalls;

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(repository.historyCalls, greaterThan(callsBeforeRetry));
  });
}
