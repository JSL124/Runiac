import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:runiac_app/core/firebase/runiac_firebase_bootstrap.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/run/data/run_repository_factory.dart';

import 'support/auth_emulator_flow_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('email password auth uses Firebase emulator app path', (
    tester,
  ) async {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final email = 'runiac-auth-$timestamp@example.test';
    final nickname = 'runiac$timestamp';
    const fullName = 'Runiac Auth Tester';
    const weightKg = '65';
    const password = 'RuniacPass123!';
    const wrongPassword = 'RuniacWrong123!';
    final region = firstSingaporeRegionOption;

    final bootstrap = await RuniacFirebaseBootstrap.initialize(
      config: RuniacFirebaseRuntimeConfig(
        useFirebaseEmulator: true,
        emulatorHost: firebaseEmulatorHost,
      ),
      enableAnonymousEmulatorSignIn: false,
    );
    final rawAuthDiagnostics = await probeRawFirebaseAuth(
      timestamp: timestamp,
      password: password,
    );
    final authRepository = DiagnosticAuthRepository(bootstrap.authRepository);
    addTearDown(authRepository.signOut);

    await authRepository.signOut();
    await pumpRuniac(
      tester,
      bootstrap,
      authRepository: authRepository,
      useRealProfilePersistence: true,
    );

    await signUp(tester, email: email, password: password);
    await completePersonalProfileCollection(
      tester,
      fullName: fullName,
      nickname: nickname,
      weightKg: weightKg,
      region: region,
    );
    await chooseFreeRunningBuddy(tester);
    await waitForText(
      tester,
      'Welcome to Runiac',
      reason: 'a chosen running buddy should open onboarding',
      diagnostics: '${authRepository.diagnostics}\n$rawAuthDiagnostics',
    );
    expect(find.text('Welcome to Runiac'), findsOneWidget);
    expect(find.text('Step 1 of 16'), findsOneWidget);
    // `Menu` is the Home stage map's menu trigger, and the cheapest proof that
    // the shell is *not* mounted. The old marker here was 'Good to see you',
    // which comes from `HomeHeader` — a widget nothing in the app builds any
    // more, so both the positive and negative form of that assertion were
    // silently vacuous.
    expect(find.text('Menu'), findsNothing);

    // The app only writes `userProfiles/{uid}` when onboarding *completes*
    // (`app.dart:_completeOnboarding`), and driving all sixteen steps is out of
    // scope for the auth suite — `friends_realtime_emulator_test.dart` skips
    // them for the same reason. Persisting the profile here through the app's
    // own production repository is what makes the login leg below a real test
    // of `RuniacProfileSetupGate`: without a profile document the gate
    // classifies the account as recoverable-missing and signs it straight back
    // out, so login could never reach Home.
    final uid = authRepository.currentUser?.uid;
    expect(uid, isNotNull, reason: 'signup should leave a signed-in user');
    await bootstrap.profilePersistenceRepository.savePersonalProfile(
      uid: uid!,
      profile: PersonalProfileDraft(
        fullName: fullName,
        nickname: nickname,
        dateOfBirthIso: defaultPickedBirthDateIso,
        weightKg: num.parse(weightKg),
        locationLabel: region,
      ).toPersonalSnapshot(),
    );

    await authRepository.signOut();
    await waitForText(
      tester,
      'Sign up',
      reason: 'repository sign-out should return to the auth welcome screen',
      diagnostics: authRepository.diagnostics,
    );
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);

    await logIn(tester, email: email, password: password);
    await waitForText(
      tester,
      'Menu',
      reason: 'login should authenticate and skip signup-only onboarding',
      diagnostics: authRepository.diagnostics,
    );
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
    // Each gate a *signup* has to clear, named individually: login must skip
    // all three rather than merely land somewhere that is not the login screen.
    expect(find.text('Tell us about you'), findsNothing);
    expect(find.text('Choose your running buddy'), findsNothing);
    expect(find.text('Welcome to Runiac'), findsNothing);

    await signOutFromAccount(tester);
    await waitForText(
      tester,
      'Sign up',
      reason: 'account sign-out should return to the auth welcome screen',
      diagnostics: authRepository.diagnostics,
    );
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Menu'), findsNothing);

    await requestPasswordReset(tester, email: email);
    await waitForText(
      tester,
      'If an account exists for that email, a reset link will be sent.',
      reason: 'password reset should surface the success confirmation',
      diagnostics: authRepository.diagnostics,
    );
    expect(
      find.text(
        'If an account exists for that email, a reset link will be sent.',
      ),
      findsOneWidget,
    );

    await tapVisibleText(tester, 'Back to log in');
    await attemptWrongPassword(
      tester,
      email: email,
      wrongPassword: wrongPassword,
    );
    await waitForText(
      tester,
      'That email and password do not match.',
      reason: 'wrong-password login should surface mapped auth error text',
      diagnostics: authRepository.diagnostics,
    );
    expect(find.text('That email and password do not match.'), findsOneWidget);
    expect(find.text('Menu'), findsNothing);
  });
}
