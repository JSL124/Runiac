import 'package:flutter/material.dart';

import '../../domain/models/run_location_sample.dart';
import '../../domain/models/run_map_view_state.dart';

const _mapBlue = Color(0xFF3153C9);
const _softRoadBlue = Color(0x337A91E5);
const _deepRoadBlue = Color(0x28304BB7);
const _routeWhite = Color(0xFFF8FAFF);
const _runnerHalo = Color(0x66304BB7);
const _runnerOrange = Color(0xFFFF6818);

/// The stand-in map used when no Mapbox token is configured.
///
/// Not an error state: it is hand-painted with `CustomPainter`, draws the real
/// route and the runner's real position, and keeps the recenter control
/// working. Run tracking is entirely independent of the map, so a build without
/// a token stays fully usable — which is what makes the offline mode described
/// in the README possible.
class RunMapPlaceholder extends StatelessWidget {
  const RunMapPlaceholder({
    super.key,
    this.mapViewState = const RunMapViewState.empty(),
    this.isFollowingRunner = true,
    this.onManualPan,
    this.onRecenter,
    this.showRecenterButton = true,
    this.recenterButtonBottom = 176,
  });

  final RunMapViewState mapViewState;
  final bool isFollowingRunner;
  final VoidCallback? onManualPan;
  final VoidCallback? onRecenter;
  final bool showRecenterButton;
  final double recenterButtonBottom;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: _mapBlue),
      child: Stack(
        children: [
          const Positioned.fill(child: _RunMapBackground()),
          if (_hasDisplayRoutePolyline(mapViewState))
            Positioned.fill(
              child: CustomPaint(
                key: const Key('run_map_route_polyline'),
                painter: _RunRoutePainter(
                  mapViewState.displayRouteSegments,
                  followPosition: isFollowingRunner
                      ? mapViewState.displayPosition
                      : null,
                ),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              key: const Key('run_map_interaction_layer'),
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (_) {
                if (isFollowingRunner) {
                  onManualPan?.call();
                }
              },
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: isFollowingRunner
                      ? Alignment.center
                      : _alignmentForCurrentPosition(
                          mapViewState,
                          constraints.biggest,
                        ),
                  child: const IgnorePointer(child: _RunnerMarker()),
                );
              },
            ),
          ),
          if (showRecenterButton && !isFollowingRunner && onRecenter != null)
            Positioned(
              right: 24,
              bottom: recenterButtonBottom,
              child: RunMapRecenterButton(onPressed: onRecenter!),
            ),
        ],
      ),
    );
  }
}

class _RunMapBackground extends StatelessWidget {
  const _RunMapBackground();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _RunMapPainter());
  }
}

class _RunnerMarker extends StatelessWidget {
  const _RunnerMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('run_map_runner_marker'),
      width: 88,
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _runnerHalo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: _runnerOrange,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class RunMapRecenterButton extends StatelessWidget {
  const RunMapRecenterButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Recenter map',
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 8,
        child: IconButton(
          key: const Key('run_map_recenter_button'),
          onPressed: onPressed,
          icon: const Icon(Icons.my_location_rounded),
          color: _mapBlue,
        ),
      ),
    );
  }
}

class _RunMapPainter extends CustomPainter {
  const _RunMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = _mapBlue;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final wideRoadPaint = Paint()
      ..color = _softRoadBlue
      ..strokeWidth = size.width * 0.17
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final deepRoadPaint = Paint()
      ..color = _deepRoadBlue
      ..strokeWidth = size.width * 0.13
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final routePaint = Paint()
      ..color = _routeWhite
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final leftRoad = Path()
      ..moveTo(size.width * -0.18, size.height * -0.02)
      ..lineTo(size.width * 0.48, size.height * 0.56);
    final lowerRoad = Path()
      ..moveTo(size.width * -0.12, size.height * 0.58)
      ..quadraticBezierTo(
        size.width * 0.36,
        size.height * 0.84,
        size.width * 1.14,
        size.height * 0.55,
      );
    final rightRoad = Path()
      ..moveTo(size.width * 1.12, size.height * 0.43)
      ..lineTo(size.width * 0.58, size.height * 0.62)
      ..lineTo(size.width * 0.78, size.height * 1.14);
    final crossRoad = Path()
      ..moveTo(size.width * -0.10, size.height * 0.50)
      ..lineTo(size.width * 1.12, size.height * 0.92);

