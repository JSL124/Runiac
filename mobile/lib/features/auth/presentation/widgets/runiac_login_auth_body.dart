import 'package:flutter/material.dart';

import '../../domain/runiac_auth_service.dart';
import 'runiac_auth_buttons.dart';
import 'runiac_auth_fields.dart';
import 'runiac_auth_validators.dart';

class RuniacLoginAuthBody extends StatefulWidget {
  const RuniacLoginAuthBody({
    required this.authRepository,
    required this.onAuthenticated,
    required this.onSignup,
    required this.onForgotPassword,
    super.key,
  });

  final RuniacAuthRepository authRepository;
  final VoidCallback onAuthenticated;
  final VoidCallback onSignup;
  final VoidCallback onForgotPassword;

  @override
  State<RuniacLoginAuthBody> createState() => _RuniacLoginAuthBodyState();
}

class _RuniacLoginAuthBodyState extends State<RuniacLoginAuthBody> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  bool _isGoogleSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || _isGoogleSubmitting) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final onAuthenticated = widget.onAuthenticated;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.authRepository.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      onAuthenticated();
    } on RuniacAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.userMessage;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'We could not complete that auth step. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submitGoogle() async {
    if (_isSubmitting || _isGoogleSubmitting) {
      return;
    }

    final onAuthenticated = widget.onAuthenticated;
    setState(() {
      _isGoogleSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.authRepository.signInWithGoogle();
      onAuthenticated();
    } on RuniacAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.userMessage;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'We could not complete Google sign-in. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleSubmitting = false;
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
          const SizedBox(height: 36),
          const RuniacAuthTitle(
            title: 'Welcome back',
            subtitle: 'Let us keep your running habit going.',
          ),
          const SizedBox(height: 26),
          RuniacAuthTextField(
            controller: _emailController,
            label: 'Email',
            hintText: 'you@runiac.app',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            validator: validateRuniacAuthEmail,
          ),
          const SizedBox(height: 16),
          RuniacAuthTextField(
            controller: _passwordController,
            label: 'Password',
            hintText: 'Enter your password',
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            validator: validateRuniacRequiredPassword,
          ),
          const SizedBox(height: 22),
          RuniacAuthButton(
            label: _isSubmitting ? 'Signing in...' : 'Sign in',
            onPressed: _isSubmitting || _isGoogleSubmitting ? null : _submit,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            RuniacAuthFeedback(message: _errorMessage!, isError: true),
          ],
          const SizedBox(height: 18),
          const RuniacAuthDivider(),
          const SizedBox(height: 18),
          RuniacAuthButton(
            label: _isGoogleSubmitting
                ? 'Signing in with Google...'
                : 'Continue with Google',
            onPressed: _isSubmitting || _isGoogleSubmitting
                ? null
                : _submitGoogle,
            variant: RuniacAuthButtonVariant.google,
            icon: const RuniacGoogleGlyph(),
          ),
          const SizedBox(height: 22),
          RuniacAuthTextLink(
            label: 'Forgot password?',
            onPressed: widget.onForgotPassword,
          ),
          const SizedBox(height: 42),
          RuniacInlineAuthAction(
            text: 'Do not have an account?',
            action: 'Sign up',
            onPressed: widget.onSignup,
          ),
        ],
      ),
    );
  }
}
