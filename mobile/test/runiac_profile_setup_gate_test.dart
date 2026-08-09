import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/auth/presentation/runiac_profile_setup_gate.dart';
import 'package:runiac_app/features/profile/data/firestore_user_profile_repository.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';

import 'support/fake_runiac_auth_repository.dart';

/// A profile read the test completes by hand, so the probe can be held in
/// flight while the gate is torn out of the tree underneath it.
class _DeferredUserProfileRepository implements UserProfileRepository {
  final completer = Completer<UserProfileReadModel>();
  int loadCalls = 0;

  @override
  Future<UserProfileReadModel> loadUserProfile() {
    loadCalls += 1;
    return completer.future;
  }
}

const _missingProfile = CurrentUserProfileException(
  uid: 'signup-user',
  reason: CurrentUserProfileFailureReason.missing,
);

const _invalidProfile = CurrentUserProfileException(
  uid: 'signup-user',
  reason: CurrentUserProfileFailureReason.invalid,
);

void main() {
  testWidgets(
    'a probe that resolves after the gate leaves the tree does not sign the '
    'account out',
    (tester) async {
      // Reproduces the signup race. RuniacAuthGate builds the post-auth flow
      // the moment its auth stream emits a user, which can land a frame before
      // the auth screen reports that this was a *signup*, so this gate mounts
      // briefly against an account whose profile document does not exist yet.
      final auth = FakeRuniacAuthRepository();
      addTearDown(auth.dispose);
      final profiles = _DeferredUserProfileRepository();
      var recoveryCalls = 0;
      auth.emitSignedIn(uid: 'signup-user');

      await tester.pumpWidget(
        MaterialApp(
          home: RuniacProfileSetupGate(
            authRepository: auth,
            profileRepository: profiles,
            currentUser: auth.currentUser!,
            onRecoverableProfileMissing: () => recoveryCalls += 1,
            child: const Text('shell'),
          ),
        ),
      );
      expect(profiles.loadCalls, 1);

      // RuniacApp learns it was a signup and swaps in profile collection, which
      // disposes this gate while its read is still in flight.
      await tester.pumpWidget(
        const MaterialApp(home: Text('Tell us about you')),
      );

      profiles.completer.completeError(_missingProfile);
      await tester.pump();
      await tester.pump();

      // Acting on the stale result here would sign the brand-new account out
      // and drop it back on the auth screen claiming it has no setup.
      expect(recoveryCalls, 0);
      expect(auth.signOutCalls, 0);
      expect(find.text('Tell us about you'), findsOneWidget);
    },
  );

  testWidgets(
    'a signed-in account with no profile document is sent to onboarding, not '
    'signed out',
    (tester) async {
      // An account created on the Runiac website reaches the app in exactly
      // this state: signed in, with no profile document, because onboarding
      // (which writes that document) only runs in the app.
      final auth = FakeRuniacAuthRepository();
      addTearDown(auth.dispose);
      final profiles = _DeferredUserProfileRepository();
      var incompleteCalls = 0;
      var recoveryCalls = 0;
      auth.emitSignedIn(uid: 'signup-user');

      await tester.pumpWidget(
        MaterialApp(
          home: RuniacProfileSetupGate(
            authRepository: auth,
            profileRepository: profiles,
            currentUser: auth.currentUser!,
            onProfileSetupIncomplete: () => incompleteCalls += 1,
            onRecoverableProfileMissing: () => recoveryCalls += 1,
            child: const Text('shell'),
          ),
        ),
      );
      expect(profiles.loadCalls, 1);

      profiles.completer.completeError(_missingProfile);
      await tester.pump();
      await tester.pump();

      // The stale-probe guard must not swallow the real signal: this gate is
      // still mounted, so it is still the authority on this account.
      expect(incompleteCalls, 1);
      expect(recoveryCalls, 0);
      expect(auth.signOutCalls, 0);
      expect(find.text('shell'), findsNothing);
    },
  );

  testWidgets('an unreadable profile document still signs the account out', (
    tester,
  ) async {
    // Distinct from a missing document: something *is* stored for this account
    // and cannot be read as a profile, so onboarding is not the answer.
    final auth = FakeRuniacAuthRepository();
    addTearDown(auth.dispose);
    final profiles = _DeferredUserProfileRepository();
    var incompleteCalls = 0;
    var recoveryCalls = 0;
    auth.emitSignedIn(uid: 'signup-user');

    await tester.pumpWidget(
      MaterialApp(
        home: RuniacProfileSetupGate(
          authRepository: auth,
          profileRepository: profiles,
          currentUser: auth.currentUser!,
          onProfileSetupIncomplete: () => incompleteCalls += 1,
          onRecoverableProfileMissing: () => recoveryCalls += 1,
          child: const Text('shell'),
        ),
      ),
    );
    expect(profiles.loadCalls, 1);

    profiles.completer.completeError(_invalidProfile);
    await tester.pump();
    await tester.pump();

    expect(incompleteCalls, 0);
    expect(recoveryCalls, 1);
    expect(auth.signOutCalls, 1);
    expect(find.text('shell'), findsNothing);
  });
}
