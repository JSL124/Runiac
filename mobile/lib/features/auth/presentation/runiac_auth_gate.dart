import 'package:flutter/material.dart';

import '../../splash/presentation/splash_three_soft_dots_screen.dart';
import '../domain/runiac_auth_service.dart';
import 'runiac_auth_flow_screen.dart';

export 'runiac_auth_flow_screen.dart'
    show RuniacAuthCompletion, RuniacAuthRecoveryPrompt;

class RuniacAuthGate extends StatefulWidget {
  const RuniacAuthGate({
    required this.authRepository,
    this.child,
    this.childBuilder,
    this.showAuth = false,
    this.onAuthenticated,
    this.onAuthStateChanged,
    this.recoveryPrompt,
    super.key,
  }) : assert(child != null || childBuilder != null);

  final RuniacAuthRepository authRepository;
  final Widget? child;
  final WidgetBuilder? childBuilder;
  final bool showAuth;
  final ValueChanged<RuniacAuthCompletion>? onAuthenticated;
  final ValueChanged<RuniacAuthUser?>? onAuthStateChanged;
  final RuniacAuthRecoveryPrompt? recoveryPrompt;

  @override
  State<RuniacAuthGate> createState() => _RuniacAuthGateState();
}

class _RuniacAuthGateState extends State<RuniacAuthGate> {
  Stream<RuniacAuthUser?>? _authStateChanges;

  Stream<RuniacAuthUser?> get _authStream {
    return _authStateChanges ??= widget.authRepository.authStateChanges();
  }

  @override
  void didUpdateWidget(covariant RuniacAuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authRepository != widget.authRepository) {
      _authStateChanges = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAuth) {
      return _buildChild(context);
    }

    return StreamBuilder<RuniacAuthUser?>(
      initialData: widget.authRepository.currentUser,
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const _RuniacAuthGateLoading();
        }

        _notifyAuthStateChanged(snapshot.data);

        if (snapshot.data != null) {
          return _buildChild(context);
        }

        return RuniacAuthFlowScreen(
          authRepository: widget.authRepository,
          recoveryPrompt: widget.recoveryPrompt,
          onAuthenticated: (completion) {
            widget.onAuthenticated?.call(completion);
          },
        );
      },
    );
  }

  Widget _buildChild(BuildContext context) {
    return widget.childBuilder?.call(context) ?? widget.child!;
  }

  void _notifyAuthStateChanged(RuniacAuthUser? user) {
    final callback = widget.onAuthStateChanged;
    if (callback == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        callback(user);
      }
    });
  }
}

class _RuniacAuthGateLoading extends StatelessWidget {
  const _RuniacAuthGateLoading();

  @override
  Widget build(BuildContext context) {
    return const SplashThreeSoftDotsScreen();
  }
}
