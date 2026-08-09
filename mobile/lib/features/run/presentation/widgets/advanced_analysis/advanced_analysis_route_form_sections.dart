import 'package:flutter/material.dart';

import '../../../domain/models/advanced_analysis_snapshot.dart';
import '../../../domain/models/cadence_graph_snapshot.dart';
import '../../data/advanced_analysis_demo_snapshots.dart';
import 'advanced_analysis_charts.dart';
import 'advanced_analysis_shared_widgets.dart';
import 'advanced_analysis_theme.dart';

/// The elevation and cadence sections of the Advanced Analysis screen.
///
/// Both describe the shape of the route and the runner's form, and both are the
/// most likely metrics to be missing — elevation needs usable altitude
/// readings, cadence needs a trustworthy source. Each section therefore has a
/// first-class unavailable state that names the reason instead of hiding, so
/// the screen keeps its structure whatever the run contained.
class AdvancedAnalysisElevationSection extends StatelessWidget {
  const AdvancedAnalysisElevationSection({super.key, this.analysis});

  final AdvancedAnalysisElevationAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    return AdvancedAnalysisSection(
      title: 'Elevation Analysis',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _elevationGraph,
          const SizedBox(height: 16),
          AdvancedAnalysisStatGrid(stats: _elevationStats, plain: true),
          const AdvancedAnalysisInterpretationRow(
            text:
                'Route insights use the movement data available for this run.',
          ),
        ],
      ),
    );
  }

  Widget get _elevationGraph {
    final graph = analysis?.elevationGraph.value;
    if (analysis == null) {
      return const _AdvancedAnalysisUnavailableElevationGraph();
    }
    if (analysis!.elevationGraph.isAvailable &&
        graph != null &&
        graph.isAvailable &&
        graph.points.length >= 2) {
      return AdvancedAnalysisChartPanel(
        height: 150,
        painter: AdvancedAnalysisElevationChartPainter(graph: graph),
        plain: true,
      );
    }
    return const _AdvancedAnalysisUnavailableElevationGraph();
  }

  List<AdvancedAnalysisStatData> get _elevationStats {
    final analysis = this.analysis;
    return [
      AdvancedAnalysisStatData(
        'Total Gain',
        _metricValue(analysis?.totalGain),
        _metricUnit(analysis?.totalGain),
        hot: analysis?.totalGain.isAvailable ?? false,
      ),
      AdvancedAnalysisStatData(
        'Highest Point',
        _metricValue(analysis?.highestPoint),
        _metricUnit(analysis?.highestPoint),
      ),
      AdvancedAnalysisStatData(
        'Lowest Point',
        _metricValue(analysis?.lowestPoint),
        _metricUnit(analysis?.lowestPoint),
      ),
      AdvancedAnalysisStatData(
        'Route Difficulty',
        _displayLabel(analysis?.routeDifficulty.valueLabel),
        '',
      ),
    ];
  }

  String _metricValue(AdvancedAnalysisMetric<String>? metric) {
    if (metric == null || !metric.isAvailable) {
      return '--';
    }
    final value = (metric.valueLabel ?? metric.value ?? '').trim();
    if (value.isEmpty) {
      return '--';
    }
    return value.split(' ').first;
  }

  String _metricUnit(AdvancedAnalysisMetric<String>? metric) {
    if (metric == null || !metric.isAvailable) {
      return '';
    }
    final value = (metric.valueLabel ?? metric.value ?? '').trim();
    final parts = value.split(' ');
    return parts.length > 1 ? parts.last : '';
  }

  String _displayLabel(String? valueLabel) {
    if (valueLabel == null || valueLabel.isEmpty) {
      return '--';
    }
    return valueLabel;
  }
}

