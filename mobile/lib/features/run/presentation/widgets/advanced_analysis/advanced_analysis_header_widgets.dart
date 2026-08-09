import 'package:flutter/material.dart';

import 'advanced_analysis_theme.dart';

class AdvancedAnalysisInsightBadge extends StatelessWidget {
  const AdvancedAnalysisInsightBadge({
    super.key,
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted ? advancedAnalysisOrange08 : advancedAnalysisSurface,
        border: Border.all(
          color: highlighted
              ? advancedAnalysisOrange16
              : advancedAnalysisBlue12,
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: highlighted ? advancedAnalysisOrange : advancedAnalysisBlue,
            size: 15,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: highlighted
                  ? advancedAnalysisOrange
                  : advancedAnalysisBlue,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
