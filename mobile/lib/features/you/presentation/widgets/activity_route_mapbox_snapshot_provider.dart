import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../../../core/imaging/eight_bit_png.dart';
import '../../../run/domain/models/run_location_sample.dart';
import 'activity_route_preview.dart';
import 'activity_route_snapshot_thumbnail_cache.dart';
import 'activity_route_thumbnail_viewport.dart';

/// Renders a route thumbnail by driving Mapbox's off-screen snapshotter.
///
/// The snapshotter is a native resource that must be created, used and disposed
/// in order; leaking one leaks memory on the device. That is what the explicit
/// runtime and lifecycle types here are for, and why the history list goes
/// through [ActivityRouteSnapshotThumbnailMemoryCache] rather than snapshotting
/// per card.
///
/// Output is re-encoded as an 8-bit PNG (`core/imaging/eight_bit_png.dart`) —
/// a thumbnail this small does not need full colour depth, and the smaller
/// bytes matter when a screen shows dozens of them.
class ActivityRouteMapboxSnapshotStyle {
  const ActivityRouteMapboxSnapshotStyle._();

  static const defaultStyle = mapbox.MapboxStyles.MAPBOX_STREETS;
}

abstract interface class ActivityRouteSnapshotterRuntime {
  Future<Uint8List?> capture({
    required String accessToken,
    required String styleUri,
    required widgets.Size logicalSize,
    required double pixelRatio,
    required ActivityRouteSnapshotCamera camera,
    required ActivityRouteSnapshotterLifecycleSink onLifecycleDiagnostic,
  });
}

class MapboxActivityRouteSnapshotterRuntime
    implements ActivityRouteSnapshotterRuntime {
  const MapboxActivityRouteSnapshotterRuntime();

  @override
  Future<Uint8List?> capture({
    required String accessToken,
    required String styleUri,
    required widgets.Size logicalSize,
    required double pixelRatio,
    required ActivityRouteSnapshotCamera camera,
    required ActivityRouteSnapshotterLifecycleSink onLifecycleDiagnostic,
  }) async {
    mapbox.MapboxOptions.setAccessToken(accessToken);
    final snapshotter = await mapbox.Snapshotter.create(
      options: mapbox.MapSnapshotOptions(
        size: mapbox.Size(width: logicalSize.width, height: logicalSize.height),
        pixelRatio: pixelRatio,
      ),
    );
    onLifecycleDiagnostic(
      ActivityRouteSnapshotterDiagnosticEvent.snapshotterCreated,
    );
    try {
      await snapshotter.setCamera(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              camera.centerLongitude,
              camera.centerLatitude,
            ),
          ),
          zoom: camera.zoom,
        ),
      );
      await snapshotter.style.setStyleURI(styleUri);
      onLifecycleDiagnostic(
        ActivityRouteSnapshotterDiagnosticEvent.startRequested,
      );
      final bytes = await snapshotter.start();
      onLifecycleDiagnostic(
        ActivityRouteSnapshotterDiagnosticEvent.startCompleted,
      );
      return bytes;
    } finally {
      onLifecycleDiagnostic(
        ActivityRouteSnapshotterDiagnosticEvent.disposeRequested,
      );
      await snapshotter.dispose();
    }
  }
}

