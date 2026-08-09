import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/leaderboard/presentation/widgets/runner_achievement_profile_screen.dart';
import 'package:runiac_app/features/profile/domain/models/runner_public_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/runner_public_profile_repository.dart';
import 'package:runiac_app/features/profile/presentation/runner_public_profile_scope.dart';
import 'package:runiac_app/features/profile/presentation/widgets/runner_profile_avatar_link.dart';

class _FakeRunnerPublicProfileRepository
    implements RunnerPublicProfileRepository {
  final requestedPayloads = <Map<String, Object?>>[];

  @override
  Future<RunnerPublicProfileReadModel?> loadRunnerPublicProfile({
    required RunnerPublicProfileQuery query,
  }) async {
    requestedPayloads.add(query.toPayload());
    return null;
  }
}

Widget _harness({
  required Widget child,
  RunnerPublicProfileRepository repository =
      const UnavailableRunnerPublicProfileRepository(),
}) {
  return MaterialApp(
    home: RunnerPublicProfileScope(
      repository: repository,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets(
    'tapping the avatar link pushes a profile screen seeded with the right uid',
    (tester) async {
      final repository = _FakeRunnerPublicProfileRepository();

      await tester.pumpWidget(
        _harness(
          repository: repository,
          child: const RunnerProfileAvatarLink(
            uid: 'runner-42',
            displayName: 'Casey',
            avatarInitials: 'C',
            levelBadgeLabel: 'Lv.5',
            child: SizedBox(width: 20, height: 20),
          ),
        ),
      );

      await tester.tap(find.byType(RunnerProfileAvatarLink));
      await tester.pumpAndSettle();

      expect(find.byType(RunnerAchievementProfileScreen), findsOneWidget);
      final screen = tester.widget<RunnerAchievementProfileScreen>(
        find.byType(RunnerAchievementProfileScreen),
      );
      expect(screen.profile.uid, 'runner-42');
      expect(screen.profile.name, 'Casey');
      expect(screen.profile.initial, 'C');
      expect(screen.profile.levelBadgeLabel, 'Lv.5');
      // Every leaderboard-only field stays empty for a uid-seeded profile.
      expect(screen.profile.snapshotId, '');
      expect(screen.profile.rankLabel, '');
      expect(screen.profile.buildId, '');
      expect(repository.requestedPayloads, <Map<String, Object?>>[
        <String, Object?>{'uid': 'runner-42'},
      ]);
    },
  );

  testWidgets('an empty uid renders no button semantics and no gesture', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _harness(
        child: const RunnerProfileAvatarLink(
          key: Key('empty-uid-link'),
          uid: '',
          displayName: 'No Uid',
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('empty-uid-link')),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel('View No Uid profile'), findsNothing);

    semantics.dispose();
  });

  testWidgets('enabled: false renders no button semantics and no gesture', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _harness(
        child: const RunnerProfileAvatarLink(
          key: Key('disabled-link'),
          uid: 'runner-42',
          displayName: 'Disabled Runner',
          enabled: false,
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('disabled-link')),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel('View Disabled Runner profile'), findsNothing);

    semantics.dispose();
  });

  testWidgets('the semantics label reads View <name> profile exactly once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _harness(
        child: const RunnerProfileAvatarLink(
          uid: 'runner-7',
          displayName: 'Jamie',
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );

    expect(find.bySemanticsLabel('View Jamie profile'), findsOneWidget);

    semantics.dispose();
  });
}
