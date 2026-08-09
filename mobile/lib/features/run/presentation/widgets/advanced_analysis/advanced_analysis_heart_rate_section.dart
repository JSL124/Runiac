import 'dart:ui';

import 'package:flutter/material.dart';

import '../../data/advanced_analysis_demo_snapshots.dart';
import 'advanced_analysis_shared_widgets.dart';
import 'advanced_analysis_theme.dart';

/// Presentation-only section. Runiac records no heart-rate signal — there is
/// no wearable integration and no workout import — so this section always
/// renders its "not recorded" state behind the guard overlay. It is kept so
/// the Advanced Analysis layout matches the documented design.
class AdvancedAnalysisHeartRateSection extends StatelessWidget {
  const AdvancedAnalysisHeartRateSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdvancedAnalysisSection(
      title: 'Heart Rate Analysis',
      child: Stack(
        children: const [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdvancedAnalysisStatGrid(
                stats: [
                  AdvancedAnalysisStatData('Avg Heart Rate', '--', ''),
                  AdvancedAnalysisStatData('Max Heart Rate', '--', ''),
                ],
                plain: true,
              ),
              SizedBox(height: 18),
              _AdvancedAnalysisHeartRateStatusPanel(),
            ],
          ),
          Positioned.fill(child: _AdvancedAnalysisHeartRateGuard()),
        ],
      ),
    );
  }
}

class _AdvancedAnalysisHeartRateStatusPanel extends StatelessWidget {
  const _AdvancedAnalysisHeartRateStatusPanel();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 132,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: advancedAnalysisSurface,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedAnalysisHeartRateGuard extends StatelessWidget {
  const _AdvancedAnalysisHeartRateGuard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.44),
            ),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Text(
                  'Heart rate was not recorded for this run.',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: advancedAnalysisOrange,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    shadows: [
                      Shadow(color: Colors.white, blurRadius: 10),
                      Shadow(
                        color: Colors.white,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
