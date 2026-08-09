// Guards the wiring the entry-point tests cannot see.
//
// `runner_profile_entry_points_test.dart` mounts a `RunnerPublicProfileScope`
// directly around the widget under test, so every avatar link passes there
// even if the real `RuniacApp` tree never provides one. Without this guard the
// feature fails silently in production: `RunnerPublicProfileScope.of` falls
// back to `UnavailableRunnerPublicProfileRepository`, every profile opens in
// its seed-only preview state, and no test notices.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/profile/data/cloud_functions_runner_public_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/runner_public_profile_repository.dart';
import 'package:runiac_app/features/profile/presentation/runner_public_profile_scope.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  testWidgets('real RuniacApp tree provides the runner profile repository', (
    tester,
  ) async {
    final authRepository = FakeRuniacAuthRepository();
    addTearDown(authRepository.dispose);
    final repository = CloudFunctionsRunnerPublicProfileRepository(
      callable: (_) async => <Object?, Object?>{},
    );

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: authRepository,
        runnerPublicProfileRepository: repository,
      ),
    );

    authRepository.emitSignedIn();
    await tester.pumpAndSettle();

    // Resolve from a context deep inside the shell, the way an avatar link
    // does when a runner taps it.
    final shellContext = tester.element(find.byTooltip('Home'));

    expect(
      RunnerPublicProfileScope.of(shellContext),
      same(repository),
      reason:
          'RuniacApp must mount a RunnerPublicProfileScope above MaterialApp '
          'carrying the repository it was constructed with',
    );
  });

  testWidgets('the scope still resolves inside a pushed route', (tester) async {
    final authRepository = FakeRuniacAuthRepository();
    addTearDown(authRepository.dispose);
    final repository = CloudFunctionsRunnerPublicProfileRepository(
      callable: (_) async => <Object?, Object?>{},
    );

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: authRepository,
        runnerPublicProfileRepository: repository,
      ),
    );

    authRepository.emitSignedIn();
    await tester.pumpAndSettle();

    final navigator = Navigator.of(tester.element(find.byTooltip('Home')));
    late BuildContext routeContext;
    unawaitedPush(navigator, (context) {
      routeContext = context;
      return const Scaffold(body: SizedBox.shrink());
    });
    await tester.pumpAndSettle();

    // Every avatar link outside the leaderboard opens its profile as a pushed
    // route, so the scope has to survive that hop.
    expect(RunnerPublicProfileScope.of(routeContext), same(repository));
  });

  testWidgets('an app built without a repository degrades to the stub', (
    tester,
  ) async {
    final authRepository = FakeRuniacAuthRepository();
    addTearDown(authRepository.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: authRepository,
      ),
    );

    authRepository.emitSignedIn();
    await tester.pumpAndSettle();

    // The no-Firebase build must stay openable: links fall back to the stub
    // rather than throwing.
    expect(
      RunnerPublicProfileScope.of(tester.element(find.byTooltip('Home'))),
      isA<UnavailableRunnerPublicProfileRepository>(),
    );
  });
}

void unawaitedPush(
  NavigatorState navigator,
  Widget Function(BuildContext context) builder,
) {
  navigator.push(MaterialPageRoute<void>(builder: builder));
}
