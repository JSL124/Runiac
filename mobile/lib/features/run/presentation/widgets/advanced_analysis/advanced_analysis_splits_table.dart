import 'package:flutter/material.dart';

import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';

import '../../data/advanced_analysis_demo_snapshots.dart';
import 'advanced_analysis_theme.dart';

/// The per-kilometre splits table on the Advanced Analysis screen.
///
/// Each row's bar is scaled relative to the run's own fastest and slowest
/// split, not an absolute pace, so the comparison is meaningful for any runner.
/// [_minFill] keeps the slowest split visible as a bar rather than collapsing
/// it to nothing.
///
/// A final partial kilometre is shown but marked, because judging it against
/// full splits would be misleading.
class AdvancedAnalysisSplitTable extends StatelessWidget {
  const AdvancedAnalysisSplitTable({super.key, required this.analysis});

  static const double _minFill = 0.32;
  static const double _partialFill = 0.4;

  final AdvancedAnalysisPaceAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final fullSplitPaces = [
      for (final row in rows)
        if (!row.isPartial) row.barScalePaceSecondsPerKm,
    ].whereType<int>().toList();
    final fastest = fullSplitPaces.isEmpty
        ? null
        : fullSplitPaces.reduce((a, b) => a < b ? a : b);
    final slowest = fullSplitPaces.isEmpty
        ? null
        : fullSplitPaces.reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        const _AdvancedAnalysisSplitHeader(),
        const Divider(color: advancedAnalysisBlue12, height: 17, thickness: 1),
        for (var i = 0; i < rows.length; i++) ...[
          _AdvancedAnalysisSplitTableRow(
            rowIndex: i,
            row: rows[i],
            displayDistance: _displayDistance(rows[i]),
            fillFraction: _fillFor(rows[i], fastest: fastest, slowest: slowest),
          ),
          if (i != rows.length - 1)
            const Divider(
              color: advancedAnalysisBlue07,
              height: 15,
              thickness: 1,
            ),
        ],
      ],
    );
  }

  List<_AdvancedAnalysisSplitRowData> get _rows {
    final analysis = this.analysis;
    if (analysis == null) {
      return [
        for (final split in advancedAnalysisSplits)
          _AdvancedAnalysisSplitRowData(
            distanceLabel: split.km,
            paceLabel: split.pace,
            isFastest: split.fastest,
            isPartial: split.partial,
            barScalePaceSecondsPerKm: _paceSeconds(split.pace),
          ),
      ];
    }

    final splits = analysis.splits.value;
    final canRenderSnapshotRows =
        (analysis.splits.isAvailable ||
            analysis.splits.availability ==
                AdvancedAnalysisMetricAvailability.demoOnly) &&
        splits != null &&
        splits.isNotEmpty;
    if (!canRenderSnapshotRows) {
      return const [_AdvancedAnalysisSplitRowData.unavailable()];
    }

    final fastestSeconds = splits
        .where((split) => !split.isPartial)
        .map(
          (split) => split.barScalePaceSecondsPerKm ?? split.paceSecondsPerKm,
        )
        .fold<int?>(null, (current, seconds) {
          if (current == null || seconds < current) {
            return seconds;
          }
          return current;
        });
    return [
      for (final split in splits)
        _AdvancedAnalysisSplitRowData(
          distanceLabel: split.distanceLabel,
          paceLabel: split.paceLabel,
          elevationLabel: split.elevationLabel,
          heartRateLabel: split.heartRateLabel,
          isFastest:
              !split.isPartial &&
              fastestSeconds != null &&
              (split.barScalePaceSecondsPerKm ?? split.paceSecondsPerKm) ==
                  fastestSeconds,
          isPartial: split.isPartial,
          barScalePaceSecondsPerKm:
              split.barScalePaceSecondsPerKm ?? split.paceSecondsPerKm,
        ),
    ];
  }

  static String _displayDistance(_AdvancedAnalysisSplitRowData row) {
    final label = row.distanceLabel;
    if (label.trim() == '--') {
      return '--';
    }
    if (row.isPartial) {
      final distance = _distanceKm(label);
      if (distance != null && distance >= 1) {
        final remainingDistance = distance - distance.floorToDouble();
        if (remainingDistance > 0) {
          return remainingDistance.toStringAsFixed(2);
        }
      }
    }
    return label.trim().replaceFirst(RegExp(r'\s*km$'), '');
  }

  static double? _distanceKm(String label) {
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*km$').firstMatch(label.trim());
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(1)!);
  }

  static double _fillFor(
    _AdvancedAnalysisSplitRowData row, {
    required int? fastest,
    required int? slowest,
  }) {
    if (row.isUnavailable) {
      return 0;
    }
    if (row.isPartial) {
      return _partialFill;
    }

    final seconds = row.barScalePaceSecondsPerKm;
    if (seconds == null || fastest == null || slowest == null) {
      return _minFill;
    }

    if (fastest == slowest) {
      return 1;
    }

    final ratio = (slowest - seconds) / (slowest - fastest);
    return (_minFill + ratio.clamp(0, 1) * (1 - _minFill)).toDouble();
  }

  static int? _paceSeconds(String pace) {
    final match = RegExp(r"^(\d+)[’'](\d{1,2})").firstMatch(pace.trim());
    if (match == null) {
      return null;
    }

    final minutes = int.tryParse(match.group(1)!);
    final seconds = int.tryParse(match.group(2)!);
    if (minutes == null || seconds == null) {
      return null;
    }

    return minutes * 60 + seconds;
  }
}

