import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../run/domain/models/run_location_sample.dart';
import '../../../run/domain/models/run_route_snapshot.dart';
import 'activity_route_thumbnail_viewport.dart';

class ActivityRoutePreview extends StatelessWidget {
  const ActivityRoutePreview({
    required this.route,
    this.thumbnailProvider = const NoopActivityRouteThumbnailProvider(),
    this.allowExternalStaticMap = false,
    this.isDemoRoute = false,
    this.isCurrentSessionRoute = false,
    this.isTrustedPersistedRoutePreview = false,
    this.activityId,
    super.key,
  });

  final RunRouteSnapshot route;
  final ActivityRouteThumbnailProvider thumbnailProvider;
  final bool allowExternalStaticMap;
  final bool isDemoRoute;
  final bool isCurrentSessionRoute;
  final bool isTrustedPersistedRoutePreview;
  final String? activityId;

  @override
  Widget build(BuildContext context) {
    const logicalSize = Size(_previewSlotSize, _previewSlotSize);
    final viewport = ActivityRouteThumbnailViewport.fromRoute(
      route,
      logicalSize: logicalSize,
    );
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final thumbnailRequest = ActivityRouteThumbnailRequest(
      route: route,
      logicalSize: logicalSize,
      devicePixelRatio: devicePixelRatio,
      allowExternalStaticMap: allowExternalStaticMap,
      isDemoRoute: isDemoRoute,
      isCurrentSessionRoute: isCurrentSessionRoute,
      isTrustedPersistedRoutePreview: isTrustedPersistedRoutePreview,
      activityId: activityId,
    );

    final canRequestLocationSnapshot = _canRequestLocationSnapshot(viewport);

    return ClipRRect(
      key: const ValueKey('activity_route_preview_slot'),
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: _previewSlotSize,
        height: _previewSlotSize,
        child: switch (viewport.mode) {
          ActivityRouteThumbnailViewportMode.meaningfulRoute =>
            _RoutePreviewSnapshotSlot(
              route: route,
              viewport: viewport,
              thumbnailProvider: thumbnailProvider,
              thumbnailRequest: thumbnailRequest,
              overlayMode: _RoutePreviewOverlayMode.route,
            ),
          ActivityRouteThumbnailViewportMode.tinyRoute =>
            canRequestLocationSnapshot
                ? _RoutePreviewSnapshotSlot(
                    route: route,
                    viewport: viewport,
                    thumbnailProvider: thumbnailProvider,
                    thumbnailRequest: thumbnailRequest,
                    overlayMode: _RoutePreviewOverlayMode.location,
                  )
                : Semantics(
                    label: 'Tiny route preview',
                    child: CustomPaint(
                      key: const ValueKey('activity_route_preview_tiny_route'),
                      painter: _TinyRoutePreviewPainter(route),
                    ),
                  ),
          ActivityRouteThumbnailViewportMode.noRoute =>
            canRequestLocationSnapshot
                ? _RoutePreviewSnapshotSlot(
                    route: route,
                    viewport: viewport,
                    thumbnailProvider: thumbnailProvider,
                    thumbnailRequest: thumbnailRequest,
                    overlayMode: _RoutePreviewOverlayMode.location,
                  )
                : Semantics(
                    label: 'Route preview unavailable',
                    child: const CustomPaint(
                      key: ValueKey('activity_route_preview_fallback'),
                      painter: _FallbackRoutePreviewPainter(),
                    ),
                  ),
        },
      ),
    );
  }

  bool _canRequestLocationSnapshot(ActivityRouteThumbnailViewport viewport) {
    return allowExternalStaticMap &&
        (isCurrentSessionRoute || isTrustedPersistedRoutePreview) &&
        viewport.hasKnownLocation;
  }
}

abstract interface class ActivityRouteThumbnailProvider {
  Future<ActivityRouteThumbnailResult> resolve(
    ActivityRouteThumbnailRequest request,
  );
}

