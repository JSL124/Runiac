import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../domain/repositories/user_profile_persistence_repository.dart';
import 'widgets/profile_form_controls.dart';

/// Collects the profile details Runiac needs after sign-up — nickname, date of
/// birth, region.
///
/// The nickname is checked for availability as the user types, debounced, and
/// re-checked on save: another account can claim it in between, so the
/// client-side check is a courtesy and the save is the authority.
/// [_NicknameStatusText] shows all three outcomes, including "could not check".
///
/// Email is shown read-only — it comes from the auth account and is not
/// editable here.
class PersonalProfileCollectionScreen extends StatefulWidget {
  const PersonalProfileCollectionScreen({
    required this.uid,
    required this.emailLabel,
    required this.persistenceRepository,
    required this.onComplete,
    super.key,
  });

  final String uid;
  final String emailLabel;
  final UserProfilePersistenceRepository persistenceRepository;
  final ValueChanged<PersonalProfileDraft> onComplete;

  @override
  State<PersonalProfileCollectionScreen> createState() =>
      _PersonalProfileCollectionScreenState();
}

class _PersonalProfileCollectionScreenState
    extends State<PersonalProfileCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _weightController = TextEditingController();
  String _dateOfBirthIso = '';
  String _region = '';
  bool _checkingNickname = false;
  bool? _nicknameAvailable;
  String? _nicknameStatusMessage;
  int _nicknameCheckGeneration = 0;
  Timer? _nicknameCheckTimer;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _weightController.dispose();
    _nicknameCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _continue() async {
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
    final draft = PersonalProfileDraft.tryCreate(
      fullName: _nameController.text,
      nickname: _nicknameController.text,
      weightKg: _weightController.text,
      dateOfBirthIso: _dateOfBirthIso,
      locationLabel: _region,
    );
    if (draft == null) {
      setState(() {
        _error = 'Choose your birthdate, weight, and Singapore region.';
      });
      return;
    }
    setState(() {
      _checkingNickname = true;
      _error = null;
    });
    try {
      final available = await widget.persistenceRepository.isNicknameAvailable(
        uid: widget.uid,
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
      widget.onComplete(draft);
    } on NicknameAvailabilityCheckException catch (error) {
      final message = _nicknameCheckErrorMessage(error);
      setState(() {
        _error = message;
      });
    } catch (_) {
      setState(() {
        _error = 'We could not check that nickname. Try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingNickname = false;
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
            .isNicknameAvailable(uid: widget.uid, nickname: nickname);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Tell us about you',
                      style: TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'These details shape your beginner running plan.',
                      style: TextStyle(
                        color: RuniacColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _ReadOnlyEmail(value: widget.emailLabel),
                    const SizedBox(height: 12),
                    _ProfileField(
                      label: 'Name',
                      controller: _nameController,
                      validator: PersonalProfileDraft.validateFullName,
                    ),
                    const SizedBox(height: 12),
                    _ProfileField(
                      label: 'Nickname',
                      controller: _nicknameController,
                      validator: PersonalProfileDraft.validateNickname,
                      onChanged: _scheduleNicknameCheck,
                    ),
                    if (_nicknameStatusMessage != null) ...[
                      const SizedBox(height: 8),
                      _NicknameStatusText(
                        message: _nicknameStatusMessage!,
                        available: _nicknameAvailable,
                      ),
                    ],
                    const SizedBox(height: 12),
                    ProfileDateOfBirthField(
                      value: _dateOfBirthIso,
                      onChanged: (value) {
                        setState(() {
                          _dateOfBirthIso = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ProfileAgeReadOnlyField(dateOfBirthIso: _dateOfBirthIso),
                    const SizedBox(height: 12),
                    _ProfileField(
                      label: 'Weight in kilograms',
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      onEditingComplete: () => FocusScope.of(context).unfocus(),
                      suffixIcon: IconButton(
                        tooltip: 'Hide keyboard',
                        onPressed: () => FocusScope.of(context).unfocus(),
                        icon: const Icon(Icons.keyboard_hide),
                      ),
                      validator: PersonalProfileDraft.validateWeight,
                    ),
                    const SizedBox(height: 12),
                    SingaporeRegionPickerField(
                      value: _region,
                      onChanged: (value) {
                        setState(() {
                          _region = value;
                        });
                      },
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
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed:
                            _checkingNickname || _nicknameAvailable == false
                            ? null
                            : _continue,
                        style: RuniacButtonStyles.primary(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _checkingNickname
                              ? 'Checking nickname...'
                              : 'Continue to onboarding',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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

class _ReadOnlyEmail extends StatelessWidget {
  const _ReadOnlyEmail({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Email'),
      child: Text(value),
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