class MapboxActivityRouteSnapshotThumbnailGenerator
    implements ActivityRouteSnapshotThumbnailGenerator {
  const MapboxActivityRouteSnapshotThumbnailGenerator({
    required this.accessToken,
    this.styleUri = ActivityRouteMapboxSnapshotStyle.defaultStyle,
    this.runtime = const MapboxActivityRouteSnapshotterRuntime(),
    this.onDiagnostic,
  });

  final String accessToken;
  final String styleUri;
  final ActivityRouteSnapshotterRuntime runtime;
  final ActivityRouteSnapshotterDiagnosticSink? onDiagnostic;

  @override
  Future<ActivityRouteThumbnailResult> generate(
    ActivityRouteSnapshotThumbnailGenerationRequest request,
  ) async {
    try {
      _reportDiagnostic(
        ActivityRouteSnapshotterDiagnostic.started(
          request: request,
          styleUri: styleUri,
        ),
      );
      final bytes = await runtime.capture(
        accessToken: accessToken,
        styleUri: styleUri,
        logicalSize: request.logicalSize,
        pixelRatio: request.devicePixelRatio,
        camera: request.camera,
        onLifecycleDiagnostic: (event) {
          _reportDiagnostic(
            ActivityRouteSnapshotterDiagnostic.lifecycle(
              request: request,
              styleUri: styleUri,
              event: event,
            ),
          );
        },
      );
      if (bytes == null || bytes.isEmpty) {
        _reportDiagnostic(
          ActivityRouteSnapshotterDiagnostic.finished(
            request: request,
            styleUri: styleUri,
            state: ActivityRouteThumbnailState.unavailable,
            byteLength: bytes?.lengthInBytes ?? 0,
          ),
        );
        return const ActivityRouteThumbnailResult.unavailable();
      }
      _reportDiagnostic(
        ActivityRouteSnapshotterDiagnostic.finished(
          request: request,
          styleUri: styleUri,
          state: ActivityRouteThumbnailState.readyImage,
          byteLength: bytes.lengthInBytes,
        ),
      );
      try {
        final maskedBytes = await encodePrivacyMaskedPng(bytes, request);
        return ActivityRouteThumbnailResult.readyPng(maskedBytes);
      } on Object {
        // Legacy/UI-only consumers can still render an invalid test double,
        // but Feed capture refuses results without verified PNG bytes.
        return ActivityRouteThumbnailResult.readyImage(
          widgets.MemoryImage(bytes),
        );
      }
    } on PlatformException catch (error) {
      _reportDiagnostic(
        _snapshotWasCancelled(error)
            ? ActivityRouteSnapshotterDiagnostic.cancelled(
                request: request,
                styleUri: styleUri,
                error: error,
              )
            : ActivityRouteSnapshotterDiagnostic.failed(
                request: request,
                styleUri: styleUri,
                error: error,
              ),
      );
      return const ActivityRouteThumbnailResult.requestFailed();
    } on Object catch (error) {
      _reportDiagnostic(
        ActivityRouteSnapshotterDiagnostic.failed(
          request: request,
          styleUri: styleUri,
          error: error,
        ),
      );
      return const ActivityRouteThumbnailResult.requestFailed();
    }
  }

  void _reportDiagnostic(ActivityRouteSnapshotterDiagnostic diagnostic) {
    final onDiagnostic = this.onDiagnostic;
    if (onDiagnostic == null) {
      return;
    }
    onDiagnostic(diagnostic);
  }
}

Future<Uint8List> encodePrivacyMaskedPng(
  Uint8List sourceBytes,
  ActivityRouteSnapshotThumbnailGenerationRequest request,
) async {
  final codec = await ui.instantiateImageCodec(sourceBytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  final width = request.outputWidthPixels;
  final height = request.outputHeightPixels;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  try {
    final destination = ui.Rect.fromLTWH(
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      ui.Paint(),
    );
    _paintRouteOverlay(canvas, request);
    final output = await recorder.endRecording().toImage(width, height);
    try {
      final data = await encodeEightBitPng(output);
      if (data == null) throw StateError('PNG encoding was unavailable.');
      return data;
    } finally {
      output.dispose();
    }
  } finally {
    image.dispose();
  }
}

void _paintRouteOverlay(
  ui.Canvas canvas,
  ActivityRouteSnapshotThumbnailGenerationRequest request,
) {
  if (request.route.segments.isEmpty) {
    return;
  }
  canvas.save();
  canvas.scale(request.devicePixelRatio, request.devicePixelRatio);
  final shadowPaint = ui.Paint()
    ..color = const ui.Color(0xCCFFFFFF)
    ..strokeWidth = 8
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;
  final routePaint = ui.Paint()
    ..color = const ui.Color(0xFFC85A09)
    ..strokeWidth = 5
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;
  for (final segment in request.route.segments) {
    final path = _routePathForSegment(segment, request.viewport);
    if (path == null) {
      continue;
    }
    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, routePaint);
  }
  canvas.restore();
}

ui.Path? _routePathForSegment(
  List<RunLocationSample> segment,
  ActivityRouteThumbnailViewport viewport,
) {
  final points = segment
      .where((point) => point.latitude.isFinite && point.longitude.isFinite)
      .toList(growable: false);
  if (points.length < 2) {
    return null;
  }
  final start = viewport.project(points.first);
  final path = ui.Path()..moveTo(start.dx, start.dy);
  for (final point in points.skip(1)) {
    final projected = viewport.project(point);
    path.lineTo(projected.dx, projected.dy);
  }
  return path;
}

typedef ActivityRouteSnapshotterLifecycleSink =
    void Function(ActivityRouteSnapshotterDiagnosticEvent event);

typedef ActivityRouteSnapshotterDiagnosticSink =
    void Function(ActivityRouteSnapshotterDiagnostic diagnostic);

enum ActivityRouteSnapshotterDiagnosticEvent {
  started,
  snapshotterCreated,
  startRequested,
  startCompleted,
  disposeRequested,
  finished,
  cancelled,
  failed,
  timeout,
}

