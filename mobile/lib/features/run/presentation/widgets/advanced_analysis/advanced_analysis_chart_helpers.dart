import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'advanced_analysis_theme.dart';

class AdvancedAnalysisChartGeometry {
  AdvancedAnalysisChartGeometry(
    Size size, {
    required this.left,
    required this.top,
    required double right,
    required double bottom,
  }) : right = size.width - right,
       bottom = size.height - bottom;

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
}

void drawAdvancedAnalysisGrid(
  Canvas canvas,
  AdvancedAnalysisChartGeometry plot,
  List<String> yLabels,
  List<String> xLabels,
) {
  final gridPaint = Paint()
    ..color = advancedAnalysisBlue10
    ..strokeWidth = 1;
  for (var i = 0; i < yLabels.length; i++) {
    final y = yLabels.length == 1
        ? plot.top
        : plot.top + (i / (yLabels.length - 1)) * plot.height;
    drawAdvancedAnalysisDashedLine(
      canvas,
      Offset(plot.left, y),
      Offset(plot.right, y),
    );
    drawAdvancedAnalysisText(
      canvas,
      yLabels[i],
      Offset(2, y - 7),
      advancedAnalysisBlue45,
      10,
    );
  }
  for (var i = 0; i < xLabels.length; i++) {
    final x = xLabels.length == 1
        ? plot.left
        : plot.left + (i / (xLabels.length - 1)) * plot.width;
    canvas.drawLine(
      Offset(x, plot.top),
      Offset(x, plot.bottom),
      gridPaint..color = const Color(0x002F51C8),
    );
    final labelPainter = _createAdvancedAnalysisTextPainter(
      xLabels[i],
      advancedAnalysisBlue45,
      10,
    );
    final minLabelX = plot.left;
    final maxLabelX = math.max(minLabelX, plot.right - labelPainter.width);
    final labelX = switch (i) {
      0 => minLabelX,
      _ when i == xLabels.length - 1 => maxLabelX,
      _ => (x - labelPainter.width / 2).clamp(minLabelX, maxLabelX).toDouble(),
    };
    labelPainter.paint(canvas, Offset(labelX, plot.bottom + 7));
  }
}

void drawAdvancedAnalysisLineArea(
  Canvas canvas,
  List<Offset> offsets,
  double bottom,
  Color fill,
  Color stroke,
) {
  final path = smoothAdvancedAnalysisPath(offsets);
  final area = Path.from(path)
    ..lineTo(offsets.last.dx, bottom)
    ..lineTo(offsets.first.dx, bottom)
    ..close();
  canvas.drawPath(area, Paint()..color = fill);
  canvas.drawPath(
    path,
    Paint()
      ..color = stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke,
  );
}

void drawAdvancedAnalysisPolyline(
  Canvas canvas,
  List<Offset> offsets,
  Color color,
) {
  canvas.drawPath(
    smoothAdvancedAnalysisPath(offsets),
    Paint()
      ..color = color
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke,
  );
}

Path smoothAdvancedAnalysisPath(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = points[(i - 1).clamp(0, points.length - 1)];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[(i + 2).clamp(0, points.length - 1)];
    path.cubicTo(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
      p2.dx,
      p2.dy,
    );
  }
  return path;
}

void drawAdvancedAnalysisDashedLine(Canvas canvas, Offset start, Offset end) {
  final paint = Paint()
    ..color = advancedAnalysisBlue10
    ..strokeWidth = 1;
  const dash = 4.0;
  const gap = 5.0;
  final distance = (end - start).distance;
  final direction = (end - start) / distance;
  var drawn = 0.0;
  while (drawn < distance) {
    final from = start + direction * drawn;
    final to = start + direction * math.min(drawn + dash, distance);
    canvas.drawLine(from, to, paint);
    drawn += dash + gap;
  }
}

void drawAdvancedAnalysisText(
  Canvas canvas,
  String text,
  Offset offset,
  Color color,
  double size,
) {
  final painter = _createAdvancedAnalysisTextPainter(text, color, size);
  painter.paint(canvas, offset);
}

TextPainter _createAdvancedAnalysisTextPainter(
  String text,
  Color color,
  double size,
) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}