class _AdvancedAnalysisUnavailableElevationGraph extends StatelessWidget {
  const _AdvancedAnalysisUnavailableElevationGraph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: ValueKey('advanced_analysis_elevation_graph_unavailable'),
      height: 150,
      child: Center(
        child: Text(
          '--',
          style: TextStyle(
            color: advancedAnalysisBlue45,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class AdvancedAnalysisCadenceSection extends StatelessWidget {
  const AdvancedAnalysisCadenceSection({super.key, this.analysis});

  final AdvancedAnalysisFormCadenceAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    return AdvancedAnalysisSection(
      title: 'Running Form / Cadence',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdvancedAnalysisStatGrid(stats: _cadenceStats(analysis), plain: true),
          const SizedBox(height: 16),
          AdvancedAnalysisChartPanel(
            height: 150,
            painter: AdvancedAnalysisCadenceChartPainter(
              graph: analysis?.cadenceGraph.value,
              showDemoFallback: _showDemoCadenceFallback(
                analysis?.cadenceGraph,
              ),
            ),
            plain: true,
          ),
          AdvancedAnalysisInterpretationRow(
            text: _cadenceInterpretation(analysis),
          ),
        ],
      ),
    );
  }

  List<AdvancedAnalysisStatData> _cadenceStats(
    AdvancedAnalysisFormCadenceAnalysis? analysis,
  ) {
    return [
      AdvancedAnalysisStatData(
        'Average Cadence',
        _cadenceValue(analysis?.averageCadence),
        _cadenceUnit(analysis?.averageCadence),
      ),
      AdvancedAnalysisStatData(
        'Lowest',
        _cadencePointValue(analysis?.cadenceGraph.value?.lowestCadencePoint),
        _cadencePointUnit(analysis?.cadenceGraph.value?.lowestCadencePoint),
      ),
      AdvancedAnalysisStatData(
        'Highest',
        _cadencePointValue(analysis?.cadenceGraph.value?.highestCadencePoint),
        _cadencePointUnit(analysis?.cadenceGraph.value?.highestCadencePoint),
      ),
      AdvancedAnalysisStatData(
        'Trend',
        _displayLabel(analysis?.cadenceStatus.valueLabel),
        '',
      ),
    ];
  }

  String _cadenceValue(AdvancedAnalysisMetric<String>? metric) {
    final valueLabel = metric?.valueLabel;
    if (valueLabel == null) {
      return '--';
    }
    return valueLabel.split(' ').first;
  }

  String _cadenceUnit(AdvancedAnalysisMetric<String>? metric) {
    final valueLabel = metric?.valueLabel;
    if (valueLabel == null) {
      return '';
    }
    final parts = valueLabel.split(' ');
    return parts.length > 1 ? parts.last : '';
  }

  String _cadencePointValue(CadenceGraphPoint? point) {
    final label = point?.displayLabel;
    if (label == null || label.isEmpty) {
      return '--';
    }
    return label.split(' ').first;
  }

  String _cadencePointUnit(CadenceGraphPoint? point) {
    final label = point?.displayLabel;
    if (label == null || label.isEmpty) {
      return '';
    }
    final parts = label.split(' ');
    return parts.length > 1 ? parts.last : '';
  }

  bool _showDemoCadenceFallback(
    AdvancedAnalysisMetric<CadenceGraphSnapshot>? metric,
  ) {
    if (metric == null) {
      return true;
    }
    return metric.availability == AdvancedAnalysisMetricAvailability.demoOnly &&
        metric.source == AdvancedAnalysisMetricSource.staticDemo;
  }

  String _displayLabel(String? valueLabel) {
    if (valueLabel == null || valueLabel.isEmpty) {
      return '--';
    }
    return '${valueLabel[0].toUpperCase()}${valueLabel.substring(1)}';
  }

  String _cadenceInterpretation(AdvancedAnalysisFormCadenceAnalysis? analysis) {
    final consistency = analysis?.strideConsistency.valueLabel;
    if (consistency == null || consistency.isEmpty) {
      return 'Cadence is unavailable for this run.';
    }
    return 'Cadence consistency is ${_displayLabel(consistency)} for this run.';
  }
}
