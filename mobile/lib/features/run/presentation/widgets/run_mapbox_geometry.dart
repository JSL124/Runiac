import '../../domain/models/run_location_sample.dart';
import '../../domain/models/run_map_view_state.dart';

class RunMapboxCoordinate {
  const RunMapboxCoordinate({required this.latitude, required this.longitude});

  factory RunMapboxCoordinate.fromSample(RunLocationSample sample) {
    return RunMapboxCoordinate(
      latitude: sample.latitude,
      longitude: sample.longitude,
    );
  }

  final double latitude;
  final double longitude;

  List<double> get position => <double>[longitude, latitude];
}

class RunMapboxRouteGeometry {
  const RunMapboxRouteGeometry({required this.segments});

  factory RunMapboxRouteGeometry.fromViewState(RunMapViewState viewState) {
    return RunMapboxRouteGeometry(
      segments: viewState.displayRouteSegments
          .where((segment) => segment.length > 1)
          .map(
            (segment) => segment
                .map(RunMapboxCoordinate.fromSample)
                .toList(growable: false),
          )
          .toList(growable: false),
    );
  }

  final List<List<RunMapboxCoordinate>> segments;

  bool get hasRoute => segments.isNotEmpty;
}

class RunMapboxCameraRequest {
  const RunMapboxCameraRequest({
    required this.center,
    this.zoom = 16,
    this.animationDuration = const Duration(milliseconds: 450),
  });

  static const RunMapboxCoordinate fallbackCenter = RunMapboxCoordinate(
    latitude: 1.300899,
    longitude: 103.800000,
  );

  static RunMapboxCameraRequest? forCurrentPosition(RunMapViewState viewState) {
    final currentPosition = viewState.displayPosition;
    if (currentPosition == null) {
      return null;
    }

    return RunMapboxCameraRequest(
      center: RunMapboxCoordinate.fromSample(currentPosition),
    );
  }

  static RunMapboxCameraRequest initialForMapViewState(
    RunMapViewState viewState,
  ) {
    return forCurrentPosition(viewState) ??
        const RunMapboxCameraRequest(center: fallbackCenter, zoom: 14);
  }

  final RunMapboxCoordinate center;
  final double zoom;
  final Duration animationDuration;
}

class RunMapboxSyncRequest {
  const RunMapboxSyncRequest({
    required this.mapViewState,
    required this.isFollowingRunner,
    this.animateCamera = false,
  });

  final RunMapViewState mapViewState;
  final bool isFollowingRunner;
  final bool animateCamera;

  bool get shouldMoveCamera => isFollowingRunner || animateCamera;

  String get cameraMoveReason {
    if (animateCamera) {
      return 'recenter';
    }
    if (isFollowingRunner) {
      return 'follow';
    }
    return 'skipped';
  }
}

class RunMapboxCameraInterruptGate {
  int _generation = 0;

  int capture() => _generation;

  int interrupt() {
    _generation++;
    return _generation;
  }

  bool allows(int generation) => generation == _generation;
}

abstract class RunMapboxSyncTarget {
  Future<void> apply(RunMapboxSyncRequest request);

  Future<void> cancelCameraAnimation();

  Future<void> dispose();
}

class RunMapboxSyncCoordinator {
  RunMapboxSyncCoordinator(this._target);

  final RunMapboxSyncTarget _target;
  RunMapboxSyncRequest? _latestRequest;
  Future<void>? _drainFuture;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  Future<void> sync(RunMapboxSyncRequest request) {
    if (_disposed) {
      return Future<void>.value();
    }

    _latestRequest = request;
    return _drainFuture ??= _drain();
  }

  Future<void> cancelCameraAnimation() {
    if (_disposed) {
      return Future<void>.value();
    }
    return _target.cancelCameraAnimation();
  }

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _latestRequest = null;
    try {
      await _drainFuture;
    } finally {
      await _target.dispose();
    }
  }

  Future<void> _drain() async {
    try {
      while (!_disposed) {
        final request = _latestRequest;
        _latestRequest = null;
        if (request == null) {
          break;
        }
        await _target.apply(request);
      }
    } finally {
      _drainFuture = null;
    }

    if (!_disposed && _latestRequest != null) {
      _drainFuture = _drain();
      return _drainFuture;
    }
  }
}
