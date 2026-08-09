import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/challenge_countdown.dart';
import 'package:runiac_app/features/challenge/presentation/home_active_challenge_display.dart';
import 'package:runiac_app/features/challenge/presentation/widgets/challenge_badge_image.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/active_challenge.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_participant_row.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_rules_snapshot.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map.dart';

const _controlKey = ValueKey<String>('homeActiveChallengeControl');

/// A ticker whose callback the test drives by hand, so no real frames are ever
/// scheduled and per-second recomputes are deterministic.
class _ControllableTicker implements ChallengeTicker {
  VoidCallback? _onTick;
  bool get started => _onTick != null;

  @override
  void start(VoidCallback onTick) {
    _onTick = onTick;
  }

  @override
  void stop() {
    _onTick = null;
  }

  void fire() => _onTick?.call();
}

// 12 days, 3 hours, 18 minutes, 42 seconds ahead of the base clock.
const _remainingSeconds = 12 * 86400 + 3 * 3600 + 18 * 60 + 42;
final _baseClock = DateTime.fromMillisecondsSinceEpoch(1000000000000);

HomeActiveChallengeDisplay _display({
  ChallengeTierId tierId = ChallengeTierId.k100,
  bool isSettling = false,
}) {
  return HomeActiveChallengeDisplay(
    tierId: tierId,
    scheduledEndsAtMs:
        _baseClock.millisecondsSinceEpoch + _remainingSeconds * 1000,
    isSettling: isSettling,
  );
}

Widget _harness({
  HomeActiveChallengeDisplay? active,
  VoidCallback? onOpenProgress,
  ChallengeTicker? ticker,
  DateTime Function()? clock,
  double textScale = 1.0,
  double width = 800,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      textScaler: TextScaler.linear(textScale),
    ),
    child: MaterialApp(
      home: Scaffold(
        body: HomeStageMap(
          model: null,
          streakCount: 4,
          onNotifications: () {},
          onProfile: () {},
          onTapTodayStage: () {},
          activeChallenge: active,
          onOpenChallengeProgress: onOpenProgress,
          challengeClock: clock ?? () => _baseClock,
          challengeTicker: ticker,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('absent when no active/settling challenge — no gap, no control', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(active: null));
    await tester.pumpAndSettle();

    expect(find.byKey(_controlKey), findsNothing);
    expect(find.byType(ChallengeBadgeImage), findsNothing);
    expect(find.text('Calculating…'), findsNothing);
    expect(find.textContaining(':'), findsNothing);
    // The streak moved into the Menu panel, so the header carries no streak
    // number of its own.
    expect(find.text('4'), findsNothing);
    expect(find.text('Menu'), findsOneWidget);
  });

  testWidgets('ACTIVE shows badge + exact DD:HH:MM:SS fixed format', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(active: _display(), ticker: _ControllableTicker()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_controlKey), findsOneWidget);
    expect(find.byType(ChallengeBadgeImage), findsOneWidget);
    expect(find.text('12:03:18:42'), findsOneWidget);
  });

  testWidgets('the challenge badge shares the profile badge y-baseline', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(active: _display(), ticker: _ControllableTicker()),
    );
    await tester.pumpAndSettle();

    final badge = tester.getRect(find.byType(ChallengeBadgeImage));
    final profile = tester.getRect(find.bySemanticsLabel('Profile'));

    expect(badge.top, profile.top);
    expect(badge.height, profile.height);
  });

  testWidgets('SETTLING shows the short Calculating copy, not a countdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        active: _display(isSettling: true),
        ticker: _ControllableTicker(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_controlKey), findsOneWidget);
    expect(find.text('Calculating…'), findsOneWidget);
    expect(find.text('12:03:18:42'), findsNothing);
  });

  test('terminal / recruiting challenges project to no control', () {
    ActiveChallenge instance(ChallengeInstanceStatus status) {
      return ActiveChallenge(
        challengeId: 'c',
        ownerUid: 'me',
        tierId: ChallengeTierId.k100,
        mode: ChallengeMode.group,
        status: status,
        rules: _rules,
        rosterUids: const <String>['me'],
        maxParticipants: 4,
        teamMeters: 10000,
        createdAtMs: 0,
        lobbyExpiresAtMs: 0,
        startsAtMs: 0,
        scheduledEndsAtMs: 1,
        terminalReason: null,
        participants: const <ChallengeParticipantRow>[],
        isCurrentUserOwner: true,
      );
    }

    expect(
      HomeActiveChallengeDisplay.fromActiveChallenge(
        instance(ChallengeInstanceStatus.recruiting),
      ),
      isNull,
    );
    for (final status in <ChallengeInstanceStatus>[
      ChallengeInstanceStatus.succeeded,
      ChallengeInstanceStatus.failed,
      ChallengeInstanceStatus.cancelled,
      ChallengeInstanceStatus.expired,
    ]) {
      expect(
        HomeActiveChallengeDisplay.fromActiveChallenge(instance(status)),
        isNull,
        reason: 'terminal $status must hide the control',
      );
    }
    expect(
      HomeActiveChallengeDisplay.fromActiveChallenge(
        instance(ChallengeInstanceStatus.active),
      ),
      isNotNull,
    );
  });

  testWidgets('tapping the control fires the navigation callback', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _harness(
        active: _display(),
        onOpenProgress: () => opened++,
        ticker: _ControllableTicker(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_controlKey));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('control is a single stable minute-level semantic button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(active: _display(), ticker: _ControllableTicker()),
    );
    await tester.pumpAndSettle();

    const label =
        'Active 100K challenge, 12 days 3 hours left. '
        'Opens challenge progress.';
    expect(find.bySemanticsLabel(label), findsOneWidget);
    handle.dispose();
  });

  testWidgets('countdown text ticks each second but semantics does not', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final ticker = _ControllableTicker();
    var now = _baseClock;
    await tester.pumpWidget(
      _harness(active: _display(), ticker: ticker, clock: () => now),
    );
    await tester.pumpAndSettle();

    const label =
        'Active 100K challenge, 12 days 3 hours left. '
        'Opens challenge progress.';
    expect(find.text('12:03:18:42'), findsOneWidget);
    expect(find.bySemanticsLabel(label), findsOneWidget);

    // Advance one wall-clock second and drive a tick.
    now = _baseClock.add(const Duration(seconds: 1));
    ticker.fire();
    await tester.pump();

    // Visible fixed-width text ticked down…
    expect(find.text('12:03:18:41'), findsOneWidget);
    // …but the minute-level semantic summary is unchanged.
    expect(find.bySemanticsLabel(label), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the countdown timer is disposed with the widget', (
    tester,
  ) async {
    final ticker = _ControllableTicker();
    await tester.pumpWidget(_harness(active: _display(), ticker: ticker));
    await tester.pumpAndSettle();
    expect(ticker.started, isTrue);

    // Remove the control from the tree.
    await tester.pumpWidget(_harness(active: null));
    await tester.pumpAndSettle();

    expect(ticker.started, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflow at 360px and textScale 1.3', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        active: _display(),
        ticker: _ControllableTicker(),
        width: 360,
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_controlKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forbidden content is absent inside the control', (tester) async {
    await tester.pumpWidget(
      _harness(active: _display(), ticker: _ControllableTicker()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('km'), findsNothing);
    expect(find.text('100K'), findsNothing); // no tier title label
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });
}

const _rules = ChallengeRulesSnapshot(
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
