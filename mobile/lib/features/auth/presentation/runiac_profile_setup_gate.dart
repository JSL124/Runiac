import 'package:flutter/material.dart';

import '../../profile/data/firestore_user_profile_repository.dart';
import '../../profile/domain/models/user_profile_read_model.dart';
import '../../profile/domain/repositories/user_profile_repository.dart';
import '../../splash/presentation/splash_three_soft_dots_screen.dart';
import '../domain/runiac_auth_service.dart';

class RuniacProfileSetupGate extends StatefulWidget {
  const RuniacProfileSetupGate({
    required this.authRepository,
    required this.profileRepository,
    required this.currentUser,
    required this.child,
    this.onLoadedProfile,
    this.onProfileSetupIncomplete,
    this.onRecoverableProfileMissing,
    super.key,
  });

  final RuniacAuthRepository authRepository;
  final UserProfileRepository profileRepository;
  final RuniacAuthUser currentUser;
  final Widget child;
  final ValueChanged<UserProfileReadModel>? onLoadedProfile;

  /// The signed-in account exists in Firebase Auth but has no profile document
  /// yet, so it has never finished onboarding. The host is expected to send it
  /// into the onboarding flow rather than out of the app.
  final VoidCallback? onProfileSetupIncomplete;

  /// The signed-in account has a profile document that cannot be read as a
  /// profile. The gate signs the account out and the host offers recovery.
  final VoidCallback? onRecoverableProfileMissing;

  @override
  State<RuniacProfileSetupGate> createState() => _RuniacProfileSetupGateState();
}

class _RuniacProfileSetupGateState extends State<RuniacProfileSetupGate> {
  Future<bool>? _profileSetupProbeFuture;
  String? _profileSetupProbeUid;

  @override
  void didUpdateWidget(covariant RuniacProfileSetupGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authRepository != widget.authRepository ||
        oldWidget.profileRepository != widget.profileRepository ||
        oldWidget.currentUser.uid != widget.currentUser.uid) {
      _profileSetupProbeUid = null;
      _profileSetupProbeFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _profileSetupProbeFor(widget.currentUser.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _ProfileSetupProbeLoadingScreen();
        }

        if (snapshot.hasError) {
          return _ProfileSetupProbeErrorScreen(
            message: _isRecoverableProfileSetupError(snapshot.error)
                ? 'We could not load your profile setup. Please sign in again.'
                : 'We could not check your profile setup. Please try again.',
          );
        }

        if (snapshot.data == false) {
          return const _ProfileSetupProbeLoadingScreen();
        }

        return widget.child;
      },
    );
  }

  Future<bool> _profileSetupProbeFor(String uid) {
    if (_profileSetupProbeUid != uid || _profileSetupProbeFuture == null) {
      _profileSetupProbeUid = uid;
      _profileSetupProbeFuture = _validateSignedInProfileSetup(uid);
    }
    return _profileSetupProbeFuture!;
  }

  Future<bool> _validateSignedInProfileSetup(String probedUid) async {
    final authRepository = widget.authRepository;
    final profileRepository = widget.profileRepository;
    try {
      final profile = await profileRepository.loadUserProfile();
      if (!mounted) {
        return true;
      }
      widget.onLoadedProfile?.call(profile);
      return true;
    } catch (error) {
      if (!_isRecoverableProfileSetupError(error)) {
        rethrow;
      }
      // A signup races this probe. RuniacAuthGate builds the post-auth flow the
      // moment its auth stream emits a user, which can be a frame before the
      // auth screen reports the completion that tells RuniacApp this is a
      // *signup* — so for that one frame `_shouldProbeSignedInProfileSetup`
      // holds and this gate mounts against an account whose profile document
      // does not exist yet, because signup writes it only when onboarding
      // completes.
      //
      // The read then fails with `missing` long after the app has moved on to
      // profile collection and disposed this gate. Acting on that stale result
      // signs the brand-new account out and drops it back on the auth screen
      // claiming no setup exists for it. `mounted` is the whole guard: a gate
      // that is no longer in the tree is no longer the authority on whether
      // this account needs recovery.
      //
      // A genuine signed-in account with no profile keeps this gate mounted for
      // the whole probe, so its sign-out path is unaffected.
      if (!mounted) {
        return true;
      }
      if (authRepository.currentUser?.uid != probedUid) {
        return true;
      }

      if (_isMissingProfileSetup(error)) {
        // The account exists in Firebase Auth but owns no profile document, so
        // onboarding has never completed for it. That is the normal state of an
        // account created on the Runiac website, and of an app signup that was
        // killed before onboarding wrote its profile.
        //
        // Signing such an account out is a dead end: the recovery prompt sends
        // it to signup, where the same email is already taken. Sending it into
        // onboarding instead finishes exactly the setup it is missing.
        widget.onProfileSetupIncomplete?.call();
        return false;
      }

      widget.onRecoverableProfileMissing?.call();
      await authRepository.signOut();
      return false;
    }
  }

  bool _isRecoverableProfileSetupError(Object? error) {
    return error is CurrentUserProfileException &&
        (error.reason == CurrentUserProfileFailureReason.missing ||
            error.reason == CurrentUserProfileFailureReason.invalid);
  }

  bool _isMissingProfileSetup(Object? error) {
    return error is CurrentUserProfileException &&
        error.reason == CurrentUserProfileFailureReason.missing;
  }
}

class _ProfileSetupProbeErrorScreen extends StatelessWidget {
  const _ProfileSetupProbeErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _ProfileSetupProbeLoadingScreen extends StatelessWidget {
  const _ProfileSetupProbeLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const SplashThreeSoftDotsScreen();
  }
}