    canvas.drawPath(leftRoad, wideRoadPaint);
    canvas.drawPath(lowerRoad, wideRoadPaint);
    canvas.drawPath(rightRoad, wideRoadPaint);
    canvas.drawPath(crossRoad, wideRoadPaint);

    final shadowRoad = Path()
      ..moveTo(size.width * 0.56, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.60,
        size.width * 1.08,
        size.height * 0.46,
      );
    canvas.drawPath(shadowRoad, deepRoadPaint);

    final routePath = Path()
      ..moveTo(size.width * -0.08, size.height * 0.64)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.58,
        size.width * 0.34,
        size.height * 0.58,
        size.width * 0.48,
        size.height * 0.50,
      )
      ..cubicTo(
        size.width * 0.63,
        size.height * 0.41,
        size.width * 0.72,
        size.height * 0.40,
        size.width * 1.08,
        size.height * 0.42,
      );
    canvas.drawPath(routePath, routePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RunRoutePainter extends CustomPainter {
  const _RunRoutePainter(this.routeSegments, {this.followPosition});

  final List<List<RunLocationSample>> routeSegments;
  final RunLocationSample? followPosition;

  @override
  void paint(Canvas canvas, Size size) {
    final transform = _RouteTransform.fromSegments(routeSegments, size);
    if (transform == null) {
      return;
    }

    final routeShadowPaint = Paint()
      ..color = const Color(0x55304BB7)
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final routePaint = Paint()
      ..color = _runnerOrange
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final segment in routeSegments.where(
      (segment) => segment.length > 1,
    )) {
      final path = Path();
      for (var index = 0; index < segment.length; index += 1) {
        final point = transform.offsetFor(
          segment[index],
          followPosition: followPosition,
        );
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, routeShadowPaint);
      canvas.drawPath(path, routePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RunRoutePainter oldDelegate) {
    return oldDelegate.routeSegments != routeSegments ||
        oldDelegate.followPosition != followPosition;
  }
}

bool _hasDisplayRoutePolyline(RunMapViewState state) {
  return state.displayRouteSegments.any((segment) => segment.length > 1);
}

Alignment _alignmentForCurrentPosition(RunMapViewState state, Size size) {
  final currentPosition = state.displayPosition;
  final transform = _RouteTransform.fromSegments(
    state.acceptedRouteSegments,
    size,
  );
  if (currentPosition == null || transform == null) {
    return Alignment.center;
  }
  return transform.alignmentFor(currentPosition);
}

class _RouteTransform {
  const _RouteTransform({
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

  static _RouteTransform? fromSegments(
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

    return _RouteTransform(
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
      size: size,
    );
  }

  Offset offsetFor(
    RunLocationSample sample, {
    RunLocationSample? followPosition,
  }) {
    final baseOffset = _baseOffsetFor(sample);
    if (followPosition == null) {
      return baseOffset;
    }

    final followOffset = _baseOffsetFor(followPosition);
    final center = Offset(size.width / 2, size.height / 2);
    return baseOffset + (center - followOffset);
  }

  Alignment alignmentFor(RunLocationSample sample) {
    final offset = _baseOffsetFor(sample);
    return Alignment(
      (offset.dx / size.width).clamp(0.0, 1.0) * 2 - 1,
      (offset.dy / size.height).clamp(0.0, 1.0) * 2 - 1,
    );
  }

  Offset _baseOffsetFor(RunLocationSample sample) {
    final normalized = normalizedFor(sample);
    final padding = size.shortestSide * 0.18;
    final drawableWidth = (size.width - padding * 2).clamp(1.0, size.width);
    final drawableHeight = (size.height - padding * 2).clamp(1.0, size.height);
    return Offset(
      padding + drawableWidth * normalized.dx,
      padding + drawableHeight * normalized.dy,
    );
  }

  Offset normalizedFor(RunLocationSample sample) {
    final longitudeRange = maxLongitude - minLongitude;
    final latitudeRange = maxLatitude - minLatitude;
    final x = longitudeRange == 0
        ? 0.5
        : ((sample.longitude - minLongitude) / longitudeRange).clamp(0.0, 1.0);
    final y = latitudeRange == 0
        ? 0.5
        : (1 - (sample.latitude - minLatitude) / latitudeRange).clamp(0.0, 1.0);
    return Offset(x, y);
  }
}
