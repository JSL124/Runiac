import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/challenge_copy.dart';
import 'package:runiac_app/features/challenge/domain/challenge_countdown.dart';
import 'package:runiac_app/features/challenge/domain/models/active_challenge.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_participant_row.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_premium_hold.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_rules_snapshot.dart';
import 'package:runiac_app/features/challenge/domain/repositories/challenge_repository.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_progress_screen.dart';
import 'package:runiac_app/features/challenge/presentation/widgets/challenge_badge_image.dart';
import 'package:runiac_app/features/challenge/presentation/widgets/challenge_widgets.dart';

import 'support/fake_challenge_repository.dart';

class _FakeTicker implements ChallengeTicker {
  @override
  void start(VoidCallback onTick) {}
  @override
  void stop() {}
}

final _clock = DateTime.fromMillisecondsSinceEpoch(1000000000000);
const _challengeId = 'ch-1';

const _rulesGroup = ChallengeRulesSnapshot(
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

const _rulesSolo = ChallengeRulesSnapshot(
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
  required String name,
  required String initials,
  required ChallengeParticipantRole role,
  required ChallengeParticipantStatus status,
  required int meters,
  required bool isCurrentUser,
  String avatarUrlSnapshot = '',
}) {
  return ChallengeParticipantRow(
    uid: uid,
    displayNameSnapshot: name,
    avatarInitialsSnapshot: initials,
    levelLabelSnapshot: '',
    role: role,
    status: status,
    creditedMeters: meters,
    reward: ChallengeRewardStatus.notEligible,
    isCurrentUser: isCurrentUser,
    avatarUrlSnapshot: avatarUrlSnapshot,
  );
}

ActiveChallenge _challenge({
  required ChallengeMode mode,
  required ChallengeRulesSnapshot rules,
  required int teamMeters,
  required List<String> rosterUids,
  required List<ChallengeParticipantRow> participants,
  required bool isCurrentUserOwner,
  required String ownerUid,
  ChallengeInstanceStatus status = ChallengeInstanceStatus.active,
  ChallengePremiumHold? premiumHold,
}) {
  return ActiveChallenge(
    premiumHold: premiumHold,
    challengeId: _challengeId,
    ownerUid: ownerUid,
    tierId: rules.tierId,
    mode: mode,
    status: status,
    rules: rules,
    rosterUids: rosterUids,
    maxParticipants: rules.maxParticipants,
    teamMeters: teamMeters,
    createdAtMs: _clock.millisecondsSinceEpoch,
    lobbyExpiresAtMs: _clock.millisecondsSinceEpoch,
    startsAtMs: _clock.millisecondsSinceEpoch,
    scheduledEndsAtMs: _clock.millisecondsSinceEpoch + rules.durationMs,
    terminalReason: null,
    participants: participants,
    isCurrentUserOwner: isCurrentUserOwner,
  );
}

/// Owner (you) + active member + a member who left, retained km included in the
/// team total.
ActiveChallenge _groupOwner({
  ChallengeInstanceStatus status = ChallengeInstanceStatus.active,
}) {
  return _challenge(
    mode: ChallengeMode.group,
    rules: _rulesGroup,
    status: status,
    teamMeters: 9000, // 4000 + 3000 + 2000 (retained)
    rosterUids: const <String>['me', 'friend'],
    ownerUid: 'me',
    isCurrentUserOwner: true,
    participants: <ChallengeParticipantRow>[
      _row(
        uid: 'me',
        name: 'Runner Me',
        initials: 'ME',
        role: ChallengeParticipantRole.owner,
        status: ChallengeParticipantStatus.active,
        meters: 4000,
        isCurrentUser: true,
      ),
      _row(
        uid: 'friend',
        name: 'Sam Runner',
        initials: 'SR',
        role: ChallengeParticipantRole.member,
        status: ChallengeParticipantStatus.active,
        meters: 3000,
        isCurrentUser: false,
      ),
      _row(
        uid: 'gone',
        name: 'Lee Gone',
        initials: 'LG',
        role: ChallengeParticipantRole.member,
        status: ChallengeParticipantStatus.left,
        meters: 2000,
        isCurrentUser: false,
      ),
    ],
  );
}

