import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../run/domain/models/run_location_sample.dart';
import '../../../run/domain/models/run_route_snapshot.dart';

/// Works out how to frame a route inside a small thumbnail.
///
/// The hard case is a very short run: fitting its bounds to the viewport would
/// zoom in so far that a 200 m jog fills the frame like a marathon. The three
/// [ActivityRouteThumbnailViewportMode] values are that decision made explicit —
/// a route worth framing, a route too small to frame honestly, and no route at
/// all — and each is drawn differently.
///
/// Pure geometry with no Flutter painting, so the fit can be unit-tested
/// directly.
enum ActivityRouteThumbnailViewportMode { meaningfulRoute, tinyRoute, noRoute }

class ActivityRouteThumbnailViewport {
  const ActivityRouteThumbnailViewport._({
    required this.mode,
    required this.logicalSize,
    required this.previewPadding,
    required this.drawablePoints,
    required this.knownLocation,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.cameraZoom,
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
    required this.offset,
    required this.scale,
  });

  factory ActivityRouteThumbnailViewport.fromRoute(
    RunRouteSnapshot route, {
    required Size logicalSize,
  }) {
    final points = _drawableRoutePoints(route);
    final knownLocation = _knownPreviewLocation(route);
    if (points.length < 2) {
      return _locationOrEmpty(
        knownLocation,
        logicalSize: logicalSize,
        drawablePoints: points,
      );
    }

    if (_routeMovementMeters(points) < _stationaryMovementThresholdMeters) {
      return _locationOrEmpty(
        knownLocation,
        logicalSize: logicalSize,
        drawablePoints: points,
      );
    }

    final bounds = _RouteBounds.fromPoints(points);
    final meaningful = ActivityRouteThumbnailViewport._fromMeaningfulRoute(
      logicalSize: logicalSize,
      drawablePoints: points,
      knownLocation: knownLocation,
      rawBounds: bounds,
    );
    final projectedBounds = meaningful.projectedBounds(points);
    if (projectedBounds.width < _tinyRouteProjectedThresholdPx &&
        projectedBounds.height < _tinyRouteProjectedThresholdPx) {
      return _locationOrEmpty(
        knownLocation,
        logicalSize: logicalSize,
        drawablePoints: points,
      );
    }

    return meaningful;
  }

  factory ActivityRouteThumbnailViewport._fromMeaningfulRoute({
    required Size logicalSize,
    required List<RunLocationSample> drawablePoints,
    required RunLocationSample? knownLocation,
    required _RouteBounds rawBounds,
  }) {
    final centerLatitude = rawBounds.centerLatitude;
    final centerLongitude = rawBounds.centerLongitude;
    final latitudeSpan = math.max(rawBounds.latitudeSpan, _minRouteSpan);
    final longitudeSpan = math.max(rawBounds.longitudeSpan, _minRouteSpan);
    final latitudeCosine = math
        .cos(centerLatitude * math.pi / 180)
        .abs()
        .clamp(_minLatitudeCosine, 1.0);
    final adjustedLongitudeSpan = longitudeSpan * latitudeCosine;
    final routeSpan = math.max(latitudeSpan, adjustedLongitudeSpan);
    final paddedCameraSpan = math.max(
      routeSpan * _cameraPaddingMultiplier,
      _minCameraSpan,
    );
    final paddedLatitudeSpan = paddedCameraSpan;
    final paddedLongitudeSpan = paddedCameraSpan / latitudeCosine;
    final minLatitude = centerLatitude - (paddedLatitudeSpan / 2);
    final maxLatitude = centerLatitude + (paddedLatitudeSpan / 2);
    final minLongitude = centerLongitude - (paddedLongitudeSpan / 2);
    final maxLongitude = centerLongitude + (paddedLongitudeSpan / 2);
    final projection = _ProjectionFit.fromBounds(
      logicalSize: logicalSize,
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
    );

    return ActivityRouteThumbnailViewport._(
      mode: ActivityRouteThumbnailViewportMode.meaningfulRoute,
      logicalSize: logicalSize,
      previewPadding: _previewPadding,
      drawablePoints: List<RunLocationSample>.unmodifiable(drawablePoints),
      knownLocation: knownLocation,
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      cameraZoom: _zoomForSpan(paddedCameraSpan),
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
      offset: projection.offset,
      scale: projection.scale,
    );
  }

