import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';

class RuniacBottomSheetHandle extends StatelessWidget {
  const RuniacBottomSheetHandle({
    this.width = 44,
    this.height = 5,
    this.color,
    this.margin = EdgeInsets.zero,
    this.borderRadius = 999,
    this.semanticLabel,
    super.key,
  });

  final double width;
  final double height;
  final Color? color;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final handle = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? RuniacColors.textSecondary.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );

    if (semanticLabel == null) {
      return handle;
    }

    return Semantics(label: semanticLabel, child: handle);
  }
}
