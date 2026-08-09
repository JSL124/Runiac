part of 'view_summary_screen.dart';

/// Paints the summary's pace line.
///
/// Deliberately simpler than the Advanced Analysis pace chart: this one is a
/// glanceable shape on the summary card, so it draws the line and its fill
/// without axes or labels.
///
/// [isLockedPreview] is the Basic-tier treatment — the real shape is still
/// drawn, then blurred and dimmed, so the runner can see there is something
/// there rather than being shown a blank teaser.
class _PaceChartPainter extends CustomPainter {
  const _PaceChartPainter({required this.graph, required this.isLockedPreview});

  final PaceGraphSnapshot graph;
  final bool isLockedPreview;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalInset = size.width > (_paceChartHorizontalPlotInset * 2)
        ? _paceChartHorizontalPlotInset
        : 0.0;
    final plotLeft = horizontalInset;
    final plotRight = size.width - horizontalInset;
    final plotWidth = (plotRight - plotLeft).clamp(1.0, double.infinity);

    double xForDisplayProgress(double progressFraction) {
      return plotLeft + (progressFraction.clamp(0.0, 1.0) * plotWidth);
    }

    double displayProgressForPoint(int index) {
      return paceChartDisplayProgressForPoint(
        index: index,
        pointCount: graph.points.length,
        rawProgressFraction: graph.points[index].progressFraction,
      );
    }

    final guidePaint = Paint()
      ..color = _rBlue10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final y in [8.0, 36.0, 64.0, 92.0]) {
      _drawDashedLine(
        canvas,
        Offset(plotLeft, y),
        Offset(plotRight, y),
        guidePaint,
      );
    }

    if (!graph.isAvailable || graph.points.length < 3) {
      return;
    }

    final rangeMin = graph.paceRangeMinSecondsPerKm;
    final rangeMax = graph.paceRangeMaxSecondsPerKm;
    if (rangeMin == null || rangeMax == null) {
      return;
    }
    final paceRange = rangeMax - rangeMin;

    double yForSeconds(int paceSecondsPerKm) {
      if (paceRange <= 0) {
        return size.height / 2;
      }
      return ((paceSecondsPerKm - rangeMin) / paceRange) * size.height;
    }

    final offsets = <_PaceChartPointOffset>[];
    for (var i = 0; i < graph.points.length; i += 1) {
      final graphPoint = graph.points[i];
      offsets.add(
        _PaceChartPointOffset(
          point: graphPoint,
          offset: Offset(
            xForDisplayProgress(displayProgressForPoint(i)),
            yForSeconds(graphPoint.paceSecondsPerKm),
          ),
        ),
      );
    }

    final line = Path();
    for (var i = 0; i < offsets.length; i += 1) {
      final point = offsets[i].offset;
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }
    final firstPoint = offsets.first.offset;
    final lastPoint = offsets.last.offset;
    final area = Path.from(line)
      ..lineTo(lastPoint.dx, size.height)
      ..lineTo(firstPoint.dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..color = isLockedPreview
            ? const Color(0x12FB6414)
            : const Color(0x14FB6414),
    );
    final averagePace = graph.averagePaceSecondsPerKm;
    if (!isLockedPreview &&
        averagePace != null &&
        averagePace >= rangeMin &&
        averagePace <= rangeMax) {
      _drawDashedLine(
        canvas,
        Offset(plotLeft, yForSeconds(averagePace)),
        Offset(plotRight, yForSeconds(averagePace)),
        Paint()
          ..color = _rBlue60
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.75,
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = isLockedPreview ? const Color(0x66FB6414) : _rOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = isLockedPreview ? 2 : 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (!isLockedPreview) {
      _drawMarker(
        canvas,
        point: graph.slowestPacePoint,
        offsets: offsets,
        fillColor: _rWhite,
        strokeColor: _rBlue45,
      );
      _drawMarker(
        canvas,
        point: graph.bestPacePoint,
        offsets: offsets,
        fillColor: _rOrange,
        strokeColor: _rWhite,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 2.0;
    const dashSpace = 4.0;
    var x = start.dx;
    while (x < end.dx) {
      canvas.drawLine(
        Offset(x, start.dy),
        Offset(x + dashWidth, end.dy),
        paint,
      );
      x += dashWidth + dashSpace;
    }
  }

  void _drawMarker(
    Canvas canvas, {
    required PaceGraphPoint? point,
    required List<_PaceChartPointOffset> offsets,
    required Color fillColor,
    required Color strokeColor,
  }) {
    if (point == null) {
      return;
    }

    final center = _offsetForPoint(offsets, point);
    if (center == null) {
      return;
    }
    canvas.drawCircle(center, 4.5, Paint()..color = fillColor);
    canvas.drawCircle(
      center,
      4.5,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  Offset? _offsetForPoint(
    List<_PaceChartPointOffset> offsets,
    PaceGraphPoint point,
  ) {
    for (final candidate in offsets) {
      if (identical(candidate.point, point)) {
        return candidate.offset;
      }
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant _PaceChartPainter oldDelegate) {
    return oldDelegate.graph != graph ||
        oldDelegate.isLockedPreview != isLockedPreview;
  }
}

class _PaceChartPointOffset {
  const _PaceChartPointOffset({required this.point, required this.offset});

  final PaceGraphPoint point;
  final Offset offset;
}
