import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/models/active_challenge.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_badge_ownership.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_participant_row.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_rules_snapshot.dart';
import 'package:runiac_app/features/challenge/domain/repositories/challenge_repository.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_explore_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_lobby_screen.dart';
import 'package:runiac_app/features/challenge/presentation/challenge_tier_detail_screen.dart';
import 'package:runiac_app/features/profile/domain/models/user_account_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_account_repository.dart';
import 'package:runiac_app/features/profile/presentation/current_session_user_account.dart';

import 'support/fake_challenge_repository.dart';

const _paywallTitleKey = Key('paywall-title');

Finder _tile(String tier) =>
    find.byKey(ValueKey<String>('challenge-tier-$tier'));

Finder _lock(String tier) =>
    find.byKey(ValueKey<String>('challenge-tier-lock-$tier'));

class _FixedUserAccountRepository implements UserAccountRepository {
  const _FixedUserAccountRepository(this.account);

  final UserAccountReadModel account;

  @override
  Future<UserAccountReadModel> loadUserAccount() async => account;
}

/// Pumps the explore hub. The account scope wraps the `MaterialApp` (as in
/// `app.dart`) so pushed routes — tier detail, paywall sheet — see it too.
/// `subscriptionStatus == null` mounts no scope at all (fail-open path).
Future<void> _pumpExplore(
  WidgetTester tester, {
  required FakeChallengeRepository repository,
  UserSubscriptionStatus? subscriptionStatus,
}) async {
  final app = MaterialApp(
    home: ChallengeExploreScreen(repository: repository, onBack: () {}),
  );
  if (subscriptionStatus == null) {
    await tester.pumpWidget(app);
  } else {
    final store = CurrentSessionUserAccount(
      repository: _FixedUserAccountRepository(
        UserAccountReadModel(subscriptionStatus: subscriptionStatus),
      ),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      CurrentSessionUserAccountScope(store: store, child: app),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _openDetail(WidgetTester tester, String tier) async {
  await tester.ensureVisible(_tile(tier));
  await tester.pumpAndSettle();
  await tester.tap(_tile(tier));
  await tester.pumpAndSettle();
  expect(find.byType(ChallengeTierDetailScreen), findsOneWidget);
}

Future<void> _tapCreate(WidgetTester tester) async {
  final createButton = find.widgetWithText(FilledButton, 'Create challenge');
  await tester.ensureVisible(createButton);
  await tester.pumpAndSettle();
  await tester.tap(createButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Disposes the pumped tree so the paywall's periodic highlight timer is
/// cancelled before the test ends.
Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

/// A RECRUITING solo instance on the premium 100K tier owned by the current
/// user — the in-progress-overrides-lock case for a lapsed Premium runner.
ActiveChallenge _recruiting100k() {
  const rules = ChallengeRulesSnapshot(
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
  return ActiveChallenge(
    challengeId: 'premium-active',
    ownerUid: 'runner-current',
    tierId: ChallengeTierId.k100,
    mode: ChallengeMode.solo,
    status: ChallengeInstanceStatus.recruiting,
    rules: rules,
    rosterUids: const <String>['runner-current'],
    maxParticipants: rules.maxParticipants,
    teamMeters: 0,
    createdAtMs: 1752307200000,
    lobbyExpiresAtMs: 1752393600000,
    startsAtMs: null,
    scheduledEndsAtMs: null,
    terminalReason: null,
    participants: const <ChallengeParticipantRow>[
      ChallengeParticipantRow(
        uid: 'runner-current',
        displayNameSnapshot: 'You',
        avatarInitialsSnapshot: 'YO',
        levelLabelSnapshot: 'Lv.5',
        role: ChallengeParticipantRole.owner,
        status: ChallengeParticipantStatus.active,
        creditedMeters: 0,
        reward: ChallengeRewardStatus.notEligible,
        isCurrentUser: true,
      ),
    ],
    isCurrentUserOwner: true,
  );
}

void main() {
  group('Explore grid lock state', () {
    testWidgets('Basic runner sees locks on premium tiers only', (
      tester,
    ) async {
      await _pumpExplore(
        tester,
        repository: FakeChallengeRepository(),
        subscriptionStatus: UserSubscriptionStatus.basic,
      );

      expect(_lock('100K'), findsOneWidget);
      expect(_lock('1000K'), findsOneWidget);
      expect(_lock('10K'), findsNothing);
      expect(_lock('20K'), findsNothing);
      expect(_lock('42K'), findsNothing);
    });

    testWidgets('Premium runner sees no locks', (tester) async {
      await _pumpExplore(
        tester,
        repository: FakeChallengeRepository(),
        subscriptionStatus: UserSubscriptionStatus.premium,
      );

      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });

    testWidgets('no account scope fails open to no locks', (tester) async {
      await _pumpExplore(tester, repository: FakeChallengeRepository());

      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });

    testWidgets('an earned premium tier is not locked', (tester) async {
      await _pumpExplore(
        tester,
        repository: FakeChallengeRepository(
          ownedBadgesOverride: ChallengeBadgeOwnership(
            ownedTierIds: <ChallengeTierId>{ChallengeTierId.k100},
          ),
        ),
        subscriptionStatus: UserSubscriptionStatus.basic,
      );

      expect(_lock('100K'), findsNothing);
      expect(_lock('200K'), findsOneWidget);
    });

    testWidgets('an in-progress premium tier is not locked', (tester) async {
      await _pumpExplore(
        tester,
        repository: FakeChallengeRepository(
          activeOverride: _recruiting100k,
        ),
        subscriptionStatus: UserSubscriptionStatus.basic,
      );

      expect(find.text('In progress'), findsOneWidget);
      expect(_lock('100K'), findsNothing);
      expect(_lock('200K'), findsOneWidget);
    });
  });

  group('Locked tier detail', () {
    testWidgets('tapping a locked tile opens the detail, not the paywall', (
      tester,
    ) async {
      await _pumpExplore(
        tester,
        repository: FakeChallengeRepository(),
        subscriptionStatus: UserSubscriptionStatus.basic,
      );

      await _openDetail(tester, '100K');

      expect(find.byKey(_paywallTitleKey), findsNothing);
      // Premium chip + dimmed hero badge with the lock roundel.
      expect(find.text('Premium'), findsOneWidget);
    });

    testWidgets('Create challenge intercepts to the paywall for Basic', (
      tester,
    ) async {
      final repository = FakeChallengeRepository();
      await _pumpExplore(
        tester,
        repository: repository,
        subscriptionStatus: UserSubscriptionStatus.basic,
      );
      await _openDetail(tester, '100K');

      await _tapCreate(tester);

      expect(find.byKey(_paywallTitleKey), findsOneWidget);
      expect(repository.createdTiers, isEmpty);

      await _teardownTree(tester);
    });

    testWidgets('Premium runner creates a premium-tier lobby as normal', (
      tester,
    ) async {
      final repository = FakeChallengeRepository();
      await _pumpExplore(
        tester,
        repository: repository,
        subscriptionStatus: UserSubscriptionStatus.premium,
      );
      await _openDetail(tester, '100K');

      expect(find.text('Premium'), findsNothing);
      await _tapCreate(tester);
      await tester.pumpAndSettle();

      expect(repository.createdTiers, <ChallengeTierId>[ChallengeTierId.k100]);
      expect(find.byType(ChallengeLobbyScreen), findsOneWidget);
      expect(find.byKey(_paywallTitleKey), findsNothing);
    });
  });

  group('Server PREMIUM_REQUIRED fallback', () {
    testWidgets('opens the paywall when the server refuses creation', (
      tester,
    ) async {
      // A free tier locally (stale catalog / config change mid-session):
      // the client gate passes, the server refuses, the paywall shows.
      final repository = FakeChallengeRepository(
        createFailure: const ChallengeFailure(reason: 'PREMIUM_REQUIRED'),
      );
      await _pumpExplore(
        tester,
        repository: repository,
        subscriptionStatus: UserSubscriptionStatus.basic,
      );
      await _openDetail(tester, '10K');

      await _tapCreate(tester);

      expect(find.byKey(_paywallTitleKey), findsOneWidget);
      expect(repository.createdTiers, <ChallengeTierId>[ChallengeTierId.k10]);

      await _teardownTree(tester);
    });

    testWidgets('falls back to copy when the paywall cannot show', (
      tester,
    ) async {
      // No account scope: the paywall gate fails open, so the refusal
      // surfaces as friendly copy instead of a raw error code.
      final repository = FakeChallengeRepository(
        createFailure: const ChallengeFailure(reason: 'PREMIUM_REQUIRED'),
      );
      await _pumpExplore(tester, repository: repository);
      await _openDetail(tester, '10K');

      await _tapCreate(tester);

      expect(find.byKey(_paywallTitleKey), findsNothing);
      expect(
        find.text('This challenge tier is part of Runiac Premium.'),
        findsOneWidget,
      );
    });
  });
}
