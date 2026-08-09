import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../domain/models/run_location_sample.dart';
import '../../domain/models/run_map_view_state.dart';
import 'run_map_placeholder.dart';
import 'run_mapbox_follow_qa_overlay.dart';
import 'run_mapbox_geometry.dart';
import 'run_mapbox_surface_config.dart';

const _runnerOrange = Color(0xFFFF6818);
const _routeOrange = Color(0xFFFF7A1A);
const _ornamentLeftMargin = 16.0;
const _ornamentTopMargin = 80.0;
const _logoBelowScaleBarTopMargin = 104.0;
const _attributionRightMargin = 24.0;

/// The live Mapbox map shown while a run is in progress.
///
/// The Mapbox widget owns its own native surface, so this file is mostly about
/// keeping that surface in step with Dart state without fighting it. The work
/// is split into small sync controllers — style-ready, runner marker, camera —
/// each of which waits for the native side to be ready before applying
/// anything; applying too early silently does nothing on a real device.
///
/// Camera follow is released as soon as the user pans and only resumes when
/// they press recenter, so the map never yanks itself back mid-gesture. If no
/// Mapbox token is configured the caller falls back to [RunMapPlaceholder] and
/// run tracking is unaffected.
class RunMapboxRunMap extends StatefulWidget {
  const RunMapboxRunMap({super.key, required this.config});

  final RunMapboxSurfaceConfig config;

  @override
  State<RunMapboxRunMap> createState() => _RunMapboxRunMapState();
}

class _RunMapboxRunMapState extends State<RunMapboxRunMap> {
  late final CameraViewportState _initialViewport = _buildInitialViewport();
  RunMapboxStyleReadySyncController? _syncController;
  bool _styleLoaded = false;
  bool _disposed = false;
  bool _mapboxCameraObserversEnabled = false;

  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(widget.config.accessToken);
  }

  @override
  void didUpdateWidget(covariant RunMapboxRunMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.accessToken != widget.config.accessToken) {
      MapboxOptions.setAccessToken(widget.config.accessToken);
    }
    final shouldAnimateCamera = shouldAnimateRunMapboxCameraSync(
      oldConfig: oldWidget.config,
      newConfig: widget.config,
    );
    unawaited(_syncCurrentMap(animateCamera: shouldAnimateCamera));
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
    await _configureMapboxOrnaments(mapboxMap);
    if (_disposed) {
      return;
    }

    final adapter = RunMapboxNativeMapAdapter(
      mapboxMap,
      followQaDiagnostics: widget.config.followQaDiagnostics,
    );
    _mapboxCameraObserversEnabled =
        widget.config.followQaDiagnostics?.enabled ?? false;
    final controller = RunMapboxStyleReadySyncController(
      RunMapboxSyncCoordinator(adapter),
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

  Future<void> _configureMapboxOrnaments(MapboxMap mapboxMap) async {
    await mapboxMap.scaleBar.updateSettings(runMapboxScaleBarSettings());
    await mapboxMap.logo.updateSettings(runMapboxLogoSettings());
    await mapboxMap.attribution.updateSettings(runMapboxAttributionSettings());
  }

  Future<void> _syncCurrentMap({bool animateCamera = false}) {
    final controller = _syncController;
    if (controller == null) {
      return Future<void>.value();
    }

    final request = RunMapboxSyncRequest(
      mapViewState: widget.config.mapViewState,
      isFollowingRunner: widget.config.isFollowingRunner,
      animateCamera: animateCamera,
    );
    widget.config.followQaDiagnostics?.recordCameraMoveRequest(
      shouldMoveCamera: request.shouldMoveCamera,
      reason: request.cameraMoveReason,
      generation: 0,
    );
    return controller.sync(request);
  }

  void _handleManualGesture(MapContentGestureContext context) {
    widget.config.followQaDiagnostics?.recordMapboxGestureCallback();
    _handleManualMapInteraction();
  }

  void _handleManualMapInteraction() {
    if (widget.config.isFollowingRunner) {
      widget.config.followQaDiagnostics?.recordManualGesture();
      widget.config.onManualPan?.call();
      unawaited(_cancelCameraAnimation().catchError((Object _) {}));
    }
  }

  void _handleCameraChanged(CameraChangedEventData event) {
    if (!_mapboxCameraObserversEnabled) {
      return;
    }
    final center = event.cameraState.center.coordinates;
    widget.config.followQaDiagnostics?.recordCameraStateSample(
      latitude: center.lat.toDouble(),
      longitude: center.lng.toDouble(),
      isFollowingRunner: widget.config.isFollowingRunner,
    );
  }

  Future<void> _cancelCameraAnimation() {
    final controller = _syncController;
    if (controller == null) {
      return Future<void>.value();
    }
    return controller.cancelCameraAnimation();
  }

  void _handleRecenter() {
    widget.config.onRecenter?.call();
    unawaited(_syncCurrentMap(animateCamera: true));
  }

  CameraViewportState _buildInitialViewport() {
    final request = RunMapboxCameraRequest.initialForMapViewState(
      widget.config.mapViewState,
    );
    return CameraViewportState(
      center: Point(
        coordinates: Position(
          request.center.longitude,
          request.center.latitude,
        ),
      ),
      zoom: request.zoom,
      pitch: 0.0,
      bearing: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('run_mapbox_surface'),
      children: [
        Positioned.fill(
          child: RunMapboxManualGestureObserver(
            key: const Key('run_mapbox_pointer_observer'),
            isFollowingRunner: widget.config.isFollowingRunner,
            followQaDiagnostics: widget.config.followQaDiagnostics,
            onManualMapInteraction: _handleManualMapInteraction,
            child: MapWidget(
              key: const Key('run_mapbox_widget'),
              styleUri: MapboxStyles.MAPBOX_STREETS,
              viewport: _initialViewport,
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _handleStyleLoaded,
              onCameraChangeListener: _handleCameraChanged,
              onScrollListener: _handleManualGesture,
              onZoomListener: _handleManualGesture,
            ),
          ),
        ),
        if (widget.config.showRecenterButton &&
            !widget.config.isFollowingRunner &&
            widget.config.onRecenter != null)
          Positioned(
            right: 24,
            bottom: widget.config.recenterButtonBottom,
            child: RunMapRecenterButton(onPressed: _handleRecenter),
          ),
      ],
    );
  }
}