class _AdvancedAnalysisSplitHeader extends StatelessWidget {
  const _AdvancedAnalysisSplitHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(width: 50, child: _AdvancedAnalysisSplitHeaderText('Km')),
        SizedBox(width: 64, child: _AdvancedAnalysisSplitHeaderText('Pace')),
        Expanded(child: SizedBox.shrink()),
        SizedBox(
          width: 46,
          child: _AdvancedAnalysisSplitHeaderText('Elev', alignRight: true),
        ),
        SizedBox(
          width: 38,
          child: _AdvancedAnalysisSplitHeaderText('HR', alignRight: true),
        ),
      ],
    );
  }
}

class _AdvancedAnalysisSplitHeaderText extends StatelessWidget {
  const _AdvancedAnalysisSplitHeaderText(this.text, {this.alignRight = false});

  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        color: advancedAnalysisBlue60,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _AdvancedAnalysisSplitTableRow extends StatelessWidget {
  const _AdvancedAnalysisSplitTableRow({
    required this.rowIndex,
    required this.row,
    required this.displayDistance,
    required this.fillFraction,
  });

  final int rowIndex;
  final _AdvancedAnalysisSplitRowData row;
  final String displayDistance;
  final double fillFraction;

  @override
  Widget build(BuildContext context) {
    final paceColor = row.isFastest
        ? advancedAnalysisOrange
        : advancedAnalysisInk;

    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            displayDistance,
            key: Key('advanced_analysis_split_${rowIndex + 1}_km'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: advancedAnalysisBlue75,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            row.paceLabel,
            key: Key('advanced_analysis_split_${rowIndex + 1}_pace'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: paceColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: AdvancedAnalysisSplitBar(
            key: Key('advanced_analysis_split_${rowIndex + 1}_bar'),
            fillFraction: fillFraction,
            highlighted: row.isFastest,
            partial: row.isPartial,
          ),
        ),
        SizedBox(
          width: 46,
          child: _AdvancedAnalysisUnavailableSplitValue(
            row.elevationLabel,
            key: Key('advanced_analysis_split_${rowIndex + 1}_elev'),
          ),
        ),
        SizedBox(
          width: 38,
          child: _AdvancedAnalysisUnavailableSplitValue(
            row.heartRateLabel,
            key: Key('advanced_analysis_split_${rowIndex + 1}_hr'),
          ),
        ),
      ],
    );
  }
}

class AdvancedAnalysisSplitBar extends StatelessWidget {
  const AdvancedAnalysisSplitBar({
    super.key,
    required this.fillFraction,
    required this.highlighted,
    required this.partial,
  });

  final double fillFraction;
  final bool highlighted;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        height: 13,
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: advancedAnalysisBlue07,
          borderRadius: BorderRadius.circular(999),
        ),
        child: FractionallySizedBox(
          widthFactor: fillFraction.clamp(0, 1),
          heightFactor: 1,
          alignment: Alignment.centerLeft,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: partial
                  ? advancedAnalysisBlue60
                  : highlighted
                  ? advancedAnalysisOrange
                  : advancedAnalysisBlue,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdvancedAnalysisUnavailableSplitValue extends StatelessWidget {
  const _AdvancedAnalysisUnavailableSplitValue(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: advancedAnalysisBlue45,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.1,
      ),
    );
  }
}

class _AdvancedAnalysisSplitRowData {
  const _AdvancedAnalysisSplitRowData({
    required this.distanceLabel,
    required this.paceLabel,
    required this.isFastest,
    required this.isPartial,
    this.elevationLabel = '--',
    this.heartRateLabel = '--',
    this.barScalePaceSecondsPerKm,
  });

  const _AdvancedAnalysisSplitRowData.unavailable()
    : distanceLabel = '--',
      paceLabel = '--',
      elevationLabel = '--',
      heartRateLabel = '--',
      isFastest = false,
      isPartial = false,
      barScalePaceSecondsPerKm = null;

  final String distanceLabel;
  final String paceLabel;
  final String elevationLabel;
  final String heartRateLabel;
  final bool isFastest;
  final bool isPartial;
  final int? barScalePaceSecondsPerKm;

  bool get isUnavailable {
    return distanceLabel == '--' && paceLabel == '--';
  }
}
