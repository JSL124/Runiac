import 'package:flutter/material.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';
import 'package:runiac_app/core/widgets/runiac_back_header.dart';
import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';

import 'widgets/advanced_analysis/advanced_analysis_metric_sections.dart';
import 'widgets/advanced_analysis/advanced_analysis_overview_section.dart';
import 'widgets/advanced_analysis/advanced_analysis_theme.dart';

class AdvancedAnalysisScreen extends StatelessWidget {
  const AdvancedAnalysisScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.analysisSnapshot,
  });

  final String title;
  final String subtitle;
  final AdvancedAnalysisSnapshot? analysisSnapshot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            RuniacBackHeader(
              title: title,
              subtitle: subtitle,
              tooltip: 'Back to summary',
              onBack: () => Navigator.of(context).maybePop(),
              titleStyle: const TextStyle(
                color: advancedAnalysisBlue,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.15,
              ),
              subtitleStyle: const TextStyle(
                color: advancedAnalysisBlue60,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: const _NoOverscrollBehavior(),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdvancedAnalysisOverviewSection(
                        analysis: analysisSnapshot?.performance,
                      ),
                      const SizedBox(height: 14),
                      AdvancedAnalysisPaceSection(
                        analysis: analysisSnapshot?.pace,
                      ),
                      const SizedBox(height: 14),
                      const AdvancedAnalysisHeartRateSection(),
                      const SizedBox(height: 14),
                      AdvancedAnalysisElevationSection(
                        analysis: analysisSnapshot?.elevation,
                      ),
                      const SizedBox(height: 14),
                      AdvancedAnalysisCadenceSection(
                        analysis: analysisSnapshot?.formCadence,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoOverscrollBehavior extends ScrollBehavior {
  const _NoOverscrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}
