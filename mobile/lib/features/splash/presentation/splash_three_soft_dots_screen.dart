import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'runiac_splash_tokens.dart';

/// The launch splash — three soft dots animating while the app decides where to
/// go.
///
/// It is a real screen rather than a native launch image because the work
/// behind it varies: restoring the session, loading progress, and choosing
/// between onboarding, Home and sign-in. The animation loops rather than
/// running once, so a slow cold start does not end up frozen on a final frame.
class SplashThreeSoftDotsScreen extends StatefulWidget {
  const SplashThreeSoftDotsScreen({super.key});

  @override
  State<SplashThreeSoftDotsScreen> createState() =>
      _SplashThreeSoftDotsScreenState();
}

class _SplashThreeSoftDotsScreenState extends State<SplashThreeSoftDotsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotsController;
  Timer? _logoTimer;
  bool _logoVisible = false;
  bool _logoPrecached = false;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: RuniacSplashTokens.dotDuration,
    );
    _logoTimer = Timer(RuniacSplashTokens.logoFadeDelay, () {
      if (!mounted) {
        return;
      }

      setState(() {
        _logoVisible = true;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_logoPrecached) {
      precacheImage(const AssetImage(RuniacSplashTokens.logoAsset), context);
      _logoPrecached = true;
    }

    final nextReduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == nextReduceMotion) {
      return;
    }

    _reduceMotion = nextReduceMotion;
    if (nextReduceMotion) {
      _dotsController.stop();
    } else {
      _dotsController.repeat();
    }
  }

  @override
  void dispose() {
    _logoTimer?.cancel();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _reduceMotion ?? false;

    return Scaffold(
      backgroundColor: RuniacSplashTokens.softWhite,
      body: Semantics(
        key: const ValueKey('runiac_splash_screen'),
        label: 'Runiac is loading',
        liveRegion: true,
        child: ExcludeSemantics(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final logoWidth = math.min(
                  RuniacSplashTokens.logoWidth,
                  math.max(
                    0.0,
                    constraints.maxWidth -
                        (RuniacSplashTokens.horizontalPadding * 2),
                  ),
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              end: reduceMotion || _logoVisible ? 1.0 : 0.0,
                            ),
                            duration: reduceMotion
                                ? Duration.zero
                                : RuniacSplashTokens.logoFadeDuration,
                            curve: RuniacSplashTokens.logoCurve,
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(
                                    0,
                                    reduceMotion
                                        ? 0
                                        : (1 - value) *
                                              RuniacSplashTokens.logoLift,
                                  ),
                                  child: child,
                                ),
                              );
                            },
                            child: Image.asset(
                              RuniacSplashTokens.logoAsset,
                              key: const ValueKey('runiac_splash_logo'),
                              width: logoWidth,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          const SizedBox(
                            height: RuniacSplashTokens.logoToDotsGap,
                          ),
                          RepaintBoundary(
                            child: Row(
                              key: const ValueKey('runiac_splash_dots'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _SoftDot(
                                  key: const ValueKey('runiac_splash_dot_0'),
                                  color: RuniacSplashTokens.blue,
                                  index: 0,
                                  controller: _dotsController,
                                  reduceMotion: reduceMotion,
                                ),
                                const SizedBox(
                                  width: RuniacSplashTokens.dotGap,
                                ),
                                _SoftDot(
                                  key: const ValueKey('runiac_splash_dot_1'),
                                  color: RuniacSplashTokens.orange,
                                  index: 1,
                                  controller: _dotsController,
                                  reduceMotion: reduceMotion,
                                ),
                                const SizedBox(
                                  width: RuniacSplashTokens.dotGap,
                                ),
                                _SoftDot(
                                  key: const ValueKey('runiac_splash_dot_2'),
                                  color: RuniacSplashTokens.blue,
                                  index: 2,
                                  controller: _dotsController,
                                  reduceMotion: reduceMotion,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: RuniacSplashTokens.horizontalPadding,
                      right: RuniacSplashTokens.horizontalPadding,
                      bottom: RuniacSplashTokens.footerBottom,
                      child: Text(
                        RuniacSplashTokens.footerText,
                        key: const ValueKey('runiac_splash_footer'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: RuniacSplashTokens.taglineBlue,
                          fontSize: RuniacSplashTokens.footerFontSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: RuniacSplashTokens.footerLetterSpacing,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftDot extends StatelessWidget {
  const _SoftDot({
    required this.color,
    required this.index,
    required this.controller,
    required this.reduceMotion,
    super.key,
  });

  final Color color;
  final int index;
  final AnimationController controller;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return _DotBody(color: color, opacity: 1, scale: 1);
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final stagger =
            RuniacSplashTokens.dotStagger.inMilliseconds /
            RuniacSplashTokens.dotDuration.inMilliseconds;
        final shifted = (controller.value - (index * stagger)) % 1.0;
        final wave = shifted < 0.5 ? shifted / 0.5 : (1 - shifted) / 0.5;
        final eased = RuniacSplashTokens.dotCurve.transform(
          wave.clamp(0.0, 1.0),
        );
        final opacity = lerpDouble(
          RuniacSplashTokens.dotMinOpacity,
          RuniacSplashTokens.dotMaxOpacity,
          eased,
        )!;
        final scale = lerpDouble(
          RuniacSplashTokens.dotMinScale,
          RuniacSplashTokens.dotMaxScale,
          eased,
        )!;

        return _DotBody(color: color, opacity: opacity, scale: scale);
      },
    );
  }
}

class _DotBody extends StatelessWidget {
  const _DotBody({
    required this.color,
    required this.opacity,
    required this.scale,
  });

  final Color color;
  final double opacity;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: RuniacSplashTokens.dotSize),
        ),
      ),
    );
  }
}
