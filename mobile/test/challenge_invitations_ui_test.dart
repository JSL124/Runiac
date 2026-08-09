import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_invitation_summary.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_rules_snapshot.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_invitations_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_lobby_screen.dart';

import 'support/fake_challenge_repository.dart';

const _rules = ChallengeRulesSnapshot(
  tierId: ChallengeTierId.k42,
  catalogVersion: 'challenge-distance-v1',
  difficultyLabel: 'Normal',
  durationDays: 21,
  durationMs: 1814400000,
  maxParticipants: 3,
  maxInvitedFriends: 2,
  targetMeters: 42000,
  personalMinimumMeters: 7000,
);

final _clock = DateTime.fromMillisecondsSinceEpoch(1000000000000);

ChallengeInvitationSummary _invite() => ChallengeInvitationSummary(
      inviteId: 'invite-1',
      challengeId: 'challenge-1',
      tierId: ChallengeTierId.k42,
      ownerUid: 'friend',
      status: ChallengeInvitationStatus.pending,
      createdAtMs: _clock.millisecondsSinceEpoch,
      expiresAtMs: _clock.millisecondsSinceEpoch + 3600000,
      rules: _rules,
    );

Widget _harness({
  required FakeChallengeRepository repository,
  bool slotHeld = false,
}) {
  return MaterialApp(
    home: ChallengeInvitationsScreen(
      repository: repository,
      slotHeld: slotHeld,
      clock: () => _clock,
      onBack: () {},
    ),
  );
}

void main() {
  testWidgets('lists pending invitations with tier and expiry', (tester) async {
    final repository = FakeChallengeRepository(
      invitationsOverride: <ChallengeInvitationSummary>[_invite()],
    );
    await tester.pumpWidget(_harness(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('42K'), findsOneWidget);
    expect(find.text('Expires in 01:00:00'), findsOneWidget);
  });

  testWidgets('empty state when there are no invitations', (tester) async {
    final repository = FakeChallengeRepository(
      invitationsOverride: const <ChallengeInvitationSummary>[],
    );
    await tester.pumpWidget(_harness(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('No invitations right now'), findsOneWidget);
  });

  testWidgets('detail accept routes to the lobby member view', (tester) async {
    final repository = FakeChallengeRepository(
      invitationsOverride: <ChallengeInvitationSummary>[_invite()],
    );
    await tester.pumpWidget(_harness(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('42K'));
    await tester.pumpAndSettle();

    // Rules card copy from the invitation detail.
    expect(find.text('42.0 km'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.ensureVisible(find.text('Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(repository.respondedAccepts, <bool>[true]);
    expect(find.byType(ChallengeLobbyScreen), findsOneWidget);
  });

  testWidgets('detail decline calls the repository and returns', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      invitationsOverride: <ChallengeInvitationSummary>[_invite()],
    );
    await tester.pumpWidget(_harness(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('42K'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(repository.respondedAccepts, <bool>[false]);
    expect(find.byType(ChallengeInvitationDetailScreen), findsNothing);
  });

  testWidgets('slot-held detail disables Accept but keeps Decline', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      invitationsOverride: <ChallengeInvitationSummary>[_invite()],
    );
    await tester.pumpWidget(_harness(repository: repository, slotHeld: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('42K'));
    await tester.pumpAndSettle();

    final accept = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Accept'),
    );
    final decline = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Decline'),
    );
    expect(accept.onPressed, isNull);
    expect(decline.onPressed, isNotNull);
    expect(
      find.text('You already have a challenge in progress'),
      findsOneWidget,
    );
  });

  testWidgets('invitations list lays out at 360px and textScale 1.3', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = FakeChallengeRepository(
      invitationsOverride: <ChallengeInvitationSummary>[_invite()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: ChallengeInvitationsScreen(
            repository: repository,
            clock: () => _clock,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('42K'), findsOneWidget);
  });
}
