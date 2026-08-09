import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Visibility;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../domain/models/run_location_sample.dart';
import '../../domain/models/run_map_view_state.dart';
import '../../domain/models/run_route_snapshot.dart';
import 'mapbox_runtime_config.dart';
import 'run_mapbox_geometry.dart';
import 'run_mapbox_run_map.dart';

const _ornamentLeftMargin = 16.0;
const _ornamentTopMargin = 80.0;
const _logoBelowScaleBarTopMargin = 104.0;
const _attributionRightMargin = 24.0;
const _previewOrnamentLeftMargin = 10.0;
const _previewOrnamentTopMargin = 10.0;
const _previewLogoBelowScaleBarTopMargin = 32.0;
const _previewAttributionRightMargin = 10.0;

typedef CompletedRouteMapboxBuilder =
    Widget Function(
      BuildContext context,
      CompletedRouteMapboxSurfaceConfig config,
    );

class CompletedRouteMapboxSurfaceConfig {
  const CompletedRouteMapboxSurfaceConfig({
    required this.accessToken,
    required this.route,
    required this.isExpanded,
  });

  final String accessToken;
  final RunRouteSnapshot route;
  final bool isExpanded;
}

/// Draws the finished route of a completed run — used by the summary, the
/// activity history and the share card.
///
/// The live map ([RunMapboxRunMap]) follows a moving point; this one has the
/// whole route up front and must frame it, so the camera is fitted to the
/// route's bounds with padding rather than centred on a position. There is no
/// follow mode and no gesture handling to unwind.
///
/// Sharing renders this same surface off-screen, which is why the camera fit is
/// a pure function of the route and viewport: the share image has to match what
/// the runner saw.
class CompletedRouteMapSurface extends StatelessWidget {
  const CompletedRouteMapSurface({
    super.key,
    required this.route,
    required this.fallback,
    this.mapboxAccessToken,
    this.mapboxBuilder,
    this.isExpanded = false,
  });

  final RunRouteSnapshot route;
  final Widget fallback;
  final String? mapboxAccessToken;
  final CompletedRouteMapboxBuilder? mapboxBuilder;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    if (!route.hasRoute && !route.hasLocation) {
      return fallback;
    }

    final runtimeConfig = mapboxAccessToken == null
        ? MapboxRuntimeConfig.fromEnvironment()
        : MapboxRuntimeConfig(accessToken: mapboxAccessToken!.trim());
    if (runtimeConfig.accessToken.isEmpty ||
        !runtimeConfig.hasPublicAccessToken) {
      return fallback;
    }

    final config = CompletedRouteMapboxSurfaceConfig(
      accessToken: runtimeConfig.accessToken,
      route: route,
      isExpanded: isExpanded,
    );
    final builder = mapboxBuilder ?? _defaultCompletedRouteMapboxBuilder;

    return KeyedSubtree(
      key: Key(
        isExpanded
            ? 'summary_route_mapbox_expanded_selected'
            : 'summary_route_mapbox_preview_selected',
      ),
      child: builder(context, config),
    );
  }
}

Widget _defaultCompletedRouteMapboxBuilder(
  BuildContext context,
  CompletedRouteMapboxSurfaceConfig config,
) {
  return CompletedRouteMapboxMap(config: config);
}

@visibleForTesting
class CompletedRouteMapboxCamera {
  const CompletedRouteMapboxCamera({required this.center, required this.zoom});

  factory CompletedRouteMapboxCamera.fromRoute(RunRouteSnapshot route) {
    final points = route.hasRoute
        ? route.segments.expand((segment) => segment).toList(growable: false)
        : <RunLocationSample>[
            if (route.lastKnownLocation != null) route.lastKnownLocation!,
          ];

    if (points.isEmpty) {
      return const CompletedRouteMapboxCamera(
        center: RunRouteMapboxPoint(latitude: 1.300899, longitude: 103.800000),
        zoom: 14,
      );
    }

    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      minLatitude = math.min(minLatitude, point.latitude);
      maxLatitude = math.max(maxLatitude, point.latitude);
      minLongitude = math.min(minLongitude, point.longitude);
      maxLongitude = math.max(maxLongitude, point.longitude);
    }

    final centerLatitude = (minLatitude + maxLatitude) / 2;
    final centerLongitude = (minLongitude + maxLongitude) / 2;
    final latitudeSpan = (maxLatitude - minLatitude).abs();
    final longitudeSpan = (maxLongitude - minLongitude).abs();

    if (!route.hasRoute || math.max(latitudeSpan, longitudeSpan) < 0.00018) {
      return CompletedRouteMapboxCamera(
        center: RunRouteMapboxPoint(
          latitude: centerLatitude,
          longitude: centerLongitude,
        ),
        zoom: 17.2,
      );
    }

    final adjustedLongitudeSpan =
        longitudeSpan * math.cos(centerLatitude * math.pi / 180).abs();
    final routeSpan = math.max(latitudeSpan, adjustedLongitudeSpan);
    final paddedSpan = math.max(routeSpan * 1.55, 0.00018);
    final zoom = (math.log(360 / paddedSpan) / math.ln2).clamp(11.5, 17.2);

