import 'package:flutter/material.dart';

import 'advanced_analysis_theme.dart';

class AdvancedAnalysisSection extends StatelessWidget {
  const AdvancedAnalysisSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: advancedAnalysisBlue12, height: 1, thickness: 1),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            color: advancedAnalysisBlue,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        child,
        const SizedBox(height: 16),
        const Divider(color: advancedAnalysisBlue12, height: 1, thickness: 1),
      ],
    );
  }
}
