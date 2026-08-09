// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/leaderboard/presentation/models/leaderboard_display_models.dart';
import 'package:runiac_app/features/leaderboard/presentation/widgets/runner_achievement_profile_screen.dart';
import 'package:runiac_app/features/profile/data/cloud_functions_runner_public_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/models/runner_public_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/runner_public_profile_repository.dart';
import 'package:runiac_app/features/profile/presentation/widgets/account_challenge_badge_case.dart';

const _rankRow = RunnerAchievementProfileSnapshot(
  name: 'Jinseo_main',
  initial: 'J',
  regionRankLabel: '#1 Jurong East, Singapore',
  levelBadgeLabel: 'Lv.8',
  divisionLevelLabel: 'Silver · Level 8',
  totalDistanceLabel: 'Not shared',
  bestStreakLabel: 'Not shared',
  badges: <RunnerAchievementBadgeSnapshot>[],
  rankLabel: '#1',
  regionLabel: 'Jurong East, Singapore',
  divisionLabel: 'Silver',
  snapshotId: 'monthly_jurong-east_tier_03_2026-07',
  buildId: 'build-2026-07-26T09',
);

/// A demo row with no backing entry — nothing to resolve.
const _previewRow = RunnerAchievementProfileSnapshot(
  name: 'Jinseo_main',
  initial: 'J',
  regionRankLabel: '#1 Jurong East, Singapore',
  levelBadgeLabel: 'Lv.8',
  divisionLevelLabel: 'Silver · Level 8',
  totalDistanceLabel: 'Not shared',
  bestStreakLabel: 'Not shared',
  badges: <RunnerAchievementBadgeSnapshot>[],
  rankLabel: '#1',
  regionLabel: 'Jurong East, Singapore',
);

const _publicProfile = RunnerPublicProfileReadModel(
  displayName: 'Jinseo_main',
  avatarInitials: 'JI',
  regionLabel: 'Jurong East, Singapore',
  level: 8,
  levelProgressFraction: 0.975,
  totalXp: 780,
  nextLevelXp: 800,
  xpToNextLevel: 20,
  divisionKey: 'tier_03',
  divisionLabel: 'Silver League',
  longestStreakLabel: '4 days',
  totalDistanceLabel: '69.8 km',
  subscriptionStatusLabel: 'Basic',
  ownedTierIds: <ChallengeTierId>{ChallengeTierId.k250},
);

class _FakeRunnerPublicProfileRepository
    implements RunnerPublicProfileRepository {
  _FakeRunnerPublicProfileRepository({this.profile, this.failure});

  final RunnerPublicProfileReadModel? profile;
  final RunnerPublicProfileFailure? failure;
  final requestedPayloads = <Map<String, Object?>>[];

  @override
  Future<RunnerPublicProfileReadModel?> loadRunnerPublicProfile({
    required RunnerPublicProfileQuery query,
  }) async {
    requestedPayloads.add(query.toPayload());
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    return profile;
  }
}

Widget _screen(
  RunnerPublicProfileRepository repository, {
  RunnerAchievementProfileSnapshot row = _rankRow,
}) {
  return MaterialApp(
    home: RunnerAchievementProfileScreen(
      profile: row,
      onBack: () {},
      publicProfileRepository: repository,
    ),
  );
}

// The report affordance's `!isCurrentUser && uid.isNotEmpty` gate is also
// guarded by a live `FirebaseAuth.instance.currentUser` read (see
// `_currentReporterUid` in runner_achievement_profile_screen.dart), which
// throws in a plain widget test with no Firebase app registered. This fakes
// just enough of the auth platform interface for that read to resolve to a
// signed-in reporter, so the "offered" half of the gate is reachable here.
class _EmptyFirebaseCoreHostApi implements TestFirebaseCoreHostApi {
  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async {
    return CoreInitializeResponse(
      name: appName,
      options: initializeAppRequest,
      pluginConstants: const {},
    );
  }

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    return const <CoreInitializeResponse>[];
  }

  @override
  Future<CoreFirebaseOptions> optionsFromResource() {
    throw UnimplementedError();
  }
}

