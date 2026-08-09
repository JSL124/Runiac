import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../domain/runiac_auth_service.dart';
import 'runiac_auth_buttons.dart';
import 'runiac_auth_fields.dart';
import 'runiac_auth_validators.dart';

class RuniacRecoveryAuthBody extends StatefulWidget {
  const RuniacRecoveryAuthBody({
    required this.authRepository,
    required this.onLogin,
    super.key,
  });

  final RuniacAuthRepository authRepository;
  final VoidCallback onLogin;

  @override
  State<RuniacRecoveryAuthBody> createState() => _RuniacRecoveryAuthBodyState();
}

class _RuniacRecoveryAuthBodyState extends State<RuniacRecoveryAuthBody> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  String? _feedbackMessage;
  bool _feedbackIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _feedbackMessage = null;
      _feedbackIsError = false;
    });

    try {
      await widget.authRepository.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _feedbackMessage =
            'If an account exists for that email, a reset link will be sent.';
        _feedbackIsError = false;
      });
    } on RuniacAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _feedbackMessage = error.userMessage;
        _feedbackIsError = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _feedbackMessage =
            'We could not complete that auth step. Please try again.';
        _feedbackIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 42),
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: RuniacColors.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                color: RuniacColors.primaryBlue,
                size: 38,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Reset your password',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: RuniacColors.primaryBlue,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'No worries. Enter your email and we will send a reset link.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: RuniacColors.primaryBlue,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 30),
          RuniacAuthTextField(
            controller: _emailController,
            label: 'Email',
            hintText: 'you@runiac.app',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            validator: validateRuniacAuthEmail,
          ),
          const SizedBox(height: 22),
          RuniacAuthButton(
            label: _isSubmitting ? 'Sending...' : 'Send reset link',
            onPressed: _isSubmitting ? null : _submit,
          ),
          if (_feedbackMessage != null) ...[
            const SizedBox(height: 12),
            RuniacAuthFeedback(
              message: _feedbackMessage!,
              isError: _feedbackIsError,
            ),
          ],
          const SizedBox(height: 70),
          RuniacInlineAuthAction(
            text: 'Remembered it?',
            action: 'Back to log in',
            onPressed: widget.onLogin,
          ),
        ],
      ),
    );
  }
}