class ActivityRouteThumbnailRequest {
  const ActivityRouteThumbnailRequest({
    required this.route,
    required this.logicalSize,
    required this.devicePixelRatio,
    required this.allowExternalStaticMap,
    required this.isDemoRoute,
    this.isCurrentSessionRoute = false,
    this.isTrustedPersistedRoutePreview = false,
    this.activityId,
  });

  final RunRouteSnapshot route;
  final Size logicalSize;
  final double devicePixelRatio;
  final bool allowExternalStaticMap;
  final bool isDemoRoute;
  final bool isCurrentSessionRoute;
  final bool isTrustedPersistedRoutePreview;
  final String? activityId;

  /// The nearest backend-approved image scale; an exact midpoint rounds up.
  int get canonicalDevicePixelRatio =>
      canonicalActivityRouteThumbnailScale(devicePixelRatio);

  @override
  bool operator ==(Object other) {
    return other is ActivityRouteThumbnailRequest &&
        other.route == route &&
        other.logicalSize == logicalSize &&
        other.devicePixelRatio == devicePixelRatio &&
        other.allowExternalStaticMap == allowExternalStaticMap &&
        other.isDemoRoute == isDemoRoute &&
        other.isCurrentSessionRoute == isCurrentSessionRoute &&
        other.isTrustedPersistedRoutePreview ==
            isTrustedPersistedRoutePreview &&
        other.activityId == activityId;
  }

  @override
  int get hashCode {
    return Object.hash(
      route,
      logicalSize,
      devicePixelRatio,
      allowExternalStaticMap,
      isDemoRoute,
      isCurrentSessionRoute,
      isTrustedPersistedRoutePreview,
      activityId,
    );
  }
}

int canonicalActivityRouteThumbnailScale(double devicePixelRatio) {
  if (!devicePixelRatio.isFinite || devicePixelRatio < 1.5) {
    return 1;
  }
  if (devicePixelRatio < 2.5) {
    return 2;
  }
  return 3;
}

enum ActivityRouteThumbnailState {
  readyImage,
  loading,
  privacyDisabled,
  tokenMissing,
  requestFailed,
  timedOut,
  unavailable,
}

class ActivityRouteThumbnailResult {
  const ActivityRouteThumbnailResult._(
    this.state, {
    this.imageProvider,
    this.pngBytes,
  });

  const ActivityRouteThumbnailResult.readyImage(ImageProvider imageProvider)
    : this._(
        ActivityRouteThumbnailState.readyImage,
        imageProvider: imageProvider,
      );

  ActivityRouteThumbnailResult.readyPng(Uint8List bytes)
    : this._(
        ActivityRouteThumbnailState.readyImage,
        imageProvider: MemoryImage(bytes),
        pngBytes: bytes,
      );

  const ActivityRouteThumbnailResult.loading()
    : this._(ActivityRouteThumbnailState.loading);

  const ActivityRouteThumbnailResult.privacyDisabled()
    : this._(ActivityRouteThumbnailState.privacyDisabled);

  const ActivityRouteThumbnailResult.tokenMissing()
    : this._(ActivityRouteThumbnailState.tokenMissing);

  const ActivityRouteThumbnailResult.requestFailed()
    : this._(ActivityRouteThumbnailState.requestFailed);

  const ActivityRouteThumbnailResult.timedOut()
    : this._(ActivityRouteThumbnailState.timedOut);

  const ActivityRouteThumbnailResult.unavailable()
    : this._(ActivityRouteThumbnailState.unavailable);

  final ActivityRouteThumbnailState state;
  final ImageProvider? imageProvider;
  final Uint8List? pngBytes;

  bool get hasReadyImage {
    return state == ActivityRouteThumbnailState.readyImage &&
        imageProvider != null;
  }

  @override
  bool operator ==(Object other) {
    return other is ActivityRouteThumbnailResult &&
        other.state == state &&
        other.imageProvider == imageProvider;
  }

  @override
  int get hashCode => Object.hash(state, imageProvider);
}

class NoopActivityRouteThumbnailProvider
    implements ActivityRouteThumbnailProvider {
  const NoopActivityRouteThumbnailProvider();

  @override
  Future<ActivityRouteThumbnailResult> resolve(
    ActivityRouteThumbnailRequest request,
  ) async {
    if (!request.allowExternalStaticMap) {
      return const ActivityRouteThumbnailResult.privacyDisabled();
    }
    return const ActivityRouteThumbnailResult.unavailable();
  }
}

