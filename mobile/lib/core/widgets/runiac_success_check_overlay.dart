import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../assets/runiac_assets.dart';
import '../haptics/runiac_haptics_scope.dart';
import '../theme/runiac_colors.dart';

/// Shows a brief, non-interactive confirmation overlay: a check animation
/// plays once, then the overlay auto-dismisses. For moments where a whole
/// piece of configuration has just been saved (profile edits, a new weekly
/// schedule) and a plain snackbar would undersell the change.
///
/// Under reduced motion the overlay is skipped entirely — callers proceed as
/// if it had already finished, so no state depends on it having been shown.
///
/// The returned future completes once the overlay has closed, so callers can
/// sequence follow-up navigation after the confirmation is done.
Future<void> showRuniacSuccessCheckOverlay(
  BuildContext context, {
  String? message,
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  // The save already succeeded by the time this is called, so the
  // confirmation haptic fires regardless of whether the visual overlay ends
  // up showing under reduced motion.
  RuniacHapticsScope.maybeOf(context)?.impactMedium();
  if (reduceMotion) {
    return Future<void>.value();
  }
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Success confirmation',
    barrierColor: Colors.black.withValues(alpha: 0.15),
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _SuccessCheckOverlay(message: message),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _SuccessCheckOverlay extends StatefulWidget {
  const _SuccessCheckOverlay({this.message});

  final String? message;

  @override
  State<_SuccessCheckOverlay> createState() => _SuccessCheckOverlayState();
}

class _SuccessCheckOverlayState extends State<_SuccessCheckOverlay>
    with SingleTickerProviderStateMixin {
  // A fixed on-screen duration, independent of whether (or how fast) the
  // Lottie composition loads, so this always settles deterministically —
  // `pumpAndSettle` can wait on an `AnimationController` tied to the
  // widget's ticker, unlike a bare `Timer` gated behind async asset
  // decoding, which never resolves in a widget test without `runAsync`.
  static const _visibleDuration = Duration(milliseconds: 1800);

  late final AnimationController _visibility;

  @override
  void initState() {
    super.initState();
    _visibility = AnimationController(vsync: this, duration: _visibleDuration)
      ..addStatusListener(_handleStatusChange)
      ..forward();
  }

  void _handleStatusChange(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _visibility
      ..removeStatusListener(_handleStatusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: RuniacColors.background,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Lottie.asset(
                  RuniacAssets.successCheckLottie,
                  repeat: false,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.check_circle,
                      size: 72,
                      color: RuniacColors.successGreen,
                    );
                  },
                ),
              ),
              if (widget.message != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
