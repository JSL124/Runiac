import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';

/// A "bloom open" route for the Challenge result/ceremony surface.
///
/// Instead of a jarring horizontal page slide (which fights the celebration
/// that plays the instant the page lands), the ceremony crossfades in over a
/// solid white base while scaling up gently from its centre — so opening the
/// ceremony reads as one continuous, dynamic flourish onto a clean white page.
///
/// The white [ColoredBox] sits INSIDE the fade and the route is non-opaque, so
/// the screen below keeps painting through the crossfade: there is never a
/// black backdrop gap during the scale or fade. Shared by every entry point
/// (auto-present, history, badge collection) so the transition is identical
/// for all tiers.
Route<T> challengeCeremonyRoute<T>({
  required WidgetBuilder builder,
  bool fullscreenDialog = false,
}) {
  return PageRouteBuilder<T>(
    fullscreenDialog: fullscreenDialog,
    opaque: false,
    transitionDuration: const Duration(milliseconds: 460),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ColoredBox(
          color: RuniacColors.background,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
