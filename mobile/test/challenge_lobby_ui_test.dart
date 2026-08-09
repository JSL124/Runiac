import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/challenge_countdown.dart';
import 'package:runiac_app/features/challenge/domain/models/active_challenge.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_invitation_summary.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_participant_row.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_rules_snapshot.dart';
import 'package:runiac_app/features/challenge/domain/repositories/challenge_repository.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_friend_picker_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_lobby_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_progress_screen.dart';
import 'package:runiac_app/core/widgets/runiac_level_profile_badge.dart';

import 'support/fake_challenge_repository.dart';

class _FakeTicker implements ChallengeTicker {
  @override
  void start(VoidCallback onTick) {}

  @override
  void stop() {}
}

const _rules = ChallengeRulesSnapshot(
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

final _clock = DateTime.fromMillisecondsSinceEpoch(1000000000000);

ChallengeParticipantRow _owner({
  bool isCurrentUser = true,
  String displayName = 'You',
  String levelLabel = 'Lv.5',
  String avatarUrlSnapshot = '',
  int levelProgressPercentSnapshot = 0,
}) =>
    ChallengeParticipantRow(
      uid: 'me',
      displayNameSnapshot: displayName,
      avatarInitialsSnapshot: 'YO',
      levelLabelSnapshot: levelLabel,
      role: ChallengeParticipantRole.owner,
      status: ChallengeParticipantStatus.accepted,
      creditedMeters: 0,
      reward: ChallengeRewardStatus.notEligible,
      isCurrentUser: isCurrentUser,
      avatarUrlSnapshot: avatarUrlSnapshot,
      levelProgressPercentSnapshot: levelProgressPercentSnapshot,
    );

ChallengeParticipantRow _member({
  bool isCurrentUser = false,
  String levelLabel = 'Lv.7',
}) =>
    ChallengeParticipantRow(
      uid: 'friend',
      displayNameSnapshot: 'Sam Runner',
      avatarInitialsSnapshot: 'SR',
      levelLabelSnapshot: levelLabel,
      role: ChallengeParticipantRole.member,
      status: ChallengeParticipantStatus.accepted,
      creditedMeters: 0,
      reward: ChallengeRewardStatus.notEligible,
      isCurrentUser: isCurrentUser,
    );

ActiveChallenge _lobby({
  required bool isOwner,
  required List<ChallengeParticipantRow> participants,
}) {
  return ActiveChallenge(
    challengeId: 'lobby-1',
    ownerUid: isOwner ? 'me' : 'friend',
    tierId: ChallengeTierId.k10,
    mode: ChallengeMode.solo,
    status: ChallengeInstanceStatus.recruiting,
    rules: _rules,
    rosterUids: participants.map((p) => p.uid).toList(),
    maxParticipants: 2,
    teamMeters: 0,
    createdAtMs: _clock.millisecondsSinceEpoch,
    lobbyExpiresAtMs: _clock.millisecondsSinceEpoch + 3600000,
    startsAtMs: null,
    scheduledEndsAtMs: null,
    terminalReason: null,
    participants: participants,
    isCurrentUserOwner: isOwner,
  );
}

Widget _harness(ChallengeLobbyScreen screen) => MaterialApp(home: screen);

ChallengeLobbyScreen _screen({
  required FakeChallengeRepository repository,
  List<ChallengeInvitationSummary> pendingInvitations =
      const <ChallengeInvitationSummary>[],
}) {
  return ChallengeLobbyScreen(
    challengeId: 'lobby-1',
    repository: repository,
    pendingInvitations: pendingInvitations,
    clock: () => _clock,
    ticker: _FakeTicker(),
    onBack: () {},
  );
}

void main() {
  testWidgets('owner sees start, cancel, invite and the closes-in countdown', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () => _lobby(isOwner: true, participants: [_owner()]),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('Start challenge'), findsOneWidget);
    expect(find.text('Cancel challenge'), findsOneWidget);
    expect(find.text('Invite friends'), findsOneWidget);
    expect(find.text('You · Owner'), findsOneWidget);
    expect(find.text('Lobby closes in 01:00:00'), findsOneWidget);
    expect(find.text('Leave lobby'), findsNothing);
    // Roster rows use the same profile-circle + XP-ring + level-pill badge as
    // Friends and the invite picker, not the plain initials avatar.
    expect(find.byType(RuniacLevelProfileBadge), findsOneWidget);
  });

  testWidgets(
    'roster badge passes the resolved avatarUrlSnapshot to the level profile badge',
    (tester) async {
      const photoUrl =
          'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok';
      final repository = FakeChallengeRepository(
        activeOverride: () => _lobby(
          isOwner: true,
          participants: [_owner(avatarUrlSnapshot: photoUrl)],
        ),
      );
      await tester.pumpWidget(_harness(_screen(repository: repository)));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<RuniacLevelProfileBadge>(
              find.byType(RuniacLevelProfileBadge),
            )
            .photoUrl,
        photoUrl,
      );
    },
  );

  testWidgets(
    'roster badge converts the backend levelProgressPercentSnapshot into the XP ring',
    (tester) async {
      final repository = FakeChallengeRepository(
        activeOverride: () => _lobby(
          isOwner: true,
          participants: [_owner(levelProgressPercentSnapshot: 64)],
        ),
      );
      await tester.pumpWidget(_harness(_screen(repository: repository)));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<RuniacLevelProfileBadge>(
              find.byType(RuniacLevelProfileBadge),
            )
            .progressFraction,
        closeTo(0.64, 1e-9),
      );
    },
  );

  testWidgets(
    'roster badge leaves the ring empty when the backend resolved no progress',
    (tester) async {
      final repository = FakeChallengeRepository(
        activeOverride: () =>
            _lobby(isOwner: true, participants: [_owner()]),
      );
      await tester.pumpWidget(_harness(_screen(repository: repository)));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<RuniacLevelProfileBadge>(
              find.byType(RuniacLevelProfileBadge),
            )
            .progressFraction,
        0,
      );
    },
  );

  testWidgets('non-owner viewer sees plain Owner and You on their own row', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () => _lobby(
        isOwner: false,
        participants: [
          _owner(isCurrentUser: false, displayName: 'jinseo'),
          _member(isCurrentUser: true),
        ],
      ),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    // The owner is someone else, so no "You" leaks onto their row.
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('You · Owner'), findsNothing);
    // The current user's own (member) row is marked "You".
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('roster shows each runner\'s backend level label', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () => _lobby(
        isOwner: true,
        participants: [
          _owner(levelLabel: 'Lv.5'),
          _member(levelLabel: 'Lv.2'),
        ],
      ),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('Lv.5'), findsOneWidget);
    expect(find.text('Lv.2'), findsOneWidget);
    expect(find.text('Lv.0'), findsNothing);
  });

  testWidgets('capacity line counts present people over total capacity', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () =>
          _lobby(isOwner: true, participants: [_owner(), _member()]),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    // Owner + one accepted member = 2 present; cap is owner + maxInvited(1) = 2.
    expect(find.text('2/2'), findsOneWidget);
    expect(find.textContaining('Invited'), findsNothing);
  });

  testWidgets('member sees leave and waiting copy, no owner controls', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () =>
          _lobby(isOwner: false, participants: [_member(), _owner()]),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('Leave lobby'), findsOneWidget);
    expect(find.text('Waiting for the owner to start'), findsOneWidget);
    expect(find.text('Start challenge'), findsNothing);
    expect(find.text('Cancel challenge'), findsNothing);
  });

  testWidgets('roster shows Accepted, Pending and Declined chips', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () =>
          _lobby(isOwner: true, participants: [_owner(), _member()]),
    );
    final invitations = <ChallengeInvitationSummary>[
      const ChallengeInvitationSummary(
        inviteId: 'i1',
        challengeId: 'lobby-1',
        tierId: ChallengeTierId.k10,
        ownerUid: 'me',
        status: ChallengeInvitationStatus.pending,
        createdAtMs: 0,
        expiresAtMs: 0,
        rules: null,
      ),
      const ChallengeInvitationSummary(
        inviteId: 'i2',
        challengeId: 'lobby-1',
        tierId: ChallengeTierId.k10,
        ownerUid: 'me',
        status: ChallengeInvitationStatus.declined,
        createdAtMs: 0,
        expiresAtMs: 0,
        rules: null,
      ),
    ];
    await tester.pumpWidget(
      _harness(_screen(repository: repository, pendingInvitations: invitations)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
  });

  testWidgets(
    'roster avatars link to profiles for others but not the current user; '
    'the pending-invitation avatar is inert',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = FakeChallengeRepository(
        activeOverride: () => _lobby(
          isOwner: false,
          participants: [
            _owner(isCurrentUser: false, displayName: 'jinseo'),
            _member(isCurrentUser: true),
          ],
        ),
      );
      final invitations = <ChallengeInvitationSummary>[
        const ChallengeInvitationSummary(
          inviteId: 'i1',
          challengeId: 'lobby-1',
          tierId: ChallengeTierId.k10,
          ownerUid: 'me',
          status: ChallengeInvitationStatus.pending,
          createdAtMs: 0,
          expiresAtMs: 0,
          rules: null,
        ),
      ];
      await tester.pumpWidget(
        _harness(
          _screen(repository: repository, pendingInvitations: invitations),
        ),
      );
      await tester.pumpAndSettle();

      // Another participant's avatar exposes profile-link button semantics.
      expect(find.bySemanticsLabel('View jinseo profile'), findsOneWidget);
      // The current user's own row is never tappable.
      expect(find.bySemanticsLabel('View Sam Runner profile'), findsNothing);
      // The pending-invitation tile ("Invited runner") stays anonymous.
      expect(
        find.bySemanticsLabel('View Invited runner profile'),
        findsNothing,
      );

      semantics.dispose();
    },
  );

  testWidgets('start confirm sheet uses solo wording when alone', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () => _lobby(isOwner: true, participants: [_owner()]),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start challenge'));
    await tester.pumpAndSettle();

    expect(find.text('Start solo — no one has joined yet.'), findsOneWidget);
  });

  testWidgets('start confirm sheet uses group wording with runners', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () =>
          _lobby(isOwner: true, participants: [_owner(), _member()]),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start challenge').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Start with 2 runners — unanswered invitations will expire.'),
      findsOneWidget,
    );
  });

  testWidgets('confirming start calls the repository and routes to progress', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () => _lobby(isOwner: true, participants: [_owner()]),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start challenge'));
    await tester.pumpAndSettle();
    // Confirm inside the sheet (the sheet's primary button).
    await tester.tap(find.text('Start challenge').last);
    await tester.pumpAndSettle();

    expect(repository.startedChallenges, <String>['lobby-1']);
    expect(find.byType(ChallengeProgressScreen), findsOneWidget);
  });

  testWidgets('cancel challenge asks for confirmation and calls repository', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () => _lobby(isOwner: true, participants: [_owner()]),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel challenge'));
    await tester.pumpAndSettle();

    expect(
      find.text('Cancel this challenge for everyone? This cannot be undone.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel challenge').last);
    await tester.pumpAndSettle();

    expect(repository.cancelledChallenges, <String>['lobby-1']);
  });

  testWidgets('expired lobby shows the calm expired state', (tester) async {
    final repository = FakeChallengeRepository(activeOverride: () => null);
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('This lobby expired'), findsOneWidget);
  });

  testWidgets('surfaces the backend reason when start fails', (tester) async {
    final repository = FakeChallengeRepository(
      activeOverride: () => _lobby(isOwner: true, participants: [_owner()]),
      startFailure: const ChallengeFailure(reason: 'LOBBY_EXPIRED'),
    );
    await tester.pumpWidget(_harness(_screen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start challenge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start challenge').last);
    await tester.pumpAndSettle();

    expect(find.text('This lobby has expired.'), findsOneWidget);
  });

  testWidgets('picker enforces the invite cap with a live counter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChallengeFriendPickerScreen(
          cap: 1,
          onBack: () {},
          friends: const [
            ChallengeInvitableFriend(
              uid: 'a',
              displayName: 'Ann',
              initials: 'AN',
              levelLabel: 'Lv.9',
            ),
            ChallengeInvitableFriend(uid: 'b', displayName: 'Bob', initials: 'BO'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invited 0 of 1'), findsWidgets);
    // Rows use the same profile-circle + XP-ring + level-pill badge as Friends.
    expect(find.byType(RuniacLevelProfileBadge), findsNWidgets(2));
    expect(find.text('Lv.9'), findsOneWidget);
    expect(find.text('Lv.0'), findsOneWidget);

    await tester.tap(find.text('Ann'));
    await tester.pumpAndSettle();

    expect(find.text('Invited 1 of 1'), findsWidgets);
    // The second row is now over cap and disabled.
    expect(find.text('Invite limit reached'), findsOneWidget);
  });

  testWidgets(
    'picker rows paint the level progress carried over from the Friends model',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChallengeFriendPickerScreen(
            cap: 2,
            onBack: () {},
            friends: const [
              ChallengeInvitableFriend(
                uid: 'a',
                displayName: 'Ann',
                initials: 'AN',
                levelLabel: 'Lv.9',
                levelProgressFraction: 0.42,
              ),
              // A friend whose level never resolved keeps the empty ring.
              ChallengeInvitableFriend(
                uid: 'b',
                displayName: 'Bob',
                initials: 'BO',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rings = tester
          .widgetList<RuniacLevelProfileBadge>(
            find.byType(RuniacLevelProfileBadge),
          )
          .map((badge) => badge.progressFraction)
          .toList();
      expect(rings, [0.42, 0.0]);
    },
  );

  testWidgets(
    'friend picker avatar exposes profile semantics and the row still '
    'toggles selection',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: ChallengeFriendPickerScreen(
            cap: 1,
            onBack: () {},
            friends: const [
              ChallengeInvitableFriend(
                uid: 'a',
                displayName: 'Ann',
                initials: 'AN',
                levelLabel: 'Lv.9',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The avatar exposes its own profile-link button semantics.
      expect(find.bySemanticsLabel('View Ann profile'), findsOneWidget);

      // Tapping the row body (not the avatar) still toggles selection.
      await tester.tap(find.text('Ann'));
      await tester.pumpAndSettle();

      expect(find.text('Invited 1 of 1'), findsWidgets);

      semantics.dispose();
    },
  );

  testWidgets('lobby lays out at 360px and textScale 1.3 without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = FakeChallengeRepository(
      activeOverride: () =>
          _lobby(isOwner: true, participants: [_owner(), _member()]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: _screen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Start challenge'), findsOneWidget);
  });
}
