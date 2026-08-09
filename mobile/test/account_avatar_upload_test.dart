import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/widgets/runiac_avatar_photo.dart';
import 'package:runiac_app/features/plan/domain/repositories/generated_plan_persistence_repository.dart';
import 'package:runiac_app/features/profile/data/avatar/firebase_avatar_upload_gateway.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_repository.dart';
import 'package:runiac_app/features/profile/presentation/account_edit_profile_screen.dart';
import 'package:runiac_app/features/profile/presentation/account_profile_screen.dart';

import 'support/fake_runiac_auth_repository.dart';

const _uploadedAvatarUrl = 'https://firebasestorage.googleapis.com/fake-avatar.png';

void main() {
  group('Edit Profile avatar upload', () {
    testWidgets(
      'choosing a photo, confirming the visibility gate, and a successful '
      'upload sets the new photo and leaves _save() untouched',
      (tester) async {
        final authRepository = FakeRuniacAuthRepository();
        addTearDown(authRepository.dispose);
        authRepository.emitSignedIn();
        final persistence = _RecordingPersistenceRepository();
        final picker = _FakeAvatarPhotoPicker(bytesToReturn: _fakePngBytes());
        final gateway = _RecordingAvatarUploadGateway(
          uploadResult: _uploadedAvatarUrl,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AccountEditProfileScreen(
              authRepository: authRepository,
              persistenceRepository: persistence,
              generatedPlanPersistenceRepository:
                  const NoopGeneratedPlanPersistenceRepository(),
              profile: _profile(),
              onBack: (_) {},
              avatarPhotoPicker: picker,
              avatarUploadGateway: gateway,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _chooseAndConfirmPhoto(tester);

        expect(gateway.uploadCallCount, 1);
        expect(picker.callCount, 1);
        expect(
          tester
              .widget<RuniacAvatarPhotoDisc>(find.byType(RuniacAvatarPhotoDisc))
              .photoUrl,
          _uploadedAvatarUrl,
        );
        // The photo flow never touched Save.
        expect(persistence.saveCallCount, 0);
        expect(find.text('Save changes'), findsOneWidget);
      },
    );

    testWidgets(
      'cancelling the visibility confirmation performs no upload at all',
      (tester) async {
        final authRepository = FakeRuniacAuthRepository();
        addTearDown(authRepository.dispose);
        authRepository.emitSignedIn();
        final picker = _FakeAvatarPhotoPicker(bytesToReturn: _fakePngBytes());
        final gateway = _RecordingAvatarUploadGateway(
          uploadResult: _uploadedAvatarUrl,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AccountEditProfileScreen(
              authRepository: authRepository,
              persistenceRepository: _RecordingPersistenceRepository(),
              generatedPlanPersistenceRepository:
                  const NoopGeneratedPlanPersistenceRepository(),
              profile: _profile(),
              onBack: (_) {},
              avatarPhotoPicker: picker,
              avatarUploadGateway: gateway,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('account-edit-avatar-tap')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose photo'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('avatar-visibility-cancel')));
        await tester.pumpAndSettle();

        expect(gateway.uploadCallCount, 0);
        expect(picker.callCount, 0);
        expect(
          tester
              .widget<RuniacAvatarPhotoDisc>(find.byType(RuniacAvatarPhotoDisc))
              .photoUrl,
          isNull,
        );
      },
    );

    testWidgets(
      'an upload failure renders an inline English error and does not crash',
      (tester) async {
        final authRepository = FakeRuniacAuthRepository();
        addTearDown(authRepository.dispose);
        authRepository.emitSignedIn();
        final picker = _FakeAvatarPhotoPicker(bytesToReturn: _fakePngBytes());
        final gateway = _RecordingAvatarUploadGateway(
          uploadError: const AvatarUploadException(
            AvatarUploadFailureReason.unknown,
            'We could not update your profile photo. Try again.',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AccountEditProfileScreen(
              authRepository: authRepository,
              persistenceRepository: _RecordingPersistenceRepository(),
              generatedPlanPersistenceRepository:
                  const NoopGeneratedPlanPersistenceRepository(),
              profile: _profile(),
              onBack: (_) {},
              avatarPhotoPicker: picker,
              avatarUploadGateway: gateway,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _chooseAndConfirmPhoto(tester);

        expect(
          find.text('We could not update your profile photo. Try again.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the cooldown reason renders its own distinct message', (
      tester,
    ) async {
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();
      final picker = _FakeAvatarPhotoPicker(bytesToReturn: _fakePngBytes());
      final gateway = _RecordingAvatarUploadGateway(
        uploadError: const AvatarUploadException(
          AvatarUploadFailureReason.cooldown,
          'You can only change your profile photo once a minute. Try again shortly.',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AccountEditProfileScreen(
            authRepository: authRepository,
            persistenceRepository: _RecordingPersistenceRepository(),
            generatedPlanPersistenceRepository:
                const NoopGeneratedPlanPersistenceRepository(),
            profile: _profile(),
            onBack: (_) {},
            avatarPhotoPicker: picker,
            avatarUploadGateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _chooseAndConfirmPhoto(tester);

      expect(
        find.text(
          'You can only change your profile photo once a minute. Try again shortly.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('We could not update your profile photo. Try again.'),
        findsNothing,
      );
    });

    testWidgets('Remove photo calls clear() and falls back to initials', (
      tester,
    ) async {
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();
      final picker = _FakeAvatarPhotoPicker(bytesToReturn: _fakePngBytes());
      final gateway = _RecordingAvatarUploadGateway(
        uploadResult: _uploadedAvatarUrl,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AccountEditProfileScreen(
            authRepository: authRepository,
            persistenceRepository: _RecordingPersistenceRepository(),
            generatedPlanPersistenceRepository:
                const NoopGeneratedPlanPersistenceRepository(),
            profile: _profile(),
            onBack: (_) {},
            avatarPhotoPicker: picker,
            avatarUploadGateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First, set a photo so "Remove photo" is enabled.
      await _chooseAndConfirmPhoto(tester);
      expect(
        tester
            .widget<RuniacAvatarPhotoDisc>(find.byType(RuniacAvatarPhotoDisc))
            .photoUrl,
        _uploadedAvatarUrl,
      );

      await tester.tap(find.byKey(const ValueKey('account-edit-avatar-tap')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();

      expect(gateway.clearCallCount, 1);
      expect(
        tester
            .widget<RuniacAvatarPhotoDisc>(find.byType(RuniacAvatarPhotoDisc))
            .photoUrl,
        isNull,
      );
      // The disc falls back to initials whenever photoUrl is null/unresolvable.
      expect(find.text(_profile().avatarInitials), findsOneWidget);
    });

    testWidgets('Remove photo is disabled when there is no photo', (
      tester,
    ) async {
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();
      final gateway = _RecordingAvatarUploadGateway(
        uploadResult: _uploadedAvatarUrl,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AccountEditProfileScreen(
            authRepository: authRepository,
            persistenceRepository: _RecordingPersistenceRepository(),
            generatedPlanPersistenceRepository:
                const NoopGeneratedPlanPersistenceRepository(),
            profile: _profile(),
            onBack: (_) {},
            avatarPhotoPicker: _FakeAvatarPhotoPicker(),
            avatarUploadGateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('account-edit-avatar-tap')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();

      expect(gateway.clearCallCount, 0);
    });
  });

  group('Account screen refresh contract after Edit Profile', () {
    testWidgets(
      'Back after a photo-only change refreshes the Account screen',
      (tester) async {
        final authRepository = FakeRuniacAuthRepository();
        addTearDown(authRepository.dispose);
        authRepository.emitSignedIn();
        final profileRepository = _CountingProfileRepository();
        final picker = _FakeAvatarPhotoPicker(bytesToReturn: _fakePngBytes());
        final gateway = _RecordingAvatarUploadGateway(
          uploadResult: _uploadedAvatarUrl,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AccountProfileScreen(
              authRepository: authRepository,
              profileRepository: profileRepository,
              profilePersistenceRepository: _RecordingPersistenceRepository(),
              generatedPlanPersistenceRepository:
                  const NoopGeneratedPlanPersistenceRepository(),
              onBack: () {},
              avatarPhotoPicker: picker,
              avatarUploadGateway: gateway,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(profileRepository.loadCallCount, 1);

        await tester.ensureVisible(find.text('Edit profile'));
        await tester.tap(find.text('Edit profile'));
        await tester.pumpAndSettle();

        await _chooseAndConfirmPhoto(tester);
        expect(gateway.uploadCallCount, 1);

        await tester.tap(find.byTooltip('Back to Account'));
        await tester.pumpAndSettle();

        expect(profileRepository.loadCallCount, 2);
      },
    );

    testWidgets('Back with no change does NOT refetch', (tester) async {
      final authRepository = FakeRuniacAuthRepository();
      addTearDown(authRepository.dispose);
      authRepository.emitSignedIn();
      final profileRepository = _CountingProfileRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfileScreen(
            authRepository: authRepository,
            profileRepository: profileRepository,
            profilePersistenceRepository: _RecordingPersistenceRepository(),
            generatedPlanPersistenceRepository:
                const NoopGeneratedPlanPersistenceRepository(),
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(profileRepository.loadCallCount, 1);

      await tester.ensureVisible(find.text('Edit profile'));
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back to Account'));
      await tester.pumpAndSettle();

      expect(profileRepository.loadCallCount, 1);
    });
  });
}

/// Taps the avatar, "Choose photo", and confirms the visibility gate —
/// the shared happy-path prelude used by every test that needs an upload
/// (successful or failing) to actually run.
Future<void> _chooseAndConfirmPhoto(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('account-edit-avatar-tap')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose photo'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('avatar-visibility-confirm')));
  await tester.pumpAndSettle();
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

Uint8List _fakePngBytes() => Uint8List.fromList(const <int>[1, 2, 3, 4]);

/// Hand-written stub picker — no mocking framework in this repo. Records how
/// many times it was invoked so tests can prove a cancelled confirmation
/// never reaches the picker at all.
class _FakeAvatarPhotoPicker implements AvatarPhotoPicker {
  _FakeAvatarPhotoPicker({this.bytesToReturn});

  final Uint8List? bytesToReturn;
  int callCount = 0;

  @override
  Future<Uint8List?> pickAndEncodeAvatarPhoto() async {
    callCount += 1;
    return bytesToReturn;
  }
}

/// Hand-written stub gateway recording call counts and simulating every
/// failure reason [AvatarUploadException] can carry.
class _RecordingAvatarUploadGateway implements AvatarUploadGateway {
  _RecordingAvatarUploadGateway({this.uploadResult, this.uploadError});

  final String? uploadResult;
  final AvatarUploadException? uploadError;

  int uploadCallCount = 0;
  int clearCallCount = 0;

  @override
  Future<String> upload(Uint8List pngBytes) async {
    uploadCallCount += 1;
    final error = uploadError;
    if (error != null) {
      throw error;
    }
    return uploadResult!;
  }

  @override
  Future<void> clear() async {
    clearCallCount += 1;
  }
}

class _RecordingPersistenceRepository
    implements UserProfilePersistenceRepository {
  int saveCallCount = 0;

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
    saveCallCount += 1;
  }
}

class _CountingProfileRepository implements UserProfileRepository {
  int loadCallCount = 0;

  @override
  Future<UserProfileReadModel> loadUserProfile() async {
    loadCallCount += 1;
    return _profile();
  }
}
