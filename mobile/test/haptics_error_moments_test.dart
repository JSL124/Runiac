import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/haptics/runiac_haptics.dart';
import 'package:runiac_app/core/haptics/runiac_haptics_scope.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';
import 'package:runiac_app/features/profile/presentation/account_edit_profile_screen.dart';
import 'package:runiac_app/features/profile/presentation/account_profile_screen.dart';

import 'support/fake_runiac_auth_repository.dart';

/// Records every haptic call by method name, so tests can assert exactly
/// which curated haptic fired (or that none fired) without depending on a
/// real platform channel.
class RecordingRuniacHaptics implements RuniacHaptics {
  final List<String> calls = [];
  bool _enabled = true;

  @override
  void selection() => calls.add('selection');

  @override
  void impactLight() => calls.add('impactLight');

  @override
  void impactMedium() => calls.add('impactMedium');

  @override
  void impactHeavy() => calls.add('impactHeavy');

  @override
  void error() => calls.add('error');

  @override
  void setEnabled(bool enabled) => _enabled = enabled;

  // ignore: unused_element
  bool get enabled => _enabled;
}

void main() {
  group('AccountProfileScreen verification email failure', () {
    testWidgets('records an error haptic when resend fails', (tester) async {
      final recorder = RecordingRuniacHaptics();
      final authRepository = FakeRuniacAuthRepository(
        emailVerificationError: const RuniacAuthException(
          code: RuniacAuthErrorCode.tooManyRequests,
          userMessage: 'Too many attempts. Please wait and try again.',
        ),
      );
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn(emailVerified: false);

      await tester.pumpWidget(
        RuniacHapticsScope(
          haptics: recorder,
          child: MaterialApp(
            home: AccountProfileScreen(
              authRepository: authRepository,
              profileRepository: const _StubProfileRepository(),
              profilePersistenceRepository:
                  const _StubProfilePersistenceRepository(),
              generatedPlanPersistenceRepository:
                  const NoopGeneratedPlanPersistenceRepository(),
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Resend email'), findsOneWidget);
      await tester.tap(find.text('Resend email'));
      await tester.pumpAndSettle();

      expect(
        find.text('Too many attempts. Please wait and try again.'),
        findsWidgets,
      );
      expect(recorder.calls, contains('error'));
    });

    testWidgets('records no error haptic when resend succeeds', (
      tester,
    ) async {
      final recorder = RecordingRuniacHaptics();
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn(emailVerified: false);

      await tester.pumpWidget(
        RuniacHapticsScope(
          haptics: recorder,
          child: MaterialApp(
            home: AccountProfileScreen(
              authRepository: authRepository,
              profileRepository: const _StubProfileRepository(),
              profilePersistenceRepository:
                  const _StubProfilePersistenceRepository(),
              generatedPlanPersistenceRepository:
                  const NoopGeneratedPlanPersistenceRepository(),
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Resend email'), findsOneWidget);
      await tester.tap(find.text('Resend email'));
      await tester.pumpAndSettle();

      expect(find.text('Verification email sent.'), findsWidgets);
      expect(recorder.calls, isNot(contains('error')));
    });
  });

  group('AccountEditProfileScreen save failure', () {
    testWidgets(
      'records an error haptic when the nickname availability check fails',
      (tester) async {
        final recorder = RecordingRuniacHaptics();
        final authRepository = FakeRuniacAuthRepository();
        addTearDown(authRepository.dispose);
        authRepository.emitSignedIn();

        await tester.pumpWidget(
          RuniacHapticsScope(
            haptics: recorder,
            child: MaterialApp(
              home: AccountEditProfileScreen(
                authRepository: authRepository,
                persistenceRepository:
                    const _NicknameCheckThrowingPersistenceRepository(),
                generatedPlanPersistenceRepository:
                    const NoopGeneratedPlanPersistenceRepository(),
                profile: _profile(),
                onBack: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Save changes'));
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Nickname check is blocked by Firestore rules. Deploy the updated rules or use the emulator.',
          ),
          findsOneWidget,
        );
        expect(recorder.calls, contains('error'));
      },
    );

    testWidgets('records an error haptic when saving the profile fails', (
      tester,
    ) async {
      final recorder = RecordingRuniacHaptics();
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();

      await tester.pumpWidget(
        RuniacHapticsScope(
          haptics: recorder,
          child: MaterialApp(
            home: AccountEditProfileScreen(
              authRepository: authRepository,
              persistenceRepository: const _SaveThrowingPersistenceRepository(),
              generatedPlanPersistenceRepository:
                  const NoopGeneratedPlanPersistenceRepository(),
              profile: _profile(),
              onBack: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(
        find.text('We could not save your profile. Try again.'),
        findsOneWidget,
      );
      expect(recorder.calls, contains('error'));
    });

    testWidgets('records no error haptic when saving succeeds', (
      tester,
    ) async {
      final recorder = RecordingRuniacHaptics();
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();
      var didPop = false;

      await tester.pumpWidget(
        RuniacHapticsScope(
          haptics: recorder,
          child: MaterialApp(
            home: Navigator(
              onGenerateRoute: (settings) =>
                  MaterialPageRoute<AccountEditProfileResult>(
                    builder: (context) => AccountEditProfileScreen(
                      authRepository: authRepository,
                      persistenceRepository:
                          const _SucceedingPersistenceRepository(),
                      generatedPlanPersistenceRepository:
                          const NoopGeneratedPlanPersistenceRepository(),
                      profile: _profile(),
                      onBack: (_) {
                        didPop = true;
                      },
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(recorder.calls, isNot(contains('error')));
      // onBack() is only reachable via the header back button in this
      // fixture; a successful save instead pops the pushed route directly.
      expect(didPop, isFalse);
    });
  });
}

UserProfileReadModel _profile() {
  return UserProfileReadModel(
    userId: 'test-auth-user-1',
    displayName: 'Maya',
    fullName: 'Maya Tan',
    nickname: 'Maya',
    avatarInitials: 'M',
    dateOfBirthIso: '2000-01-01',
    ageYears: 24,
    weightKg: 58.5,
    locationLabel: 'Queenstown, Singapore',
  );
}

class _StubProfileRepository implements UserProfileRepository {
  const _StubProfileRepository();

  @override
  Future<UserProfileReadModel> loadUserProfile() async => _profile();
}

class _StubProfilePersistenceRepository
    implements UserProfilePersistenceRepository {
  const _StubProfilePersistenceRepository();

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async => true;

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

/// Fails the nickname availability check during save, exercising the
/// `on NicknameAvailabilityCheckException` failure branch in `_save()`.
class _NicknameCheckThrowingPersistenceRepository
    implements UserProfilePersistenceRepository {
  const _NicknameCheckThrowingPersistenceRepository();

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async {
    throw const NicknameAvailabilityCheckException(
      NicknameAvailabilityFailureReason.rulesUnavailable,
    );
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

/// Passes the nickname check but fails the actual profile save with a
/// generic exception, exercising the `catch (_)` failure branch in `_save()`.
class _SaveThrowingPersistenceRepository
    implements UserProfilePersistenceRepository {
  const _SaveThrowingPersistenceRepository();

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async => true;

  @override
  Future<void> saveOnboardingProfile({
    required String uid,
    required UserProfileOnboardingSnapshot profile,
  }) async {}

  @override
  Future<void> savePersonalProfile({
    required String uid,
    required UserProfilePersonalSnapshot profile,
  }) async {
    throw StateError('profile save failed');
  }
}

class _SucceedingPersistenceRepository
    implements UserProfilePersistenceRepository {
  const _SucceedingPersistenceRepository();

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async => true;

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
