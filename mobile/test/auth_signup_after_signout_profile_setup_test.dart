import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/app.dart';

import 'support/auth_flow_test_helpers.dart';
import 'support/fake_runiac_auth_repository.dart';

/// Regression coverage for test case 1.3.2: signing up for a new account in
/// the same app process immediately after signing out of another account —
/// without a full app relaunch — must not skip the "Tell us about you"
/// personal-profile step. `_RuniacAppState` tracks `_authCompletion` and
/// `_personalProfileDraft` across the whole app lifetime, not per signed-in
/// uid, so a sign-out that leaves them set lets the very next signup's
/// `_shouldShowPersonalProfile` check read the outgoing account's leftover
/// `signup` completion and non-null draft and read them as "already done".
void main() {
  testWidgets(
    'signing up again right after signing out still asks for a personal '
    'profile instead of skipping straight to character selection',
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

      // First account: sign up and complete the personal-profile step, which
      // is what sets the stale `_personalProfileDraft` behind this defect.
      await tapVisibleText(tester, 'Sign up');
      await enterAuthCredentials(
        tester,
        email: 'first-runner@runiac.app',
        password: 'password123',
      );
      await tapVisibleText(tester, 'Create account');
      await tester.pumpAndSettle();

      expect(find.text('Tell us about you'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('Name'), 'Maya Tan');
      await tester.enterText(find.bySemanticsLabel('Nickname'), 'Maya');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.bySemanticsLabel('Date of birth'));
      await tester.pumpAndSettle();
      await tapVisibleText(tester, 'Use selected date');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('Weight in kilograms'),
        '58.5',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.ensureVisible(find.bySemanticsLabel('Region'));
      await tester.tap(find.bySemanticsLabel('Region'));
      await tester.pumpAndSettle();
      await tapVisibleText(tester, 'Orchard, Singapore');
      await tester.pumpAndSettle();
      await tapVisibleText(tester, 'Continue to onboarding');

      expect(find.text('Choose your running buddy'), findsOneWidget);

      // The first runner signs out of this same app process — no relaunch —
      // before onboarding (and its buddy pick) is ever finished.
      repository.emitSignedOut();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('auth_welcome_runiac_logo')),
        findsOneWidget,
      );

      // A second, distinct account signs up right away.
      await tapVisibleText(tester, 'Sign up');
      await enterAuthCredentials(
        tester,
        email: 'second-runner@runiac.app',
        password: 'password123',
      );
      await tapVisibleText(tester, 'Create account');
      await tester.pumpAndSettle();

      expect(repository.createUserCalls, 2);
      expect(repository.lastCreateUserEmail, 'second-runner@runiac.app');
      expect(
        find.text('Tell us about you'),
        findsOneWidget,
        reason:
            'The new account must be asked for its own personal profile, '
            'not inherit the outgoing account\'s completed draft.',
      );
      expect(
        find.text('Choose your running buddy'),
        findsNothing,
        reason:
            'The buggy state would jump straight past personal-profile '
            'collection to character selection for the new account.',
      );
    },
  );
}
