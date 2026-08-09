import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/profile/presentation/personal_profile_collection_screen.dart';

/// Regression coverage for the `_continue()` `mounted` guard: the nickname
/// availability check awaited inside `_continue()` must not resume into a
/// `setState`, and must not fire the `onComplete` callback, once the screen
/// has already been torn down. This screen sits between signup and
/// onboarding, so a stale `onComplete(draft)` firing after the runner has
/// already navigated away would hand a torn-down draft to whatever replaced
/// this screen.
void main() {
  testWidgets(
    'a nickname availability check that resolves after the screen is '
    'unmounted does not throw and does not call onComplete',
    (tester) async {
      final persistence = _HoldingPersistenceRepository();
      var onCompleteCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: PersonalProfileCollectionScreen(
            uid: 'test-uid-1',
            emailLabel: 'runner@runiac.app',
            persistenceRepository: persistence,
            onComplete: (_) => onCompleteCalls += 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.bySemanticsLabel('Name'), 'Maya Tan');
      await tester.enterText(find.bySemanticsLabel('Nickname'), 'Maya');
      // Let the debounced nickname-availability check (unrelated to the
      // `_continue()` call under test) settle normally.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Nickname is available.'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Date of birth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use selected date'));
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
      await tester.tap(find.text('Jurong East, Singapore'));
      await tester.pumpAndSettle();

      // From here on, `isNicknameAvailable` stays pending until the test
      // completes it explicitly.
      persistence.holdNext = true;
      await tester.ensureVisible(find.text('Continue to onboarding'));
      await tester.tap(find.text('Continue to onboarding'));
      await tester.pump();
      expect(persistence.heldCallCount, 1);

      // Tear the screen down — mirrors the runner navigating away (or the
      // app routing elsewhere) while the check is still in flight.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      persistence.completeHeld(true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        onCompleteCalls,
        0,
        reason:
            'A torn-down profile screen must not fire a stale completion '
            'callback into whatever replaced it.',
      );
    },
  );
}

/// Hand-written stub. By default `isNicknameAvailable` resolves immediately
/// with `true`, so the debounced nickname check completes normally. Once
/// [holdNext] is set, the next call instead returns a controllable future,
/// letting the test pin down exactly when `_continue()`'s await resumes
/// relative to unmounting the screen.
class _HoldingPersistenceRepository implements UserProfilePersistenceRepository {
  bool holdNext = false;
  Completer<bool>? _held;
  int heldCallCount = 0;

  void completeHeld(bool value) {
    final held = _held;
    if (held != null && !held.isCompleted) {
      held.complete(value);
    }
  }

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) {
    if (holdNext) {
      holdNext = false;
      final held = Completer<bool>();
      _held = held;
      heldCallCount += 1;
      return held.future;
    }
    return Future<bool>.value(true);
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