class ActivityRouteSnapshotterDiagnostic {
  const ActivityRouteSnapshotterDiagnostic._({
    required this.event,
    required this.activityId,
    required this.styleUri,
    required this.logicalSize,
    required this.devicePixelRatio,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.zoom,
    this.state,
    this.byteLength,
    this.errorType,
    this.errorDescription,
  });

  factory ActivityRouteSnapshotterDiagnostic.started({
    required ActivityRouteSnapshotThumbnailGenerationRequest request,
    required String styleUri,
  }) {
    return ActivityRouteSnapshotterDiagnostic._(
      event: ActivityRouteSnapshotterDiagnosticEvent.started,
      activityId: request.activityId,
      styleUri: styleUri,
      logicalSize: request.logicalSize,
      devicePixelRatio: request.devicePixelRatio,
      centerLatitude: request.camera.centerLatitude,
      centerLongitude: request.camera.centerLongitude,
      zoom: request.camera.zoom,
    );
  }

  factory ActivityRouteSnapshotterDiagnostic.finished({
    required ActivityRouteSnapshotThumbnailGenerationRequest request,
    required String styleUri,
    required ActivityRouteThumbnailState state,
    required int byteLength,
  }) {
    return ActivityRouteSnapshotterDiagnostic._(
      event: ActivityRouteSnapshotterDiagnosticEvent.finished,
      activityId: request.activityId,
      styleUri: styleUri,
      logicalSize: request.logicalSize,
      devicePixelRatio: request.devicePixelRatio,
      centerLatitude: request.camera.centerLatitude,
      centerLongitude: request.camera.centerLongitude,
      zoom: request.camera.zoom,
      state: state,
      byteLength: byteLength,
    );
  }

  factory ActivityRouteSnapshotterDiagnostic.lifecycle({
    required ActivityRouteSnapshotThumbnailGenerationRequest request,
    required String styleUri,
    required ActivityRouteSnapshotterDiagnosticEvent event,
  }) {
    return ActivityRouteSnapshotterDiagnostic._(
      event: event,
      activityId: request.activityId,
      styleUri: styleUri,
      logicalSize: request.logicalSize,
      devicePixelRatio: request.devicePixelRatio,
      centerLatitude: request.camera.centerLatitude,
      centerLongitude: request.camera.centerLongitude,
      zoom: request.camera.zoom,
    );
  }

  factory ActivityRouteSnapshotterDiagnostic.cancelled({
    required ActivityRouteSnapshotThumbnailGenerationRequest request,
    required String styleUri,
    required Object error,
  }) {
    return ActivityRouteSnapshotterDiagnostic._(
      event: ActivityRouteSnapshotterDiagnosticEvent.cancelled,
      activityId: request.activityId,
      styleUri: styleUri,
      logicalSize: request.logicalSize,
      devicePixelRatio: request.devicePixelRatio,
      centerLatitude: request.camera.centerLatitude,
      centerLongitude: request.camera.centerLongitude,
      zoom: request.camera.zoom,
      state: ActivityRouteThumbnailState.requestFailed,
      byteLength: 0,
      errorType: error.runtimeType.toString(),
      errorDescription: error.toString(),
    );
  }

  factory ActivityRouteSnapshotterDiagnostic.failed({
    required ActivityRouteSnapshotThumbnailGenerationRequest request,
    required String styleUri,
    required Object error,
  }) {
    return ActivityRouteSnapshotterDiagnostic._(
      event: ActivityRouteSnapshotterDiagnosticEvent.failed,
      activityId: request.activityId,
      styleUri: styleUri,
      logicalSize: request.logicalSize,
      devicePixelRatio: request.devicePixelRatio,
      centerLatitude: request.camera.centerLatitude,
      centerLongitude: request.camera.centerLongitude,
      zoom: request.camera.zoom,
      state: ActivityRouteThumbnailState.requestFailed,
      byteLength: 0,
      errorType: error.runtimeType.toString(),
      errorDescription: error.toString(),
    );
  }

  final ActivityRouteSnapshotterDiagnosticEvent event;
  final String? activityId;
  final String styleUri;
  final widgets.Size logicalSize;
  final double devicePixelRatio;
  final double centerLatitude;
  final double centerLongitude;
  final double zoom;
  final ActivityRouteThumbnailState? state;
  final int? byteLength;
  final String? errorType;
  final String? errorDescription;
}

bool _snapshotWasCancelled(PlatformException error) {
  final description = '${error.code} ${error.message ?? ''} ${error.details}'
      .toLowerCase();
  return error.code == 'snapshotFailed' && description.contains('cancel');
}
