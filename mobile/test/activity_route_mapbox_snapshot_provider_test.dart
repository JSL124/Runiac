import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_mapbox_snapshot_provider.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_snapshot_thumbnail_cache.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_thumbnail_viewport.dart';

void main() {
  test(
    'Mapbox snapshot generator returns ready image from runtime bytes',
    () async {
      final diagnostics = <ActivityRouteSnapshotterDiagnostic>[];
      final runtime = _FakeSnapshotterRuntime(
        bytes: Uint8List.fromList(const [1, 2, 3]),
      );
      final generator = MapboxActivityRouteSnapshotThumbnailGenerator(
        accessToken: _testPublicToken,
        runtime: runtime,
        onDiagnostic: diagnostics.add,
      );

      final result = await generator.generate(_generationRequest());

      expect(result.state, ActivityRouteThumbnailState.readyImage);
      expect(result.imageProvider, isA<MemoryImage>());
      expect(runtime.callCount, 1);
      expect(runtime.lastAccessToken, _testPublicToken);
      expect(
        runtime.lastStyleUri,
        ActivityRouteMapboxSnapshotStyle.defaultStyle,
      );
      expect(runtime.lastLogicalSize, const Size(88, 88));
      expect(runtime.lastPixelRatio, 3);
      expect(runtime.lastCamera!.centerLatitude, 1.3015);
      expect(runtime.lastCamera!.centerLongitude, 103.8015);
      expect(runtime.lastCamera!.zoom, 15.5);
      expect(diagnostics.map((diagnostic) => diagnostic.event), [
        ActivityRouteSnapshotterDiagnosticEvent.started,
        ActivityRouteSnapshotterDiagnosticEvent.finished,
      ]);
      expect(diagnostics.last.state, ActivityRouteThumbnailState.readyImage);
      expect(diagnostics.last.byteLength, 3);
      expect(diagnostics.last.activityId, 'session-activity');
    },
  );

  test(
    'Mapbox snapshot generator falls back for null or empty bytes',
    () async {
      final nullRuntime = _FakeSnapshotterRuntime(bytes: null);
      final emptyRuntime = _FakeSnapshotterRuntime(bytes: Uint8List(0));

      final nullResult = await MapboxActivityRouteSnapshotThumbnailGenerator(
        accessToken: _testPublicToken,
        runtime: nullRuntime,
      ).generate(_generationRequest());
      final emptyResult = await MapboxActivityRouteSnapshotThumbnailGenerator(
        accessToken: _testPublicToken,
        runtime: emptyRuntime,
      ).generate(_generationRequest());

      expect(nullResult, const ActivityRouteThumbnailResult.unavailable());
      expect(emptyResult, const ActivityRouteThumbnailResult.unavailable());
    },
  );

  test(
    'Mapbox snapshot generator reports request failure from runtime error',
    () async {
      final diagnostics = <ActivityRouteSnapshotterDiagnostic>[];
      final runtime = _FakeSnapshotterRuntime(error: StateError('boom'));

      final result = await MapboxActivityRouteSnapshotThumbnailGenerator(
        accessToken: _testPublicToken,
        runtime: runtime,
        onDiagnostic: diagnostics.add,
      ).generate(_generationRequest());

      expect(result, const ActivityRouteThumbnailResult.requestFailed());
      expect(diagnostics.map((diagnostic) => diagnostic.event), [
        ActivityRouteSnapshotterDiagnosticEvent.started,
        ActivityRouteSnapshotterDiagnosticEvent.failed,
      ]);
      expect(diagnostics.last.state, ActivityRouteThumbnailState.requestFailed);
      expect(diagnostics.last.byteLength, 0);
      expect(diagnostics.last.errorType, 'StateError');
      expect(diagnostics.last.errorDescription, contains('boom'));
    },
  );

  test(
    'Mapbox snapshot generator reports cancelled state from snapshot failure',
    () async {
      final diagnostics = <ActivityRouteSnapshotterDiagnostic>[];
      final runtime = _FakeSnapshotterRuntime(
        error: PlatformException(
          code: 'snapshotFailed',
          message: 'Snapshot cancelled',
        ),
      );

      final result = await MapboxActivityRouteSnapshotThumbnailGenerator(
        accessToken: _testPublicToken,
        runtime: runtime,
        onDiagnostic: diagnostics.add,
      ).generate(_generationRequest());

      expect(result, const ActivityRouteThumbnailResult.requestFailed());
      expect(diagnostics.map((diagnostic) => diagnostic.event), [
        ActivityRouteSnapshotterDiagnosticEvent.started,
        ActivityRouteSnapshotterDiagnosticEvent.cancelled,
      ]);
      expect(diagnostics.last.state, ActivityRouteThumbnailState.requestFailed);
      expect(diagnostics.last.errorType, 'PlatformException');
      expect(diagnostics.last.errorDescription, contains('Snapshot cancelled'));
    },
  );

  test(
    'Mapbox snapshot runtime reports lifecycle in completion order',
    () async {
      final diagnostics = <ActivityRouteSnapshotterDiagnostic>[];
      final runtime = _FakeSnapshotterRuntime(
        bytes: Uint8List.fromList(const [4, 5, 6]),
        lifecycleEvents: [
          ActivityRouteSnapshotterDiagnosticEvent.snapshotterCreated,
          ActivityRouteSnapshotterDiagnosticEvent.startRequested,
          ActivityRouteSnapshotterDiagnosticEvent.startCompleted,
          ActivityRouteSnapshotterDiagnosticEvent.disposeRequested,
        ],
      );

      final result = await MapboxActivityRouteSnapshotThumbnailGenerator(
        accessToken: _testPublicToken,
        runtime: runtime,
        onDiagnostic: diagnostics.add,
      ).generate(_generationRequest());

      expect(result.state, ActivityRouteThumbnailState.readyImage);
      expect(diagnostics.map((diagnostic) => diagnostic.event), [
        ActivityRouteSnapshotterDiagnosticEvent.started,
        ActivityRouteSnapshotterDiagnosticEvent.snapshotterCreated,
        ActivityRouteSnapshotterDiagnosticEvent.startRequested,
        ActivityRouteSnapshotterDiagnosticEvent.startCompleted,
        ActivityRouteSnapshotterDiagnosticEvent.disposeRequested,
        ActivityRouteSnapshotterDiagnosticEvent.finished,
      ]);
    },
  );
}

