import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/haptics/runiac_haptics_scope.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_avatar_photo.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../../../core/widgets/runiac_confirm_sheet.dart';
import '../../auth/domain/runiac_auth_service.dart';
import '../../onboarding/domain/models/local_onboarding_draft.dart';
import '../../onboarding/presentation/onboarding_flow_screen.dart';
import '../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import '../../plan/domain/repositories/generated_plan_persistence_repository.dart';
import '../../plan/domain/services/beginner_adaptive_plan_generator.dart';
import '../../plan/presentation/current_session_generated_plan.dart';
import '../data/avatar/avatar_image_encoder.dart';
import '../data/avatar/firebase_avatar_upload_gateway.dart';
import '../domain/models/user_profile_read_model.dart';
import '../domain/repositories/user_profile_persistence_repository.dart';
import 'widgets/avatar_action_sheet.dart';
import 'widgets/profile_form_controls.dart';

/// Result popped by [AccountEditProfileScreen], replacing a plain `bool` so
/// the Account screen can tell apart three distinct outcomes: nothing
/// changed, a photo-only change made via the header Back button, and an
/// explicit Save. See [profileChanged]/[showSuccessOverlay] for why a bool
/// alone could not express this.
class AccountEditProfileResult {
  const AccountEditProfileResult({
    required this.profileChanged,
    required this.showSuccessOverlay,
  });

  /// Nothing changed (Back with no edits). The Account screen must not
  /// refetch its profile or show any confirmation.
  static const unchanged = AccountEditProfileResult(
    profileChanged: false,
    showSuccessOverlay: false,
  );

  /// An explicit Save completed. The Account screen refetches its profile
  /// and shows the "Profile updated." overlay, exactly as before this result
  /// type existed.
  static const saved = AccountEditProfileResult(
    profileChanged: true,
    showSuccessOverlay: true,
  );

  /// Back was pressed after a photo-only change (no explicit Save). The
  /// Account screen must still refetch its profile — otherwise it renders
  /// the stale pre-photo avatar — but does NOT show the Save-flow success
  /// overlay: the runner never tapped Save, so a "Profile updated."
  /// confirmation would misattribute an action they did not take.
  static const photoOnly = AccountEditProfileResult(
    profileChanged: true,
    showSuccessOverlay: false,
  );

  /// Whether the Account screen should refetch `loadUserProfile()`.
  final bool profileChanged;

  /// Whether the Account screen should play the "Profile updated." overlay.
  final bool showSuccessOverlay;
}

/// Pick-and-encode seam for the avatar flow. Kept as its own interface (not
/// a bare function) so widget tests can hand-write an `implements` stub that
/// returns fixed bytes, or null for "picker dismissed with no photo chosen",
/// with no real `image_picker` platform channel and no mocking framework.
abstract interface class AvatarPhotoPicker {
  /// Returns already-encoded, upload-ready avatar PNG bytes, or null if the
  /// caller dismissed the photo library without choosing a photo.
  Future<Uint8List?> pickAndEncodeAvatarPhoto();
}

/// Production [AvatarPhotoPicker]. `maxWidth`/`maxHeight`/`imageQuality` are
/// load-bearing, not an optimisation: iOS gallery photos are frequently
/// HEIC, `ui.instantiateImageCodec` (used by [encodeAvatarPng]) cannot
/// decode HEIC, and passing these resize parameters forces the iOS
/// `image_picker` plugin to re-encode the asset (JPEG) via `UIImage` before
/// Dart ever sees the bytes. `image_picker` has no crop UI of its own — the
/// centre-crop to a square happens inside [encodeAvatarPng].
class ImagePickerAvatarPhotoPicker implements AvatarPhotoPicker {
  ImagePickerAvatarPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pickAndEncodeAvatarPhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (file == null) {
      return null;
    }
    final rawBytes = await file.readAsBytes();
    return encodeAvatarPng(rawBytes);
  }
}

