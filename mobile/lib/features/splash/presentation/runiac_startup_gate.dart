import 'dart:async';

import 'package:flutter/material.dart';

import 'runiac_splash_tokens.dart';
import 'splash_three_soft_dots_screen.dart';

class RuniacStartupGate extends StatefulWidget {
  const RuniacStartupGate({
    required this.child,
    this.showSplash = true,
    this.splashDuration = RuniacSplashTokens.minVisibleDuration,
    this.transitionDuration = RuniacSplashTokens.transitionDuration,
    super.key,
  });

  final Widget child;
  final bool showSplash;
  final Duration splashDuration;
  final Duration transitionDuration;

  @override
  State<RuniacStartupGate> createState() => _RuniacStartupGateState();
}

class _RuniacStartupGateState extends State<RuniacStartupGate> {
  Timer? _splashTimer;
  late bool _showSplash;
  int _scheduleGeneration = 0;

  @override
  void initState() {
    super.initState();
    _showSplash = widget.showSplash;
    _scheduleSplashHandoff();
  }

  @override
  void didUpdateWidget(covariant RuniacStartupGate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.showSplash) {
      _splashTimer?.cancel();
      _showSplash = false;
      return;
    }

    if (!oldWidget.showSplash ||
        oldWidget.splashDuration != widget.splashDuration) {
      _showSplash = true;
      _scheduleSplashHandoff();
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  void _scheduleSplashHandoff() {
    _splashTimer?.cancel();

    if (!widget.showSplash) {
      return;
    }

    final generation = ++_scheduleGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.showSplash ||
          !_showSplash ||
          generation != _scheduleGeneration) {
        return;
      }

      _splashTimer = Timer(widget.splashDuration, () {
        if (!mounted) {
          return;
        }

        setState(() {
          _showSplash = false;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: widget.transitionDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _showSplash
          ? const SplashThreeSoftDotsScreen()
          : KeyedSubtree(
              key: const ValueKey('runiac_startup_shell'),
              child: widget.child,
            ),
    );
  }
}