class _RoutePreviewSnapshotSlot extends StatefulWidget {
  const _RoutePreviewSnapshotSlot({
    required this.route,
    required this.viewport,
    required this.thumbnailProvider,
    required this.thumbnailRequest,
    required this.overlayMode,
  });

  final RunRouteSnapshot route;
  final ActivityRouteThumbnailViewport viewport;
  final ActivityRouteThumbnailProvider thumbnailProvider;
  final ActivityRouteThumbnailRequest thumbnailRequest;
  final _RoutePreviewOverlayMode overlayMode;

  @override
  State<_RoutePreviewSnapshotSlot> createState() =>
      _RoutePreviewSnapshotSlotState();
}

class _RoutePreviewSnapshotSlotState extends State<_RoutePreviewSnapshotSlot> {
  late Future<ActivityRouteThumbnailResult> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = widget.thumbnailProvider.resolve(
      widget.thumbnailRequest,
    );
  }

  @override
  void didUpdateWidget(covariant _RoutePreviewSnapshotSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailProvider != widget.thumbnailProvider ||
        oldWidget.thumbnailRequest != widget.thumbnailRequest) {
      _thumbnailFuture = widget.thumbnailProvider.resolve(
        widget.thumbnailRequest,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ActivityRouteThumbnailResult>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        final thumbnailResult =
            snapshot.data ?? const ActivityRouteThumbnailResult.loading();
        final imageProvider = thumbnailResult.imageProvider;
        if (thumbnailResult.hasReadyImage && imageProvider != null) {
          return Semantics(
            label: 'Static route map thumbnail',
            image: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(
                  key: const ValueKey(
                    'activity_route_preview_static_thumbnail',
                  ),
                  image: imageProvider,
                  fit: BoxFit.cover,
                ),
                switch (widget.overlayMode) {
                  _RoutePreviewOverlayMode.route => CustomPaint(
                    key: const ValueKey(
                      'activity_route_preview_static_thumbnail_route_overlay',
                    ),
                    painter: _RoutePolylinePreviewPainter(
                      widget.route,
                      viewport: widget.viewport,
                      paintBackdrop: false,
                    ),
                  ),
                  _RoutePreviewOverlayMode.location => const CustomPaint(
                    key: ValueKey(
                      'activity_route_preview_static_thumbnail_location_dot',
                    ),
                    painter: _LocationDotPreviewPainter(),
                  ),
                },
              ],
            ),
          );
        }

        return Semantics(
          label: 'Route-backed activity preview',
          child: CustomPaint(
            key: widget.overlayMode == _RoutePreviewOverlayMode.route
                ? const ValueKey('activity_route_preview_polyline')
                : const ValueKey('activity_route_preview_tiny_route'),
            painter: widget.overlayMode == _RoutePreviewOverlayMode.route
                ? _RoutePolylinePreviewPainter(
                    widget.route,
                    viewport: widget.viewport,
                  )
                : _TinyRoutePreviewPainter(widget.route),
          ),
        );
      },
    );
  }
}

enum _RoutePreviewOverlayMode { route, location }

class _FallbackRoutePreviewPainter extends CustomPainter {
  const _FallbackRoutePreviewPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _paintPreviewBackdrop(canvas, size);
    _paintPreviewGrid(canvas, size);

    final center = Offset(size.width * 0.5, size.height * 0.52);
    final outerPaint = Paint()
      ..color = const Color(0x247D93E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final innerPaint = Paint()
      ..color = const Color(0x1A7D93E1)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 9, outerPaint);
    canvas.drawCircle(center, 3.5, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _FallbackRoutePreviewPainter oldDelegate) {
    return false;
  }
}

class _TinyRoutePreviewPainter extends CustomPainter {
  const _TinyRoutePreviewPainter(this.route);

  final RunRouteSnapshot route;