    return CompletedRouteMapboxCamera(
      center: RunRouteMapboxPoint(
        latitude: centerLatitude,
        longitude: centerLongitude,
      ),
      zoom: zoom.toDouble(),
    );
  }

  final RunRouteMapboxPoint center;
  final double zoom;
}

@visibleForTesting
class RunRouteMapboxPoint {
  const RunRouteMapboxPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class CompletedRouteMapboxMap extends StatefulWidget {
  const CompletedRouteMapboxMap({super.key, required this.config});

  final CompletedRouteMapboxSurfaceConfig config;

  @override
  State<CompletedRouteMapboxMap> createState() =>
      _CompletedRouteMapboxMapState();
}

class _CompletedRouteMapboxMapState extends State<CompletedRouteMapboxMap> {
  late final CameraViewportState _initialViewport = _buildInitialViewport();
  RunMapboxStyleReadySyncController? _syncController;
  bool _styleLoaded = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(widget.config.accessToken);
  }

  @override
  void didUpdateWidget(covariant CompletedRouteMapboxMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.accessToken != widget.config.accessToken) {
      MapboxOptions.setAccessToken(widget.config.accessToken);
    }
    unawaited(_syncCurrentMap());
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _syncController;
    _syncController = null;
    if (controller != null) {
      unawaited(controller.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    await _configureMapbox(mapboxMap);
    if (_disposed) {
      return;
    }

    final controller = RunMapboxStyleReadySyncController(
      RunMapboxSyncCoordinator(_CompletedRouteMapboxAdapter(mapboxMap)),
    );
    if (_disposed) {
      await controller.dispose();
      return;
    }

    _syncController = controller;
    if (_styleLoaded) {
      await controller.markStyleLoaded();
    }
    await _syncCurrentMap();
  }

  void _handleStyleLoaded(StyleLoadedEventData event) {
    _styleLoaded = true;
    final controller = _syncController;
    if (controller != null) {
      unawaited(controller.markStyleLoaded());
    }
  }

  Future<void> _configureMapbox(MapboxMap mapboxMap) async {
    await mapboxMap.scaleBar.updateSettings(
      completedRouteScaleBarSettings(isExpanded: widget.config.isExpanded),
    );
    await mapboxMap.logo.updateSettings(
      completedRouteLogoSettings(isExpanded: widget.config.isExpanded),
    );
    await mapboxMap.attribution.updateSettings(
      completedRouteAttributionSettings(isExpanded: widget.config.isExpanded),
    );
    if (!widget.config.isExpanded) {
      await mapboxMap.gestures.updateSettings(
        GesturesSettings(
          scrollEnabled: false,
          pinchToZoomEnabled: false,
          rotateEnabled: false,
          pitchEnabled: false,
          doubleTapToZoomInEnabled: false,
          doubleTouchToZoomOutEnabled: false,
          quickZoomEnabled: false,
          pinchPanEnabled: false,
        ),
      );
    }
  }

  Future<void> _syncCurrentMap() {
    final controller = _syncController;
    if (controller == null) {
      return Future<void>.value();
    }
    return controller.sync(
      _CompletedRouteMapboxSyncRequest(route: widget.config.route),
    );
  }

  CameraViewportState _buildInitialViewport() {
    final camera = CompletedRouteMapboxCamera.fromRoute(widget.config.route);
    return CameraViewportState(
      center: Point(
        coordinates: Position(camera.center.longitude, camera.center.latitude),
      ),
      zoom: camera.zoom,
      pitch: 0,
      bearing: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MapWidget(
      key: Key(
        widget.config.isExpanded
            ? 'summary_route_mapbox_expanded_widget'
            : 'summary_route_mapbox_preview_widget',
      ),
      styleUri: MapboxStyles.MAPBOX_STREETS,
      viewport: _initialViewport,
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: _handleStyleLoaded,
    );
  }
}

@visibleForTesting
ScaleBarSettings completedRouteScaleBarSettings({required bool isExpanded}) {
  return ScaleBarSettings(
    enabled: true,
    position: OrnamentPosition.TOP_LEFT,
    marginLeft: isExpanded ? _ornamentLeftMargin : _previewOrnamentLeftMargin,
    marginTop: isExpanded ? _ornamentTopMargin : _previewOrnamentTopMargin,
  );
}

@visibleForTesting
LogoSettings completedRouteLogoSettings({required bool isExpanded}) {
  return LogoSettings(
    enabled: true,
    position: OrnamentPosition.TOP_LEFT,
    marginLeft: isExpanded ? _ornamentLeftMargin : _previewOrnamentLeftMargin,
    marginTop: isExpanded
        ? _logoBelowScaleBarTopMargin
        : _previewLogoBelowScaleBarTopMargin,
  );
}

@visibleForTesting
AttributionSettings completedRouteAttributionSettings({
  required bool isExpanded,
}) {
  return AttributionSettings(
    enabled: true,
    clickable: true,
    position: OrnamentPosition.TOP_RIGHT,
    marginTop: isExpanded ? _ornamentTopMargin : _previewOrnamentTopMargin,
    marginRight: isExpanded
        ? _attributionRightMargin
        : _previewAttributionRightMargin,
  );
}

class _CompletedRouteMapboxSyncRequest extends RunMapboxSyncRequest {
  const _CompletedRouteMapboxSyncRequest({required this.route})
    : super(
        mapViewState: const RunMapViewState.empty(),
        isFollowingRunner: false,
      );

  final RunRouteSnapshot route;

  @override
  bool get shouldMoveCamera => true;
}

class _CompletedRouteMapboxAdapter implements RunMapboxSyncTarget {
  _CompletedRouteMapboxAdapter(this._mapboxMap);

  final MapboxMap _mapboxMap;
  PolylineAnnotationManager? _routeManager;
  CircleAnnotationManager? _dotManager;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  @override
  Future<void> apply(RunMapboxSyncRequest request) async {
    if (_disposed || request is! _CompletedRouteMapboxSyncRequest) {
      return;
    }

    await _ensureAnnotationManagers();
    if (_disposed) {
      return;
    }

    await _syncRoute(request.route);
    await _syncDots(request.route);
    await _moveCamera(request.route);
  }

  @override
  Future<void> cancelCameraAnimation() async {
    if (_disposed) {
      return;
    }
    await _mapboxMap.cancelCameraAnimation();
  }

  @override
  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    _disposed = true;
    final routeManager = _routeManager;
    final dotManager = _dotManager;
    _routeManager = null;
    _dotManager = null;

    if (routeManager != null) {
      await routeManager.deleteAll();
      await _mapboxMap.annotations.removeAnnotationManager(routeManager);
    }
    if (dotManager != null) {
      await dotManager.deleteAll();
      await _mapboxMap.annotations.removeAnnotationManager(dotManager);
    }
  }

  Future<void> _ensureAnnotationManagers() async {
    if (_routeManager == null) {
      final routeManager = await _mapboxMap.annotations
          .createPolylineAnnotationManager();
      await routeManager.setLineCap(LineCap.ROUND);
      await routeManager.setLineJoin(LineJoin.ROUND);
      _routeManager = routeManager;
    }
    _dotManager ??= await _mapboxMap.annotations
        .createCircleAnnotationManager();
  }

  Future<void> _syncRoute(RunRouteSnapshot route) async {
    final routeManager = _routeManager;
    if (routeManager == null) {
      return;
    }
    await routeManager.deleteAll();
    if (!route.hasRoute) {
      return;
    }

    final segments = route.segments.where((segment) => segment.length > 1);
    await routeManager.createMulti(
      segments
          .map(
            (segment) => PolylineAnnotationOptions(
              geometry: LineString(
                coordinates: segment
                    .map((point) => Position(point.longitude, point.latitude))
                    .toList(growable: false),
              ),
              lineColor: const Color(0xFFFF7A1A).toARGB32(),
              lineWidth: 5.5,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _syncDots(RunRouteSnapshot route) async {
    final dotManager = _dotManager;
    if (dotManager == null) {
      return;
    }
    await dotManager.deleteAll();

    if (route.hasRoute) {
      final first = _firstRoutePoint(route);
      final last = _lastRoutePoint(route);
      if (first == null || last == null) {
        return;
      }
      await dotManager.createMulti([
        _dotOptions(first, color: const Color(0xFF2F51C8), radius: 6),
        _dotOptions(last, color: const Color(0xFFFF6818), radius: 7),
      ]);
      return;
    }

    final location = route.lastKnownLocation;
    if (location == null) {
      return;
    }
    await dotManager.create(
      _dotOptions(location, color: const Color(0xFFFF6818), radius: 9),
    );
  }

  Future<void> _moveCamera(RunRouteSnapshot route) async {
    final camera = CompletedRouteMapboxCamera.fromRoute(route);
    await _mapboxMap.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(
            camera.center.longitude,
            camera.center.latitude,
          ),
        ),
        zoom: camera.zoom,
        pitch: 0,
        bearing: 0,
      ),
    );
  }

  CircleAnnotationOptions _dotOptions(
    RunLocationSample sample, {
    required Color color,
    required double radius,
  }) {
    return CircleAnnotationOptions(
      geometry: Point(coordinates: Position(sample.longitude, sample.latitude)),
      circleSortKey: 1000,
      circleColor: color.toARGB32(),
      circleRadius: radius,
      circleStrokeColor: Colors.white.toARGB32(),
      circleStrokeWidth: 3,
    );
  }

  RunLocationSample? _firstRoutePoint(RunRouteSnapshot route) {
    for (final segment in route.segments) {
      if (segment.isNotEmpty) {
        return segment.first;
      }
    }
    return null;
  }

  RunLocationSample? _lastRoutePoint(RunRouteSnapshot route) {
    for (final segment in route.segments.reversed) {
      if (segment.isNotEmpty) {
        return segment.last;
      }
    }
    return route.lastKnownLocation;
  }
}