/// You are a non-owner member; the owner is someone else.
ActiveChallenge _groupMember() {
  return _challenge(
    mode: ChallengeMode.group,
    rules: _rulesGroup,
    teamMeters: 7000,
    rosterUids: const <String>['friend', 'me'],
    ownerUid: 'friend',
    isCurrentUserOwner: false,
    participants: <ChallengeParticipantRow>[
      _row(
        uid: 'friend',
        name: 'Sam Runner',
        initials: 'SR',
        role: ChallengeParticipantRole.owner,
        status: ChallengeParticipantStatus.active,
        meters: 3000,
        isCurrentUser: false,
      ),
      _row(
        uid: 'me',
        name: 'Runner Me',
        initials: 'ME',
        role: ChallengeParticipantRole.member,
        status: ChallengeParticipantStatus.active,
        meters: 4000,
        isCurrentUser: true,
      ),
    ],
  );
}

ActiveChallenge _solo() {
  return _challenge(
    mode: ChallengeMode.solo,
    rules: _rulesSolo,
    teamMeters: 6000,
    rosterUids: const <String>['me'],
    ownerUid: 'me',
    isCurrentUserOwner: true,
    participants: <ChallengeParticipantRow>[
      _row(
        uid: 'me',
        name: 'Runner Me',
        initials: 'ME',
        role: ChallengeParticipantRole.owner,
        status: ChallengeParticipantStatus.active,
        meters: 6000,
        isCurrentUser: true,
      ),
    ],
  );
}

ChallengeProgressScreen _screen(FakeChallengeRepository repository) {
  return ChallengeProgressScreen(
    challengeId: _challengeId,
    repository: repository,
    clock: () => _clock,
    ticker: _FakeTicker(),
    onBack: () {},
  );
}

