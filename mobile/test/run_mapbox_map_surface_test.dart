import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_map_view_state.dart';
import 'package:runiac_app/features/run/presentation/widgets/completed_route_map_surface.dart';
import 'package:runiac_app/features/run/presentation/widgets/display_route_smoother.dart';
import 'package:runiac_app/features/run/presentation/widgets/mapbox_runtime_config.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_map_placeholder.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_mapbox_follow_qa_overlay.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_mapbox_geometry.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_mapbox_run_map.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_mapbox_surface_config.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_tracking_map_surface.dart';

const _demoMapboxPublicToken =
    'p'
    'k.demo-public-token';

void main() {
  group('MapboxRuntimeConfig', () {
    test('fromEnvironment defaults snapshot thumbnails off without token', () {
      final config = MapboxRuntimeConfig.fromEnvironment();

      expect(config.accessToken, isEmpty);
      expect(config.hasPublicAccessToken, isFalse);
      expect(config.snapshotThumbnailsEnabled, isFalse);
    });

    test('validates only public Mapbox tokens', () {
      expect(
        const MapboxRuntimeConfig(
          accessToken: _demoMapboxPublicToken,
        ).hasPublicAccessToken,
        isTrue,
      );
      expect(
        const MapboxRuntimeConfig(
          accessToken: 'private-token',
        ).hasPublicAccessToken,
        isFalse,
      );
      expect(
        const MapboxRuntimeConfig(
          accessToken: 'demo-public-token',
        ).hasPublicAccessToken,
        isFalse,
      );
    });

    test('parses snapshot thumbnail flag explicitly', () {
      expect(
        MapboxRuntimeConfig.fromRaw(
          accessToken: _demoMapboxPublicToken,
          snapshotThumbnailsFlag: 'true',
        ).snapshotThumbnailsEnabled,
        isTrue,
      );
      expect(
        MapboxRuntimeConfig.fromRaw(
          accessToken: _demoMapboxPublicToken,
          snapshotThumbnailsFlag: 'false',
        ).snapshotThumbnailsEnabled,
        isFalse,
      );
      expect(
        MapboxRuntimeConfig.fromRaw(
          accessToken: _demoMapboxPublicToken,
          snapshotThumbnailsFlag: '',
        ).snapshotThumbnailsEnabled,
        isFalse,
      );
    });
  });

  group('RunMapViewState', () {
    test('displayPosition prefers active current position over preview', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final preview = _sample(startedAt, latitude: 1.300000);
      final current = _sample(
        startedAt.add(const Duration(seconds: 30)),
        latitude: 1.300500,
      );

      final viewState = RunMapViewState(
        previewPosition: preview,
        currentPosition: current,
      );

      expect(viewState.displayPosition, same(current));
    });

    test('displayPosition falls back to preview before active GPS', () {
      final preview = _sample(DateTime.utc(2026, 6, 14, 7));

      final viewState = RunMapViewState(previewPosition: preview);

      expect(viewState.displayPosition, same(preview));
    });

    test('displayPosition is null without preview or current position', () {
      expect(const RunMapViewState.empty().displayPosition, isNull);
    });

    test('routeSegments remains a compatibility alias for accepted route', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final acceptedRouteSegments = [
        [
          _sample(startedAt, latitude: 1.300000),
          _sample(startedAt.add(const Duration(seconds: 60)), latitude: 1.301),
        ],
      ];

      final viewState = RunMapViewState(
        acceptedRouteSegments: acceptedRouteSegments,
      );

      expect(viewState.routeSegments, viewState.acceptedRouteSegments);
      expect(viewState.routeSegments, acceptedRouteSegments);
    });

    test('displayRouteSegments defaults to accepted route segments', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final acceptedRouteSegments = [
        [
          _sample(startedAt, latitude: 1.300000),
          _sample(startedAt.add(const Duration(seconds: 60)), latitude: 1.301),
        ],
      ];

      final viewState = RunMapViewState(
        acceptedRouteSegments: acceptedRouteSegments,
      );

      expect(viewState.displayRouteSegments, viewState.acceptedRouteSegments);
      expect(viewState.displayRouteSegments, acceptedRouteSegments);
    });

    test(
      'explicit displayRouteSegments override drawing while routeSegments remains accepted',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        RunLocationSample sample(int seconds, double latitude) {
          return _sample(
            startedAt.add(Duration(seconds: seconds)),
            latitude: latitude,
            longitude: 103.800000,
          );
        }

        final acceptedRouteSegments = [
          [sample(0, 1.300000), sample(60, 1.300500)],
        ];
        final displayRouteSegments = [
          [sample(0, 1.400000), sample(60, 1.400500)],
        ];

        final viewState = RunMapViewState(
          acceptedRouteSegments: acceptedRouteSegments,
          displayRouteSegments: displayRouteSegments,
        );
        final geometry = RunMapboxRouteGeometry.fromViewState(viewState);

        expect(viewState.routeSegments, viewState.acceptedRouteSegments);
        expect(viewState.routeSegments, acceptedRouteSegments);
        expect(viewState.displayRouteSegments, displayRouteSegments);
        expect(viewState.routePointCount, 2);
        expect(viewState.hasRoutePolyline, isTrue);
        expect(geometry.segments.single.map((point) => point.position), [
          <double>[103.800000, 1.400000],
          <double>[103.800000, 1.400500],
        ]);
      },
    );

    test('route metrics derive only from accepted route segments', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final preview = _sample(startedAt, latitude: 1.299000);
      final current = _sample(
        startedAt.add(const Duration(seconds: 30)),
        latitude: 1.399000,
      );

      final viewState = RunMapViewState(
        previewPosition: preview,
        currentPosition: current,
        acceptedRouteSegments: [
          [
            _sample(startedAt.add(const Duration(seconds: 60))),
            _sample(startedAt.add(const Duration(seconds: 120))),
          ],
          [_sample(startedAt.add(const Duration(seconds: 180)))],
        ],
      );

      expect(viewState.routePointCount, 3);
      expect(viewState.hasRoutePolyline, isTrue);
    });

    test('preview and current positions alone do not create route metrics', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      final viewState = RunMapViewState(
        previewPosition: _sample(startedAt, latitude: 1.299000),
        currentPosition: _sample(
          startedAt.add(const Duration(seconds: 30)),
          latitude: 1.399000,
        ),
      );

      expect(viewState.routePointCount, 0);
      expect(viewState.hasRoutePolyline, isFalse);
      expect(viewState.routeSegments, isEmpty);
    });
  });

  group('DisplayRouteSmoother', () {
    test('empty segment list stays empty', () {
      expect(DisplayRouteSmoother.smoothSegments([]), isEmpty);
    });

    test('empty one-point and two-point segments stay unchanged', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final onePoint = [_sample(startedAt, latitude: 1.300000)];
      final twoPoint = [
        _sample(startedAt, latitude: 1.300000),
        _sample(startedAt.add(const Duration(seconds: 60)), latitude: 1.301),
      ];

      final smoothed = DisplayRouteSmoother.smoothSegments([
        <RunLocationSample>[],
        onePoint,
        twoPoint,
      ]);

      expect(smoothed, hasLength(3));
      expect(smoothed[0], isEmpty);
      expect(smoothed[1], onePoint);
      expect(smoothed[2], twoPoint);
    });

    test('three-plus-point segment adds display-only points', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final segment = [
        _sample(startedAt, latitude: 1.300000, longitude: 103.800000),
        _sample(
          startedAt.add(const Duration(seconds: 60)),
          latitude: 1.300500,
          longitude: 103.800500,
        ),
        _sample(
          startedAt.add(const Duration(seconds: 120)),
          latitude: 1.301000,
          longitude: 103.800000,
        ),
      ];

      final smoothed = DisplayRouteSmoother.smoothSegments([segment]);

      expect(smoothed.single, hasLength(greaterThan(segment.length)));
      expect(smoothed.single.first, same(segment.first));
      expect(smoothed.single.last, same(segment.last));
      expect(smoothed.single[1].latitude, closeTo(1.300375, 0.000001));
      expect(smoothed.single[1].longitude, closeTo(103.800375, 0.000001));
      expect(smoothed.single[2].latitude, closeTo(1.300625, 0.000001));
      expect(smoothed.single[2].longitude, closeTo(103.800375, 0.000001));
    });

    test('multi-segment input preserves segment boundaries and order', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      RunLocationSample sample(int seconds, double latitude) {
        return _sample(
          startedAt.add(Duration(seconds: seconds)),
          latitude: latitude,
          longitude: 103.800000,
        );
      }

      final firstSegment = [sample(0, 1.300000), sample(60, 1.300500)];
      final secondSegment = [
        sample(180, 1.301000),
        sample(240, 1.301500),
        sample(300, 1.302000),
      ];

      final smoothed = DisplayRouteSmoother.smoothSegments([
        firstSegment,
        secondSegment,
      ]);

      expect(smoothed, hasLength(2));
      expect(smoothed.first, firstSegment);
      expect(smoothed.last.first, same(secondSegment.first));
      expect(smoothed.last.last, same(secondSegment.last));
      expect(smoothed.last, hasLength(greaterThan(secondSegment.length)));
    });

    test('does not mutate input segment lists', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final segment = [
        _sample(startedAt, latitude: 1.300000),
        _sample(startedAt.add(const Duration(seconds: 60)), latitude: 1.300500),
        _sample(startedAt.add(const Duration(seconds: 120)), latitude: 1.301),
      ];
      final originalPoints = segment.toList();

      final smoothed = DisplayRouteSmoother.smoothSegments([segment]);
      segment.add(
        _sample(startedAt.add(const Duration(seconds: 180)), latitude: 1.3015),
      );

      expect(originalPoints, hasLength(3));
      expect(smoothed.single, hasLength(4));
      expect(smoothed.single.first, same(originalPoints.first));
      expect(smoothed.single.last, same(originalPoints.last));
    });
  });

  group('RunTrackingMapSurface Mapbox boundary', () {
    testWidgets('missing token renders placeholder fallback', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox.expand(
            child: RunTrackingMapSurface(mapboxAccessToken: ''),
          ),
        ),
      );

      expect(find.byType(RunMapPlaceholder), findsOneWidget);
      expect(
        find.byKey(const Key('run_mapbox_placeholder_selected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('run_mapbox_surface_selected')),
        findsNothing,
      );
      expect(find.byKey(const Key('run_mapbox_surface')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('invalid token renders placeholder fallback', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox.expand(
            child: RunTrackingMapSurface(
              mapboxAccessToken: 'demo-public-token',
            ),
          ),
        ),
      );

      expect(find.byType(RunMapPlaceholder), findsOneWidget);
      expect(
        find.byKey(const Key('run_mapbox_placeholder_selected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('run_mapbox_surface_selected')),
        findsNothing,
      );
      expect(find.byKey(const Key('run_mapbox_surface')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'token-present path selects injectable Mapbox surface without platform view',
      (tester) async {
        RunMapboxSurfaceConfig? capturedConfig;

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox.expand(
              child: RunTrackingMapSurface(
                mapboxAccessToken: _demoMapboxPublicToken,
                recenterRequestId: 7,
                mapboxBuilder: (context, config) {
                  capturedConfig = config;
                  return const ColoredBox(
                    key: Key('fake_mapbox_surface'),
                    color: Colors.black,
                  );
                },
              ),
            ),
          ),
        );

        expect(find.byType(RunMapPlaceholder), findsNothing);
        expect(
          find.byKey(const Key('run_mapbox_placeholder_selected')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('run_mapbox_surface_selected')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('fake_mapbox_surface')), findsOneWidget);
        expect(capturedConfig, isNotNull);
        expect(capturedConfig!.accessToken, _demoMapboxPublicToken);
        expect(capturedConfig!.recenterRequestId, 7);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('follow QA overlay is hidden by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox.expand(
            child: RunTrackingMapSurface(mapboxAccessToken: ''),
          ),
        ),
      );

      expect(
        find.byKey(const Key('run_mapbox_follow_qa_overlay')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'follow QA overlay shows non-sensitive diagnostics when enabled',
      (tester) async {
        final diagnostics = RunMapboxFollowQaDiagnostics(
          enabled: true,
          screenPath: 'launch',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox.expand(
              child: RunTrackingMapSurface(
                mapboxAccessToken: _demoMapboxPublicToken,
                isFollowingRunner: false,
                recenterRequestId: 3,
                followQaDiagnostics: diagnostics,
                mapboxBuilder: (context, config) {
                  return const ColoredBox(
                    key: Key('fake_mapbox_surface'),
                    color: Colors.black,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        diagnostics
          ..recordMapboxGestureCallback()
          ..recordPointerObserverMove()
          ..recordManualGesture()
          ..recordOnManualPan()
          ..recordCameraMoveRequest(
            shouldMoveCamera: false,
            reason: 'skipped',
            generation: 2,
          )
          ..recordRouteSync(isFollowingRunner: false)
          ..recordMarkerSync(isFollowingRunner: false)
          ..recordCameraMoveSkipped(
            shouldMoveCamera: false,
            generation: 2,
            isFollowingRunner: false,
          )
          ..recordCameraMove(shouldMoveCamera: true, generation: 3)
          ..recordCameraCancel(interruptGeneration: 4)
          ..recordCameraStateSample(
            latitude: 1.300899,
            longitude: 103.800000,
            isFollowingRunner: false,
          )
          ..recordCameraStateSample(
            latitude: 1.300999,
            longitude: 103.800000,
            isFollowingRunner: false,
          )
          ..recordResume();
        await tester.pump();

        expect(
          find.byKey(const Key('run_mapbox_follow_qa_overlay')),
          findsOneWidget,
        );
        expect(find.text('map: mapbox'), findsOneWidget);
        expect(find.text('screen: launch'), findsOneWidget);
        expect(find.text('follow: OFF'), findsOneWidget);
        expect(find.text('manual gesture: 1'), findsOneWidget);
        expect(find.text('mapbox cb: 1'), findsOneWidget);
        expect(find.text('pointer move: 1'), findsOneWidget);
        expect(find.text('onManualPan: 1'), findsOneWidget);
        expect(find.text('shouldMoveCamera: false'), findsOneWidget);
        expect(find.text('camera move: 1 should: true'), findsOneWidget);
        expect(find.text('camera cancel: 1'), findsOneWidget);
        expect(find.text('camera sample: 2'), findsOneWidget);
        expect(find.text('center changed: yes'), findsOneWidget);
        expect(find.text('center change count: 1'), findsOneWidget);
        expect(find.text('camera source: unknown/native'), findsOneWidget);
        expect(find.text('camera reason: skipped'), findsOneWidget);
        expect(find.text('unknown/native: 1'), findsOneWidget);
        expect(find.text('route sync: 1'), findsOneWidget);
        expect(find.text('marker sync: 1'), findsOneWidget);
        expect(find.text('camera skipped: 1'), findsOneWidget);
        expect(find.text('follow-off route sync: 1'), findsOneWidget);
        expect(find.text('follow-off marker sync: 1'), findsOneWidget);
        expect(find.text('follow-off skipped: 1'), findsOneWidget);
        expect(find.text('camera gen: 3'), findsOneWidget);
        expect(find.text('interrupt gen: 4'), findsOneWidget);
        expect(find.text('follow-off gen: 1'), findsOneWidget);
        expect(find.text('recenter id: 3'), findsOneWidget);
        expect(find.text('resume: 1'), findsOneWidget);

        final visibleText = tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data ?? '')
            .join('\n');
        expect(visibleText, isNot(contains(_demoMapboxPublicToken)));
        expect(visibleText, isNot(contains('http')));
        expect(visibleText, isNot(contains('103.')));
        expect(visibleText, isNot(contains('1.300')));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Mapbox pointer fallback invokes manual interaction callback', (
      tester,
    ) async {
      var manualInteractions = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: RunMapboxManualGestureObserver(
            isFollowingRunner: true,
            followQaDiagnostics: null,
            onManualMapInteraction: () {
              manualInteractions++;
            },
            child: const SizedBox.expand(
              child: ColoredBox(
                key: Key('fake_mapbox_pointer_layer'),
                color: Colors.black,
              ),
            ),
          ),
        ),
      );

      await tester.drag(
        find.byKey(const Key('fake_mapbox_pointer_layer')),
        const Offset(48, 0),
      );
      await tester.pump();

      expect(manualInteractions, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'manual pan disables follow and recenter restores camera intent',
      (tester) async {
        var isFollowingRunner = true;
        var recenterCameraRequests = 0;
        final startedAt = DateTime.utc(2026, 6, 14, 7);
        final mapViewState = RunMapViewState(
          currentPosition: RunLocationSample(
            recordedAt: startedAt,
            latitude: 1.300899,
            longitude: 103.800000,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return SizedBox.expand(
                  child: RunTrackingMapSurface(
                    mapViewState: mapViewState,
                    isFollowingRunner: isFollowingRunner,
                    mapboxAccessToken: _demoMapboxPublicToken,
                    onManualPan: () {
                      setState(() => isFollowingRunner = false);
                    },
                    onRecenter: () {
                      setState(() {
                        isFollowingRunner = true;
                        if (RunMapboxCameraRequest.forCurrentPosition(
                              mapViewState,
                            ) !=
                            null) {
                          recenterCameraRequests++;
                        }
                      });
                    },
                    mapboxBuilder: (context, config) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              key: const Key('fake_mapbox_pan_layer'),
                              onPanUpdate: (_) => config.onManualPan?.call(),
                              child: const ColoredBox(color: Colors.black),
                            ),
                          ),
                          if (!config.isFollowingRunner &&
                              config.onRecenter != null)
                            RunMapRecenterButton(onPressed: config.onRecenter!),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        );

        expect(find.byKey(const Key('run_map_recenter_button')), findsNothing);

        await tester.drag(
          find.byKey(const Key('fake_mapbox_pan_layer')),
          const Offset(40, 0),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('run_map_recenter_button')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('run_map_recenter_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('run_map_recenter_button')), findsNothing);
        expect(recenterCameraRequests, 1);
        expect(tester.takeException(), isNull);
      },
    );

    test(
      'real Mapbox surface wires move and zoom gestures to follow disable',
      () {
        final source = File(
          'lib/features/run/presentation/widgets/run_mapbox_run_map.dart',
        ).readAsStringSync();

        expect(source, contains('onScrollListener: _handleManualGesture'));
        expect(source, contains('onZoomListener: _handleManualGesture'));
        expect(
          source,
          contains('onCameraChangeListener: _handleCameraChanged'),
        );

        expect(source, contains('RunMapboxManualGestureObserver('));
        expect(
          source,
          contains('onManualMapInteraction: _handleManualMapInteraction'),
        );
      },
    );

    test(
      'real Mapbox surface keeps viewport initial-only instead of rebuild-driven',
      () {
        final source = File(
          'lib/features/run/presentation/widgets/run_mapbox_run_map.dart',
        ).readAsStringSync();

        expect(
          source,
          contains('late final CameraViewportState _initialViewport'),
        );
        expect(source, contains('viewport: _initialViewport'));
        expect(source, isNot(contains('viewport: _initialViewport()')));
      },
    );

    test('real Mapbox surface keeps attribution right at scale height', () {
      final scaleBarSettings = runMapboxScaleBarSettings();
      final logoSettings = runMapboxLogoSettings();
      final attributionSettings = runMapboxAttributionSettings();

      expect(scaleBarSettings.enabled, isTrue);
      expect(scaleBarSettings.position, OrnamentPosition.TOP_LEFT);
      expect(scaleBarSettings.marginLeft, 16);
      expect(scaleBarSettings.marginTop, 80);

      expect(logoSettings.enabled, isTrue);
      expect(logoSettings.position, OrnamentPosition.TOP_LEFT);
      expect(logoSettings.marginLeft, scaleBarSettings.marginLeft);
      expect(logoSettings.marginTop, greaterThan(scaleBarSettings.marginTop!));
      expect(
        logoSettings.marginTop! - scaleBarSettings.marginTop!,
        lessThanOrEqualTo(24),
      );

      expect(attributionSettings.enabled, isTrue);
      expect(attributionSettings.clickable, isTrue);
      expect(attributionSettings.position, OrnamentPosition.TOP_RIGHT);
      expect(attributionSettings.marginTop, scaleBarSettings.marginTop);
      expect(attributionSettings.marginRight, 24);
      expect(attributionSettings.marginLeft, isNull);
    });

    test('null-to-current-position transition animates while following', () {
      final oldConfig = _surfaceConfig(
        mapViewState: const RunMapViewState.empty(),
        isFollowingRunner: true,
      );
      final newConfig = _surfaceConfig(
        mapViewState: _viewStateWithCurrentPosition(1.300899),
        isFollowingRunner: true,
      );

      expect(
        shouldAnimateRunMapboxCameraSync(
          oldConfig: oldConfig,
          newConfig: newConfig,
        ),
        isTrue,
      );
    });

    test('null-to-current-position transition does not animate off follow', () {
      final oldConfig = _surfaceConfig(
        mapViewState: const RunMapViewState.empty(),
        isFollowingRunner: false,
      );
      final newConfig = _surfaceConfig(
        mapViewState: _viewStateWithCurrentPosition(1.300899),
        isFollowingRunner: false,
      );

      expect(
        shouldAnimateRunMapboxCameraSync(
          oldConfig: oldConfig,
          newConfig: newConfig,
        ),
        isFalse,
      );
    });

    test('explicit recenter and restored follow still animate camera sync', () {
      final currentPosition = _viewStateWithCurrentPosition(1.300899);

      expect(
        shouldAnimateRunMapboxCameraSync(
          oldConfig: _surfaceConfig(
            mapViewState: currentPosition,
            isFollowingRunner: true,
          ),
          newConfig: _surfaceConfig(
            mapViewState: currentPosition,
            isFollowingRunner: true,
            recenterRequestId: 1,
          ),
        ),
        isTrue,
      );
      expect(
        shouldAnimateRunMapboxCameraSync(
          oldConfig: _surfaceConfig(
            mapViewState: currentPosition,
            isFollowingRunner: false,
          ),
          newConfig: _surfaceConfig(
            mapViewState: currentPosition,
            isFollowingRunner: true,
          ),
        ),
        isTrue,
      );
    });
  });

  group('RunMapboxSyncCoordinator', () {
    test(
      'replays the latest pending state after in-flight sync finishes',
      () async {
        final target = _FakeRunMapboxSyncTarget();
        final coordinator = RunMapboxSyncCoordinator(target);
        final firstBlocker = Completer<void>();
        target.nextBlocker = firstBlocker;

        final startedAt = DateTime.utc(2026, 6, 14, 7);
        RunMapboxSyncRequest request(double latitude) {
          return RunMapboxSyncRequest(
            mapViewState: RunMapViewState(
              currentPosition: RunLocationSample(
                recordedAt: startedAt,
                latitude: latitude,
                longitude: 103.8,
              ),
            ),
            isFollowingRunner: true,
          );
        }

        final firstSync = coordinator.sync(request(1.300000));
        await Future<void>.delayed(Duration.zero);

        expect(target.appliedLatitudes, <double>[1.300000]);

        unawaited(coordinator.sync(request(1.301000)));
        unawaited(coordinator.sync(request(1.302000)));
        await Future<void>.delayed(Duration.zero);

        expect(target.appliedLatitudes, <double>[1.300000]);

        firstBlocker.complete();
        await firstSync;

        expect(target.appliedLatitudes, <double>[1.300000, 1.302000]);
      },
    );

    test('cleans up the map adapter and ignores later sync requests', () async {
      final target = _FakeRunMapboxSyncTarget();
      final coordinator = RunMapboxSyncCoordinator(target);

      await coordinator.dispose();
      await coordinator.sync(
        const RunMapboxSyncRequest(
          mapViewState: RunMapViewState.empty(),
          isFollowingRunner: true,
        ),
      );

      expect(target.disposeCalls, 1);
      expect(target.appliedLatitudes, isEmpty);
    });

    test('dispose waits for an in-flight sync before cleanup', () async {
      final target = _FakeRunMapboxSyncTarget();
      final coordinator = RunMapboxSyncCoordinator(target);
      final blocker = Completer<void>();
      target.nextBlocker = blocker;

      final syncFuture = coordinator.sync(_syncRequest(1.300000));
      await Future<void>.delayed(Duration.zero);

      final disposeFuture = coordinator.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(target.appliedLatitudes, <double>[1.300000]);
      expect(target.disposeCalls, 0);

      blocker.complete();
      await syncFuture;
      await disposeFuture;

      expect(target.disposeCalls, 1);
    });

    test(
      'cancels camera animation without waiting for in-flight sync',
      () async {
        final target = _FakeRunMapboxSyncTarget();
        final coordinator = RunMapboxSyncCoordinator(target);
        final blocker = Completer<void>();
        target.nextBlocker = blocker;

        final syncFuture = coordinator.sync(_syncRequest(1.300000));
        await Future<void>.delayed(Duration.zero);

        await coordinator.cancelCameraAnimation();

        expect(target.appliedLatitudes, <double>[1.300000]);
        expect(target.cancelCameraAnimationCalls, 1);

        blocker.complete();
        await syncFuture;
      },
    );

    test(
      'dispose clears pending sync replay while apply is in flight',
      () async {
        final target = _FakeRunMapboxSyncTarget();
        final coordinator = RunMapboxSyncCoordinator(target);
        final blocker = Completer<void>();
        target.nextBlocker = blocker;

        final syncFuture = coordinator.sync(_syncRequest(1.300000));
        await Future<void>.delayed(Duration.zero);

        unawaited(coordinator.sync(_syncRequest(1.301000)));
        unawaited(coordinator.sync(_syncRequest(1.302000)));
        final disposeFuture = coordinator.dispose();

        blocker.complete();
        await syncFuture;
        await disposeFuture;

        expect(target.appliedLatitudes, <double>[1.300000]);
        expect(target.disposeCalls, 1);
      },
    );

    test('dispose is idempotent and no apply runs after disposal', () async {
      final target = _FakeRunMapboxSyncTarget();
      final coordinator = RunMapboxSyncCoordinator(target);

      await coordinator.dispose();
      await coordinator.dispose();
      await coordinator.sync(_syncRequest(1.300000));

      expect(target.disposeCalls, 1);
      expect(target.appliedLatitudes, isEmpty);
    });
  });

  group('RunMapboxStyleReadySyncController', () {
    test('defers native sync until the Mapbox style is loaded', () async {
      final target = _FakeRunMapboxSyncTarget();
      final controller = RunMapboxStyleReadySyncController(
        RunMapboxSyncCoordinator(target),
      );

      await controller.sync(_syncRequest(1.300899));

      expect(target.appliedLatitudes, isEmpty);

      await controller.markStyleLoaded();

      expect(target.appliedLatitudes, <double>[1.300899]);
    });

    test(
      'applies only the latest pending state when style becomes ready',
      () async {
        final target = _FakeRunMapboxSyncTarget();
        final controller = RunMapboxStyleReadySyncController(
          RunMapboxSyncCoordinator(target),
        );

        await controller.sync(
          const RunMapboxSyncRequest(
            mapViewState: RunMapViewState.empty(),
            isFollowingRunner: true,
          ),
        );
        await controller.sync(_syncRequest(1.301234));

        await controller.markStyleLoaded();

        expect(target.appliedLatitudes, <double>[1.301234]);
      },
    );

    test('syncs null-to-non-null currentPosition after style load', () async {
      final target = _FakeRunMapboxSyncTarget();
      final controller = RunMapboxStyleReadySyncController(
        RunMapboxSyncCoordinator(target),
      );

      await controller.markStyleLoaded();
      await controller.sync(
        const RunMapboxSyncRequest(
          mapViewState: RunMapViewState.empty(),
          isFollowingRunner: true,
        ),
      );
      await controller.sync(_syncRequest(1.302345));

      expect(target.appliedLatitudes, <double?>[null, 1.302345]);
    });

    test('syncs marker state even when camera follow is disabled', () async {
      final target = _FakeRunMapboxSyncTarget();
      final controller = RunMapboxStyleReadySyncController(
        RunMapboxSyncCoordinator(target),
      );
      await controller.markStyleLoaded();

      await controller.sync(
        RunMapboxSyncRequest(
          mapViewState: _viewStateWithCurrentPosition(1.303456),
          isFollowingRunner: false,
        ),
      );

      expect(target.appliedLatitudes, <double>[1.303456]);
      expect(target.appliedFollowStates, <bool>[false]);
      expect(target.appliedCameraMoveIntents, <bool>[false]);
    });

    test(
      'forwards manual gesture camera cancellation to the native seam',
      () async {
        final target = _FakeRunMapboxSyncTarget();
        final controller = RunMapboxStyleReadySyncController(
          RunMapboxSyncCoordinator(target),
        );

        await controller.cancelCameraAnimation();

        expect(target.cancelCameraAnimationCalls, 1);
        expect(target.appliedLatitudes, isEmpty);
      },
    );

    test('allows camera movement only for follow or explicit recenter', () {
      expect(
        RunMapboxSyncRequest(
          mapViewState: _viewStateWithCurrentPosition(1.300899),
          isFollowingRunner: true,
        ).shouldMoveCamera,
        isTrue,
      );
      expect(
        RunMapboxSyncRequest(
          mapViewState: _viewStateWithCurrentPosition(1.300899),
          isFollowingRunner: false,
        ).shouldMoveCamera,
        isFalse,
      );
      expect(
        RunMapboxSyncRequest(
          mapViewState: _viewStateWithCurrentPosition(1.300899),
          isFollowingRunner: false,
          animateCamera: true,
        ).shouldMoveCamera,
        isTrue,
      );
    });

    test('reports camera request reason without exposing coordinates', () {
      expect(
        RunMapboxSyncRequest(
          mapViewState: _viewStateWithCurrentPosition(1.300899),
          isFollowingRunner: true,
        ).cameraMoveReason,
        'follow',
      );
      expect(
        RunMapboxSyncRequest(
          mapViewState: _viewStateWithCurrentPosition(1.300899),
          isFollowingRunner: false,
        ).cameraMoveReason,
        'skipped',
      );
      expect(
        RunMapboxSyncRequest(
          mapViewState: _viewStateWithCurrentPosition(1.300899),
          isFollowingRunner: false,
          animateCamera: true,
        ).cameraMoveReason,
        'recenter',
      );
    });

    test(
      'camera diagnostics mark unknown native movement while follow is off',
      () {
        final diagnostics = RunMapboxFollowQaDiagnostics(
          enabled: true,
          screenPath: 'active',
        );

        diagnostics
          ..updateMapState(
            mapPath: 'mapbox',
            isFollowingRunner: false,
            recenterRequestId: 0,
          )
          ..recordCameraStateSample(
            latitude: 1.300899,
            longitude: 103.800000,
            isFollowingRunner: false,
          )
          ..recordCameraStateSample(
            latitude: 1.300999,
            longitude: 103.800000,
            isFollowingRunner: false,
          );

        expect(diagnostics.cameraStateSampleCount, 2);
        expect(diagnostics.cameraCenterChangedCount, 1);
        expect(diagnostics.cameraCenterChanged, isTrue);
        expect(diagnostics.unknownNativeCameraChangeCount, 1);
        expect(diagnostics.lastCameraMovementSource, 'unknown/native');
      },
    );

    test('camera interrupt gate rejects stale in-flight camera moves', () {
      final gate = RunMapboxCameraInterruptGate();
      final beforeManualGesture = gate.capture();

      gate.interrupt();

      expect(gate.allows(beforeManualGesture), isFalse);
      expect(gate.allows(gate.capture()), isTrue);
    });
  });

  group('RunMapboxRunnerMarkerSyncController', () {
    test(
      'first non-null currentPosition creates one styled runner marker',
      () async {
        final operations = _FakeRunnerMarkerOperations();
        final controller =
            RunMapboxRunnerMarkerSyncController<_FakeRunnerMarker>();

        await controller.sync(
          mapViewState: _viewStateWithCurrentPosition(
            1.300899,
            longitude: 103.812345,
          ),
          operations: operations,
        );

        expect(operations.createCalls, 1);
        expect(operations.updateCalls, 0);
        expect(operations.deleteCalls, 0);
        expect(operations.lastPoint, <double>[103.812345, 1.300899]);
        expect(operations.createdOptions.single.circleRadius, 12);
        expect(operations.createdOptions.single.circleStrokeWidth, 4);
        expect(operations.createdOptions.single.circleSortKey, 1000);
        expect(
          operations.createdOptions.single.circleColor,
          const Color(0xFFFF6818).toARGB32(),
        );
        expect(
          operations.createdOptions.single.circleStrokeColor,
          Colors.white.toARGB32(),
        );
        expect(controller.hasMarker, isTrue);
      },
    );

    test('second non-null currentPosition updates existing marker', () async {
      final operations = _FakeRunnerMarkerOperations();
      final controller =
          RunMapboxRunnerMarkerSyncController<_FakeRunnerMarker>();

      await controller.sync(
        mapViewState: _viewStateWithCurrentPosition(1.300000),
        operations: operations,
      );
      await controller.sync(
        mapViewState: _viewStateWithCurrentPosition(
          1.301000,
          longitude: 103.801000,
        ),
        operations: operations,
      );

      expect(operations.createCalls, 1);
      expect(operations.updateCalls, 1);
      expect(operations.deleteCalls, 0);
      expect(operations.lastPoint, <double>[103.801000, 1.301000]);
      expect(
        operations.updatedMarkers.single,
        same(operations.createdMarkers.single),
      );
      expect(controller.hasMarker, isTrue);
    });

    test('null currentPosition deletes existing marker once', () async {
      final operations = _FakeRunnerMarkerOperations();
      final controller =
          RunMapboxRunnerMarkerSyncController<_FakeRunnerMarker>();

      await controller.sync(
        mapViewState: _viewStateWithCurrentPosition(1.300000),
        operations: operations,
      );
      await controller.sync(
        mapViewState: const RunMapViewState.empty(),
        operations: operations,
      );
      await controller.sync(
        mapViewState: const RunMapViewState.empty(),
        operations: operations,
      );

      expect(operations.createCalls, 1);
      expect(operations.updateCalls, 0);
      expect(operations.deleteCalls, 1);
      expect(
        operations.deletedMarkers.single,
        same(operations.createdMarkers.single),
      );
      expect(controller.hasMarker, isFalse);
    });

    test('route-only sync does not delete existing runner marker', () async {
      final operations = _FakeRunnerMarkerOperations();
      final controller =
          RunMapboxRunnerMarkerSyncController<_FakeRunnerMarker>();
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      await controller.sync(
        mapViewState: _viewStateWithCurrentPosition(1.300000),
        operations: operations,
      );
      await controller.sync(
        mapViewState: RunMapViewState(
          currentPosition: RunLocationSample(
            recordedAt: startedAt.add(const Duration(seconds: 60)),
            latitude: 1.300500,
            longitude: 103.800500,
          ),
          routeSegments: [
            [
              RunLocationSample(
                recordedAt: startedAt,
                latitude: 1.300000,
                longitude: 103.800000,
              ),
              RunLocationSample(
                recordedAt: startedAt.add(const Duration(seconds: 60)),
                latitude: 1.300500,
                longitude: 103.800500,
              ),
            ],
          ],
        ),
        operations: operations,
      );

      expect(operations.createCalls, 1);
      expect(operations.updateCalls, 1);
      expect(operations.deleteCalls, 0);
      expect(operations.lastPoint, <double>[103.800500, 1.300500]);
      expect(controller.hasMarker, isTrue);
    });
  });

  group('RunMapPlaceholder', () {
    testWidgets(
      'does not render route geometry from preview or current positions only',
      (tester) async {
        final startedAt = DateTime.utc(2026, 6, 14, 7);

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 320,
              height: 320,
              child: RunMapPlaceholder(
                mapViewState: RunMapViewState(
                  previewPosition: _sample(startedAt, latitude: 1.300000),
                  currentPosition: _sample(
                    startedAt.add(const Duration(seconds: 30)),
                    latitude: 1.301000,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('run_map_route_polyline')), findsNothing);
        expect(find.byKey(const Key('run_map_runner_marker')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders route geometry from accepted route segments', (
      tester,
    ) async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 320,
            child: RunMapPlaceholder(
              mapViewState: RunMapViewState(
                currentPosition: _sample(
                  startedAt.add(const Duration(seconds: 60)),
                  latitude: 1.300899,
                ),
                acceptedRouteSegments: [
                  [
                    _sample(startedAt, latitude: 1.300000),
                    _sample(
                      startedAt.add(const Duration(seconds: 60)),
                      latitude: 1.300899,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('run_map_route_polyline')), findsOneWidget);
      expect(find.byKey(const Key('run_map_runner_marker')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders route geometry from display route segments', (
      tester,
    ) async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 320,
            child: RunMapPlaceholder(
              mapViewState: RunMapViewState(
                currentPosition: _sample(
                  startedAt.add(const Duration(seconds: 60)),
                  latitude: 1.300899,
                ),
                displayRouteSegments: [
                  [
                    _sample(startedAt, latitude: 1.300000),
                    _sample(
                      startedAt.add(const Duration(seconds: 60)),
                      latitude: 1.300899,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('run_map_route_polyline')), findsOneWidget);
      expect(find.byKey(const Key('run_map_runner_marker')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unfollowed marker alignment uses display position fallback', (
      tester,
    ) async {
      final startedAt = DateTime.utc(2026, 6, 14, 7);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 320,
            child: RunMapPlaceholder(
              isFollowingRunner: false,
              mapViewState: RunMapViewState(
                previewPosition: _sample(
                  startedAt.add(const Duration(seconds: 60)),
                  latitude: 1.301000,
                ),
                acceptedRouteSegments: [
                  [
                    _sample(startedAt, latitude: 1.300000),
                    _sample(
                      startedAt.add(const Duration(seconds: 60)),
                      latitude: 1.301000,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

      final markerAlign = tester.widget<Align>(
        find.ancestor(
          of: find.byKey(const Key('run_map_runner_marker')),
          matching: find.byType(Align),
        ),
      );

      expect(markerAlign.alignment, isNot(Alignment.center));
      expect(tester.takeException(), isNull);
    });
  });

  group('CompletedRouteMapSurface ornaments', () {
    test('preview keeps Mapbox controls near the top of the clipped map', () {
      final scaleBar = completedRouteScaleBarSettings(isExpanded: false);
      final logo = completedRouteLogoSettings(isExpanded: false);
      final attribution = completedRouteAttributionSettings(isExpanded: false);

      expect(scaleBar.enabled, isTrue);
      expect(scaleBar.position, OrnamentPosition.TOP_LEFT);
      expect(scaleBar.marginTop, 10);
      expect(logo.enabled, isTrue);
      expect(logo.position, OrnamentPosition.TOP_LEFT);
      expect(logo.marginTop, 32);
      expect(attribution.enabled, isTrue);
      expect(attribution.clickable, isTrue);
      expect(attribution.position, OrnamentPosition.TOP_RIGHT);
      expect(attribution.marginTop, 10);
    });

    test('fullscreen keeps roomier Mapbox control spacing', () {
      final scaleBar = completedRouteScaleBarSettings(isExpanded: true);
      final logo = completedRouteLogoSettings(isExpanded: true);
      final attribution = completedRouteAttributionSettings(isExpanded: true);

      expect(scaleBar.marginTop, 80);
      expect(logo.marginTop, 104);
      expect(attribution.marginTop, 80);
      expect(attribution.marginRight, 24);
    });
  });

  group('RunMapboxRunnerMarkerAnnotation', () {
    test('does not create a runner marker without currentPosition', () {
      expect(
        RunMapboxRunnerMarkerAnnotation.fromViewState(
          const RunMapViewState.empty(),
        ),
        isNull,
      );
    });

    test('does not use fallback camera coordinates as runner marker', () {
      final fallbackCamera = RunMapboxCameraRequest.initialForMapViewState(
        const RunMapViewState.empty(),
      );

      expect(fallbackCamera.center, RunMapboxCameraRequest.fallbackCenter);
      expect(
        RunMapboxRunnerMarkerAnnotation.fromViewState(
          const RunMapViewState.empty(),
        ),
        isNull,
      );
    });

    test('creates a visible runner circle from currentPosition', () {
      final options = RunMapboxRunnerMarkerAnnotation.fromViewState(
        _viewStateWithCurrentPosition(1.300899, longitude: 103.812345),
      );

      expect(options, isNotNull);
      expect(options!.circleRadius, 12);
      expect(options.circleStrokeWidth, 4);
      expect(options.circleSortKey, 1000);
      expect(options.circleColor, const Color(0xFFFF6818).toARGB32());
      expect(options.circleStrokeColor, Colors.white.toARGB32());
      expect(options.geometry.toJson()['coordinates'], <double>[
        103.812345,
        1.300899,
      ]);
    });

    test('creates a visible runner circle from preview display position', () {
      final preview = RunLocationSample(
        recordedAt: DateTime.utc(2026, 6, 14, 7),
        latitude: 1.300555,
        longitude: 103.812555,
      );
      final options = RunMapboxRunnerMarkerAnnotation.fromViewState(
        RunMapViewState(previewPosition: preview),
      );

      expect(options, isNotNull);
      expect(options!.geometry.toJson()['coordinates'], <double>[
        103.812555,
        1.300555,
      ]);
    });
  });

  group('RunMapboxGeometry', () {
    test('initial camera uses current position when GPS is available', () {
      // Given: a run map state with a current GPS sample.
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final viewState = RunMapViewState(
        currentPosition: RunLocationSample(
          recordedAt: startedAt,
          latitude: 1.301234,
          longitude: 103.812345,
        ),
      );

      // When: Mapbox derives its initial camera.
      final request = RunMapboxCameraRequest.initialForMapViewState(viewState);

      // Then: the camera starts at the runner location, not the fallback.
      expect(request.center.latitude, 1.301234);
      expect(request.center.longitude, 103.812345);
      expect(request.zoom, 16);
    });

    test('initial camera uses local fallback while GPS is unavailable', () {
      // Given: no current GPS sample has arrived yet.
      const viewState = RunMapViewState.empty();

      // When: Mapbox derives its initial camera.
      final request = RunMapboxCameraRequest.initialForMapViewState(viewState);

      // Then: it uses the presentation-only local fallback, not a world view.
      expect(request.center, RunMapboxCameraRequest.fallbackCenter);
      expect(request.zoom, 14);
    });

    test('initial camera uses preview display position before active GPS', () {
      final preview = RunLocationSample(
        recordedAt: DateTime.utc(2026, 6, 14, 7),
        latitude: 1.301111,
        longitude: 103.811111,
      );
      final viewState = RunMapViewState(previewPosition: preview);

      final request = RunMapboxCameraRequest.initialForMapViewState(viewState);

      expect(request.center.position, <double>[103.811111, 1.301111]);
      expect(request.zoom, 16);
    });

    test('current position camera becomes available after GPS transition', () {
      // Given: GPS is initially unavailable.
      const waitingForGps = RunMapViewState.empty();
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      final gpsReady = RunMapViewState(
        currentPosition: RunLocationSample(
          recordedAt: startedAt,
          latitude: 1.300899,
          longitude: 103.800000,
        ),
      );

      // When: the camera request is derived before and after GPS arrives.
      final beforeGps = RunMapboxCameraRequest.forCurrentPosition(
        waitingForGps,
      );
      final afterGps = RunMapboxCameraRequest.forCurrentPosition(gpsReady);

      // Then: runtime camera movement remains gated on real current position.
      expect(beforeGps, isNull);
      expect(afterGps, isNotNull);
      expect(afterGps!.center.position, <double>[103.800000, 1.300899]);
    });

    test('uses longitude-first Mapbox coordinate ordering', () {
      final coordinate = RunMapboxCoordinate.fromSample(
        RunLocationSample(
          recordedAt: DateTime.utc(2026, 6, 14, 7),
          latitude: 1.300899,
          longitude: 103.800000,
        ),
      );

      expect(coordinate.position, <double>[103.800000, 1.300899]);
    });

    test('keeps route segments separate for pause and resume gaps', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      RunLocationSample sample(int seconds, double latitude) {
        return RunLocationSample(
          recordedAt: startedAt.add(Duration(seconds: seconds)),
          latitude: latitude,
          longitude: 103.800000,
        );
      }

      final geometry = RunMapboxRouteGeometry.fromViewState(
        RunMapViewState(
          routeSegments: [
            [sample(0, 1.300000), sample(60, 1.300899)],
            [sample(180, 1.301100), sample(240, 1.301500)],
          ],
        ),
      );

      expect(geometry.segments, hasLength(2));
      expect(geometry.segments.first.map((point) => point.position), [
        <double>[103.800000, 1.300000],
        <double>[103.800000, 1.300899],
      ]);
      expect(geometry.segments.last.map((point) => point.position), [
        <double>[103.800000, 1.301100],
        <double>[103.800000, 1.301500],
      ]);
    });

    test('uses accepted route segments without preview or current points', () {
      final startedAt = DateTime.utc(2026, 6, 14, 7);
      RunLocationSample sample(int seconds, double latitude) {
        return RunLocationSample(
          recordedAt: startedAt.add(Duration(seconds: seconds)),
          latitude: latitude,
          longitude: 103.800000,
        );
      }

      final geometry = RunMapboxRouteGeometry.fromViewState(
        RunMapViewState(
          previewPosition: sample(0, 1.299000),
          currentPosition: sample(30, 1.399000),
          acceptedRouteSegments: [
            [sample(60, 1.300000), sample(120, 1.300899)],
          ],
        ),
      );

      expect(geometry.segments, hasLength(1));
      expect(geometry.segments.single.map((point) => point.position), [
        <double>[103.800000, 1.300000],
        <double>[103.800000, 1.300899],
      ]);
    });

    test('real Mapbox route manager configures round line rendering', () {
      final source = File(
        'lib/features/run/presentation/widgets/run_mapbox_run_map.dart',
      ).readAsStringSync();

      expect(source, contains('setLineCap(LineCap.ROUND)'));
      expect(source, contains('setLineJoin(LineJoin.ROUND)'));
    });
  });

  test('Mapbox surface and adapter do not import each other cyclically', () {
    final surfaceSource = File(
      'lib/features/run/presentation/widgets/run_tracking_map_surface.dart',
    ).readAsStringSync();
    final adapterSource = File(
      'lib/features/run/presentation/widgets/run_mapbox_run_map.dart',
    ).readAsStringSync();

    expect(surfaceSource, contains("import 'run_mapbox_run_map.dart';"));
    expect(surfaceSource, contains("import 'run_mapbox_surface_config.dart';"));
    expect(
      adapterSource,
      isNot(contains("import 'run_tracking_map_surface.dart';")),
    );
    expect(adapterSource, contains("import 'run_mapbox_surface_config.dart';"));
  });
}

RunMapboxSyncRequest _syncRequest(double latitude) {
  return RunMapboxSyncRequest(
    mapViewState: _viewStateWithCurrentPosition(latitude),
    isFollowingRunner: true,
  );
}

RunMapboxSurfaceConfig _surfaceConfig({
  required RunMapViewState mapViewState,
  required bool isFollowingRunner,
  int recenterRequestId = 0,
}) {
  return RunMapboxSurfaceConfig(
    accessToken: _demoMapboxPublicToken,
    mapViewState: mapViewState,
    isFollowingRunner: isFollowingRunner,
    recenterRequestId: recenterRequestId,
    showRecenterButton: true,
    recenterButtonBottom: 176,
  );
}

RunLocationSample _sample(
  DateTime recordedAt, {
  double latitude = 1.300000,
  double longitude = 103.800000,
}) {
  return RunLocationSample(
    recordedAt: recordedAt,
    latitude: latitude,
    longitude: longitude,
  );
}

RunMapViewState _viewStateWithCurrentPosition(
  double latitude, {
  double longitude = 103.8,
}) {
  return RunMapViewState(
    currentPosition: RunLocationSample(
      recordedAt: DateTime.utc(2026, 6, 14, 7),
      latitude: latitude,
      longitude: longitude,
    ),
  );
}

class _FakeRunMapboxSyncTarget implements RunMapboxSyncTarget {
  final List<double?> appliedLatitudes = <double?>[];
  final List<bool> appliedFollowStates = <bool>[];
  final List<bool> appliedCameraMoveIntents = <bool>[];
  Completer<void>? nextBlocker;
  int cancelCameraAnimationCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> apply(RunMapboxSyncRequest request) async {
    appliedLatitudes.add(request.mapViewState.displayPosition?.latitude);
    appliedFollowStates.add(request.isFollowingRunner);
    appliedCameraMoveIntents.add(request.shouldMoveCamera);
    final blocker = nextBlocker;
    nextBlocker = null;
    if (blocker != null) {
      await blocker.future;
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  Future<void> cancelCameraAnimation() async {
    cancelCameraAnimationCalls++;
  }
}

class _FakeRunnerMarker {
  _FakeRunnerMarker(this.options);

  CircleAnnotationOptions options;
}

class _FakeRunnerMarkerOperations
    implements RunMapboxRunnerMarkerOperations<_FakeRunnerMarker> {
  final List<CircleAnnotationOptions> createdOptions =
      <CircleAnnotationOptions>[];
  final List<_FakeRunnerMarker> createdMarkers = <_FakeRunnerMarker>[];
  final List<_FakeRunnerMarker> updatedMarkers = <_FakeRunnerMarker>[];
  final List<_FakeRunnerMarker> deletedMarkers = <_FakeRunnerMarker>[];
  List<double>? lastPoint;

  int get createCalls => createdMarkers.length;
  int get updateCalls => updatedMarkers.length;
  int get deleteCalls => deletedMarkers.length;

  @override
  Future<_FakeRunnerMarker> create(CircleAnnotationOptions options) async {
    createdOptions.add(options);
    lastPoint = _coordinatesFor(options);
    final marker = _FakeRunnerMarker(options);
    createdMarkers.add(marker);
    return marker;
  }

  @override
  Future<void> update(
    _FakeRunnerMarker marker,
    CircleAnnotationOptions options,
  ) async {
    marker.options = options;
    updatedMarkers.add(marker);
    lastPoint = _coordinatesFor(options);
  }

  @override
  Future<void> delete(_FakeRunnerMarker marker) async {
    deletedMarkers.add(marker);
  }

  List<double> _coordinatesFor(CircleAnnotationOptions options) {
    return (options.geometry.toJson()['coordinates'] as List<Object?>)
        .cast<double>();
  }
}