  final ActivityRouteThumbnailViewportMode mode;
  final Size logicalSize;
  final double previewPadding;
  final List<RunLocationSample> drawablePoints;
  final RunLocationSample? knownLocation;
  final double centerLatitude;
  final double centerLongitude;
  final double cameraZoom;
  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;
  final Offset offset;
  final double scale;

  bool get hasKnownLocation => knownLocation != null;

  Offset project(RunLocationSample point) {
    final x = (point.longitude - minLongitude) * scale;
    final y = (maxLatitude - point.latitude) * scale;
    return offset + Offset(x, y);
  }

  Rect projectedBounds(List<RunLocationSample> points) {
    final firstProjected = project(points.first);
    var minX = firstProjected.dx;
    var maxX = firstProjected.dx;
    var minY = firstProjected.dy;
    var maxY = firstProjected.dy;

    for (final point in points.skip(1)) {
      final projected = project(point);
      minX = math.min(minX, projected.dx);
      maxX = math.max(maxX, projected.dx);
      minY = math.min(minY, projected.dy);
      maxY = math.max(maxY, projected.dy);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static ActivityRouteThumbnailViewport _locationOrEmpty(
    RunLocationSample? location, {
    required Size logicalSize,
    required List<RunLocationSample> drawablePoints,
  }) {
    if (location == null) {
      return ActivityRouteThumbnailViewport._empty(
        logicalSize: logicalSize,
        drawablePoints: drawablePoints,
      );
    }
    return ActivityRouteThumbnailViewport._location(
      location,
      logicalSize: logicalSize,
      drawablePoints: drawablePoints,
    );
  }

  factory ActivityRouteThumbnailViewport._location(
    RunLocationSample location, {
    required Size logicalSize,
    required List<RunLocationSample> drawablePoints,
  }) {
    return ActivityRouteThumbnailViewport._(
      mode: ActivityRouteThumbnailViewportMode.tinyRoute,
      logicalSize: logicalSize,
      previewPadding: _previewPadding,
      drawablePoints: List<RunLocationSample>.unmodifiable(drawablePoints),
      knownLocation: location,
      centerLatitude: location.latitude,
      centerLongitude: location.longitude,
      cameraZoom: _locationSnapshotZoom,
      minLatitude: location.latitude,
      maxLatitude: location.latitude,
      minLongitude: location.longitude,
      maxLongitude: location.longitude,
      offset: Offset.zero,
      scale: 1,
    );
  }

  factory ActivityRouteThumbnailViewport._empty({
    required Size logicalSize,
    required List<RunLocationSample> drawablePoints,
  }) {
    return ActivityRouteThumbnailViewport._(
      mode: ActivityRouteThumbnailViewportMode.noRoute,
      logicalSize: logicalSize,
      previewPadding: _previewPadding,
      drawablePoints: List<RunLocationSample>.unmodifiable(drawablePoints),
      knownLocation: null,
      centerLatitude: 0,
      centerLongitude: 0,
      cameraZoom: _locationSnapshotZoom,
      minLatitude: 0,
      maxLatitude: 0,
      minLongitude: 0,
      maxLongitude: 0,
      offset: Offset.zero,
      scale: 1,
    );
  }
}

class _RouteBounds {
  const _RouteBounds({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  factory _RouteBounds.fromPoints(List<RunLocationSample> points) {
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
    return _RouteBounds(
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
    );
  }

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  double get centerLatitude => (minLatitude + maxLatitude) / 2;
  double get centerLongitude => (minLongitude + maxLongitude) / 2;
  double get latitudeSpan => (maxLatitude - minLatitude).abs();
  double get longitudeSpan => (maxLongitude - minLongitude).abs();
}

class _ProjectionFit {
  const _ProjectionFit({required this.offset, required this.scale});

  factory _ProjectionFit.fromBounds({
    required Size logicalSize,
    required double minLatitude,
    required double maxLatitude,
    required double minLongitude,
    required double maxLongitude,
  }) {
    final drawableSize = Size(
      math.max(1, logicalSize.width - (_previewPadding * 2)),
      math.max(1, logicalSize.height - (_previewPadding * 2)),
    );
    final longitudeSpan = math.max(maxLongitude - minLongitude, _minRouteSpan);
    final latitudeSpan = math.max(maxLatitude - minLatitude, _minRouteSpan);
    final scale = math.min(
      drawableSize.width / longitudeSpan,
      drawableSize.height / latitudeSpan,
    );
    final projectedWidth = longitudeSpan * scale;
    final projectedHeight = latitudeSpan * scale;

    return _ProjectionFit(
      offset: Offset(
        _previewPadding + ((drawableSize.width - projectedWidth) / 2),
        _previewPadding + ((drawableSize.height - projectedHeight) / 2),
      ),
      scale: scale,
    );
  }

  final Offset offset;
  final double scale;
}

List<RunLocationSample> _drawableRoutePoints(RunRouteSnapshot route) {
  return route.segments
      .expand((segment) => segment)
      .where(_isDrawableRoutePoint)
      .toList(growable: false);
}

bool _isDrawableRoutePoint(RunLocationSample point) {
  return point.latitude.isFinite && point.longitude.isFinite;
}

RunLocationSample? _knownPreviewLocation(RunRouteSnapshot route) {
  final lastKnownLocation = route.lastKnownLocation;
  if (lastKnownLocation != null && _isDrawableRoutePoint(lastKnownLocation)) {
    return lastKnownLocation;
  }
  for (final segment in route.segments.reversed) {
    for (final point in segment.reversed) {
      if (_isDrawableRoutePoint(point)) {
        return point;
      }
    }
  }
  return null;
}

double _routeMovementMeters(List<RunLocationSample> points) {
  var maxDistance = 0.0;
  for (var index = 1; index < points.length; index += 1) {
    maxDistance = math.max(
      maxDistance,
      _distanceMeters(points.first, points[index]),
    );
  }
  return maxDistance;
}

double _distanceMeters(RunLocationSample a, RunLocationSample b) {
  const metersPerLatitudeDegree = 111320.0;
  final meanLatitudeRadians = ((a.latitude + b.latitude) / 2) * math.pi / 180;
  final metersPerLongitudeDegree =
      metersPerLatitudeDegree * math.cos(meanLatitudeRadians).abs();
  final latitudeMeters = (b.latitude - a.latitude) * metersPerLatitudeDegree;
  final longitudeMeters =
      (b.longitude - a.longitude) * metersPerLongitudeDegree;
  return math.sqrt(
    (latitudeMeters * latitudeMeters) + (longitudeMeters * longitudeMeters),
  );
}

double _zoomForSpan(double span) {
  return (math.log(360 / span) / math.ln2)
      .clamp(_minSnapshotZoom, _maxSnapshotZoom)
      .toDouble();
}

const double activityRouteThumbnailPreviewPadding = _previewPadding;
const _previewPadding = 7.0;
const _minRouteSpan = 0.000001;
const _stationaryMovementThresholdMeters = 6.0;
const _tinyRouteProjectedThresholdPx = 6.0;
const _cameraPaddingMultiplier = 1.8;
const _minCameraSpan = 0.00018;
const _minSnapshotZoom = 11.5;
const _maxSnapshotZoom = 17.2;
const _locationSnapshotZoom = 16.5;
const _minLatitudeCosine = 0.01;
