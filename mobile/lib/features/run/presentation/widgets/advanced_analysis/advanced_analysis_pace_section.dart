import 'package:flutter/material.dart';

import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';

import '../../data/advanced_analysis_demo_snapshots.dart';
import 'advanced_analysis_charts.dart';
import 'advanced_analysis_shared_widgets.dart';
import 'advanced_analysis_splits_table.dart';
import 'advanced_analysis_theme.dart';

class AdvancedAnalysisPaceSection extends StatelessWidget {
  const AdvancedAnalysisPaceSection({super.key, this.analysis});

  final AdvancedAnalysisPaceAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    return AdvancedAnalysisSection(
      title: 'Pace Analysis',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdvancedAnalysisStatGrid(stats: _paceStats, plain: true),
          const SizedBox(height: 18),
          const _AdvancedAnalysisPaceGraphTitle(),
          const SizedBox(height: 8),
          _paceGraph,
          const SizedBox(height: 16),
          const _AdvancedAnalysisSplitsTitle(),
          const SizedBox(height: 10),
          AdvancedAnalysisSplitTable(analysis: analysis),
          const AdvancedAnalysisInterpretationRow(
            text:
                'Your pace slowed slightly in the middle section but recovered well in the final part.',
          ),
        ],
      ),
    );
  }

  List<AdvancedAnalysisStatData> get _paceStats {
    final analysis = this.analysis;
    if (analysis == null) {
      return advancedAnalysisPaceStats;
    }

    return [
      AdvancedAnalysisStatData(
        'Avg Pace',
        _metricValue(analysis.averagePace, stripPaceUnit: true),
        analysis.averagePace.isAvailable ? '/km' : '',
      ),
      AdvancedAnalysisStatData(
        'Fastest Pace',
        _metricValue(analysis.fastestPace, stripPaceUnit: true),
        analysis.fastestPace.isAvailable ? '/km' : '',
        hot: analysis.fastestPace.isAvailable,
      ),
      AdvancedAnalysisStatData(
        'Slowest Pace',
        _metricValue(analysis.slowestPace, stripPaceUnit: true),
        analysis.slowestPace.isAvailable ? '/km' : '',
      ),
      AdvancedAnalysisStatData(
        'Pace Stability',
        _metricValue(analysis.paceStability),
        analysis.paceStability.isAvailable ? '%' : '',
      ),
    ];
  }

  Widget get _paceGraph {
    final analysis = this.analysis;
    if (analysis == null) {
      return const AdvancedAnalysisChartPanel(
        height: 170,
        painter: AdvancedAnalysisPaceChartPainter(),
        plain: true,
      );
    }

    final graph = analysis.paceGraph.value;
    if (analysis.paceGraph.isAvailable &&
        graph != null &&
        graph.isAvailable &&
        graph.hasDistanceAxis) {
      return AdvancedAnalysisChartPanel(
        height: 170,
        painter: AdvancedAnalysisPaceChartPainter(graph: graph),
        plain: true,
      );
    }

    return const _AdvancedAnalysisUnavailablePaceGraph();
  }

  String _metricValue(
    AdvancedAnalysisMetric<String> metric, {
    bool stripPaceUnit = false,
  }) {
    if (!metric.isAvailable) {
      return '--';
    }

    final value = (metric.valueLabel ?? metric.value ?? '').trim();
    if (value.isEmpty) {
      return '--';
    }

    return stripPaceUnit ? _stripPaceUnit(value) : value;
  }

  String _stripPaceUnit(String value) {
    return value
        .replaceAll(RegExp(r'\s*/\s*km$', caseSensitive: false), '')
        .trim();
  }
}

class _AdvancedAnalysisUnavailablePaceGraph extends StatelessWidget {
  const _AdvancedAnalysisUnavailablePaceGraph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: ValueKey('advanced_analysis_pace_graph_unavailable'),
      height: 170,
      child: Center(
        child: Text(
          '--',
          style: TextStyle(
            color: advancedAnalysisInk,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
      ),
    );
  }
}

class _AdvancedAnalysisPaceGraphTitle extends StatelessWidget {
  const _AdvancedAnalysisPaceGraphTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Pace Over Distance',
      style: TextStyle(
        color: advancedAnalysisBlue60,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _AdvancedAnalysisSplitsTitle extends StatelessWidget {
  const _AdvancedAnalysisSplitsTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Splits',
      style: TextStyle(
        color: advancedAnalysisBlue,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }
}
