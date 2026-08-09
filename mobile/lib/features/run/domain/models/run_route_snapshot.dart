import 'run_location_sample.dart';
import 'run_map_view_state.dart';

class RunRouteSnapshot {
  const RunRouteSnapshot({
    this.segments = const <List<RunLocationSample>>[],
    this.lastKnownLocation,
  });

  factory RunRouteSnapshot.fromMapViewState(RunMapViewState state) {
    return RunRouteSnapshot(
      segments: state.acceptedRouteSegments,
      lastKnownLocation: state.displayPosition ?? _lastRoutePoint(state),
    );
  }

  static const empty = RunRouteSnapshot();

  final List<List<RunLocationSample>> segments;
  final RunLocationSample? lastKnownLocation;

  bool get hasRoute {
    return segments.any((segment) => segment.length > 1);
  }

  bool get hasLocation => lastKnownLocation != null;

  static RunLocationSample? _lastRoutePoint(RunMapViewState state) {
    for (final segment in state.acceptedRouteSegments.reversed) {
      if (segment.isNotEmpty) {
        return segment.last;
      }
    }
    return null;
  }
}
