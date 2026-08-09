import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/auth/presentation/runiac_auth_flow_screen.dart';

import 'support/auth_flow_test_helpers.dart';
import 'support/fake_runiac_auth_repository.dart';

void main() {
  testWidgets(
    'signup validates email and stronger password before onboarding',
    (tester) async {
      final repository = FakeRuniacAuthRepository();
      addTearDown(repository.dispose);
      var authenticated = false;
      RuniacAuthCompletion? completion;

      await tester.pumpWidget(
        MaterialApp(
          home: RuniacAuthFlowScreen(
            authRepository: repository,
            onAuthenticated: (value) {
              completion = value;
              authenticated = true;
            },
          ),
        ),
      );

      await tapVisibleText(tester, 'Sign up');
      await enterAuthCredentials(
        tester,
        email: 'runner@runiac.app',
        password: 'short',
      );
      await tapVisibleText(tester, 'Create account');

      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(authenticated, isFalse);

      await enterAuthCredentials(
        tester,
        email: 'runner@runiac.app',
        password: 'password123',
      );
      await tapVisibleText(tester, 'Create account');

      expect(authenticated, isTrue);
      expect(completion, RuniacAuthCompletion.signup);
      expect(repository.createUserCalls, 1);
      expect(repository.lastCreateUserEmail, 'runner@runiac.app');
      expect(repository.lastCreateUserPassword, 'password123');
    },
  );

  testWidgets('signup error shows auth repository message', (tester) async {
    final repository = FakeRuniacAuthRepository(
      createUserError: RuniacAuthException.fromFirebaseCode(
        'email-already-in-use',
      ),
    );
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

    await tapVisibleText(tester, 'Sign up');
    await enterAuthCredentials(
      tester,
      email: 'runner@runiac.app',
      password: 'password123',
    );
    await tapVisibleText(tester, 'Create account');

    expect(repository.createUserCalls, 1);
    expect(
      find.text('An account already exists for this email. Try logging in.'),
      findsOneWidget,
    );
    expect(authenticated, isFalse);
  });

  testWidgets('reset sends request and shows neutral success', (tester) async {
    final repository = FakeRuniacAuthRepository();
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
    await tapVisibleText(tester, 'Forgot password?');
    await tapVisibleText(tester, 'Send reset link');

    expect(find.text('Enter your email'), findsOneWidget);
    expect(
      find.text(
        'If an account exists for that email, a reset link will be sent.',
      ),
      findsNothing,
    );
    expect(repository.resetCalls, 0);

    await tester.enterText(
      find.byType(TextFormField).first,
      'runner@runiac.app',
    );
    await tapVisibleText(tester, 'Send reset link');

    expect(repository.resetCalls, 1);
    expect(repository.lastResetEmail, 'runner@runiac.app');
    expect(
      find.text(
        'If an account exists for that email, a reset link will be sent.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reset error shows auth repository message', (tester) async {
    final repository = FakeRuniacAuthRepository(
      resetError: RuniacAuthException.fromFirebaseCode('too-many-requests'),
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
    await tapVisibleText(tester, 'Forgot password?');
    await tester.enterText(
      find.byType(TextFormField).first,
      'runner@runiac.app',
    );
    await tapVisibleText(tester, 'Send reset link');

    expect(repository.resetCalls, 1);
    expect(
      find.text('Too many attempts. Please wait a moment and try again.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'signup auth completion asks for personal profile before onboarding',
    (tester) async {
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

      await tapVisibleText(tester, 'Sign up');
      await enterAuthCredentials(
        tester,
        email: 'runner@runiac.app',
        password: 'password123',
      );
      await tapVisibleText(tester, 'Create account');

      await tester.pumpAndSettle();

      expect(repository.createUserCalls, 1);
      expect(find.text('Tell us about you'), findsOneWidget);
      expect(find.text('runner@runiac.app'), findsOneWidget);
      expect(find.text('Welcome to Runiac'), findsNothing);
      expect(find.text('Step 1 of 16'), findsNothing);
      expect(find.text('Good to see you'), findsNothing);

      await tester.enterText(find.bySemanticsLabel('Name'), 'Maya Tan');
      await tester.enterText(find.bySemanticsLabel('Nickname'), 'Maya');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Nickname is available.'), findsOneWidget);
      expect(
        _textColor(tester, 'Nickname is available.'),
        RuniacColors.successGreen,
      );
      await tester.tap(find.bySemanticsLabel('Date of birth'));
      await tester.pumpAndSettle();
      expect(find.text('Select birthdate'), findsOneWidget);
      await tapVisibleText(tester, 'Use selected date');
      await tester.pumpAndSettle();
      expect(find.text('Age'), findsOneWidget);
      expect(find.text('26'), findsOneWidget);
      await tester.enterText(
        find.bySemanticsLabel('Weight in kilograms'),
        '58.5',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      await tester.ensureVisible(find.bySemanticsLabel('Region'));
      await tester.tap(find.bySemanticsLabel('Region'));
      await tester.pumpAndSettle();
      expect(find.text('Jurong East, Singapore'), findsOneWidget);
      expect(find.text('Orchard, Singapore'), findsOneWidget);
      await tapVisibleText(tester, 'Orchard, Singapore');
      await tester.pumpAndSettle();
      await tapVisibleText(tester, 'Continue to onboarding');

      // Guide-character selection now sits between profile setup and the
      // onboarding question flow.
      expect(find.text('Choose your running buddy'), findsOneWidget);
      await tapVisibleText(tester, 'Bolt');
      await tapVisibleText(tester, "Let's go with Bolt");

      expect(find.text('Welcome to Runiac'), findsOneWidget);
      expect(find.text('Step 1 of 16'), findsOneWidget);
    },
  );

  testWidgets(
    'Google signup completion asks for personal profile before onboarding',
    (tester) async {
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

      await tapVisibleText(tester, 'Sign up');
      await tapVisibleText(tester, 'Continue with Google');

      await tester.pumpAndSettle();

      expect(repository.googleSignInCalls, 1);
      expect(find.text('Tell us about you'), findsOneWidget);
      expect(find.text('runner@runiac.app'), findsOneWidget);
      expect(find.text('Welcome to Runiac'), findsNothing);
      expect(find.text('Step 1 of 16'), findsNothing);
      expect(find.text('Good to see you'), findsNothing);
    },
  );

  testWidgets('signup blocks a duplicate nickname before onboarding', (
    tester,
  ) async {
    final repository = FakeRuniacAuthRepository();
    final persistenceRepository = _DuplicateNicknameProfileRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      RuniacApp(
        showSplash: false,
        showAuth: true,
        showOnboarding: true,
        enableForegroundGps: false,
        authRepository: repository,
        profilePersistenceRepository: persistenceRepository,
      ),
    );
    repository.emitSignedOut();
    await tester.pumpAndSettle();

    await tapVisibleText(tester, 'Sign up');
    await enterAuthCredentials(
      tester,
      email: 'runner@runiac.app',
      password: 'password123',
    );
    await tapVisibleText(tester, 'Create account');
    await tester.pumpAndSettle();

    await tester.enterText(find.bySemanticsLabel('Name'), 'Maya Tan');
    await tester.enterText(find.bySemanticsLabel('Nickname'), 'TakenRunner');
    await tester.pump(const Duration(milliseconds: 500));

    expect(persistenceRepository.checkedNickname, 'TakenRunner');
    expect(find.text('Nickname is already taken.'), findsOneWidget);
    expect(
      _textColor(tester, 'Nickname is already taken.'),
      RuniacColors.errorRed,
    );

    await tester.tap(find.bySemanticsLabel('Date of birth'));
    await tester.pumpAndSettle();
    await tapVisibleText(tester, 'Use selected date');
    await tester.enterText(
      find.bySemanticsLabel('Weight in kilograms'),
      '58.5',
    );
    await tester.ensureVisible(find.bySemanticsLabel('Region'));
    await tester.tap(find.bySemanticsLabel('Region'));
    await tester.pumpAndSettle();
    await tapVisibleText(tester, 'Jurong East, Singapore');
    await tapVisibleText(tester, 'Continue to onboarding');
    await tester.pumpAndSettle();

    expect(find.text('Nickname is already taken.'), findsOneWidget);
    expect(find.text('Welcome to Runiac'), findsNothing);
  });
}

Color? _textColor(WidgetTester tester, String text) {
  return tester.widget<Text>(find.text(text)).style?.color;
}

class _DuplicateNicknameProfileRepository
    implements UserProfilePersistenceRepository {
  String? checkedNickname;

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async {
    checkedNickname = nickname;
    return false;
  }

  @override
  Future<void> saveOnboardingProfile({
    required String uid,
    required UserProfileOnboardingSnapshot profile,
  }) async {}

  @override
  Future<void> savePersonalProfile({
    required String uid,
    required UserProfilePersonalSnapshot profile,
  }) async {}
}