/// Pushes the screen over a seed route so an in-screen `Navigator.pop()` on
/// confirmed exit returns cleanly instead of popping the app root. Sets a real
/// surface size (so lazy roster rows lay out) and applies [textScale] below the
/// app's own MediaQuery.
Future<void> _pump(
  WidgetTester tester,
  FakeChallengeRepository repository, {
  double width = 800,
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => _screen(repository)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no premium-lapse warning for a runner in good standing', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(activeOverride: _solo);
    await _pump(tester, repository);

    // The banner collapses to a zero-extent box, which a lazy sliver list may
    // not even keep in the tree — the contract that matters is that nothing
    // about it is visible. `renders nothing when there is no hold` in
    // challenge_premium_lapse_ui_test.dart covers the widget itself.
    expect(find.text(ChallengeCopy.premiumLapseTitle), findsNothing);
    expect(find.text(ChallengeCopy.premiumLapseCta), findsNothing);
  });

  testWidgets('premium-lapse warning renders above the progress ring', (
    tester,
  ) async {
    // The relay is server-scoped to the caller, so a rendered banner always
    // concerns the runner looking at it — never a lobby-mate.
    final lapsed = _challenge(
      mode: ChallengeMode.solo,
      rules: _rulesSolo,
      teamMeters: 6000,
      rosterUids: const <String>['me'],
      ownerUid: 'me',
      isCurrentUserOwner: true,
      participants: <ChallengeParticipantRow>[
        _row(
          uid: 'me',
          name: 'Runner Me',
          initials: 'ME',
          role: ChallengeParticipantRole.owner,
          status: ChallengeParticipantStatus.active,
          meters: 6000,
          isCurrentUser: true,
        ),
      ],
      premiumHold: ChallengePremiumHold(
        graceExpiresAtMs:
            DateTime.now().add(const Duration(hours: 8)).millisecondsSinceEpoch,
      ),
    );
    final repository = FakeChallengeRepository(activeOverride: () => lapsed);
    await _pump(tester, repository);

    expect(find.text(ChallengeCopy.premiumLapseTitle), findsOneWidget);
    expect(find.text(ChallengeCopy.premiumLapseCta), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(ChallengeCopy.premiumLapseTitle)).dy,
      lessThan(tester.getTopLeft(find.byType(ChallengeBadgeImage).first).dy),
    );
  });

  testWidgets('solo variant shows Solo challenge and no personal-minimum bar', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(activeOverride: _solo);
    await _pump(tester, repository);

    expect(find.text('Solo challenge'), findsOneWidget);
    expect(find.textContaining('My distance'), findsNothing);
    expect(find.textContaining('Personal minimum'), findsNothing);
    // Team ring + team total still render.
    expect(find.text('6.0 / 10.0 km'), findsOneWidget);
    expect(find.byType(ChallengeBadgeImage), findsWidgets);
  });

  testWidgets(
    'participant tile passes the resolved avatarUrlSnapshot to ChallengeInitialsAvatar',
    (tester) async {
      // Roster tiles (and their avatars) only render for a group challenge:
      // a solo challenge shows the "Solo challenge" text instead.
      const photoUrl =
          'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok';
      final withPhoto = _challenge(
        mode: ChallengeMode.group,
        rules: _rulesGroup,
        teamMeters: 4000,
        rosterUids: const <String>['me', 'friend'],
        ownerUid: 'me',
        isCurrentUserOwner: true,
        participants: <ChallengeParticipantRow>[
          _row(
            uid: 'me',
            name: 'Runner Me',
            initials: 'ME',
            role: ChallengeParticipantRole.owner,
            status: ChallengeParticipantStatus.active,
            meters: 4000,
            isCurrentUser: true,
            avatarUrlSnapshot: photoUrl,
          ),
          _row(
            uid: 'friend',
            name: 'Sam Runner',
            initials: 'SR',
            role: ChallengeParticipantRole.member,
            status: ChallengeParticipantStatus.active,
            meters: 0,
            isCurrentUser: false,
          ),
        ],
      );
      final repository = FakeChallengeRepository(
        activeOverride: () => withPhoto,
      );
      await _pump(tester, repository);

      final badges = tester.widgetList<ChallengeInitialsAvatar>(
        find.byType(ChallengeInitialsAvatar),
      );
      // Only the current user's row was seeded with a photo.
      expect(
        badges.where((b) => (b.photoUrl ?? '').isNotEmpty).single.photoUrl,
        photoUrl,
      );
      expect(badges.where((b) => (b.photoUrl ?? '').isEmpty).length, 1);
    },
  );

  testWidgets('group: You first, active by km desc, muted Left group, km sums', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(activeOverride: _groupOwner);
    await _pump(tester, repository);

    // Team total reconciles retained km (4000 + 3000 + 2000 = 9000).
    expect(find.text('9.0 / 100.0 km'), findsOneWidget);
    // Current user labelled "You" and shown first.
    expect(find.text('You'), findsOneWidget);
    expect(find.text('4.0 km'), findsOneWidget);
    expect(find.text('3.0 km'), findsOneWidget);
    // Left group heading + retained km for the exited member.
    expect(find.text('Left the challenge'), findsOneWidget);
    expect(find.text('2.0 km'), findsOneWidget);
    expect(find.text('Lee Gone'), findsOneWidget);

    // "You" appears above "Sam Runner" (active, km desc, current user first).
    final youY = tester.getTopLeft(find.text('You')).dy;
    final samY = tester.getTopLeft(find.text('Sam Runner')).dy;
    final leftY = tester.getTopLeft(find.text('Lee Gone')).dy;
    expect(youY, lessThan(samY));
    expect(samY, lessThan(leftY));
  });

  testWidgets(
    "another participant's avatar links to their profile; the current "
    'user is not tappable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = FakeChallengeRepository(activeOverride: _groupOwner);
      await _pump(tester, repository);

      expect(find.bySemanticsLabel('View Sam Runner profile'), findsOneWidget);
      expect(find.bySemanticsLabel('View Runner Me profile'), findsNothing);

      semantics.dispose();
    },
  );

  testWidgets('my block: personal minimum caption uses 0.1 km formatting', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(activeOverride: _groupOwner);
    await _pump(tester, repository);

    expect(find.text('My distance 4.0 km'), findsOneWidget);
    expect(find.text('Personal minimum 13.0 km'), findsOneWidget);
    expect(find.text('Minimum reached'), findsNothing);
  });

  testWidgets('my block shows Minimum reached when the minimum is met', (
    tester,
  ) async {
    ActiveChallenge met() {
      final base = _groupOwner();
      return ActiveChallenge(
        challengeId: base.challengeId,
        ownerUid: base.ownerUid,
        tierId: base.tierId,
        mode: base.mode,
        status: base.status,
        rules: base.rules,
        rosterUids: base.rosterUids,
        maxParticipants: base.maxParticipants,
        teamMeters: base.teamMeters,
        createdAtMs: base.createdAtMs,
        lobbyExpiresAtMs: base.lobbyExpiresAtMs,
        startsAtMs: base.startsAtMs,
        scheduledEndsAtMs: base.scheduledEndsAtMs,
        terminalReason: base.terminalReason,
        participants: <ChallengeParticipantRow>[
          _row(
            uid: 'me',
            name: 'Runner Me',
            initials: 'ME',
            role: ChallengeParticipantRole.owner,
            status: ChallengeParticipantStatus.active,
            meters: 15000,
            isCurrentUser: true,
          ),
          ...base.participants.where((p) => !p.isCurrentUser),
        ],
        isCurrentUserOwner: base.isCurrentUserOwner,
      );
    }

    final repository = FakeChallengeRepository(activeOverride: met);
    await _pump(tester, repository);

    expect(find.text('Minimum reached'), findsOneWidget);
    expect(find.text('My distance 15.0 km'), findsOneWidget);
  });

  testWidgets('owner sees only Abandon; Leave is absent', (tester) async {
    final repository = FakeChallengeRepository(activeOverride: _groupOwner);
    await _pump(tester, repository);

    expect(find.text('Abandon challenge'), findsOneWidget);
    expect(find.text('Leave challenge'), findsNothing);
    expect(find.byKey(const ValueKey('challengeAbandonButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('challengeLeaveButton')), findsNothing);
  });

  testWidgets('non-owner sees only Leave; Abandon is absent', (tester) async {
    final repository = FakeChallengeRepository(activeOverride: _groupMember);
    await _pump(tester, repository);

    expect(find.text('Leave challenge'), findsOneWidget);
    expect(find.text('Abandon challenge'), findsNothing);
    expect(find.byKey(const ValueKey('challengeLeaveButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('challengeAbandonButton')), findsNothing);
  });

  testWidgets('leave confirmation copy, then confirm calls the repository', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(activeOverride: _groupMember);
    await _pump(tester, repository);

    await tester.tap(find.byKey(const ValueKey('challengeLeaveButton')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Your 4.0 km stays with the team, but you can't rejoin and you "
        "won't earn the badge even if the team succeeds.",
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Leave challenge').last);
    await tester.pumpAndSettle();

    expect(repository.leftChallenges, <String>[_challengeId]);
    expect(find.text('Left the challenge'), findsOneWidget); // snackbar
  });

  testWidgets('abandon confirmation copy names N runners, then calls repo', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(activeOverride: _groupOwner);
    await _pump(tester, repository);

    await tester.tap(find.byKey(const ValueKey('challengeAbandonButton')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This cancels the challenge for all 2 runners. '
        'No one will earn the badge.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Abandon challenge').last);
    await tester.pumpAndSettle();

    expect(repository.abandonedChallenges, <String>[_challengeId]);
  });

  testWidgets('server race rejection surfaces the mapped message and refreshes', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: _groupMember,
      leaveFailure: const ChallengeFailure(reason: 'CHALLENGE_NOT_ACTIVE'),
    );
    await _pump(tester, repository);
    final callsBefore = repository.activeCalls;

    await tester.tap(find.byKey(const ValueKey('challengeLeaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave challenge').last);
    await tester.pumpAndSettle();

    expect(find.text('This challenge is no longer active.'), findsOneWidget);
    // The screen re-read trusted state after the rejection.
    expect(repository.activeCalls, greaterThan(callsBefore));
  });

  testWidgets('SETTLING shows Calculating results and no Time left', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(
      activeOverride: () => _groupOwner(status: ChallengeInstanceStatus.settling),
    );
    await _pump(tester, repository);

    expect(find.text('Calculating results…'), findsOneWidget);
    expect(find.textContaining('Time left'), findsNothing);
  });

  testWidgets('terminal / missing challenge shows the ended state', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(activeOverride: () => null);
    await _pump(tester, repository);

    expect(find.text('This challenge has ended'), findsOneWidget);
    expect(find.text('Abandon challenge'), findsNothing);
    expect(find.text('Leave challenge'), findsNothing);
  });

  testWidgets('renders without overflow at 360px and textScale 1.3', (
    tester,
  ) async {
    final repository = FakeChallengeRepository(activeOverride: _groupOwner);
    await _pump(tester, repository, width: 360, textScale: 1.3);

    expect(find.text('9.0 / 100.0 km'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
