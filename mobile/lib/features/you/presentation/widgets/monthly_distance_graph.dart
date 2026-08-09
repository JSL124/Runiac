import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../data/you_overview_demo_snapshots.dart';

const _graphHeight = 178.0;
const _leftInset = 58.0;
const _rightInset = 12.0;
const _topInset = 30.0;
const _bottomInset = 38.0;
const _axisLabelRightGap = 8.0;
const _axisLabelMaxWidth = 56.0;
const _showVerticalGridLines = true;
const _showTopHorizontalGuideLine = true;
const _contextLabel = 'Past 12 weeks';
const _contextLabelTop = 0.0;
const _contextLabelLeft = 0.0;
const _gridStrokeWidth = 1.1;
const _lineStrokeWidth = 3.2;
const _markerRadius = 4.5;
const _markerStrokeWidth = 2.2;
const _finalMarkerRadius = 7.0;
const _finalHaloRadius = 13.0;
const _contextLabelFontSize = 10.0;
const _axisFontSize = 13.0;
const _monthFontSize = 13.0;
const _monthLabelMaxWidth = 48.0;
const _monthLabelMinGap = 4.0;

/// Horizontal space the painted chart gives up on each side, exposed so tests
/// can derive the real chart bounds from the laid-out graph instead of
/// hard-coding numbers that drift when the insets change.
@visibleForTesting
const monthlyDistanceGraphLeftInset = _leftInset;
@visibleForTesting
const monthlyDistanceGraphRightInset = _rightInset;

@visibleForTesting
class MonthLabelPlacement {
  const MonthLabelPlacement({
    required this.label,
    required this.index,
    required this.centerX,
    required this.left,
    required this.right,
  });

  final String label;
  final int index;
  final double centerX;
  final double left;
  final double right;
}

class PastTwelveWeeksDistanceGraph extends StatelessWidget {
  const PastTwelveWeeksDistanceGraph({
    super.key,
    List<String>? labels,
    List<double>? values,
    this.labelWeekIndices,
  }) : _labels = labels ?? pastTwelveWeeksDistanceGraphLabels,
       _values = values ?? pastTwelveWeeksDistanceGraphValues;

  final List<String> _labels;
  final List<double> _values;

  /// Week bucket index (0-based) each label should sit under. When null, labels
  /// are spread evenly across the chart width.
  final List<int>? labelWeekIndices;

  List<String> get labels => _labels;
  List<double> get values => _values;

