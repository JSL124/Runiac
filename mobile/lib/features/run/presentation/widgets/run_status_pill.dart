import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';

// Run-status palette. Shared by the pre-run (run_launch) and active-run
// (run_active) status pills so both stay in sync. Note this orange
// (0xFFFF7A1A) is intentionally distinct from RuniacColors.accentOrange.
const _sportOrange = Color(0xFFFF7A1A);
const _softControlBlue = Color(0x667A91E5);

/// Soft blue capsule with an orange status dot and a single-line label, used
/// to surface the current run/permission status. The pre-run and active-run
/// surfaces render the same pill with slightly different width/padding, so the
/// shared geometry lives here and only those two values vary per call site.
class RunStatusPill extends StatelessWidget {
  const RunStatusPill({
    required this.label,
    this.maxWidth = 190,
    this.horizontalPadding = 18,
    super.key,
  });

  final String label;
  final double maxWidth;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
      decoration: BoxDecoration(
        color: _softControlBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: _sportOrange, size: 14),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  color: RuniacColors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
