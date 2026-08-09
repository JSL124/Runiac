import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/features/profile/data/firestore_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/auth/presentation/runiac_auth_gate.dart';

import 'support/auth_flow_test_helpers.dart';
import 'support/fake_runiac_auth_repository.dart';

void main() {
  testWidgets('showAuth false immediately renders child without auth stream', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthGate(
          authRepository: repository,
          showAuth: false,
          child: const Text('Protected app shell'),
        ),
      ),
    );

    expect(find.text('Protected app shell'), findsOneWidget);
    expect(repository.authStateListenCount, 0);
  });

  testWidgets(
    'loading state appears while waiting for first repository auth state',
    (tester) async {
      final repository = FakeRuniacAuthRepository();
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: RuniacAuthGate(
            authRepository: repository,
            showAuth: true,
            child: const Text('Protected app shell'),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('runiac_splash_screen')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('runiac_splash_logo')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Protected app shell'), findsNothing);
    },
  );

  testWidgets('showAuth true reuses auth stream across parent rebuilds', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthGate(
          authRepository: repository,
          showAuth: true,
          child: const Text('Protected app shell A'),
        ),
      ),
    );

    expect(repository.authStateListenCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthGate(
          authRepository: repository,
          showAuth: true,
          child: const Text('Protected app shell B'),
        ),
      ),
    );

    expect(repository.authStateListenCount, 1);

    repository.emitSignedIn();
    await tester.pumpAndSettle();

    expect(find.text('Protected app shell B'), findsOneWidget);
    expect(find.text('Protected app shell A'), findsNothing);
  });

  testWidgets('signed-out repository state shows auth flow', (tester) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthGate(
          authRepository: repository,
          showAuth: true,
          child: const Text('Protected app shell'),
        ),
      ),
    );

    repository.emitSignedOut();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('auth_welcome_runiac_logo')),
      findsOneWidget,
    );
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Protected app shell'), findsNothing);
  });

  testWidgets('auth state callback emits null when user signs out', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);
    final ownerEvents = <String?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthGate(
          authRepository: repository,
          showAuth: true,
          onAuthStateChanged: (user) => ownerEvents.add(user?.uid),
          child: const Text('Protected app shell'),
        ),
      ),
    );

    repository.emitSignedIn();
    await tester.pumpAndSettle();

    repository.emitSignedOut();
    await tester.pumpAndSettle();

    expect(ownerEvents, contains('test-auth-user-1'));
    expect(ownerEvents.last, isNull);
    expect(find.text('Protected app shell'), findsNothing);
  });

  testWidgets('signed-in repository user reaches app shell after restart', (
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

    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.text('Welcome to Runiac'), findsNothing);
    expect(find.text('Step 1 of 16'), findsNothing);
  });

  testWidgets(
    'signed-in user with no profile document starts onboarding instead of '
    'being signed out',
    (tester) async {
      // The state an account created on the Runiac website arrives in: the
      // Firebase Auth identity exists, but nothing has written its profile
      // document because onboarding only ever runs in the app. An abandoned
      // in-app signup lands here too. Signing the account out would send it to
      // a signup screen where its own email is already taken, so the app owes
      // it the setup flow instead.
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

      repository.emitSignedIn();
      await tester.pumpAndSettle();

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
      expect(find.text('Profile setup was not found'), findsNothing);
    },
  );

  testWidgets(
    'stale missing profile probe does not sign out newer signed-in session',
    (tester) async {
      final authRepository = _SwitchableRuniacAuthRepository();
      final profileRepository = _StaleMissingProfileRepository();
      addTearDown(authRepository.dispose);

      await tester.pumpWidget(
        RuniacApp(
          showSplash: false,
          showAuth: true,
          showOnboarding: true,
          enableForegroundGps: false,
          authRepository: authRepository,
          profileRepository: profileRepository,
        ),
      );

      authRepository.emitSignedIn(uid: 'test-auth-user-1');
      await tester.pump();

      expect(profileRepository.loadCalls, 1);
      expect(
        find.byKey(const ValueKey('runiac_splash_screen')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      authRepository.emitSignedIn(uid: 'test-auth-user-2');
      await tester.pump();
      await tester.pump();

      expect(profileRepository.loadCalls, greaterThanOrEqualTo(2));
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth_welcome_runiac_logo')),
        findsNothing,
      );

      profileRepository.completeFirstProbeWithMissingProfile();
      await tester.pump();
      await tester.pump();

      expect(authRepository.signOutCalls, 0);
      expect(authRepository.currentUser?.uid, 'test-auth-user-2');
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth_welcome_runiac_logo')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'login form signs in through repository and opens after auth stream',
    (tester) async {
      final repository = FakeRuniacAuthRepository();
      addTearDown(repository.dispose);
      RuniacAuthCompletion? completion;

      await tester.pumpWidget(
        MaterialApp(
          home: RuniacAuthGate(
            authRepository: repository,
            showAuth: true,
            onAuthenticated: (value) {
              completion = value;
            },
            child: const Text('Protected app shell'),
          ),
        ),
      );

      repository.emitSignedOut();
      await tester.pump();
      await tapVisibleText(tester, 'Log in');
      await enterAuthCredentials(
        tester,
        email: 'runner@runiac.app',
        password: 'password123',
      );
      await tapVisibleText(tester, 'Sign in');

      expect(completion, RuniacAuthCompletion.login);
      await tester.pumpAndSettle();

      expect(repository.signInCalls, 1);
      expect(find.text('Protected app shell'), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
    },
  );

  testWidgets('login waits for signed-in profile probe before app shell', (
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
        profileRepository: const _NeverCompletingProfileRepository(),
      ),
    );

    repository.emitSignedOut();
    await tester.pump();
    await tapVisibleText(tester, 'Log in');
    await enterAuthCredentials(
      tester,
      email: 'runner@runiac.app',
      password: 'password123',
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(repository.signInCalls, 1);
    expect(find.byKey(const ValueKey('runiac_splash_screen')), findsOneWidget);
    expect(find.text('Good to see you'), findsNothing);
    expect(find.text('Welcome back'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('signed-out after signed-in returns to auth flow', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacAuthGate(
          authRepository: repository,
          showAuth: true,
          child: const Text('Protected app shell'),
        ),
      ),
    );

    repository.emitSignedIn();
    await tester.pumpAndSettle();
    expect(find.text('Protected app shell'), findsOneWidget);

    repository.emitSignedOut();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('auth_welcome_runiac_logo')),
      findsOneWidget,
    );
    expect(find.text('Protected app shell'), findsNothing);
  });

  testWidgets('sign out returns to auth flow and allows login again', (
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

    expect(find.byTooltip('Home'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Return to the Runiac welcome screen'), findsOneWidget);

    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(repository.signOutCalls, 0);
    expect(find.text('Sign out?'), findsOneWidget);
    expect(
      find.text('You can sign back in with your email any time.'),
      findsOneWidget,
    );

    final staySignedIn = find.textContaining(RegExp('Cancel|Stay signed in'));
    expect(staySignedIn, findsOneWidget);

    await tester.ensureVisible(staySignedIn);
    await tester.pumpAndSettle();
    await tester.tap(staySignedIn);
    await tester.pumpAndSettle();

    expect(repository.signOutCalls, 0);
    expect(find.text('Sign out?'), findsNothing);
    expect(find.text('Profile'), findsOneWidget);

    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(repository.signOutCalls, 0);
    expect(find.text('Sign out?'), findsOneWidget);

    final confirmSignOut = find.text('Sign out').last;
    await tester.ensureVisible(confirmSignOut);
    await tester.pumpAndSettle();
    await tester.tap(confirmSignOut);
    await tester.pumpAndSettle();

    expect(repository.signOutCalls, 1);
    expect(
      find.byKey(const ValueKey('auth_welcome_runiac_logo')),
      findsOneWidget,
    );
    expect(find.text('Profile'), findsNothing);

    await tapVisibleText(tester, 'Log in');
    await enterAuthCredentials(
      tester,
      email: 'runner@runiac.app',
      password: 'password123',
    );
    await tapVisibleText(tester, 'Sign in');

    expect(repository.signInCalls, 1);
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('sign out prevents double submit while pending', (tester) async {
    final repository = FakeRuniacAuthRepository();
    addTearDown(repository.dispose);
    repository.holdNextSignOut();

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        enableForegroundGps: false,
        authRepository: repository,
      ),
    );

    repository.emitSignedIn();
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    final confirmSignOut = find.text('Sign out').last;
    await tester.ensureVisible(confirmSignOut);
    await tester.pumpAndSettle();
    await tester.tap(confirmSignOut);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('account_sign_out_confirmation')),
        matching: find.text('Signing out...'),
      ),
    );
    await tester.pump();

    expect(repository.signOutCalls, 1);

    repository.completePendingSignOut();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('auth_welcome_runiac_logo')),
      findsOneWidget,
    );
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

