import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';

class SkeletonDot extends StatelessWidget {
  const SkeletonDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: RuniacColors.border,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  const SkeletonLine({this.width, super.key});

  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 10,
      decoration: BoxDecoration(
        color: RuniacColors.border,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
