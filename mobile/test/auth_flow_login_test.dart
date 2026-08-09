import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/profile/data/firestore_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/auth/presentation/runiac_auth_flow_screen.dart';

import 'support/auth_flow_test_helpers.dart';
import 'support/fake_runiac_auth_repository.dart';

void main() {
  testWidgets('login validates email and password before completion', (
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
    await tapVisibleText(tester, 'Sign in');

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(authenticated, isFalse);

    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tapVisibleText(tester, 'Sign in');

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(authenticated, isFalse);

    await enterAuthCredentials(
      tester,
      email: 'runner@runiac.app',
      password: 'password123',
    );
    await tapVisibleText(tester, 'Sign in');

    expect(authenticated, isTrue);
    expect(repository.signInCalls, 1);
  });

  testWidgets('valid login calls auth repository and opens app shell', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);
    repository.holdNextSignIn();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: repository,
      ),
    );
    repository.emitSignedOut();
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Log in');
    await enterAuthCredentials(
      tester,
      email: 'runner@runiac.app',
      password: 'password123',
    );
    await tapVisibleText(tester, 'Sign in');

    expect(repository.signInCalls, 1);
    expect(repository.lastSignInEmail, 'runner@runiac.app');
    expect(repository.lastSignInPassword, 'password123');
    expect(find.text('Signing in...'), findsOneWidget);

    await tester.tap(find.text('Signing in...'));
    await tester.pump();
    expect(
      repository.signInCalls,
      1,
      reason: 'Loading auth buttons must prevent double submit.',
    );
    expect(find.text('Good to see you'), findsNothing);

    repository.completeHeldSignIn();
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Runiac'), findsNothing);
    expect(find.text('Step 1 of 16'), findsNothing);
    expect(find.byTooltip('Home'), findsOneWidget);
  });

  testWidgets('Google login calls auth repository and opens app shell', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);
    repository.holdNextGoogleSignIn();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: repository,
      ),
    );
    repository.emitSignedOut();
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Log in');
    await tapVisibleText(tester, 'Continue with Google');

    expect(repository.googleSignInCalls, 1);
    expect(find.text('Signing in with Google...'), findsOneWidget);

    await tester.tap(find.text('Signing in with Google...'));
    await tester.pump();
    expect(
      repository.googleSignInCalls,
      1,
      reason: 'Loading Google auth button must prevent double submit.',
    );

    repository.completeHeldGoogleSignIn();
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Runiac'), findsNothing);
    expect(find.text('Step 1 of 16'), findsNothing);
    expect(find.byTooltip('Home'), findsOneWidget);
  });

  testWidgets('Google login with no profile document starts onboarding', (
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
        profileRepository: const _MissingCurrentUserProfileRepository(),
      ),
    );
    repository.emitSignedOut();
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Log in');
    await tapVisibleText(tester, 'Continue with Google');
    await tester.pumpAndSettle();

    // A Google account signing in for the first time — on the website or here —
    // owns no profile document yet, so it is owed onboarding, not a sign-out.
    expect(repository.googleSignInCalls, 1);
    expect(repository.signOutCalls, 0);
    expect(find.text('Tell us about you'), findsOneWidget);
    expect(find.text('Create your account'), findsNothing);
    expect(
      find.text(
        'No Runiac account setup exists for this account. Sign up to create your profile and start onboarding.',
      ),
      findsNothing,
    );
    expect(find.text('Good to see you'), findsNothing);
    expect(find.text('Welcome to Runiac'), findsNothing);
    expect(find.text('Step 1 of 16'), findsNothing);
  });

  testWidgets('Google login error shows auth repository message', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository(
      googleSignInError: RuniacAuthException.fromFirebaseCode(
        'network-request-failed',
      ),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthFlowScreen(
          authRepository: repository,
          onAuthenticated: (_) {},
        ),
      ),
    );

    await tapVisibleText(tester, 'Log in');
    await tapVisibleText(tester, 'Continue with Google');

    expect(repository.googleSignInCalls, 1);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Good to see you'), findsNothing);
  });

  testWidgets('invalid credentials show auth repository message', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository(
      signInError: RuniacAuthException.fromFirebaseCode('invalid-credential'),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthFlowScreen(
          authRepository: repository,
          onAuthenticated: (_) {},
        ),
      ),
    );

    await tapVisibleText(tester, 'Log in');
    await enterAuthCredentials(
      tester,
      email: 'runner@runiac.app',
      password: 'wrong-password',
    );
    await tapVisibleText(tester, 'Sign in');

    expect(repository.signInCalls, 1);
    expect(find.text('That email and password do not match.'), findsOneWidget);
    expect(find.text('Good to see you'), findsNothing);
  });

  testWidgets('login auth completion hands off to the app shell', (
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
    repository.emitSignedOut();
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Log in');
    await enterAuthCredentials(
      tester,
      email: 'runner@runiac.app',
      password: 'password123',
    );
    await tapVisibleText(tester, 'Sign in');

    await tester.pumpAndSettle();

    expect(repository.signInCalls, 1);
    expect(find.text('Welcome to Runiac'), findsNothing);
    expect(find.text('Step 1 of 16'), findsNothing);
    expect(find.byTooltip('Home'), findsOneWidget);
  });
}

class _MissingCurrentUserProfileRepository implements UserProfileRepository {
  const _MissingCurrentUserProfileRepository();

  @override
  Future<UserProfileReadModel> loadUserProfile() async {
    throw const CurrentUserProfileException(
      uid: 'test-auth-user-1',
      reason: CurrentUserProfileFailureReason.missing,
    );
  }
}
