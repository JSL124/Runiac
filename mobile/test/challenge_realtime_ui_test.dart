import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/challenge_countdown.dart';
import 'package:runiac_app/features/challenge/domain/models/active_challenge.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_invitation_summary.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_participant_row.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_rules_snapshot.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_invitations_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_lobby_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_progress_screen.dart';

import 'support/fake_challenge_repository.dart';

/// Widget coverage for the cross-device realtime fix: invitations, lobby, and
/// progress each now subscribe to [FakeChallengeRepository]'s injected watch
/// streams (rather than a one-shot load), so a controller-driven emission
/// must update the rendered UI live, without any re-entry / pop-triggered
/// refetch.
class _FakeTicker implements ChallengeTicker {
  @override
  void start(VoidCallback onTick) {}
  @override
  void stop() {}
}

final _clock = DateTime.fromMillisecondsSinceEpoch(1000000000000);

const _lobbyRules = ChallengeRulesSnapshot(
  tierId: ChallengeTierId.k10,
  catalogVersion: 'challenge-distance-v1',
  difficultyLabel: 'Beginner',
  durationDays: 7,
  durationMs: 604800000,
  maxParticipants: 2,
  maxInvitedFriends: 1,
  targetMeters: 10000,
  personalMinimumMeters: 3000,
);

ChallengeParticipantRow _row({
  required String uid,
  required ChallengeParticipantRole role,
  required bool isCurrentUser,
  String name = 'Sam Runner',
  String initials = 'SR',
  String levelLabel = 'Lv.7',
  ChallengeParticipantStatus status = ChallengeParticipantStatus.accepted,
  int meters = 0,
}) {
  return ChallengeParticipantRow(
    uid: uid,
    displayNameSnapshot: name,
    avatarInitialsSnapshot: initials,
    levelLabelSnapshot: levelLabel,
    role: role,
    status: status,
    creditedMeters: meters,
    reward: ChallengeRewardStatus.notEligible,
    isCurrentUser: isCurrentUser,
  );
}

ActiveChallenge _lobbyInstance({
  required List<ChallengeParticipantRow> participants,
  ChallengeInstanceStatus status = ChallengeInstanceStatus.recruiting,
}) {
  return ActiveChallenge(
    challengeId: 'lobby-1',
    ownerUid: 'me',
    tierId: ChallengeTierId.k10,
    mode: ChallengeMode.solo,
    status: status,
    rules: _lobbyRules,
    rosterUids: participants.map((p) => p.uid).toList(),
    maxParticipants: 2,
    teamMeters: 0,
    createdAtMs: _clock.millisecondsSinceEpoch,
    lobbyExpiresAtMs: _clock.millisecondsSinceEpoch + 3600000,
    startsAtMs: status == ChallengeInstanceStatus.recruiting
        ? null
        : _clock.millisecondsSinceEpoch,
    scheduledEndsAtMs: status == ChallengeInstanceStatus.recruiting
        ? null
        : _clock.millisecondsSinceEpoch + _lobbyRules.durationMs,
    terminalReason: status == ChallengeInstanceStatus.cancelled
        ? ChallengeTerminalReason.ownerAbandoned
        : null,
    participants: participants,
    isCurrentUserOwner: true,
  );
}

ChallengeLobbyScreen _lobbyScreen(FakeChallengeRepository repository) {
  return ChallengeLobbyScreen(
    challengeId: 'lobby-1',
    repository: repository,
    clock: () => _clock,
    ticker: _FakeTicker(),
    onBack: () {},
  );
}

const _progressRules = ChallengeRulesSnapshot(
  tierId: ChallengeTierId.k100,
  catalogVersion: 'challenge-distance-v1',
  difficultyLabel: 'Challenging',
  durationDays: 28,
  durationMs: 2419200000,
  maxParticipants: 4,
  maxInvitedFriends: 3,
  targetMeters: 100000,
  personalMinimumMeters: 13000,
);

ActiveChallenge _progressInstance({
  required int teamMeters,
  required int meMeters,
  required int friendMeters,
  ChallengeParticipantStatus friendStatus = ChallengeParticipantStatus.active,
  ChallengeInstanceStatus status = ChallengeInstanceStatus.active,
}) {
  return ActiveChallenge(
    challengeId: 'progress-1',
    ownerUid: 'me',
    tierId: _progressRules.tierId,
    mode: ChallengeMode.group,
    status: status,
    rules: _progressRules,
    rosterUids: const <String>['me', 'friend'],
    maxParticipants: _progressRules.maxParticipants,
    teamMeters: teamMeters,
    createdAtMs: _clock.millisecondsSinceEpoch,
    lobbyExpiresAtMs: _clock.millisecondsSinceEpoch,
    startsAtMs: _clock.millisecondsSinceEpoch,
    scheduledEndsAtMs: _clock.millisecondsSinceEpoch + _progressRules.durationMs,
    terminalReason:
        status == ChallengeInstanceStatus.cancelled
            ? ChallengeTerminalReason.ownerAbandoned
            : null,
    participants: <ChallengeParticipantRow>[
      _row(
        uid: 'me',
        role: ChallengeParticipantRole.owner,
        isCurrentUser: true,
        name: 'Runner Me',
        initials: 'ME',
        status: ChallengeParticipantStatus.active,
        meters: meMeters,
      ),
      _row(
        uid: 'friend',
        role: ChallengeParticipantRole.member,
        isCurrentUser: false,
        status: friendStatus,
        meters: friendMeters,
      ),
    ],
    isCurrentUserOwner: true,
  );
}