class _NeverCompletingProfileRepository implements UserProfileRepository {
  const _NeverCompletingProfileRepository();

  @override
  Future<UserProfileReadModel> loadUserProfile() {
    return Completer<UserProfileReadModel>().future;
  }
}

class _StaleMissingProfileRepository implements UserProfileRepository {
  final Completer<UserProfileReadModel> _firstProbe =
      Completer<UserProfileReadModel>();

  int loadCalls = 0;

  @override
  Future<UserProfileReadModel> loadUserProfile() {
    loadCalls += 1;
    if (loadCalls == 1) {
      return _firstProbe.future;
    }
    return Future<UserProfileReadModel>.value(_profileFor('test-auth-user-2'));
  }

  void completeFirstProbeWithMissingProfile() {
    _firstProbe.completeError(
      const CurrentUserProfileException(
        uid: 'test-auth-user-1',
        reason: CurrentUserProfileFailureReason.missing,
      ),
    );
  }
}

class _SwitchableRuniacAuthRepository implements RuniacAuthRepository {
  final StreamController<RuniacAuthUser?> _controller =
      StreamController<RuniacAuthUser?>.broadcast();

  RuniacAuthUser? _currentUser;
  int signOutCalls = 0;

  @override
  Stream<RuniacAuthUser?> authStateChanges() => _controller.stream;

  @override
  RuniacAuthUser? get currentUser => _currentUser;

  void emitSignedIn({required String uid}) {
    _currentUser = RuniacAuthUser(
      uid: uid,
      email: '$uid@runiac.app',
      emailVerified: true,
    );
    _controller.add(_currentUser);
  }

  void dispose() {
    _controller.close();
  }

  @override
  Future<RuniacAuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendEmailVerification() {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    throw UnimplementedError();
  }

  @override
  Future<RuniacAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<RuniacAuthUser> signInWithGoogle() {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    _currentUser = null;
    _controller.add(null);
  }
}

UserProfileReadModel _profileFor(String uid) {
  return UserProfileReadModel(
    userId: uid,
    displayName: 'Maya Tan',
    avatarInitials: 'MT',
    locationLabel: 'Queenstown, Singapore',
  );
}
