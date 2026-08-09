import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/skeleton.dart';

const _placeholderSurface = Color(0xFFF8FAFF);

class ProgressPlaceholder extends StatelessWidget {
  const ProgressPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: _placeholderSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: RuniacColors.border),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(child: SkeletonLine()),
            SizedBox(width: 12),
            SkeletonLine(width: 58),
          ],
        ),
      ],
    );
  }
}

class PlanSkeletonRow extends StatelessWidget {
  const PlanSkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _placeholderSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RuniacColors.border),
      ),
      child: const Row(
        children: [
          SkeletonDot(),
          SizedBox(width: 12),
          Expanded(child: SkeletonLine()),
          SizedBox(width: 12),
          SkeletonLine(width: 44),
        ],
      ),
    );
  }
}
