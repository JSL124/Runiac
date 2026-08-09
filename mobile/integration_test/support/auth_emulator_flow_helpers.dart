import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/core/firebase/runiac_firebase_bootstrap.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/profile/domain/singapore_region_options.dart';
import 'package:runiac_app/features/run/data/run_repository_factory.dart';

String get firebaseEmulatorHost {
  const configuredHost = String.fromEnvironment(
    'RUNIAC_FIREBASE_EMULATOR_HOST',
  );
  if (configuredHost.isNotEmpty) {
    return configuredHost;
  }
  return Platform.isAndroid
      ? '10.0.2.2'
      : RuniacFirebaseRuntimeConfig.defaultEmulatorHost;
}

Future<String> probeRawFirebaseAuth({
  required int timestamp,
  required String password,
}) async {
  try {
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
          email: 'runiac-raw-auth-$timestamp@example.test',
          password: password,
        );
    await FirebaseAuth.instance.signOut();
    final uidLength = credential.user?.uid.length ?? 0;
    return 'Raw FirebaseAuth probe: success uid=<redacted-uid> '
        'uidLength=$uidLength';
  } on FirebaseAuthException catch (error) {
    return 'Raw FirebaseAuth probe: FirebaseAuthException('
        'code=${error.code}, message=${error.message}, plugin=${error.plugin})';
  } catch (error) {
    return 'Raw FirebaseAuth probe: ${error.runtimeType}: $error';
  }
}

Future<void> pumpRuniac(
  WidgetTester tester,
  RuniacFirebaseBootstrapResult bootstrap, {
  required RuniacAuthRepository authRepository,
  bool showAuth = true,
  bool showOnboarding = true,
  bool useRealProfilePersistence = false,
}) async {
  await tester.pumpWidget(
    RuniacApp(
      authRepository: authRepository,
      runRepository: bootstrap.runRepository,
      friendsRepository: bootstrap.friendsRepository,
      profileRepository: bootstrap.profileRepository,
      // Defaults to the Noop persistence repository so suites that never reach
      // the personal-profile screen keep their previous behaviour. The auth
      // suite opts in, because the screen's nickname check is a real
      // `checkNicknameAvailability` callable and the Noop always answers
      // "available", which would make that gate untested.
      profilePersistenceRepository: useRealProfilePersistence
          ? bootstrap.profilePersistenceRepository
          : const NoopUserProfilePersistenceRepository(),
      showSplash: false,
      showAuth: showAuth,
      showOnboarding: showOnboarding,
      enableForegroundGps: false,
    ),
  );
  await tester.pumpAndSettle();
}

class DiagnosticAuthRepository implements RuniacAuthRepository {
  DiagnosticAuthRepository(this._delegate);

  final RuniacAuthRepository _delegate;
  Object? _lastError;
  StackTrace? _lastStackTrace;
  String? _lastOperation;

  String get diagnostics {
    final error = _lastError;
    if (error == null) {
      return 'Last auth operation: $_lastOperation; last auth error: none';
    }

    return 'Last auth operation: $_lastOperation; '
        'last auth error type: ${error.runtimeType}; '
        'last auth error: $error; '
        'last auth stack: $_lastStackTrace';
  }

  @override
  Stream<RuniacAuthUser?> authStateChanges() {
    return _delegate.authStateChanges();
  }

  @override
  RuniacAuthUser? get currentUser => _delegate.currentUser;

  @override
  Future<RuniacAuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _record(
      'createUserWithEmailAndPassword',
      () => _delegate.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    return _record(
      'sendPasswordResetEmail',
      () => _delegate.sendPasswordResetEmail(email: email),
    );
  }

  @override
  Future<void> sendEmailVerification() {
    return _record('sendEmailVerification', _delegate.sendEmailVerification);
  }

  @override
  Future<RuniacAuthUser> signInWithGoogle() {
    return _record('signInWithGoogle', _delegate.signInWithGoogle);
  }