  @override
  Widget build(BuildContext context) {
    final graphLabels = labels;
    final graphValues = values;
    final axisLabels = _axisLabelsFor(graphValues);

    return Semantics(
      label:
          'Past 12 weeks distance graph ${graphLabels.join(' ')} '
          '${axisLabels.join(' ')}',
      child: SizedBox(
        height: _graphHeight,
        width: double.infinity,
        child: Stack(
          children: [
            CustomPaint(
              painter: _PastTwelveWeeksDistanceGraphPainter(
                labels: graphLabels,
                values: graphValues,
                labelWeekIndices: labelWeekIndices,
              ),
              child: const SizedBox.expand(),
            ),
            const Positioned(
              top: _contextLabelTop,
              left: _contextLabelLeft,
              child: Text(
                _contextLabel,
                style: TextStyle(
                  color: RuniacColors.textSecondary,
                  fontSize: _contextLabelFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PastTwelveWeeksDistanceGraphPainter extends CustomPainter {
  const _PastTwelveWeeksDistanceGraphPainter({
    required this.labels,
    required this.values,
    required this.labelWeekIndices,
  });

  final List<String> labels;
  final List<double> values;
  final List<int>? labelWeekIndices;

  @override
  void paint(Canvas canvas, Size size) {
    const backgroundColor = RuniacColors.white;
    final topGuideColor = RuniacColors.cardBorder.withValues(alpha: 0.72);
    final verticalGridColor = RuniacColors.cardBorder.withValues(alpha: 0.58);
    final fillColor = RuniacColors.accentOrange.withValues(alpha: 0.1);
    const axisLabelColor = RuniacColors.textPrimary;
    const monthLabelColor = RuniacColors.textSecondary;

    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);

    final chartRect = Rect.fromLTWH(
      _leftInset,
      _topInset,
      math.max(0, size.width - _leftInset - _rightInset),
      math.max(0, size.height - _topInset - _bottomInset),
    );
    if (chartRect.width <= 0 ||
        chartRect.height <= 0 ||
        labels.length < 2 ||
        values.length < 2) {
      return;
    }

    final gridPaint = Paint()
      ..color = verticalGridColor
      ..strokeWidth = _gridStrokeWidth;
    if (_showVerticalGridLines) {
      for (var i = 0; i <= values.length; i += 1) {
        final x = _boundaryX(chartRect, i, values.length);
        canvas.drawLine(
          Offset(x, chartRect.top),
          Offset(x, chartRect.bottom),
          gridPaint,
        );
      }
    }
    if (_showTopHorizontalGuideLine) {
      gridPaint.color = topGuideColor;
      canvas.drawLine(
        Offset(chartRect.left, chartRect.top),
        Offset(chartRect.right, chartRect.top),
        gridPaint,
      );
    }

    final axisValues = _axisValuesFor(values);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i += 1) {
      points.add(
        Offset(
          _pointX(chartRect, i, values.length),
          _pointY(chartRect, values[i], axisValues.max),
        ),
      );
    }

    final areaPath = Path()..moveTo(points.first.dx, chartRect.bottom);
    for (final point in points) {
      areaPath.lineTo(point.dx, point.dy);
    }
    areaPath
      ..lineTo(points.last.dx, chartRect.bottom)
      ..close();
    canvas.drawPath(areaPath, Paint()..color = fillColor);

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i += 1) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = RuniacColors.accentOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = _lineStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final markerFillPaint = Paint()..color = backgroundColor;
    final markerRingPaint = Paint()
      ..color = RuniacColors.accentOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = _markerStrokeWidth;
    final markerPaint = Paint()..color = RuniacColors.accentOrange;
    final haloPaint = Paint()
      ..color = RuniacColors.accentOrange.withValues(alpha: 0.16);
    for (var i = 0; i < points.length; i += 1) {
      if (i == points.length - 1) {
        canvas
          ..drawCircle(points[i], _finalHaloRadius, haloPaint)
          ..drawCircle(points[i], _finalMarkerRadius, markerPaint);
        continue;
      }
      canvas
        ..drawCircle(points[i], _markerRadius, markerFillPaint)
        ..drawCircle(points[i], _markerRadius, markerRingPaint);
    }

    const axisLabelStyle = TextStyle(
      color: axisLabelColor,
      fontSize: _axisFontSize,
      fontWeight: FontWeight.w700,
    );
    final axisLabelRightEdge = chartRect.left - _axisLabelRightGap;
    _paintAxisText(
      canvas,
      _formatAxisLabel(axisValues.max),
      rightEdge: axisLabelRightEdge,
      top: chartRect.top - 7,
      axisLabelStyle,
    );
    _paintAxisText(
      canvas,
      _formatAxisLabel(axisValues.middle, roundDown: true),
      rightEdge: axisLabelRightEdge,
      top: chartRect.center.dy - 8,
      axisLabelStyle,
    );
    _paintAxisText(
      canvas,
      '0 km',
      rightEdge: axisLabelRightEdge,
      top: chartRect.bottom - 8,
      axisLabelStyle,
    );

    const monthLabelStyle = TextStyle(
      color: monthLabelColor,
      fontSize: _monthFontSize,
      fontWeight: FontWeight.w600,
    );
    final visibleMonthLabels = visibleMonthLabelPlacementsForGraph(
      labels: labels,
      pointCount: values.length,
      labelWeekIndices: labelWeekIndices,
      chartLeft: chartRect.left,
      chartRight: chartRect.right,
      style: monthLabelStyle,
    );
    for (final label in visibleMonthLabels) {
      _paintCenteredLabel(
        canvas,
        label.label,
        centerX: label.centerX,
        top: chartRect.bottom + 9,
        style: monthLabelStyle,
      );
    }
  }

  void _paintCenteredLabel(
    Canvas canvas,
    String value, {
    required double centerX,
    required double top,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: _monthLabelMaxWidth);
    final dx = centerX - painter.width / 2;
    painter.paint(canvas, Offset(dx, top));
  }

  double _pointX(Rect chartRect, int index, int pointCount) {
    return chartRect.left +
        chartRect.width * (index + 0.5) / math.max(1, pointCount);
  }

  double _boundaryX(Rect chartRect, int index, int pointCount) {
    return chartRect.left + chartRect.width * index / math.max(1, pointCount);
  }

  double _pointY(Rect chartRect, double value, double maxValue) {
    final normalized = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return chartRect.bottom - chartRect.height * normalized;
  }

  void _paintText(
    Canvas canvas,
    String value,
    Offset offset,
    TextStyle style, {
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  void _paintAxisText(
    Canvas canvas,
    String value,
    TextStyle style, {
    required double rightEdge,
    required double top,
  }) {
    final offset = axisLabelOffsetFor(
      value: value,
      style: style,
      rightEdge: rightEdge,
      top: top,
      maxWidth: _axisLabelMaxWidth,
    );
    _paintText(canvas, value, offset, style, maxWidth: _axisLabelMaxWidth);
  }

  @override
  bool shouldRepaint(
    covariant _PastTwelveWeeksDistanceGraphPainter oldDelegate,
  ) {
    return !_sameStringList(oldDelegate.labels, labels) ||
        !_sameDoubleList(oldDelegate.values, values) ||
        !_sameIntList(oldDelegate.labelWeekIndices, labelWeekIndices);
  }

  bool _sameIntList(List<int>? a, List<int>? b) {
    if (a == null || b == null) {
      return a == b;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  bool _sameDoubleList(List<double> a, List<double> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

@visibleForTesting
Offset axisLabelOffsetFor({
  required String value,
  required TextStyle style,
  required double rightEdge,
  required double top,
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  return Offset(rightEdge - painter.width, top);
}

({double middle, double max}) _axisValuesFor(List<double> values) {
  final finiteValues = values.where((value) => value.isFinite);
  final maxValue = finiteValues.fold<double>(
    0,
    (currentMax, value) => math.max(currentMax, value),
  );
  return (middle: maxValue / 2, max: maxValue);
}

List<String> _axisLabelsFor(List<double> values) {
  final axisValues = _axisValuesFor(values);
  return [
    '0 km',
    _formatAxisLabel(axisValues.middle, roundDown: true),
    _formatAxisLabel(axisValues.max),
  ];
}

String _formatAxisLabel(double value, {bool roundDown = false}) {
  if (roundDown) {
    return '${value.floor()} km';
  }
  final roundedDown = value.floor();
  if ((value - roundedDown).abs() < 0.001) {
    return '$roundedDown km';
  }
  return '${value.toStringAsFixed(1)} km';
}

@visibleForTesting
List<double> monthLabelFractionsForGraph({
  required int labelCount,
  required int pointCount,
}) {
  if (labelCount <= 0 || pointCount <= 0) {
    return const [];
  }
  final pointsPerLabel = pointCount / labelCount;
  return List.generate(labelCount, (index) {
    final centeredWeek = (index + 0.5) * pointsPerLabel;
    final intervalCenter = centeredWeek + 0.5;
    return (intervalCenter / pointCount).clamp(0.0, 1.0);
  });
}

@visibleForTesting
List<MonthLabelPlacement> visibleMonthLabelPlacementsForGraph({
  required List<String> labels,
  required int pointCount,
  required double chartLeft,
  required double chartRight,
  List<int>? labelWeekIndices,
  TextStyle style = const TextStyle(
    fontSize: _monthFontSize,
    fontWeight: FontWeight.w600,
  ),
}) {
  if (labels.isEmpty || pointCount <= 0 || chartRight <= chartLeft) {
    return const [];
  }
  final chartWidth = chartRight - chartLeft;
  final fallbackFractions = monthLabelFractionsForGraph(
    labelCount: labels.length,
    pointCount: pointCount,
  );
  final candidates = <MonthLabelPlacement>[];
  for (var index = 0; index < labels.length; index += 1) {
    final naturalCenterX = _monthLabelCenterX(
      index: index,
      labelCount: labels.length,
      pointCount: pointCount,
      labelWeekIndices: labelWeekIndices,
      fallbackFractions: fallbackFractions,
      chartLeft: chartLeft,
      chartWidth: chartWidth,
    );
    final painter = TextPainter(
      text: TextSpan(text: labels[index], style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: _monthLabelMaxWidth);
    final centerX = _clampedMonthLabelCenterX(
      centerX: naturalCenterX,
      width: painter.width,
      chartLeft: chartLeft,
      chartRight: chartRight,
    );
    candidates.add(
      MonthLabelPlacement(
        label: labels[index],
        index: index,
        centerX: centerX,
        left: centerX - painter.width / 2,
        right: centerX + painter.width / 2,
      ),
    );
  }

  final accepted = <MonthLabelPlacement>[];
  for (final candidate in _monthLabelPriorityOrder(candidates)) {
    final overlaps = accepted.any(
      (visible) =>
          candidate.left < visible.right + _monthLabelMinGap &&
          candidate.right + _monthLabelMinGap > visible.left,
    );
    if (!overlaps) {
      accepted.add(candidate);
    }
  }
  accepted.sort((a, b) => a.index.compareTo(b.index));
  return accepted;
}

/// Nudges a month label back inside the chart instead of dropping it when its
/// bucket centre sits closer to an edge than half the label width.
///
/// The first and last week buckets are only half a slot from the chart bounds —
/// about 12 logical pixels on a common phone — which is narrower than a
/// three-letter month at the label font size. Dropping those labels silently
/// hid the current month for the first days of every month, because the marker
/// builder deliberately anchors the current month to the final bucket. A label
/// wider than the whole chart is centred, since no shift can satisfy both
/// bounds.
double _clampedMonthLabelCenterX({
  required double centerX,
  required double width,
  required double chartLeft,
  required double chartRight,
}) {
  final chartWidth = chartRight - chartLeft;
  if (width >= chartWidth) {
    return chartLeft + chartWidth / 2;
  }
  final half = width / 2;
  return centerX.clamp(chartLeft + half, chartRight - half).toDouble();
}

double _monthLabelCenterX({
  required int index,
  required int labelCount,
  required int pointCount,
  required List<int>? labelWeekIndices,
  required List<double> fallbackFractions,
  required double chartLeft,
  required double chartWidth,
}) {
  final weekIndices = labelWeekIndices;
  if (weekIndices != null && index < weekIndices.length) {
    final weekIndex = weekIndices[index]
        .clamp(0, math.max(0, pointCount - 1))
        .toInt();
    return chartLeft + chartWidth * (weekIndex + 0.5) / pointCount;
  }
  if (index < fallbackFractions.length) {
    return chartLeft + chartWidth * fallbackFractions[index];
  }
  return chartLeft + chartWidth * (index + 0.5) / math.max(1, labelCount);
}

List<MonthLabelPlacement> _monthLabelPriorityOrder(
  List<MonthLabelPlacement> candidates,
) {
  final ordered = [...candidates];
  final currentMonthIndex = candidates.fold<int>(
    -1,
    (maxIndex, candidate) => math.max(maxIndex, candidate.index),
  );
  ordered.sort((a, b) {
    final aIsCurrentMonth = a.index == currentMonthIndex;
    final bIsCurrentMonth = b.index == currentMonthIndex;
    if (aIsCurrentMonth != bIsCurrentMonth) {
      return aIsCurrentMonth ? -1 : 1;
    }
    return a.index.compareTo(b.index);
  });
  return ordered;
}