@visibleForTesting
bool shouldAnimateRunMapboxCameraSync({
  required RunMapboxSurfaceConfig oldConfig,
  required RunMapboxSurfaceConfig newConfig,
}) {
  final explicitRecenterRequested =
      oldConfig.recenterRequestId != newConfig.recenterRequestId;
  final followRestored =
      !oldConfig.isFollowingRunner && newConfig.isFollowingRunner;
  final currentPositionBecameAvailable =
      oldConfig.mapViewState.displayPosition == null &&
      newConfig.mapViewState.displayPosition != null;

  return explicitRecenterRequested ||
      followRestored ||
      (currentPositionBecameAvailable && newConfig.isFollowingRunner);
}

@visibleForTesting
class RunMapboxManualGestureObserver extends StatelessWidget {
  const RunMapboxManualGestureObserver({
    super.key,
    required this.isFollowingRunner,
    required this.followQaDiagnostics,
    required this.onManualMapInteraction,
    required this.child,
  });

  final bool isFollowingRunner;
  final RunMapboxFollowQaDiagnostics? followQaDiagnostics;
  final VoidCallback onManualMapInteraction;
  final Widget child;

  void _handlePointerMove(PointerMoveEvent event) {
    followQaDiagnostics?.recordPointerObserverMove();
    if (isFollowingRunner) {
      onManualMapInteraction();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: _handlePointerMove,
      child: child,
    );
  }
}

class RunMapboxStyleReadySyncController {
  RunMapboxStyleReadySyncController(this._coordinator);

  final RunMapboxSyncCoordinator _coordinator;
  RunMapboxSyncRequest? _latestRequest;
  bool _styleLoaded = false;
  bool _disposed = false;

  Future<void> sync(RunMapboxSyncRequest request) {
    if (_disposed) {
      return Future<void>.value();
    }

    _latestRequest = request;
    if (!_styleLoaded) {
      return Future<void>.value();
    }
    return _flushLatest();
  }

  Future<void> markStyleLoaded() {
    if (_disposed) {
      return Future<void>.value();
    }

    _styleLoaded = true;
    return _flushLatest();
  }

  Future<void> cancelCameraAnimation() {
    if (_disposed) {
      return Future<void>.value();
    }
    return _coordinator.cancelCameraAnimation();
  }