ChallengeProgressScreen _progressScreen(FakeChallengeRepository repository) {
  return ChallengeProgressScreen(
    challengeId: 'progress-1',
    repository: repository,
    clock: () => _clock,
    ticker: _FakeTicker(),
    onBack: () {},
  );
}

ChallengeInvitationSummary _invite() => ChallengeInvitationSummary(
      inviteId: 'invite-1',
      challengeId: 'challenge-1',
      tierId: ChallengeTierId.k42,
      ownerUid: 'friend',
      status: ChallengeInvitationStatus.pending,
      createdAtMs: _clock.millisecondsSinceEpoch,
      expiresAtMs: _clock.millisecondsSinceEpoch + 3600000,
      rules: null,
    );

void main() {
  testWidgets(
    'invitations screen renders live: empty -> row appears -> row disappears',
    (tester) async {
      final controller = StreamController<List<ChallengeInvitationSummary>>.broadcast();
      addTearDown(controller.close);
      final repository =
          FakeChallengeRepository(watchInvitationsOverride: controller.stream);

      await tester.pumpWidget(
        MaterialApp(
          home: ChallengeInvitationsScreen(
            repository: repository,
            clock: () => _clock,
            onBack: () {},
          ),
        ),
      );
      await tester.pump();

      controller.add(const <ChallengeInvitationSummary>[]);
      await tester.pump();
      await tester.pump();
      expect(find.text('No invitations right now'), findsOneWidget);

      controller.add(<ChallengeInvitationSummary>[_invite()]);
      await tester.pump();
      await tester.pump();
      expect(find.text('42K'), findsOneWidget);
      // No navigation happened just from the emission.
      expect(find.byType(ChallengeInvitationsScreen), findsOneWidget);

      controller.add(const <ChallengeInvitationSummary>[]);
      await tester.pump();
      await tester.pump();
      expect(find.text('42K'), findsNothing);
      expect(find.text('No invitations right now'), findsOneWidget);
    },
  );

  testWidgets(
    'lobby screen renders roster join/withdraw live and keeps the seeded '
    'level label fixed',
    (tester) async {
      final controller = StreamController<ActiveChallenge?>.broadcast();
      addTearDown(controller.close);
      final repository =
          FakeChallengeRepository(watchActiveOverride: controller.stream);

      await tester.pumpWidget(MaterialApp(home: _lobbyScreen(repository)));
      await tester.pump();

      final owner = _row(
        uid: 'me',
        role: ChallengeParticipantRole.owner,
        isCurrentUser: true,
        name: 'You',
        initials: 'YO',
        levelLabel: 'Lv.5',
      );
      controller.add(_lobbyInstance(participants: <ChallengeParticipantRow>[owner]));
      await tester.pump();
      await tester.pump();
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('Lv.5'), findsOneWidget);

      final member = _row(
        uid: 'friend',
        role: ChallengeParticipantRole.member,
        isCurrentUser: false,
        levelLabel: 'Lv.7',
      );
      controller.add(
        _lobbyInstance(participants: <ChallengeParticipantRow>[owner, member]),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('Sam Runner'), findsOneWidget);
      // The owner's seeded label is untouched by the roster change.
      expect(find.text('Lv.5'), findsOneWidget);
      expect(find.text('Lv.7'), findsOneWidget);

      controller.add(_lobbyInstance(participants: <ChallengeParticipantRow>[owner]));
      await tester.pump();
      await tester.pump();
      expect(find.text('Sam Runner'), findsNothing);
      expect(find.text('1/2'), findsOneWidget);
    },
  );

  testWidgets(
    'lobby screen navigates to progress once the owner starts remotely',
    (tester) async {
      final controller = StreamController<ActiveChallenge?>.broadcast();
      addTearDown(controller.close);
      final repository =
          FakeChallengeRepository(watchActiveOverride: controller.stream);

      await tester.pumpWidget(MaterialApp(home: _lobbyScreen(repository)));
      await tester.pump();

      final owner = _row(
        uid: 'me',
        role: ChallengeParticipantRole.owner,
        isCurrentUser: true,
        name: 'You',
        initials: 'YO',
      );
      controller.add(_lobbyInstance(participants: <ChallengeParticipantRow>[owner]));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChallengeProgressScreen), findsNothing);

      controller.add(
        _lobbyInstance(
          participants: <ChallengeParticipantRow>[owner],
          status: ChallengeInstanceStatus.active,
        ),
      );
      // Deliver the broadcast event (two frames — the broadcast delivery lands
      // one microtask before the rebuild that navigates), then advance the
      // pushReplacement transition without pumpAndSettle (the progress screen
      // sits in its loading spinner — the shared broadcast stream doesn't
      // replay to the late subscriber; that's a harness artifact, not a
      // product issue).
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ChallengeProgressScreen), findsOneWidget);
      expect(find.byType(ChallengeLobbyScreen), findsNothing);
    },
  );

  testWidgets(
    'lobby screen shows the expired state when cancelled remotely',
    (tester) async {
      final controller = StreamController<ActiveChallenge?>.broadcast();
      addTearDown(controller.close);
      final repository =
          FakeChallengeRepository(watchActiveOverride: controller.stream);

      await tester.pumpWidget(MaterialApp(home: _lobbyScreen(repository)));
      await tester.pump();

      final owner = _row(
        uid: 'me',
        role: ChallengeParticipantRole.owner,
        isCurrentUser: true,
        name: 'You',
        initials: 'YO',
      );
      controller.add(_lobbyInstance(participants: <ChallengeParticipantRow>[owner]));
      await tester.pump();
      await tester.pump();
      expect(find.text('This lobby expired'), findsNothing);

      controller.add(
        _lobbyInstance(
          participants: <ChallengeParticipantRow>[owner],
          status: ChallengeInstanceStatus.cancelled,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('This lobby expired'), findsOneWidget);
    },
  );

  testWidgets(
    'progress screen updates metres live, moves a leaver to the Left group, '
    'and ends the screen when cancelled remotely',
    (tester) async {
      final controller = StreamController<ActiveChallenge?>.broadcast();
      addTearDown(controller.close);
      final repository =
          FakeChallengeRepository(watchActiveOverride: controller.stream);

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: _progressScreen(repository)));
      await tester.pump();

      controller.add(
        _progressInstance(teamMeters: 9000, meMeters: 4000, friendMeters: 3000),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('9.0 / 100.0 km'), findsOneWidget);
      expect(find.text('4.0 km'), findsOneWidget);

      controller.add(
        _progressInstance(teamMeters: 12000, meMeters: 6000, friendMeters: 3000),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('12.0 / 100.0 km'), findsOneWidget);
      expect(find.text('6.0 km'), findsOneWidget);

      controller.add(
        _progressInstance(
          teamMeters: 12000,
          meMeters: 6000,
          friendMeters: 3000,
          friendStatus: ChallengeParticipantStatus.left,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Left the challenge'), findsOneWidget);
      expect(find.text('Sam Runner'), findsOneWidget);

      controller.add(
        _progressInstance(
          teamMeters: 12000,
          meMeters: 6000,
          friendMeters: 3000,
          status: ChallengeInstanceStatus.cancelled,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('This challenge has ended'), findsOneWidget);
    },
  );

  group('subscription lifecycle', () {
    testWidgets('invitations screen cancels its listener on dispose', (
      tester,
    ) async {
      final controller = StreamController<List<ChallengeInvitationSummary>>.broadcast();
      addTearDown(controller.close);
      final repository =
          FakeChallengeRepository(watchInvitationsOverride: controller.stream);

      await tester.pumpWidget(
        MaterialApp(
          home: ChallengeInvitationsScreen(
            repository: repository,
            clock: () => _clock,
            onBack: () {},
          ),
        ),
      );
      await tester.pump();
      expect(controller.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(controller.hasListener, isFalse);
    });

    testWidgets('lobby screen cancels its listener on dispose', (
      tester,
    ) async {
      final controller = StreamController<ActiveChallenge?>.broadcast();
      addTearDown(controller.close);
      final repository =
          FakeChallengeRepository(watchActiveOverride: controller.stream);

      await tester.pumpWidget(MaterialApp(home: _lobbyScreen(repository)));
      await tester.pump();
      expect(controller.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(controller.hasListener, isFalse);
    });

    testWidgets('progress screen cancels its listener on dispose', (
      tester,
    ) async {
      final controller = StreamController<ActiveChallenge?>.broadcast();
      addTearDown(controller.close);
      final repository =
          FakeChallengeRepository(watchActiveOverride: controller.stream);

      await tester.pumpWidget(MaterialApp(home: _progressScreen(repository)));
      await tester.pump();
      expect(controller.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(controller.hasListener, isFalse);
    });
  });
}