  @override
  Future<RuniacAuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _record(
      'signInWithEmailAndPassword',
      () => _delegate.signInWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  @override
  Future<void> signOut() {
    return _record('signOut', _delegate.signOut);
  }

  Future<T> _record<T>(String operation, Future<T> Function() action) async {
    _lastOperation = operation;
    _lastError = null;
    _lastStackTrace = null;
    try {
      return await action();
    } catch (error, stackTrace) {
      _lastOperation = operation;
      _lastError = error;
      _lastStackTrace = stackTrace;
      rethrow;
    }
  }
}

Future<void> signUp(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await tapVisibleText(tester, 'Sign up');
  await enterAuthCredentials(tester, email: email, password: password);
  await tapVisibleText(tester, 'Create account');
}

/// The birthdate `ProfileDateOfBirthField` pre-selects when it opens with no
/// stored value, i.e. what "Use selected date" returns if the wheel is not
/// scrolled. Kept here so the seeded profile and the on-screen assertion agree.
final String defaultPickedBirthDateIso = birthDateIso(DateTime(2000));

/// A fresh signup no longer lands on onboarding. `app.dart`'s
/// `_shouldShowPersonalProfile` routes it through
/// `PersonalProfileCollectionScreen` first, and `_shouldShowOnboarding` only
/// turns true once that screen hands back a draft, so the auth suite has to
/// clear it the way a real user does.
Future<void> completePersonalProfileCollection(
  WidgetTester tester, {
  required String fullName,
  required String nickname,
  required String weightKg,
  required String region,
}) async {
  await waitForText(
    tester,
    'Tell us about you',
    reason: 'signup should open the personal profile screen',
  );

  await tester.enterText(_profileFieldByLabel('Name'), fullName);
  await tester.pump();

  await tester.enterText(_profileFieldByLabel('Nickname'), nickname);
  await tester.pump();
  await waitForText(
    tester,
    'Nickname is available.',
    reason:
        'the checkNicknameAvailability callable should clear a fresh nickname',
  );

  await tapVisibleText(tester, 'Choose birthdate');
  await waitForText(
    tester,
    'Select birthdate',
    reason: 'the birthdate field should open the picker sheet',
  );
  await tapVisibleText(tester, 'Use selected date');

  await tester.enterText(_profileFieldByLabel('Weight in kilograms'), weightKg);
  await tester.pump();

  await tapVisibleText(tester, 'Choose a Singapore region');
  await waitForText(
    tester,
    'Choose region',
    reason: 'the region field should open the picker sheet',
  );
  await tapVisibleText(tester, region);

  await tapVisibleText(tester, 'Continue to onboarding');
}

/// The first Singapore planning area the region picker offers.
String get firstSingaporeRegionOption => SingaporeRegionOptions.values.first;

/// Onboarding sits behind one more gate: `_buildOnboardingAndShell` wraps it in
/// `RuniacCharacterSelectionGate`, so a fresh signup picks a buddy before it
/// ever sees step 1. Bolt is free for a Basic account, which keeps this suite
/// off the premium-lock path that `character_selection_test.dart` owns.
Future<void> chooseFreeRunningBuddy(WidgetTester tester) async {
  await waitForText(
    tester,
    'Choose your running buddy',
    reason: 'a completed personal profile should open character selection',
  );
  await tapVisibleText(tester, 'Bolt');
  await tapVisibleText(tester, "Let's go with Bolt");
}

Finder _profileFieldByLabel(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(TextFormField),
  );
}

Future<void> logIn(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await tapVisibleText(tester, 'Log in');
  await enterAuthCredentials(tester, email: email, password: password);
  await tapVisibleText(tester, 'Sign in');
}

Future<void> requestPasswordReset(
  WidgetTester tester, {
  required String email,
}) async {
  await tapVisibleText(tester, 'Log in');
  await tapVisibleText(tester, 'Forgot password?');
  await tester.enterText(find.byType(TextFormField).first, email);
  await tapVisibleText(tester, 'Send reset link');
}

Future<void> attemptWrongPassword(
  WidgetTester tester, {
  required String email,
  required String wrongPassword,
}) async {
  await enterAuthCredentials(tester, email: email, password: wrongPassword);
  await tapVisibleText(tester, 'Sign in');
}

Future<void> signOutFromAccount(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Profile'));
  await tester.pumpAndSettle();
  expect(find.text('Profile'), findsOneWidget);

  await tester.ensureVisible(find.text('Sign out'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sign out'));
  await tester.pumpAndSettle();

  // Account sign-out is confirmed, not immediate — the first tap only opens the
  // sheet, as `test/auth_gate_test.dart` asserts. Tapping once and waiting for
  // the welcome screen would just time out behind the open sheet.
  expect(find.text('Sign out?'), findsOneWidget);
  final confirmSignOut = find.text('Sign out').last;
  await tester.ensureVisible(confirmSignOut);
  await tester.pumpAndSettle();
  await tester.tap(confirmSignOut);
  await tester.pump();
}

Future<void> enterAuthCredentials(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.first, email);
  await tester.enterText(fields.at(1), password);
}

Future<void> tapVisibleText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> waitForText(
  WidgetTester tester,
  String text, {
  required String reason,
  String? diagnostics,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final finder = find.text(text);
  const pumpStep = Duration(milliseconds: 100);
  final attempts = timeout.inMilliseconds <= 0
      ? 1
      : (timeout.inMilliseconds / pumpStep.inMilliseconds).ceil();

  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(pumpStep);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  await tester.pumpAndSettle(
    pumpStep,
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
  if (finder.evaluate().isNotEmpty) {
    return;
  }

  fail(
    'Timed out after ${timeout.inSeconds}s waiting for "$text": $reason.\n'
    '${diagnostics ?? 'No auth diagnostics provided'}\n'
    'Visible Text widgets:\n${_visibleTextDiagnostics(tester)}',
  );
}

/// Mirrors [waitForText] but asserts a live disappearance instead of an
/// appearance (e.g. a friend request row that should vanish from a
/// snapshot-backed list once the sender's request is accepted/declined).
Future<void> waitForTextGone(
  WidgetTester tester,
  String text, {
  required String reason,
  String? diagnostics,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final finder = find.text(text);
  const pumpStep = Duration(milliseconds: 100);
  final attempts = timeout.inMilliseconds <= 0
      ? 1
      : (timeout.inMilliseconds / pumpStep.inMilliseconds).ceil();

  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(pumpStep);
    if (finder.evaluate().isEmpty) {
      return;
    }
  }

  if (finder.evaluate().isEmpty) {
    return;
  }

  fail(
    'Timed out after ${timeout.inSeconds}s waiting for "$text" to disappear: '
    '$reason.\n'
    '${diagnostics ?? 'No auth diagnostics provided'}\n'
    'Visible Text widgets:\n${_visibleTextDiagnostics(tester)}',
  );
}

String _visibleTextDiagnostics(WidgetTester tester) {
  final visibleTexts =
      tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .map((text) => text.trim())
          .where((text) => text.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  if (visibleTexts.isEmpty) {
    return '  (no non-empty Text widgets found)';
  }

  return visibleTexts.map((text) => '  - $text').join('\n');
}
