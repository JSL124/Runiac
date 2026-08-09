import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';

/// The app's shared button styles and tap surfaces.
///
/// Every button in Runiac should come from here rather than from a locally
/// styled `ElevatedButton` — that is what keeps tap targets, radii and
/// disabled states consistent across features written at different times.
///
/// [RuniacButtonTone] is the only choice a caller normally makes: blue is the
/// default action, orange is reserved for the primary action of a screen.
enum RuniacButtonTone { blue, orange }

class RuniacButtonStyles {
  const RuniacButtonStyles._();

  static ButtonStyle primary({
    RuniacButtonTone tone = RuniacButtonTone.blue,
    Size? minimumSize,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    double? elevation,
    Color? shadowColor,
    Color foregroundColor = RuniacColors.white,
    Color? disabledBackgroundColor,
    Color? disabledForegroundColor,
  }) {
    final color = switch (tone) {
      RuniacButtonTone.blue => RuniacColors.primaryBlue,
      RuniacButtonTone.orange => RuniacColors.accentOrange,
    };

    return FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      disabledForegroundColor: disabledForegroundColor,
      minimumSize: minimumSize,
      shape: shape,
      textStyle: textStyle,
      padding: padding,
      elevation: elevation,
      shadowColor: shadowColor,
    );
  }

  static ButtonStyle secondary({
    Color foregroundColor = RuniacColors.primaryBlue,
    Color backgroundColor = RuniacColors.white,
    BorderSide side = const BorderSide(color: RuniacColors.border),
    Size? minimumSize,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      side: side,
      minimumSize: minimumSize,
      shape: shape,
      textStyle: textStyle,
      padding: padding,
    );
  }

  static ButtonStyle ghost({
    Color foregroundColor = RuniacColors.primaryBlue,
    Size? minimumSize,
    EdgeInsetsGeometry? padding,
    TextStyle? textStyle,
    MaterialTapTargetSize? tapTargetSize,
  }) {
    return TextButton.styleFrom(
      foregroundColor: foregroundColor,
      minimumSize: minimumSize,
      padding: padding,
      textStyle: textStyle,
      tapTargetSize: tapTargetSize,
    );
  }
}

class RuniacTappableSurface extends StatelessWidget {
  const RuniacTappableSurface({
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.decoration,
    this.padding,
    this.alignment,
    this.constraints,
    this.height,
    this.width,
    this.semanticLabel,
    this.semanticsButton = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Decoration? decoration;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;
  final BoxConstraints? constraints;
  final double? height;
  final double? width;
  final String? semanticLabel;
  final bool semanticsButton;

  @override
  Widget build(BuildContext context) {
    final surface = Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Ink(
          width: width,
          height: height,
          padding: padding,
          decoration: decoration,
          child: Container(
            constraints: constraints,
            alignment: alignment,
            child: child,
          ),
        ),
      ),
    );

    if (!semanticsButton && semanticLabel == null) {
      return surface;
    }

    return Semantics(
      label: semanticLabel,
      button: semanticsButton,
      enabled: onTap != null,
      onTap: semanticLabel == null ? null : onTap,
      excludeSemantics: semanticLabel != null,
      child: surface,
    );
  }
}

class RuniacIconTileButton extends StatelessWidget {
  const RuniacIconTileButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.size = 44,
    this.iconSize = 24,
    this.iconColor = RuniacColors.primaryBlue,
    this.backgroundColor = RuniacColors.white,
    this.borderColor,
    this.borderRadius,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? semanticLabel;
  final double size;
  final double iconSize;
  final Color iconColor;
  final Color backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius =
        borderRadius ?? BorderRadius.circular(size / 2);
    final button = Material(
      color: backgroundColor,
      borderRadius: effectiveBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: effectiveBorderRadius,
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: effectiveBorderRadius,
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!),
          ),
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );

    final semanticButton = Semantics(
      label: semanticLabel ?? tooltip,
      button: true,
      child: button,
    );

    if (tooltip == null) {
      return semanticButton;
    }

    return Tooltip(message: tooltip!, child: semanticButton);
  }
}
