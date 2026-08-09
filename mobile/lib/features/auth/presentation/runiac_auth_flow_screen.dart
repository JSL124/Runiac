import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../data/non_production_auth_repository.dart';
import '../domain/runiac_auth_service.dart';
import 'widgets/runiac_auth_frame.dart';
import 'widgets/runiac_login_auth_body.dart';
import 'widgets/runiac_recovery_auth_body.dart';
import 'widgets/runiac_signup_auth_body.dart';
import 'widgets/runiac_welcome_auth_body.dart';

enum _AuthStep { welcome, login, signup, forgotPassword }

enum RuniacAuthCompletion { login, signup }

class RuniacAuthRecoveryPrompt {
  const RuniacAuthRecoveryPrompt.signup({required this.message})
    : startsAtSignup = true;

  final bool startsAtSignup;
  final String message;
}

class RuniacAuthFlowScreen extends StatefulWidget {
  const RuniacAuthFlowScreen({
    required this.onAuthenticated,
    this.authRepository = const NonProductionAuthRepository(),
    this.recoveryPrompt,
    super.key,
  });

  final RuniacAuthRepository authRepository;
  final ValueChanged<RuniacAuthCompletion> onAuthenticated;
  final RuniacAuthRecoveryPrompt? recoveryPrompt;

  @override
  State<RuniacAuthFlowScreen> createState() => _RuniacAuthFlowScreenState();
}

class _RuniacAuthFlowScreenState extends State<RuniacAuthFlowScreen> {
  late _AuthStep _step;

  @override
  void initState() {
    super.initState();
    _step = _initialStepFor(widget.recoveryPrompt);
  }

  @override
  void didUpdateWidget(covariant RuniacAuthFlowScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final recoveryPrompt = widget.recoveryPrompt;
    if (oldWidget.recoveryPrompt != recoveryPrompt && recoveryPrompt != null) {
      _step = _initialStepFor(recoveryPrompt);
    }
  }

  void _show(_AuthStep step) {
    setState(() {
      _step = step;
    });
  }

  _AuthStep _initialStepFor(RuniacAuthRecoveryPrompt? recoveryPrompt) {
    return recoveryPrompt?.startsAtSignup ?? false
        ? _AuthStep.signup
        : _AuthStep.welcome;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.sectionSurface,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: RuniacAuthScreenFrame(
            key: ValueKey(_step),
            child: switch (_step) {
              _AuthStep.welcome => RuniacWelcomeAuthBody(
                onSignup: () => _show(_AuthStep.signup),
                onLogin: () => _show(_AuthStep.login),
              ),
              _AuthStep.login => RuniacLoginAuthBody(
                authRepository: widget.authRepository,
                onAuthenticated: () {
                  widget.onAuthenticated(RuniacAuthCompletion.login);
                },
                onSignup: () => _show(_AuthStep.signup),
                onForgotPassword: () => _show(_AuthStep.forgotPassword),
              ),
              _AuthStep.signup => RuniacSignupAuthBody(
                authRepository: widget.authRepository,
                onAuthenticated: () {
                  widget.onAuthenticated(RuniacAuthCompletion.signup);
                },
                onLogin: () => _show(_AuthStep.login),
                recoveryMessage: widget.recoveryPrompt?.message,
              ),
              _AuthStep.forgotPassword => RuniacRecoveryAuthBody(
                authRepository: widget.authRepository,
                onLogin: () => _show(_AuthStep.login),
              ),
            },
          ),
        ),
      ),
    );
  }
}
