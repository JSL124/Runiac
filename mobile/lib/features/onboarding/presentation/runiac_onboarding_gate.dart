import 'package:flutter/material.dart';

import 'onboarding_flow_screen.dart';

class RuniacOnboardingGate extends StatefulWidget {
  const RuniacOnboardingGate({
    required this.child,
    this.showOnboarding = false,
    this.onCompletedDraft,
    super.key,
  });

  final Widget child;
  final bool showOnboarding;
  final OnboardingCompleteCallback? onCompletedDraft;

  @override
  State<RuniacOnboardingGate> createState() => _RuniacOnboardingGateState();
}

class _RuniacOnboardingGateState extends State<RuniacOnboardingGate> {
  bool _completed = false;

  @override
  void didUpdateWidget(covariant RuniacOnboardingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showOnboarding && oldWidget.showOnboarding) {
      _completed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showOnboarding || _completed) {
      return widget.child;
    }

    return OnboardingFlowScreen(
      onComplete: (draft) async {
        final completed =
            await (widget.onCompletedDraft?.call(draft) ??
                Future<bool>.value(true));
        if (completed && mounted) {
          setState(() {
            _completed = true;
          });
        }
        return completed;
      },
    );
  }
}