class _FakeMultiFactor extends MultiFactorPlatform {
  _FakeMultiFactor(super.auth);
}

class _FakeUser extends UserPlatform {
  _FakeUser(FirebaseAuthPlatform auth, String uid)
    : super(
        auth,
        _FakeMultiFactor(auth),
        InternalUserDetails(
          userInfo: InternalUserInfo(
            uid: uid,
            isAnonymous: false,
            isEmailVerified: true,
          ),
          providerData: const [],
        ),
      );
}

class _FakeFirebaseAuthPlatform extends FirebaseAuthPlatform {
  _FakeFirebaseAuthPlatform(this._reporterUid) : super();

  final String _reporterUid;
  UserPlatform? _currentUser;

  @override
  UserPlatform? get currentUser => _currentUser;

  @override
  set currentUser(UserPlatform? userPlatform) => _currentUser = userPlatform;

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) {
    // Ignore the (empty, in this fake) method-channel plugin constants and
    // seed a fixed signed-in reporter instead.
    _currentUser ??= _FakeUser(this, _reporterUid);
    return this;
  }
}

const _fakeReporterUid = 'reporter-uid-1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestFirebaseCoreHostApi.setUp(_EmptyFirebaseCoreHostApi());
  FirebaseAuthPlatform.instance = _FakeFirebaseAuthPlatform(_fakeReporterUid);

  setUpAll(() async {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'test-api-key',
        appId: '1:000000000000:ios:test',
        messagingSenderId: '000000000000',
        projectId: 'runiac-test',
      ),
    );
  });

  testWidgets('shows the runner backend-owned public profile values', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRunnerPublicProfileRepository(
      profile: _publicProfile,
    );

    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();

    // The viewer never held a uid: the row is addressed by the entry it came
    // from, and the backend resolves the owner.
    expect(repository.requestedPayloads, <Map<String, Object?>>[
      <String, Object?>{
        'snapshotId': 'monthly_jurong-east_tier_03_2026-07',
        'rankLabel': '#1',
        'buildId': 'build-2026-07-26T09',
      },
    ]);
    expect(find.text('Jinseo_main'), findsOneWidget);
    expect(find.text('BASIC'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Jurong East, Singapore'), findsOneWidget);
    expect(find.text('Lv.8'), findsWidgets);
    expect(find.text('Lv.9'), findsOneWidget);
    expect(find.text('20 XP to level up'), findsOneWidget);
    expect(find.text('780 / 800 XP'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('Max streak'), findsOneWidget);
    expect(find.text('69.8 km'), findsOneWidget);
    expect(find.text('Total distance'), findsOneWidget);
    expect(find.byType(AccountChallengeBadgeCase), findsOneWidget);
    expect(
      tester
          .widget<AccountChallengeBadgeCase>(
            find.byType(AccountChallengeBadgeCase),
          )
          .ownedTierIds,
      <ChallengeTierId>{ChallengeTierId.k250},
    );
  });

  testWidgets('never renders the account-only sections of a profile', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _screen(_FakeRunnerPublicProfileRepository(profile: _publicProfile)),
    );
    await tester.pumpAndSettle();

    for (final accountOnly in [
      'RUNNING SETUP',
      'MANAGE',
      'Edit profile',
      'Settings',
      'Privacy & Safety',
      'Notifications',
      'Watch & Health Apps',
      'About Runiac',
      'Feedback',
      'Current goal',
      'Preferred unit',
      'Weekly rhythm',
      'Experience',
    ]) {
      expect(find.text(accountOnly), findsNothing, reason: accountOnly);
    }
  });

  testWidgets('guards a private record and shows no figures behind it', (
    WidgetTester tester,
  ) async {
    // Exactly the shape the backend returns for a hidden runner: identity
    // intact, every record value already blanked server-side.
    const hidden = RunnerPublicProfileReadModel(
      displayName: 'Jinseo_main',
      avatarInitials: 'JI',
      regionLabel: 'Jurong East, Singapore',
      level: 8,
      divisionKey: 'tier_03',
      divisionLabel: 'Silver League',
      subscriptionStatusLabel: 'Basic',
      statsHidden: true,
    );

    await tester.pumpWidget(
      _screen(_FakeRunnerPublicProfileRepository(profile: hidden)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('runner_profile_private_record_guard')),
      findsOneWidget,
    );
    // Identity survives — it is already public on the board this viewer came
    // from.
    expect(find.text('Jinseo_main'), findsOneWidget);
    // The blur is cosmetic, so the real assertion is that there is nothing
    // underneath it to reveal: the leaderboard row's own placeholders must not
    // stand in for the withheld values either.
    expect(find.text('69.8 km'), findsNothing);
    expect(find.text('4 days'), findsNothing);
    expect(find.textContaining('780'), findsNothing);
  });

  testWidgets('a visible record renders without the private guard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _screen(_FakeRunnerPublicProfileRepository(profile: _publicProfile)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('runner_profile_private_record_guard')),
      findsNothing,
    );
    expect(find.text('69.8 km'), findsOneWidget);
  });

  testWidgets('shows the failure message and no earned badges when denied', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        _FakeRunnerPublicProfileRepository(
          failure: const RunnerPublicProfileFailure(
            'This runner profile is not available.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This runner profile is not available.'), findsOneWidget);
    expect(
      tester
          .widget<AccountChallengeBadgeCase>(
            find.byType(AccountChallengeBadgeCase),
          )
          .ownedTierIds,
      isEmpty,
    );
    // The rank-row facts still label the screen.
    expect(find.text('Jinseo_main'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
  });

  testWidgets('keeps the leaderboard row values when no backend is wired', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _screen(const UnavailableRunnerPublicProfileRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jinseo_main'), findsOneWidget);
    expect(find.text('Not shared'), findsNWidgets(2));
    expect(
      find.text('Only public running achievements are shown.'),
      findsOneWidget,
    );
  });

  testWidgets('never calls the backend for a row with nothing to resolve', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRunnerPublicProfileRepository(
      profile: _publicProfile,
    );

    await tester.pumpWidget(_screen(repository, row: _previewRow));
    await tester.pumpAndSettle();

    expect(repository.requestedPayloads, isEmpty);
    expect(find.text('Not shared'), findsNWidgets(2));
  });

  testWidgets('surfaces a superseded board build as unavailable', (
    WidgetTester tester,
  ) async {
    // The backend answers not-found when the rank was reassigned since this
    // row was rendered; the screen must say so rather than show another runner.
    await tester.pumpWidget(
      _screen(
        _FakeRunnerPublicProfileRepository(
          failure: const RunnerPublicProfileFailure(
            'This runner profile is not available.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This runner profile is not available.'), findsOneWidget);
  });

  testWidgets('a forRunner seed sends the uid payload and offers reporting', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRunnerPublicProfileRepository(
      profile: _publicProfile,
    );

    await tester.pumpWidget(
      _screen(
        repository,
        row: const RunnerAchievementProfileSnapshot.forRunner(
          uid: 'runner-42',
          name: 'Jinseo_main',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The uid form addresses the runner directly; no leaderboard entry keys.
    expect(repository.requestedPayloads, <Map<String, Object?>>[
      <String, Object?>{'uid': 'runner-42'},
    ]);
    // A uid-seeded profile has a real backing runner (and this harness's
    // fake FirebaseAuth resolves a signed-in reporter), so reporting is
    // offered.
    expect(
      find.byKey(const Key('runner_profile_report_action')),
      findsOneWidget,
    );
  });

  testWidgets('a seed with neither uid nor snapshot never calls the backend', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRunnerPublicProfileRepository(
      profile: _publicProfile,
    );

    await tester.pumpWidget(
      _screen(
        repository,
        row: const RunnerAchievementProfileSnapshot.forRunner(
          uid: '',
          name: 'Jinseo_main',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedPayloads, isEmpty);
    // No backing runner to report either.
    expect(find.byKey(const Key('runner_profile_report_action')), findsNothing);
  });

  testWidgets(
    'the report action is absent for a leaderboard seed with no uid',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _screen(
          _FakeRunnerPublicProfileRepository(profile: _publicProfile),
          row: _rankRow,
        ),
      );
      await tester.pumpAndSettle();

      // _rankRow is a leaderboard-entry seed: the public snapshot never
      // carries a uid, so the report affordance stays hidden.
      expect(
        find.byKey(const Key('runner_profile_report_action')),
        findsNothing,
      );
    },
  );

  group('Cloud Functions runner public profile repository', () {
    test('maps the callable payload into the read model', () async {
      Map<String, Object?>? sentPayload;
      final repository = CloudFunctionsRunnerPublicProfileRepository(
        callable: (payload) async {
          sentPayload = payload;
          return <Object?, Object?>{
            'displayName': 'Jinseo_main',
            'avatarInitials': 'JI',
            'avatarUrl':
                'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok',
            'regionLabel': 'Jurong East, Singapore',
            'level': 8,
            'levelProgressPercent': 97.5,
            'totalXp': 780,
            'nextLevelXp': 800,
            'xpToNextLevel': 20,
            'isMaxLevel': false,
            'divisionKey': 'tier_03',
            'divisionLabel': 'Silver League',
            'longestStreakLabel': '4 days',
            'totalDistanceLabel': '69.8 km',
            'subscriptionStatusLabel': 'Basic',
            'ownedBadgeTierIds': <Object?>['250K', 'not-a-tier'],
          };
        },
      );

      final profile = await repository.loadRunnerPublicProfile(
        query: const RunnerPublicProfileQuery.leaderboardEntry(
          snapshotId: 'monthly_jurong-east_tier_03_2026-07',
          rankLabel: '#3',
          buildId: 'build-2026-07-26T09',
        ),
      );

      expect(sentPayload, <String, Object?>{
        'snapshotId': 'monthly_jurong-east_tier_03_2026-07',
        'rankLabel': '#3',
        'buildId': 'build-2026-07-26T09',
      });
      expect(profile!.displayName, 'Jinseo_main');
      expect(profile.levelBadgeLabel, 'Lv.8');
      expect(profile.levelProgressFraction, closeTo(0.975, 0.0001));
      expect(profile.xpToNextLevel, 20);
      expect(profile.subscriptionStatusLabel, 'Basic');
      expect(
        profile.avatarUrl,
        'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok',
      );
      // An id this build does not know is skipped, never thrown on.
      expect(profile.ownedTierIds, <ChallengeTierId>{ChallengeTierId.k250});
    });

    test(
      'defaults avatarUrl to empty when an older deployment omits it',
      () async {
        final repository = CloudFunctionsRunnerPublicProfileRepository(
          callable: (payload) async {
            return <Object?, Object?>{
              'displayName': 'Jinseo_main',
              'avatarInitials': 'JI',
              'regionLabel': 'Jurong East, Singapore',
              'level': 8,
            };
          },
        );

        final profile = await repository.loadRunnerPublicProfile(
          query: const RunnerPublicProfileQuery.runner(uid: 'runner-uid'),
        );

        expect(profile!.avatarUrl, '');
      },
    );

    test('reports an unusable response as a failure', () async {
      final repository = CloudFunctionsRunnerPublicProfileRepository(
        callable: (_) async => 'unexpected',
      );

      expect(
        () => repository.loadRunnerPublicProfile(
          query: const RunnerPublicProfileQuery.leaderboardEntry(
            snapshotId: 'monthly_jurong-east_tier_03_2026-07',
            rankLabel: '#3',
            buildId: 'build-2026-07-26T09',
          ),
        ),
        throwsA(isA<RunnerPublicProfileFailure>()),
      );
    });
  });
}