class AccountEditProfileScreen extends StatefulWidget {
  const AccountEditProfileScreen({
    required this.authRepository,
    required this.persistenceRepository,
    required this.generatedPlanPersistenceRepository,
    required this.profile,
    required this.onBack,
    this.avatarUploadGateway,
    this.avatarPhotoPicker,
    super.key,
  });

  final RuniacAuthRepository authRepository;
  final UserProfilePersistenceRepository persistenceRepository;
  final GeneratedPlanPersistenceRepository generatedPlanPersistenceRepository;
  final UserProfileReadModel profile;

  /// Called with the outcome the header Back button should pop with — see
  /// [AccountEditProfileResult] for why this is no longer a plain
  /// `VoidCallback`.
  final ValueChanged<AccountEditProfileResult> onBack;

  /// Defaults to [FirebaseAvatarUploadGateway] in production; tests inject a
  /// hand-written stub.
  final AvatarUploadGateway? avatarUploadGateway;

  /// Defaults to [ImagePickerAvatarPhotoPicker] in production; tests inject
  /// a hand-written stub.
  final AvatarPhotoPicker? avatarPhotoPicker;

  @override
  State<AccountEditProfileScreen> createState() =>
      _AccountEditProfileScreenState();
}

class _AccountEditProfileScreenState extends State<AccountEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _weightController;
  late String _dateOfBirthIso;
  late String _region;
  bool _saving = false;
  bool _checkingNickname = false;
  bool? _nicknameAvailable = true;
  String? _nicknameStatusMessage;
  int _nicknameCheckGeneration = 0;
  Timer? _nicknameCheckTimer;
  String? _error;

  // Avatar flow state. Deliberately separate from `_saving`/`_error`: the
  // photo flow is independent of `_save()` and must neither block, nor be
  // blocked by, the nickname check or the Save button.
  bool _uploadingAvatar = false;
  String? _avatarError;
  bool _avatarChanged = false;

  /// The runner's current avatar photo URL: seeded from
  /// `widget.profile.avatarUrl` on first build, then replaced by whatever a
  /// photo change (upload or remove) produces during THIS visit.
  /// `RuniacAvatarPhotoDisc` falls back to initials whenever this is null or
  /// fails the sanitiser, which is exactly the right rendering for "no photo".
  String? _avatarPhotoUrl;

  late final AvatarUploadGateway _avatarUploadGateway =
      widget.avatarUploadGateway ?? FirebaseAvatarUploadGateway();
  late final AvatarPhotoPicker _avatarPhotoPicker =
      widget.avatarPhotoPicker ?? ImagePickerAvatarPhotoPicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.profile.fullName.isEmpty
          ? widget.profile.displayName
          : widget.profile.fullName,
    );
    _nicknameController = TextEditingController(
      text: widget.profile.nickname.isEmpty
          ? widget.profile.displayName
          : widget.profile.nickname,
    );
    _weightController = TextEditingController(
      text: widget.profile.weightKg?.toString() ?? '',
    );
    _dateOfBirthIso = widget.profile.dateOfBirthIso;
    _region = widget.profile.locationLabel;
    _avatarPhotoUrl = widget.profile.avatarUrl.isEmpty
        ? null
        : widget.profile.avatarUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _weightController.dispose();
    _nicknameCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _checkingNickname) {
      setState(() {
        _error = 'Wait for the nickname check to finish.';
      });
      return;
    }
    if (_nicknameAvailable == false) {
      setState(() {
        _error = 'Choose an available nickname.';
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final user = widget.authRepository.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Sign in again before saving your profile.';
      });
      return;
    }
    final draft = PersonalProfileDraft.tryCreate(
      fullName: _nameController.text,
      nickname: _nicknameController.text,
      dateOfBirthIso: _dateOfBirthIso,
      weightKg: _weightController.text,
      locationLabel: _region,
    );
    if (draft == null) {
      setState(() {
        _error = 'Choose your birthdate, weight, and Singapore region.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final available = await widget.persistenceRepository.isNicknameAvailable(
        uid: user.uid,
        nickname: draft.nickname,
      );
      if (!mounted) {
        return;
      }
      if (!available) {
        setState(() {
          _nicknameAvailable = false;
          _nicknameStatusMessage = 'Nickname is already taken.';
          _error = 'Nickname is already taken.';
        });
        return;
      }
      setState(() {
        _nicknameAvailable = true;
        _nicknameStatusMessage = 'Nickname is available.';
      });
      await widget.persistenceRepository.savePersonalProfile(
        uid: user.uid,
        profile: draft.toPersonalSnapshot(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(AccountEditProfileResult.saved);
    } on NicknameUnavailableException {
      if (!mounted) {
        return;
      }
      setState(() {
        _nicknameAvailable = false;
        _nicknameStatusMessage = 'Nickname is already taken.';
        _error = 'Nickname is already taken.';
      });
    } on NicknameAvailabilityCheckException catch (error) {
      if (!mounted) {
        return;
      }
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() {
        _error = _nicknameCheckErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() {
        _error = 'We could not save your profile. Try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _scheduleNicknameCheck(String value) {
    _nicknameCheckTimer?.cancel();
    final nickname = value.trim();
    final generation = ++_nicknameCheckGeneration;
    if (PersonalProfileDraft.validateNickname(nickname) != null) {
      setState(() {
        _checkingNickname = false;
        _nicknameAvailable = null;
        _nicknameStatusMessage = null;
      });
      return;
    }
    final user = widget.authRepository.currentUser;
    if (user == null) {
      setState(() {
        _checkingNickname = false;
        _nicknameAvailable = null;
        _nicknameStatusMessage = null;
      });
      return;
    }
    setState(() {
      _checkingNickname = true;
      _nicknameAvailable = null;
      _nicknameStatusMessage = 'Checking nickname...';
      if (_error == 'Nickname is already taken.' ||
          _error == 'Choose an available nickname.' ||
          _error ==
              'Nickname check is blocked by Firestore rules. Deploy the updated rules or use the emulator.' ||
          _error == 'We could not check that nickname. Try again.') {
        _error = null;
      }
    });
    _nicknameCheckTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final available = await widget.persistenceRepository
            .isNicknameAvailable(uid: user.uid, nickname: nickname);
        if (!mounted || generation != _nicknameCheckGeneration) {
          return;
        }
        setState(() {
          _checkingNickname = false;
          _nicknameAvailable = available;
          _nicknameStatusMessage = available
              ? 'Nickname is available.'
              : 'Nickname is already taken.';
        });
      } on NicknameAvailabilityCheckException catch (error) {
        if (!mounted || generation != _nicknameCheckGeneration) {
          return;
        }
        setState(() {
          _checkingNickname = false;
          _nicknameAvailable = null;
          _nicknameStatusMessage = _nicknameCheckErrorMessage(error);
        });
      } catch (_) {
        if (!mounted || generation != _nicknameCheckGeneration) {
          return;
        }
        setState(() {
          _checkingNickname = false;
          _nicknameAvailable = null;
          _nicknameStatusMessage =
              'We could not check that nickname. Try again.';
        });
      }
    });
  }

  Future<void> _retakeOnboarding() async {
    if (_checkingNickname) {
      setState(() {
        _error = 'Wait for the nickname check to finish.';
      });
      return;
    }
    if (_nicknameAvailable == false) {
      setState(() {
        _error = 'Choose an available nickname.';
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final personalProfile = PersonalProfileDraft.tryCreate(
      fullName: _nameController.text,
      nickname: _nicknameController.text,
      dateOfBirthIso: _dateOfBirthIso,
      weightKg: _weightController.text,
      locationLabel: _region,
    );
    if (personalProfile == null) {
      setState(() {
        _error = 'Choose your birthdate, weight, and Singapore region.';
      });
      return;
    }
    final confirmed = await showRuniacConfirmSheet(
      context,
      title: 'Reset your plan?',
      body:
          'Starting a new onboarding plan will reset your consistency streak. '
          'Your run history will not be deleted.',
      confirmLabel: 'Reset streak & continue',
      icon: Icons.restart_alt_rounded,
    );
    if (!mounted || !confirmed) {
      return;
    }
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _RetakeOnboardingScreen(
          authRepository: widget.authRepository,
          persistenceRepository: widget.persistenceRepository,
          generatedPlanPersistenceRepository:
              widget.generatedPlanPersistenceRepository,
          personalProfile: personalProfile,
        ),
      ),
    );
    if (!mounted || updated != true) {
      return;
    }
    Navigator.of(context).pop(AccountEditProfileResult.saved);
  }

  Future<void> _openAvatarActionSheet() async {
    if (_uploadingAvatar) {
      return;
    }
    final action = await showAvatarActionSheet(
      context,
      hasPhoto: _avatarPhotoUrl != null,
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case AvatarSheetAction.choosePhoto:
        await _pickAndUploadAvatar();
      case AvatarSheetAction.removePhoto:
        await _removeAvatar();
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    // The visibility gate is a real consent step: cancelling it must leave
    // this method returning here, before the picker or the upload gateway
    // are ever touched.
    final confirmed = await showAvatarVisibilityConfirmation(context);
    if (!mounted || !confirmed) {
      return;
    }
    final Uint8List? encodedBytes;
    try {
      encodedBytes = await _avatarPhotoPicker.pickAndEncodeAvatarPhoto();
    } catch (_) {
      if (!mounted) {
        return;
      }
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() {
        _avatarError = 'We could not open your photo library. Try again.';
      });
      return;
    }
    if (encodedBytes == null) {
      // The caller dismissed the picker without choosing a photo.
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadingAvatar = true;
      _avatarError = null;
    });
    try {
      final avatarUrl = await _avatarUploadGateway.upload(encodedBytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarPhotoUrl = avatarUrl;
        _avatarChanged = true;
      });
    } on AvatarUploadException catch (error) {
      if (!mounted) {
        return;
      }
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() {
        _avatarError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() {
        _avatarError = 'We could not update your profile photo. Try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _removeAvatar() async {
    setState(() {
      _uploadingAvatar = true;
      _avatarError = null;
    });
    try {
      await _avatarUploadGateway.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _avatarPhotoUrl = null;
        _avatarChanged = true;
      });
    } on AvatarUploadException catch (error) {
      if (!mounted) {
        return;
      }
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() {
        _avatarError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() {
        _avatarError = 'We could not remove your profile photo. Try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email =
        widget.authRepository.currentUser?.email ?? 'Email unavailable';

    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Edit profile',
              tooltip: 'Back to Account',
              onBack: () => widget.onBack(
                _avatarChanged
                    ? AccountEditProfileResult.photoOnly
                    : AccountEditProfileResult.unchanged,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AvatarSection(
                        initials: widget.profile.avatarInitials,
                        photoUrl: _avatarPhotoUrl,
                        uploading: _uploadingAvatar,
                        onTap: _openAvatarActionSheet,
                      ),
                      if (_avatarError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _avatarError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: RuniacColors.errorRed,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _Section(
                        title: 'Personal details',
                        children: [
                          _ReadOnlyValue(label: 'Email', value: email),
                          _ProfileField(
                            label: 'Name',
                            controller: _nameController,
                            validator: PersonalProfileDraft.validateFullName,
                          ),
                          _ProfileField(
                            label: 'Nickname',
                            controller: _nicknameController,
                            validator: PersonalProfileDraft.validateNickname,
                            onChanged: _scheduleNicknameCheck,
                          ),
                          if (_nicknameStatusMessage != null)
                            _NicknameStatusText(
                              message: _nicknameStatusMessage!,
                              available: _nicknameAvailable,
                            ),
                          ProfileDateOfBirthField(
                            value: _dateOfBirthIso,
                            onChanged: (value) {
                              setState(() {
                                _dateOfBirthIso = value;
                              });
                            },
                          ),
                          ProfileAgeReadOnlyField(
                            dateOfBirthIso: _dateOfBirthIso,
                          ),
                          _ProfileField(
                            label: 'Weight in kilograms',
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.done,
                            onEditingComplete: () =>
                                FocusScope.of(context).unfocus(),
                            suffixIcon: IconButton(
                              tooltip: 'Hide keyboard',
                              onPressed: () => FocusScope.of(context).unfocus(),
                              icon: const Icon(Icons.keyboard_hide),
                            ),
                            validator: PersonalProfileDraft.validateWeight,
                          ),
                          SingaporeRegionPickerField(
                            value: _region,
                            onChanged: (value) {
                              setState(() {
                                _region = value;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _Section(
                        title: 'Your training profile',
                        children: [
                          for (final item in widget.profile.setupItems)
                            _ReadOnlyValue(
                              label: item.title,
                              value: item.value,
                            ),
                          if (widget.profile.setupNote.isNotEmpty)
                            _SetupNote(note: widget.profile.setupNote),
                          SizedBox(
                            height: 50,
                            child: OutlinedButton(
                              onPressed: _retakeOnboarding,
                              style: RuniacButtonStyles.secondary(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text('Retake onboarding'),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: RuniacColors.accentOrange,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed:
                              _saving ||
                                  _checkingNickname ||
                                  _nicknameAvailable == false
                              ? null
                              : _save,
                          style: RuniacButtonStyles.primary(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(_saving ? 'Saving...' : 'Save changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _nicknameCheckErrorMessage(NicknameAvailabilityCheckException error) {
  return switch (error.reason) {
    NicknameAvailabilityFailureReason.rulesUnavailable =>
      'Nickname check is blocked by Firestore rules. Deploy the updated rules or use the emulator.',
    NicknameAvailabilityFailureReason.unavailable =>
      'We could not check that nickname. Try again.',
  };
}

class _RetakeOnboardingScreen extends StatefulWidget {
  const _RetakeOnboardingScreen({
    required this.authRepository,
    required this.persistenceRepository,
    required this.generatedPlanPersistenceRepository,
    required this.personalProfile,
  });

  final RuniacAuthRepository authRepository;
  final UserProfilePersistenceRepository persistenceRepository;
  final GeneratedPlanPersistenceRepository generatedPlanPersistenceRepository;
  final PersonalProfileDraft personalProfile;

  @override
  State<_RetakeOnboardingScreen> createState() =>
      _RetakeOnboardingScreenState();
}

class _RetakeOnboardingScreenState extends State<_RetakeOnboardingScreen> {
  String? _error;

  Future<bool> _completeRetake(LocalOnboardingDraft draft) async {
    final user = widget.authRepository.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Sign in again before saving your onboarding result.';
      });
      return false;
    }
    final plan = const BeginnerAdaptivePlanGenerator()
        .generate(draft)
        .withStartsOnDate(generatedPlanDateLabel(DateTime.now()));
    try {
      await widget.persistenceRepository.saveOnboardingProfile(
        uid: user.uid,
        profile: UserProfileOnboardingSnapshot(
          displayName: widget.personalProfile.displayName,
          fullName: widget.personalProfile.fullName,
          nickname: widget.personalProfile.nickname,
          avatarInitials: widget.personalProfile.avatarInitials,
          dateOfBirthIso: widget.personalProfile.dateOfBirthIso,
          ageYears: widget.personalProfile.ageYears,
          weightKg: widget.personalProfile.weightKg,
          locationLabel: widget.personalProfile.locationLabel,
          fitnessLevel: draft.experience.value,
          goals: <String>[draft.goal.value],
          availability: <String, Object>{
            'weeklySessions': draft.availability.value,
            'preferredDays': draft.preferredDays
                .map((day) => day.value)
                .toList(growable: false),
            'preferredTime': draft.preferredTime.value,
            'sessionLengthMinutes': draft.sessionLength.value,
          },
          planCautiousness: draft.planStyle.value,
          healthSafetyReadiness: <String, Object>{
            'comfort': draft.healthComfort.value,
            'activitySymptoms': draft.activitySymptoms
                .map((symptom) => symptom.value)
                .toList(growable: false),
            'recentRunningConsistency': draft.recentRunningConsistency.value,
            'currentWeeklyRunFrequency': draft.currentWeeklyRunFrequency.value,
            'continuousRunCapacity': draft.continuousRunCapacity.value,
            'runningPlace': draft.runningPlace.value,
            'motivationStyle': draft.motivationStyle.value,
          },
        ),
      );
      try {
        await widget.generatedPlanPersistenceRepository.saveGeneratedPlan(
          uid: user.uid,
          plan: plan,
          resetCreatedAt: true,
        );
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'runiac account',
            context: ErrorDescription('saving regenerated onboarding plan'),
          ),
        );
        if (mounted) {
          setState(() {
            _error = 'We could not save your onboarding result. Try again.';
          });
        }
        return false;
      }
      if (!mounted) {
        return true;
      }
      final store = CurrentSessionGeneratedPlanScope.maybeOf(context);
      if (store != null && !store.setActivePlan(plan)) {
        store.clear();
      }
      Navigator.of(context).pop(true);
      return true;
    } catch (_) {
      setState(() {
        _error = 'We could not save your onboarding result. Try again.';
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        OnboardingFlowScreen(onComplete: _completeRetake),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                tooltip: 'Cancel onboarding retake',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
        if (_error != null)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Material(
                color: RuniacColors.accentOrange,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: RuniacColors.white),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tappable circular avatar at the top of Edit Profile: renders [photoUrl]
/// (via [RuniacAvatarPhotoDisc], falling back to [initials]) with a small
/// camera badge, and a spinner overlay while [uploading]. Tapping opens the
/// avatar action sheet unless an upload/remove is already in flight.
class _AvatarSection extends StatelessWidget {
  const _AvatarSection({
    required this.initials,
    required this.photoUrl,
    required this.uploading,
    required this.onTap,
  });

  final String initials;
  final String? photoUrl;
  final bool uploading;
  final VoidCallback onTap;

  static const _diameter = 88.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        key: const ValueKey('account-edit-avatar-tap'),
        onTap: uploading ? null : onTap,
        child: SizedBox(
          width: _diameter,
          height: _diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: _diameter,
                height: _diameter,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RuniacColors.sectionSurfaceStrong,
                  shape: BoxShape.circle,
                  border: Border.all(color: RuniacColors.border),
                ),
                child: RuniacAvatarPhotoDisc(
                  photoUrl: photoUrl,
                  fallback: Text(
                    initials,
                    style: const TextStyle(
                      color: RuniacColors.primaryBlue,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (uploading)
                const SizedBox.square(
                  dimension: _diameter,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: RuniacColors.primaryBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: RuniacColors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: RuniacColors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final child in children) ...[
              child,
              if (child != children.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyValue extends StatelessWidget {
  const _ReadOnlyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Text(value.isEmpty ? 'Not set' : value),
    );
  }
}

/// Inset variant of the profile card's setup note. The profile screen renders
/// its own footer-shaped version, so only the wording is shared.
class _SetupNote extends StatelessWidget {
  const _SetupNote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: RuniacColors.innerTileSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RuniacColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            color: RuniacColors.primaryBlue,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note,
              softWrap: true,
              style: const TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NicknameStatusText extends StatelessWidget {
  const _NicknameStatusText({required this.message, required this.available});

  final String message;
  final bool? available;

  @override
  Widget build(BuildContext context) {
    final color = switch (available) {
      true => RuniacColors.successGreen,
      false => RuniacColors.errorRed,
      null => RuniacColors.textSecondary,
    };
    return Text(
      message,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.controller,
    required this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onEditingComplete,
    this.onChanged,
    this.suffixIcon,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String) validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onEditingComplete: onEditingComplete,
      onChanged: onChanged,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(labelText: label, suffixIcon: suffixIcon),
      validator: (value) => validator(value ?? ''),
    );
  }
}