  Future<void> dispose() {
    _disposed = true;
    _latestRequest = null;
    return _coordinator.dispose();
  }

  Future<void> _flushLatest() {
    final request = _latestRequest;
    _latestRequest = null;
    if (request == null) {
      return Future<void>.value();
    }
    return _coordinator.sync(request);
  }
}

@visibleForTesting
abstract class RunMapboxRunnerMarkerOperations<T extends Object> {
  Future<T> create(CircleAnnotationOptions options);

  Future<void> update(T marker, CircleAnnotationOptions options);

  Future<void> delete(T marker);
}

@visibleForTesting
class RunMapboxRunnerMarkerSyncController<T extends Object> {
  T? _marker;

  bool get hasMarker => _marker != null;

  Future<void> sync({
    required RunMapViewState mapViewState,
    required RunMapboxRunnerMarkerOperations<T> operations,
  }) async {
    final markerOptions = RunMapboxRunnerMarkerAnnotation.fromViewState(
      mapViewState,
    );
    final existingMarker = _marker;
    if (markerOptions == null) {
      if (existingMarker != null) {
        await operations.delete(existingMarker);
        _marker = null;
      }
      return;
    }

    if (existingMarker == null) {
      _marker = await operations.create(markerOptions);
      return;
    }

    await operations.update(existingMarker, markerOptions);
  }

  void clearReference() {
    _marker = null;
  }
}

class _MapboxRunnerMarkerOperations
    implements RunMapboxRunnerMarkerOperations<CircleAnnotation> {
  const _MapboxRunnerMarkerOperations(this._manager);

  final CircleAnnotationManager _manager;

  @override
  Future<CircleAnnotation> create(CircleAnnotationOptions options) {
    return _manager.create(options);
  }

  @override
  Future<void> update(
    CircleAnnotation marker,
    CircleAnnotationOptions options,
  ) {
    marker.geometry = options.geometry;
    return _manager.update(marker);
  }

  @override
  Future<void> delete(CircleAnnotation marker) {
    return _manager.delete(marker);
  }
}

@visibleForTesting
ScaleBarSettings runMapboxScaleBarSettings() {
  return ScaleBarSettings(
    enabled: true,
    position: OrnamentPosition.TOP_LEFT,
    marginLeft: _ornamentLeftMargin,
    marginTop: _ornamentTopMargin,
  );
}

@visibleForTesting
LogoSettings runMapboxLogoSettings() {
  return LogoSettings(
    enabled: true,
    position: OrnamentPosition.TOP_LEFT,
    marginLeft: _ornamentLeftMargin,
    marginTop: _logoBelowScaleBarTopMargin,
  );
}

@visibleForTesting
AttributionSettings runMapboxAttributionSettings() {
  return AttributionSettings(
    enabled: true,
    clickable: true,
    position: OrnamentPosition.TOP_RIGHT,
    marginTop: _ornamentTopMargin,
    marginRight: _attributionRightMargin,
  );
}

class RunMapboxNativeMapAdapter implements RunMapboxSyncTarget {
  RunMapboxNativeMapAdapter(this._mapboxMap, {this._followQaDiagnostics});

  final MapboxMap _mapboxMap;
  final RunMapboxFollowQaDiagnostics? _followQaDiagnostics;
  final RunMapboxCameraInterruptGate _cameraInterruptGate =
      RunMapboxCameraInterruptGate();
  final RunMapboxRunnerMarkerSyncController<CircleAnnotation>
  _runnerMarkerSync = RunMapboxRunnerMarkerSyncController<CircleAnnotation>();
  CircleAnnotationManager? _runnerManager;
  PolylineAnnotationManager? _routeManager;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  @override
  Future<void> apply(RunMapboxSyncRequest request) async {
    if (_disposed) {
      return;
    }

    final cameraGeneration = _cameraInterruptGate.capture();
    _followQaDiagnostics?.recordCameraMoveRequest(
      shouldMoveCamera: request.shouldMoveCamera,
      reason: request.cameraMoveReason,
      generation: cameraGeneration,
    );
    await _ensureAnnotationManagers();
    if (_disposed) {
      return;
    }

    await _syncRouteSegments(request.mapViewState);
    _followQaDiagnostics?.recordRouteSync(
      isFollowingRunner: request.isFollowingRunner,
    );
    if (_disposed) {
      return;
    }

    await _syncRunnerMarker(request.mapViewState);
    _followQaDiagnostics?.recordMarkerSync(
      isFollowingRunner: request.isFollowingRunner,
    );
    if (!_disposed &&
        request.shouldMoveCamera &&
        _cameraInterruptGate.allows(cameraGeneration)) {
      _followQaDiagnostics?.recordCameraMove(
        shouldMoveCamera: request.shouldMoveCamera,
        generation: cameraGeneration,
      );
      await _moveCamera(request.mapViewState, animated: request.animateCamera);
      return;
    }
    _followQaDiagnostics?.recordCameraMoveSkipped(
      shouldMoveCamera: request.shouldMoveCamera,
      generation: cameraGeneration,
      isFollowingRunner: request.isFollowingRunner,
    );
  }