const _testPublicToken =
    'p'
    'k.test-public-token';

ActivityRouteSnapshotThumbnailGenerationRequest _generationRequest() {
  const logicalSize = Size(88, 88);
  final viewport = ActivityRouteThumbnailViewport.fromRoute(
    RunRouteSnapshot.empty,
    logicalSize: logicalSize,
  );
  return ActivityRouteSnapshotThumbnailGenerationRequest(
    logicalSize: logicalSize,
    devicePixelRatio: 3,
    styleId: 'runiac-card-static-v1',
    activityId: 'session-activity',
    camera: const ActivityRouteSnapshotCamera(
      centerLatitude: 1.3015,
      centerLongitude: 103.8015,
      zoom: 15.5,
    ),
    route: RunRouteSnapshot.empty,
    viewport: viewport,
  );
}

class _FakeSnapshotterRuntime implements ActivityRouteSnapshotterRuntime {
  _FakeSnapshotterRuntime({this.bytes, this.error, this.lifecycleEvents});

  final Uint8List? bytes;
  final Object? error;
  final List<ActivityRouteSnapshotterDiagnosticEvent>? lifecycleEvents;
  int callCount = 0;
  String? lastAccessToken;
  String? lastStyleUri;
  Size? lastLogicalSize;
  double? lastPixelRatio;
  ActivityRouteSnapshotCamera? lastCamera;

  @override
  Future<Uint8List?> capture({
    required String accessToken,
    required String styleUri,
    required Size logicalSize,
    required double pixelRatio,
    required ActivityRouteSnapshotCamera camera,
    required ActivityRouteSnapshotterLifecycleSink onLifecycleDiagnostic,
  }) async {
    callCount += 1;
    lastAccessToken = accessToken;
    lastStyleUri = styleUri;
    lastLogicalSize = logicalSize;
    lastPixelRatio = pixelRatio;
    lastCamera = camera;
    final error = this.error;
    if (error != null) {
      throw error;
    }
    for (final event in lifecycleEvents ?? const []) {
      onLifecycleDiagnostic(event);
    }
    return bytes;
  }
}