  @override
  void paint(Canvas canvas, Size size) {
    _paintPreviewBackdrop(canvas, size);
    _paintPreviewGrid(canvas, size);

    final center = Offset(size.width * 0.5, size.height * 0.5);

    final haloPaint = Paint()
      ..color = const Color(0x2E2F50C7)
      ..style = PaintingStyle.fill;
    final dotPaint = Paint()..color = RuniacColors.primaryBlue;
    final ringPaint = Paint()
      ..color = RuniacColors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, 10, haloPaint);
    canvas.drawCircle(center, 5.5, dotPaint);
    canvas.drawCircle(center, 5.5, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _TinyRoutePreviewPainter oldDelegate) {
    return oldDelegate.route != route;
  }
}

class _LocationDotPreviewPainter extends CustomPainter {
  const _LocationDotPreviewPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final haloPaint = Paint()
      ..color = const Color(0x66304BB7)
      ..style = PaintingStyle.fill;
    final dotPaint = Paint()
      ..color = _runnerOrange
      ..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..color = RuniacColors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, 12, haloPaint);
    canvas.drawCircle(center, 7, dotPaint);
    canvas.drawCircle(center, 7, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _LocationDotPreviewPainter oldDelegate) {
    return false;
  }
}

class _RoutePolylinePreviewPainter extends CustomPainter {
  const _RoutePolylinePreviewPainter(
    this.route, {
    required this.viewport,
    this.paintBackdrop = true,
  });

  final RunRouteSnapshot route;
  final ActivityRouteThumbnailViewport viewport;
  final bool paintBackdrop;

  @override
  void paint(Canvas canvas, Size size) {
    if (paintBackdrop) {
      _paintPreviewBackdrop(canvas, size);
      _paintPreviewGrid(canvas, size);
    }

    if (viewport.mode != ActivityRouteThumbnailViewportMode.meaningfulRoute) {
      if (paintBackdrop) {
        const _FallbackRoutePreviewPainter().paint(canvas, size);
      }
      return;
    }

    final pathPaint = _routePathPaint(RuniacColors.primaryBlue, 3);
    for (final segment in route.segments) {
      final segmentPath = _pathForSegment(segment, viewport);
      if (segmentPath != null) {
        canvas.drawPath(segmentPath, pathPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePolylinePreviewPainter oldDelegate) {
    return oldDelegate.route != route ||
        oldDelegate.viewport != viewport ||
        oldDelegate.paintBackdrop != paintBackdrop;
  }
}

Path? _pathForSegment(
  List<RunLocationSample> segment,
  ActivityRouteThumbnailViewport viewport,
) {
  final points = segment.where(_isDrawableRoutePoint).toList(growable: false);
  if (points.length < 2) {
    return null;
  }

  final start = viewport.project(points.first);
  final path = Path()..moveTo(start.dx, start.dy);
  for (final point in points.skip(1)) {
    final projected = viewport.project(point);
    path.lineTo(projected.dx, projected.dy);
  }

  return path;
}

bool _isDrawableRoutePoint(RunLocationSample point) {
  return point.latitude.isFinite && point.longitude.isFinite;
}

void _paintPreviewBackdrop(Canvas canvas, Size size) {
  final backdropPaint = Paint()..color = const Color(0xFFF8FAFF);
  canvas.drawRect(Offset.zero & size, backdropPaint);
}

void _paintPreviewGrid(Canvas canvas, Size size) {
  final gridPaint = Paint()
    ..color = const Color(0x0F2F50C7)
    ..strokeWidth = 1;

  canvas.drawLine(
    Offset(size.width * 0.32, 0),
    Offset(size.width * 0.32, size.height),
    gridPaint,
  );
  canvas.drawLine(
    Offset(size.width * 0.68, 0),
    Offset(size.width * 0.68, size.height),
    gridPaint,
  );
  canvas.drawLine(
    Offset(0, size.height * 0.45),
    Offset(size.width, size.height * 0.45),
    gridPaint,
  );
}

Paint _routePathPaint(Color color, double strokeWidth) {
  return Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
}

const _previewSlotSize = 88.0;
const _runnerOrange = Color(0xFFFF6818);