  @override
  Future<void> cancelCameraAnimation() async {
    if (_disposed) {
      return Future<void>.value();
    }
    final interruptGeneration = _cameraInterruptGate.interrupt();
    await _mapboxMap.cancelCameraAnimation();
    _followQaDiagnostics?.recordCameraCancel(
      interruptGeneration: interruptGeneration,
    );
  }

  @override
  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    _disposed = true;
    final runnerManager = _runnerManager;
    final routeManager = _routeManager;
    _runnerMarkerSync.clearReference();
    _runnerManager = null;
    _routeManager = null;

    if (runnerManager != null) {
      await runnerManager.deleteAll();
      await _mapboxMap.annotations.removeAnnotationManager(runnerManager);
    }
    if (routeManager != null) {
      await routeManager.deleteAll();
      await _mapboxMap.annotations.removeAnnotationManager(routeManager);
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
    _runnerManager ??= await _mapboxMap.annotations
        .createCircleAnnotationManager();
  }

  Future<void> _syncRunnerMarker(RunMapViewState mapViewState) async {
    final runnerManager = _runnerManager;
    if (runnerManager == null) {
      return;
    }

    await _runnerMarkerSync.sync(
      mapViewState: mapViewState,
      operations: _MapboxRunnerMarkerOperations(runnerManager),
    );
  }

  Future<void> _syncRouteSegments(RunMapViewState mapViewState) async {
    final routeManager = _routeManager;
    if (routeManager == null) {
      return;
    }

    await routeManager.deleteAll();
    final geometry = RunMapboxRouteGeometry.fromViewState(mapViewState);
    if (!geometry.hasRoute) {
      return;
    }

    await routeManager.createMulti(
      geometry.segments
          .map(
            (segment) => PolylineAnnotationOptions(
              geometry: LineString(
                coordinates: segment
                    .map((point) => Position(point.longitude, point.latitude))
                    .toList(growable: false),
              ),
              lineColor: _routeOrange.toARGB32(),
              lineWidth: 6,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _moveCamera(
    RunMapViewState mapViewState, {
    required bool animated,
  }) async {
    final request = RunMapboxCameraRequest.forCurrentPosition(mapViewState);
    if (request == null) {
      return;
    }

    final camera = CameraOptions(
      center: Point(
        coordinates: Position(
          request.center.longitude,
          request.center.latitude,
        ),
      ),
      zoom: request.zoom,
      pitch: 0,
      bearing: 0,
    );
    if (animated) {
      await _mapboxMap.easeTo(
        camera,
        MapAnimationOptions(duration: request.animationDuration.inMilliseconds),
      );
      return;
    }
    await _mapboxMap.setCamera(camera);
  }
}

class RunMapboxRunnerMarkerAnnotation {
  static CircleAnnotationOptions? fromViewState(RunMapViewState mapViewState) {
    final currentPosition = mapViewState.displayPosition;
    if (currentPosition == null) {
      return null;
    }
    return fromSample(currentPosition);
  }

  static CircleAnnotationOptions fromSample(RunLocationSample currentPosition) {
    final coordinate = RunMapboxCoordinate.fromSample(currentPosition);
    return CircleAnnotationOptions(
      geometry: Point(
        coordinates: Position(coordinate.longitude, coordinate.latitude),
      ),
      circleSortKey: 1000,
      circleColor: _runnerOrange.toARGB32(),
      circleRadius: 12,
      circleStrokeColor: Colors.white.toARGB32(),
      circleStrokeWidth: 4,
    );
  }
}
