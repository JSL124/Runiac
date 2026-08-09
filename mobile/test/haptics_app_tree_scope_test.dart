// Guards the wiring the other haptics tests cannot see.
//
// `haptics_moments_test.dart` and `haptics_error_moments_test.dart` mount a
// `RuniacHapticsScope` directly around the screen under test, so they pass
// even if the real `RuniacApp` tree never provides one. These tests pump the
// actual app instead and assert the scope resolves from screen-level
// contexts — including inside a pushed route, since the scope sits above
// `MaterialApp` and every feature screen reaches it through the Navigator.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/core/haptics/runiac_haptics.dart';
import 'package:runiac_app/core/haptics/runiac_haptics_scope.dart';

import 'support/fake_runiac_auth_repository.dart';

void main() {
  testWidgets('real RuniacApp tree provides haptics to the signed-in shell', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: repository,
      ),
    );

    repository.emitSignedIn();
    await tester.pumpAndSettle();

    // Resolve from a context deep inside the app shell, the way feature code
    // does, rather than from the root element.
    final shellContext = tester.element(find.byTooltip('Home'));
    final haptics = RuniacHapticsScope.maybeOf(shellContext);

    expect(
      haptics,
      isNotNull,
      reason: 'RuniacApp must mount a RuniacHapticsScope above MaterialApp',
    );
    expect(haptics, isA<SystemRuniacHaptics>());
  });

  testWidgets('haptics scope still resolves inside a pushed route', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: repository,
      ),
    );

    repository.emitSignedIn();
    await tester.pumpAndSettle();

    RuniacHaptics? resolvedInRoute;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) {
            resolvedInRoute = RuniacHapticsScope.maybeOf(context);
            return const Scaffold(body: Text('pushed route'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('pushed route'), findsOneWidget);
    expect(
      resolvedInRoute,
      isNotNull,
      reason: 'Routes pushed on the app Navigator must still reach the scope',
    );
  });
}
