part of 'view_summary_screen.dart';

class _MapPreviewPainter extends CustomPainter {
  const _MapPreviewPainter({required this.route});

  final RunRouteSnapshot route;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _rBlue06);
    canvas.save();
    canvas.scale(size.width / 360, size.height / 240);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 360, 240));

    final gridPaint = Paint()
      ..color = _rBlue10
      ..strokeWidth = 1;
    for (var x = 0.0; x <= 360; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, 240), gridPaint);
    }
    for (var y = 0.0; y <= 240; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(360, y), gridPaint);
    }

    final roadPaint = Paint()
      ..color = _rBlue18
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-20, 40), const Offset(380, 240), roadPaint);
    canvas.drawLine(const Offset(-20, 200), const Offset(380, 40), roadPaint);
    canvas.drawLine(const Offset(120, -20), const Offset(240, 260), roadPaint);

    final riverPath = Path()
      ..moveTo(-20, 130)
      ..cubicTo(60, 100, 140, 170, 220, 130)
      ..cubicTo(280, 100, 340, 100, 380, 130);
    canvas.drawPath(
      riverPath,
      Paint()
        ..color = _rBlue10
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22,
    );

    if (route.hasRoute) {
      _drawCompletedRoute(canvas, const Size(360, 240));
    } else if (route.hasLocation) {
      _drawLocationDot(canvas, const Offset(180, 120));
    }

    canvas.restore();
  }

  void _drawCompletedRoute(Canvas canvas, Size size) {
    final transform = _SummaryRouteTransform.fromSegments(route.segments, size);
    if (transform == null) {
      return;
    }

    final shadowPaint = Paint()
      ..color = const Color(0x66304BB7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final routePaint = Paint()
      ..color = _rOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset? startPoint;
    Offset? endPoint;
    for (final segment in route.segments.where(
      (segment) => segment.length > 1,
    )) {
      final path = Path();
      for (var index = 0; index < segment.length; index += 1) {
        final point = transform.offsetFor(segment[index]);
        startPoint ??= point;
        endPoint = point;
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, shadowPaint);
      canvas.drawPath(path, routePaint);
    }

    if (startPoint != null) {
      canvas.drawCircle(startPoint, 7, Paint()..color = _rBlue);
      canvas.drawCircle(startPoint, 3, Paint()..color = _rWhite);
    }
    if (endPoint != null) {
      _drawLocationDot(canvas, endPoint);
    }
  }

  void _drawLocationDot(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 15, Paint()..color = const Color(0x33FB6414));
    canvas.drawCircle(center, 8, Paint()..color = _rOrange);
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..color = _rWhite
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _MapPreviewPainter oldDelegate) {
    return oldDelegate.route != route;
  }
}

class _SummaryRouteTransform {
  const _SummaryRouteTransform({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
    required this.size,
  });

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;
  final Size size;

  static _SummaryRouteTransform? fromSegments(
    List<List<RunLocationSample>> segments,
    Size size,
  ) {
    final points = segments.expand((segment) => segment).toList();
    if (points.isEmpty) {
      return null;
    }

    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      minLatitude = point.latitude < minLatitude ? point.latitude : minLatitude;
      maxLatitude = point.latitude > maxLatitude ? point.latitude : maxLatitude;
      minLongitude = point.longitude < minLongitude
          ? point.longitude
          : minLongitude;
      maxLongitude = point.longitude > maxLongitude
          ? point.longitude
          : maxLongitude;
    }

    return _SummaryRouteTransform(
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
      size: size,
    );
  }

  Offset offsetFor(RunLocationSample sample) {
    final longitudeRange = maxLongitude - minLongitude;
    final latitudeRange = maxLatitude - minLatitude;
    final x = longitudeRange == 0
        ? 0.5
        : ((sample.longitude - minLongitude) / longitudeRange).clamp(0.0, 1.0);
    final y = latitudeRange == 0
        ? 0.5
        : (1 - (sample.latitude - minLatitude) / latitudeRange).clamp(0.0, 1.0);
    final padding = size.shortestSide * 0.18;
    final drawableWidth = (size.width - padding * 2).clamp(1.0, size.width);
    final drawableHeight = (size.height - padding * 2).clamp(1.0, size.height);
    return Offset(padding + drawableWidth * x, padding + drawableHeight * y);
  }
}
