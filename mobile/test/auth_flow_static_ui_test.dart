import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/auth/presentation/runiac_auth_flow_screen.dart';

import 'support/auth_flow_test_helpers.dart';
import 'support/fake_runiac_auth_repository.dart';

void main() {
  testWidgets('auth renders before onboarding when enabled', (tester) async {
    await tester.pumpWidget(
      const RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('auth_welcome_runiac_logo')),
      findsOneWidget,
    );
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Welcome to Runiac'), findsNothing);
    expect(find.text('Good to see you'), findsNothing);
  });

  testWidgets('auth welcome routes to login, password recovery, and signup', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);
    var authenticated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthFlowScreen(
          authRepository: repository,
          onAuthenticated: (_) {
            authenticated = true;
          },
        ),
      ),
    );

    await tapVisibleText(tester, 'Log in');

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Email or username'), findsNothing);
    expect(find.text('alex.morgan'), findsNothing);
    expect(find.text('password'), findsNothing);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Forgot email or username?'), findsNothing);

    await tapVisibleText(tester, 'Forgot password?');
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);

    await tapVisibleText(tester, 'Back to log in');
    await tapVisibleText(tester, 'Sign up');
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('First name'), findsNothing);
    expect(find.text('Alex'), findsNothing);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    await enterAuthCredentials(
      tester,
      email: 'new.runner@runiac.app',
      password: 'password123',
    );
    await tapVisibleText(tester, 'Create account');
    expect(authenticated, isTrue);
    expect(repository.createUserCalls, 1);
  });

  testWidgets('Google action uses the approved auth provider path', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);
    var completion = RuniacAuthCompletion.signup;

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthFlowScreen(
          authRepository: repository,
          onAuthenticated: (value) {
            completion = value;
          },
        ),
      ),
    );

    await tapVisibleText(tester, 'Log in');
    expect(find.text('Google sign-in coming later'), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
    await tapVisibleText(tester, 'Continue with Google');

    expect(completion, RuniacAuthCompletion.login);
    expect(repository.googleSignInCalls, 1);
    expect(repository.signInCalls, 0);
    expect(repository.createUserCalls, 0);
  });

  testWidgets('auth flow remains reachable on phone and tablet viewports', (
    tester,
  ) async {
    addTearDown(tester.view.reset);

    for (final size in [const Size(390, 844), const Size(768, 1024)]) {
      final repository = FakeRuniacAuthRepository();
      addTearDown(repository.dispose);
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: RuniacAuthFlowScreen(
            key: ValueKey('auth_flow_${size.width}_${size.height}'),
            authRepository: repository,
            onAuthenticated: (_) {},
          ),
        ),
      );

      expect(find.text('Sign up'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);

      await tapVisibleText(tester, 'Log in');
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);

      await tapVisibleText(tester, 'Forgot password?');
      expect(find.text('Reset your password'), findsOneWidget);
      expect(find.text('Send reset link'), findsOneWidget);

      await tapVisibleText(tester, 'Back to log in');
      await tapVisibleText(tester, 'Sign up');
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
    }
  });
}
