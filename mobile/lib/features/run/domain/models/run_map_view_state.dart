import 'run_location_sample.dart';

class RunMapViewState {
  RunMapViewState({
    this.previewPosition,
    this.currentPosition,
    List<List<RunLocationSample>> routeSegments =
        const <List<RunLocationSample>>[],
    List<List<RunLocationSample>>? acceptedRouteSegments,
    List<List<RunLocationSample>>? displayRouteSegments,
  }) : acceptedRouteSegments = _immutableSegments(
         acceptedRouteSegments ?? routeSegments,
       ),
       displayRouteSegments = _immutableSegments(
         displayRouteSegments ?? acceptedRouteSegments ?? routeSegments,
       );

  const RunMapViewState.empty()
    : previewPosition = null,
      currentPosition = null,
      acceptedRouteSegments = const <List<RunLocationSample>>[],
      displayRouteSegments = const <List<RunLocationSample>>[];

  final RunLocationSample? previewPosition;
  final RunLocationSample? currentPosition;
  final List<List<RunLocationSample>> acceptedRouteSegments;
  final List<List<RunLocationSample>> displayRouteSegments;

  List<List<RunLocationSample>> get routeSegments => acceptedRouteSegments;

  RunLocationSample? get displayPosition {
    return currentPosition ?? previewPosition;
  }

  int get routePointCount {
    return acceptedRouteSegments.fold<int>(
      0,
      (total, segment) => total + segment.length,
    );
  }

  bool get hasRoutePolyline {
    return acceptedRouteSegments.any((segment) => segment.length > 1);
  }

  static List<List<RunLocationSample>> _immutableSegments(
    List<List<RunLocationSample>> segments,
  ) {
    return List<List<RunLocationSample>>.unmodifiable(
      segments.map(List<RunLocationSample>.unmodifiable),
    );
  }
}
