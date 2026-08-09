import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';

enum RuniacAuthButtonVariant { primary, secondary, google }

class RuniacAuthButton extends StatelessWidget {
  const RuniacAuthButton({
    required this.label,
    required this.onPressed,
    this.variant = RuniacAuthButtonVariant.primary,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final RuniacAuthButtonVariant variant;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: 10)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final textStyle = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      height: 1,
    );

    if (variant == RuniacAuthButtonVariant.primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: RuniacColors.primaryBlue,
          foregroundColor: RuniacColors.white,
          textStyle: textStyle,
          shape: shape,
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: RuniacColors.white,
        foregroundColor: variant == RuniacAuthButtonVariant.google
            ? RuniacColors.textPrimary
            : RuniacColors.primaryBlue,
        side: BorderSide(
          color: RuniacColors.primaryBlue.withValues(alpha: 0.12),
          width: 2,
        ),
        textStyle: textStyle,
        shape: shape,
      ),
      child: child,
    );
  }
}

class RuniacAuthDivider extends StatelessWidget {
  const RuniacAuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: RuniacColors.cardBorder, thickness: 2),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or',
            style: TextStyle(
              color: RuniacColors.primaryBlue.withValues(alpha: 0.45),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Expanded(
          child: Divider(color: RuniacColors.cardBorder, thickness: 2),
        ),
      ],
    );
  }
}

class RuniacAuthTextLink extends StatelessWidget {
  const RuniacAuthTextLink({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: RuniacColors.primaryBlue,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }
}

class RuniacInlineAuthAction extends StatelessWidget {
  const RuniacInlineAuthAction({
    required this.text,
    required this.action,
    required this.onPressed,
    super.key,
  });

  final String text;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(
          text,
          style: const TextStyle(
            color: RuniacColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: RuniacColors.primaryBlue,
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          child: Text(action),
        ),
      ],
    );
  }
}

class RuniacGoogleGlyph extends StatelessWidget {
  const RuniacGoogleGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 22,
      child: Image(
        image: AssetImage('assets/icons/google_icon.png'),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}
