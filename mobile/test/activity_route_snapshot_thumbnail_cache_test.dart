import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_thumbnail_viewport.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_snapshot_thumbnail_cache.dart';

RunRouteSnapshot _routeFixture({
  double latitudeOffset = 0,
  double longitudeOffset = 0,
}) {
  final startedAt = DateTime.utc(2026, 6, 18, 8, 10);
  return RunRouteSnapshot(
    segments: [
      [
        RunLocationSample(
          recordedAt: startedAt,
          latitude: 1.301 + latitudeOffset,
          longitude: 103.801 + longitudeOffset,
        ),
        RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 90)),
          latitude: 1.302 + latitudeOffset,
          longitude: 103.802 + longitudeOffset,
        ),
      ],
    ],
    lastKnownLocation: RunLocationSample(
      recordedAt: startedAt.add(const Duration(seconds: 90)),
      latitude: 1.302 + latitudeOffset,
      longitude: 103.802 + longitudeOffset,
    ),
  );
}

RunRouteSnapshot _singlePointRouteFixture() {
  final startedAt = DateTime.utc(2026, 6, 18, 8, 10);
  final location = RunLocationSample(
    recordedAt: startedAt,
    latitude: 1.301,
    longitude: 103.801,
  );
  return RunRouteSnapshot(
    segments: [
      [location],
    ],
    lastKnownLocation: location,
  );
}

RunRouteSnapshot _turnRouteFixture() {
  final startedAt = DateTime.utc(2026, 6, 18, 8, 10);
  return RunRouteSnapshot(
    segments: [
      [
        RunLocationSample(
          recordedAt: startedAt,
          latitude: 1.3000,
          longitude: 103.8000,
        ),
        RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 60)),
          latitude: 1.3009,
          longitude: 103.8000,
        ),
        RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 120)),
          latitude: 1.3009,
          longitude: 103.8012,
        ),
      ],
    ],
    lastKnownLocation: RunLocationSample(
      recordedAt: startedAt.add(const Duration(seconds: 120)),
      latitude: 1.3009,
      longitude: 103.8012,
    ),
  );
}

RunRouteSnapshot _longNarrowRouteFixture() {
  final startedAt = DateTime.utc(2026, 6, 18, 8, 10);
  return RunRouteSnapshot(
    segments: [
      [
        RunLocationSample(
          recordedAt: startedAt,
          latitude: 1.3000,
          longitude: 103.8000,
        ),
        RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 120)),
          latitude: 1.3060,
          longitude: 103.8001,
        ),
      ],
    ],
    lastKnownLocation: RunLocationSample(
      recordedAt: startedAt.add(const Duration(seconds: 120)),
      latitude: 1.3060,
      longitude: 103.8001,
    ),
  );
}

ActivityRouteThumbnailRequest _request({
  required RunRouteSnapshot route,
  Size logicalSize = const Size(88, 88),
  double devicePixelRatio = 3,
  bool allowExternalStaticMap = true,
  bool isDemoRoute = true,
  bool isCurrentSessionRoute = false,
  bool isTrustedPersistedRoutePreview = false,
  String? activityId = 'activity-1',
}) {
  return ActivityRouteThumbnailRequest(
    route: route,
    logicalSize: logicalSize,
    devicePixelRatio: devicePixelRatio,
    allowExternalStaticMap: allowExternalStaticMap,
    isDemoRoute: isDemoRoute,
    isCurrentSessionRoute: isCurrentSessionRoute,
    isTrustedPersistedRoutePreview: isTrustedPersistedRoutePreview,
    activityId: activityId,
  );
}

class _FakeSnapshotThumbnailGenerator
    implements ActivityRouteSnapshotThumbnailGenerator {
  _FakeSnapshotThumbnailGenerator(this._generate);

  final Future<ActivityRouteThumbnailResult> Function(
    ActivityRouteSnapshotThumbnailGenerationRequest request,
  )
  _generate;
  int requestCount = 0;
  ActivityRouteSnapshotThumbnailGenerationRequest? lastRequest;

  @override
  Future<ActivityRouteThumbnailResult> generate(
    ActivityRouteSnapshotThumbnailGenerationRequest request,
  ) {
    requestCount += 1;
    lastRequest = request;
    return _generate(request);
  }
}

void main() {
  test(
    'snapshot generation request does not carry endpoint marker overlays',
    () {
      final request = _request(route: _turnRouteFixture());

      final generation =
          ActivityRouteSnapshotThumbnailGenerationRequest.fromThumbnailRequest(
            request,
            styleId: 'test',
          );

      expect(generation, isNotNull);
      expect(generation!.projectedStart, Offset.zero);
      expect(generation.projectedEnd, Offset.zero);
    },
  );

  test(
    'owner-scoped cache-only lookup never generates or leaks another owner artifact',
    () async {
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      final request = _request(route: _routeFixture());
      final key = ActivityRouteSnapshotThumbnailCacheKey.fromRequest(request);
      final bytes = Uint8List.fromList(const <int>[137, 80, 78, 71]);
      final stored = ActivityRouteThumbnailResult.readyPng(bytes);
      cache.store(key, stored, ownerUid: 'owner-a');

      final ownerA = CachedActivityRouteThumbnailProvider(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        ownerUidProvider: () => 'owner-a',
      );
      final ownerB = CachedActivityRouteThumbnailProvider(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        ownerUidProvider: () => 'owner-b',
      );

      expect(await ownerA.resolve(request), same(stored));
      expect(
        await ownerB.resolve(request),
        const ActivityRouteThumbnailResult.unavailable(),
      );
      expect(
        await ownerA.resolve(
          _request(route: _routeFixture(), activityId: 'other'),
        ),
        const ActivityRouteThumbnailResult.unavailable(),
      );
    },
  );
  test('auth transition evicts prior owner sensitive thumbnail', () async {
    var owner = 'owner-a';
    final cache = ActivityRouteSnapshotThumbnailMemoryCache();
    final request = _request(route: _routeFixture());
    final key = ActivityRouteSnapshotThumbnailCacheKey.fromRequest(request);
    final artifact = ActivityRouteThumbnailResult.readyPng(
      Uint8List.fromList(const <int>[1]),
    );
    cache.store(key, artifact, ownerUid: owner);
    final provider = CachedActivityRouteThumbnailProvider(
      cache: cache,
      ownerUidProvider: () => owner,
    );
    expect(await provider.resolve(request), same(artifact));
    owner = 'owner-b';
    expect(
      await provider.resolve(request),
      const ActivityRouteThumbnailResult.unavailable(),
    );
    owner = 'owner-a';
    expect(
      await provider.resolve(request),
      const ActivityRouteThumbnailResult.unavailable(),
    );
  });
  test(
    'app auth lifecycle evicts global History bytes before a fresh resolver can reuse them',
    () async {
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      final request = _request(route: _routeFixture());
      final key = ActivityRouteSnapshotThumbnailCacheKey.fromRequest(request);
      final artifact = ActivityRouteThumbnailResult.readyPng(
        Uint8List.fromList(const <int>[1]),
      );
      final lifecycle = ActivityRouteSnapshotThumbnailArtifactLifecycle(
        initialOwnerUid: 'owner-a',
      );

      cache.store(key, artifact, ownerUid: 'owner-a');
      lifecycle.syncOwner('owner-a');
      expect(
        await CachedActivityRouteThumbnailProvider(
          cache: ActivityRouteSnapshotThumbnailMemoryCache(),
          ownerUidProvider: () => 'owner-a',
        ).resolve(request),
        same(artifact),
      );

      lifecycle.syncOwner(null);
      expect(
        await CachedActivityRouteThumbnailProvider(
          cache: ActivityRouteSnapshotThumbnailMemoryCache(),
          ownerUidProvider: () => 'owner-a',
        ).resolve(request),
        const ActivityRouteThumbnailResult.unavailable(),
      );
    },
  );
  test(
    'app auth lifecycle evicts owner A global History bytes on an owner switch',
    () async {
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      final request = _request(route: _routeFixture());
      final key = ActivityRouteSnapshotThumbnailCacheKey.fromRequest(request);
      final lifecycle = ActivityRouteSnapshotThumbnailArtifactLifecycle(
        initialOwnerUid: 'owner-a',
      );
      cache.store(
        key,
        ActivityRouteThumbnailResult.readyPng(
          Uint8List.fromList(const <int>[2]),
        ),
        ownerUid: 'owner-a',
      );

      lifecycle.syncOwner('owner-b');

      expect(
        await CachedActivityRouteThumbnailProvider(
          cache: ActivityRouteSnapshotThumbnailMemoryCache(),
          ownerUidProvider: () => 'owner-a',
        ).resolve(request),
        const ActivityRouteThumbnailResult.unavailable(),
      );
    },
  );
  test(
    'delayed owner A generation does not store or return after an auth switch',
    () async {
      var owner = 'owner-a';
      final lifecycle = ActivityRouteSnapshotThumbnailArtifactLifecycle(
        initialOwnerUid: 'test-reset',
      );
      lifecycle.syncOwner(owner);
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      final request = _request(route: _routeFixture());
      final generation = Completer<ActivityRouteThumbnailResult>();
      final bytes = Uint8List.fromList(const <int>[3, 4, 5, 6]);
      final generator = _FakeSnapshotThumbnailGenerator(
        (request) => generation.future,
      );
      final provider = CachedActivityRouteThumbnailProvider(
        cache: cache,
        generator: generator,
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
        ownerUidProvider: () => owner,
      );

      final delayedOwnerAResult = provider.resolve(request);
      expect(generator.requestCount, 1);

      owner = 'owner-b';
      lifecycle.syncOwner(owner);
      generation.complete(ActivityRouteThumbnailResult.readyPng(bytes));

      expect(
        await delayedOwnerAResult,
        const ActivityRouteThumbnailResult.unavailable(),
      );
      expect(cache.length, 0);
      expect(
        await CachedActivityRouteThumbnailProvider(
          cache: ActivityRouteSnapshotThumbnailMemoryCache(),
          ownerUidProvider: () => 'owner-a',
        ).resolve(request),
        const ActivityRouteThumbnailResult.unavailable(),
      );
    },
  );
  test(
    'fresh owner A generation does not reuse stale owner A in-flight work after owner cycle',
    () async {
      var owner = 'owner-a';
      final lifecycle = ActivityRouteSnapshotThumbnailArtifactLifecycle(
        initialOwnerUid: 'test-reset',
      );
      lifecycle.syncOwner(owner);
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      final request = _request(route: _routeFixture());
      final staleOwnerA = Completer<ActivityRouteThumbnailResult>();
      final ownerB = Completer<ActivityRouteThumbnailResult>();
      final freshOwnerA = Completer<ActivityRouteThumbnailResult>();
      final generations = <Completer<ActivityRouteThumbnailResult>>[
        staleOwnerA,
        ownerB,
        freshOwnerA,
      ];
      final freshOwnerABytes = Uint8List.fromList(const <int>[41, 42, 43, 44]);
      final staleOwnerABytes = Uint8List.fromList(const <int>[51, 52, 53, 54]);
      final ownerBBytes = Uint8List.fromList(const <int>[61, 62, 63, 64]);
      final generator = _FakeSnapshotThumbnailGenerator(
        (request) => generations.removeAt(0).future,
      );
      final provider = CachedActivityRouteThumbnailProvider(
        cache: cache,
        generator: generator,
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
        ownerUidProvider: () => owner,
      );

      final staleOwnerAResult = provider.resolve(request);
      expect(generator.requestCount, 1);

      owner = 'owner-b';
      lifecycle.syncOwner(owner);
      final ownerBResult = provider.resolve(request);
      expect(generator.requestCount, 2);

      owner = 'owner-a';
      lifecycle.syncOwner(owner);
      final freshOwnerAResult = provider.resolve(request);
      expect(generator.requestCount, 3);

      freshOwnerA.complete(
        ActivityRouteThumbnailResult.readyPng(freshOwnerABytes),
      );
      final resolvedFreshOwnerA = await freshOwnerAResult;
      expect(resolvedFreshOwnerA.state, ActivityRouteThumbnailState.readyImage);
      expect(resolvedFreshOwnerA.pngBytes, freshOwnerABytes);
      expect(cache.length, 1);

      staleOwnerA.complete(
        ActivityRouteThumbnailResult.readyPng(staleOwnerABytes),
      );
      expect(
        await staleOwnerAResult,
        const ActivityRouteThumbnailResult.unavailable(),
      );
      expect(cache.length, 1);
      expect(
        await CachedActivityRouteThumbnailProvider(
          cache: ActivityRouteSnapshotThumbnailMemoryCache(),
          ownerUidProvider: () => 'owner-a',
        ).resolve(request),
        same(resolvedFreshOwnerA),
      );

      owner = 'owner-b';
      ownerB.complete(ActivityRouteThumbnailResult.readyPng(ownerBBytes));
      await ownerBResult;
    },
  );
  test(
    'delayed owner A generation does not store or return after sign out',
    () async {
      String? owner = 'owner-a';
      final lifecycle = ActivityRouteSnapshotThumbnailArtifactLifecycle(
        initialOwnerUid: 'test-reset',
      );
      lifecycle.syncOwner(owner);
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      final request = _request(route: _routeFixture());
      final generation = Completer<ActivityRouteThumbnailResult>();
      final bytes = Uint8List.fromList(const <int>[30, 31, 32, 33]);
      final generator = _FakeSnapshotThumbnailGenerator(
        (request) => generation.future,
      );
      final provider = CachedActivityRouteThumbnailProvider(
        cache: cache,
        generator: generator,
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
        ownerUidProvider: () => owner,
      );

      final delayedOwnerAResult = provider.resolve(request);
      expect(generator.requestCount, 1);

      owner = null;
      lifecycle.syncOwner(owner);
      generation.complete(ActivityRouteThumbnailResult.readyPng(bytes));

      expect(
        await delayedOwnerAResult,
        const ActivityRouteThumbnailResult.unavailable(),
      );
      expect(cache.length, 0);
      expect(
        cache.resolve(
          ActivityRouteSnapshotThumbnailCacheKey.fromRequest(request),
          ownerUid: 'owner-a',
        ),
        isNull,
      );
      expect(
        await CachedActivityRouteThumbnailProvider(
          cache: ActivityRouteSnapshotThumbnailMemoryCache(),
          ownerUidProvider: () => 'owner-a',
        ).resolve(request),
        const ActivityRouteThumbnailResult.unavailable(),
      );
    },
  );
  test('delayed same-owner generation still stores and resolves', () async {
    const owner = 'owner-a';
    final lifecycle = ActivityRouteSnapshotThumbnailArtifactLifecycle(
      initialOwnerUid: 'test-reset',
    );
    lifecycle.syncOwner(owner);
    final cache = ActivityRouteSnapshotThumbnailMemoryCache();
    final request = _request(route: _routeFixture());
    final generation = Completer<ActivityRouteThumbnailResult>();
    final generator = _FakeSnapshotThumbnailGenerator(
      (request) => generation.future,
    );
    final provider = CachedActivityRouteThumbnailProvider(
      cache: cache,
      generator: generator,
      snapshotThumbnailsEnabled: true,
      hasValidMapboxToken: true,
      ownerUidProvider: () => owner,
    );

    final delayedResult = provider.resolve(request);
    generation.complete(
      ActivityRouteThumbnailResult.readyPng(
        Uint8List.fromList(const <int>[7, 8, 9, 10]),
      ),
    );
    final resolved = await delayedResult;

    expect(resolved.state, ActivityRouteThumbnailState.readyImage);
    expect(generator.requestCount, 1);
    expect(cache.length, 1);
    expect(
      await CachedActivityRouteThumbnailProvider(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        ownerUidProvider: () => owner,
      ).resolve(request),
      same(resolved),
    );
  });
  test('fractional DPR rounds to the canonical 3x generation dimensions', () {
    final request = _request(route: _routeFixture(), devicePixelRatio: 2.625);

    final generation =
        ActivityRouteSnapshotThumbnailGenerationRequest.fromThumbnailRequest(
          request,
          styleId: 'test',
        );

    expect(generation, isNotNull);
    expect(generation!.devicePixelRatio, 3);
    expect(generation.outputPixels, 264);
  });
  test('shared viewport derives deterministic camera for a turn route', () {
    final route = _turnRouteFixture();
    final viewport = ActivityRouteThumbnailViewport.fromRoute(
      route,
      logicalSize: const Size(88, 88),
    );

    expect(viewport.mode, ActivityRouteThumbnailViewportMode.meaningfulRoute);
    expect(viewport.centerLatitude, closeTo(1.30045, 0.000001));
    expect(viewport.centerLongitude, closeTo(103.8006, 0.000001));
    expect(viewport.cameraZoom, inInclusiveRange(11.5, 17.2));

    final camera = ActivityRouteSnapshotCamera.fromViewport(viewport);
    expect(camera, isNotNull);
    expect(camera!.centerLatitude, viewport.centerLatitude);
    expect(camera.centerLongitude, viewport.centerLongitude);
    expect(camera.zoom, viewport.cameraZoom);
  });

  test(
    'shared viewport projects turn route points inside thumbnail bounds',
    () {
      final viewport = ActivityRouteThumbnailViewport.fromRoute(
        _turnRouteFixture(),
        logicalSize: const Size(88, 88),
      );

      expect(viewport.mode, ActivityRouteThumbnailViewportMode.meaningfulRoute);
      for (final point in viewport.drawablePoints) {
        final projected = viewport.project(point);
        expect(projected.dx, inInclusiveRange(7, 81));
        expect(projected.dy, inInclusiveRange(7, 81));
      }
    },
  );

  test('shared viewport keeps long narrow route inside thumbnail bounds', () {
    final viewport = ActivityRouteThumbnailViewport.fromRoute(
      _longNarrowRouteFixture(),
      logicalSize: const Size(88, 88),
    );

    expect(viewport.mode, ActivityRouteThumbnailViewportMode.meaningfulRoute);
    for (final point in viewport.drawablePoints) {
      final projected = viewport.project(point);
      expect(projected.dx, inInclusiveRange(7, 81));
      expect(projected.dy, inInclusiveRange(7, 81));
    }
  });

  test('shared viewport keeps stationary and no-route modes distinct', () {
    final stationary = ActivityRouteThumbnailViewport.fromRoute(
      _singlePointRouteFixture(),
      logicalSize: const Size(88, 88),
    );
    final noRoute = ActivityRouteThumbnailViewport.fromRoute(
      RunRouteSnapshot.empty,
      logicalSize: const Size(88, 88),
    );

    expect(stationary.mode, ActivityRouteThumbnailViewportMode.tinyRoute);
    expect(stationary.hasKnownLocation, isTrue);
    expect(noRoute.mode, ActivityRouteThumbnailViewportMode.noRoute);
    expect(noRoute.hasKnownLocation, isFalse);
  });

  test('cache returns deterministic hit for stored thumbnail result', () async {
    // Given: a session cache with a stored fake snapshot result.
    final cache = ActivityRouteSnapshotThumbnailMemoryCache();
    final request = _request(route: _routeFixture());
    final image = MemoryImage(Uint8List.fromList(const [1, 2, 3]));
    final result = ActivityRouteThumbnailResult.readyImage(image);
    const styleId = 'runiac-card-streets-v1';
    final key = ActivityRouteSnapshotThumbnailCacheKey.fromRequest(
      request,
      styleId: styleId,
    );

    // When: the result is stored and resolved through the provider.
    cache.store(key, result);
    final provider = CachedActivityRouteThumbnailProvider(
      cache: cache,
      styleId: styleId,
    );
    final resolved = await provider.resolve(request);

    // Then: the same ready image result is returned from memory.
    expect(resolved.state, ActivityRouteThumbnailState.readyImage);
    expect(resolved.imageProvider, same(image));
    expect(cache.length, 1);
  });

  test('cache miss returns unavailable without creating external work', () async {
    // Given: an empty session cache and a meaningful route request.
    final cache = ActivityRouteSnapshotThumbnailMemoryCache();
    final provider = CachedActivityRouteThumbnailProvider(cache: cache);

    // When: no thumbnail was stored for this route.
    final resolved = await provider.resolve(_request(route: _routeFixture()));

    // Then: the provider reports unavailable so the preview can use CustomPaint.
    expect(resolved, const ActivityRouteThumbnailResult.unavailable());
    expect(cache.length, 0);
  });

  test(
    'cache key changes for activity, route, size, dpr, style, and privacy',
    () {
      // Given: equivalent and changed route thumbnail requests.
      final base = _request(route: _routeFixture());
      final same = _request(route: _routeFixture());
      final moved = _request(route: _routeFixture(latitudeOffset: 0.001));
      final turn = _request(route: _turnRouteFixture());
      final resized = _request(
        route: _routeFixture(),
        logicalSize: const Size(96, 88),
      );
      final dprChanged = _request(route: _routeFixture(), devicePixelRatio: 2);
      final activityChanged = _request(
        route: _routeFixture(),
        activityId: 'activity-2',
      );
      final lastKnownChanged = _request(
        route: RunRouteSnapshot(
          segments: _routeFixture().segments,
          lastKnownLocation: RunLocationSample(
            recordedAt: DateTime.utc(2026, 6, 18, 8, 12),
            latitude: 1.305,
            longitude: 103.805,
          ),
        ),
      );
      final privacyChanged = _request(
        route: _routeFixture(),
        allowExternalStaticMap: false,
      );

      // When: deterministic cache keys are derived.
      final baseKey = ActivityRouteSnapshotThumbnailCacheKey.fromRequest(base);

      // Then: identical requests match, while meaningful dimensions differ.
      expect(ActivityRouteSnapshotThumbnailCacheKey.fromRequest(same), baseKey);
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(moved),
        isNot(baseKey),
      );
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(turn),
        isNot(baseKey),
      );
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(resized),
        isNot(baseKey),
      );
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(dprChanged),
        isNot(baseKey),
      );
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(activityChanged),
        isNot(baseKey),
      );
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(lastKnownChanged),
        isNot(baseKey),
      );
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(
          base,
          styleId: 'alternate-style',
        ),
        isNot(baseKey),
      );
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(privacyChanged),
        isNot(baseKey),
      );
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(
          _request(route: _routeFixture(), devicePixelRatio: 2.625),
        ),
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(
          _request(route: _routeFixture(), devicePixelRatio: 3),
        ),
      );
    },
  );

  test('cache clear removes only current session memory', () {
    // Given: a memory-only cache with one stored result.
    final cache = ActivityRouteSnapshotThumbnailMemoryCache();
    final key = ActivityRouteSnapshotThumbnailCacheKey.fromRequest(
      _request(route: _routeFixture()),
    );
    cache.store(
      key,
      ActivityRouteThumbnailResult.readyImage(
        MemoryImage(Uint8List.fromList(const [4, 5, 6])),
      ),
    );

    // When: the current session cache is cleared.
    cache.clear();

    // Then: the entry is removed without any disk persistence surface.
    expect(cache.resolve(key), isNull);
    expect(cache.length, 0);
  });

  test(
    'snapshot provider resolves demo request and stores ready image',
    () async {
      // Given: the explicit demo/static flag and a valid public token are present.
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      final image = MemoryImage(Uint8List.fromList(const [7, 8, 9]));
      final generator = _FakeSnapshotThumbnailGenerator((request) async {
        return ActivityRouteThumbnailResult.readyImage(image);
      });
      final provider = CachedActivityRouteThumbnailProvider(
        cache: cache,
        generator: generator,
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
      );

      // When: a demo route asks for a static background image.
      final request = _request(route: _routeFixture(), isDemoRoute: true);
      final resolved = await provider.resolve(request);
      final secondResolved = await provider.resolve(request);

      // Then: the fake generator is used once and the ready image is cached.
      expect(resolved.state, ActivityRouteThumbnailState.readyImage);
      expect(resolved.imageProvider, same(image));
      expect(secondResolved.imageProvider, same(image));
      expect(generator.requestCount, 1);
      expect(generator.lastRequest!.logicalSize, request.logicalSize);
      expect(generator.lastRequest!.devicePixelRatio, request.devicePixelRatio);
      expect(generator.lastRequest!.activityId, request.activityId);
      expect(
        generator.lastRequest!.camera.centerLatitude,
        closeTo(1.3015, 0.001),
      );
      expect(
        generator.lastRequest!.camera.centerLongitude,
        closeTo(103.8015, 0.001),
      );
      expect(cache.length, 1);
    },
  );

  test('snapshot provider resolves current-session route thumbnails', () async {
    final cache = ActivityRouteSnapshotThumbnailMemoryCache();
    final diagnostics = <ActivityRouteThumbnailDiagnostic>[];
    final image = MemoryImage(Uint8List.fromList(const [10, 11, 12]));
    final generator = _FakeSnapshotThumbnailGenerator((request) async {
      return ActivityRouteThumbnailResult.readyImage(image);
    });
    final provider = CachedActivityRouteThumbnailProvider(
      cache: cache,
      generator: generator,
      snapshotThumbnailsEnabled: true,
      hasValidMapboxToken: true,
      onDiagnostic: diagnostics.add,
    );

    final request = _request(
      route: _routeFixture(),
      isDemoRoute: false,
      isCurrentSessionRoute: true,
    );

    final resolved = await provider.resolve(request);

    expect(resolved.state, ActivityRouteThumbnailState.readyImage);
    expect(generator.requestCount, 1);
    expect(generator.lastRequest!.activityId, request.activityId);
    expect(cache.length, 1);
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.fallbackReason, 'readyImage');
    expect(
      diagnostics.single.source,
      ActivityRouteThumbnailDiagnosticSource.generator,
    );
    expect(diagnostics.single.isCurrentSessionRoute, isTrue);
    expect(diagnostics.single.isTrustedPersistedRoutePreview, isFalse);
    expect(diagnostics.single.hasKnownLocation, isTrue);
  });

  test(
    'snapshot provider resolves trusted persisted previews without current-session provenance',
    () async {
      // Given: a backend-masked persisted preview with explicit trusted
      // provenance and no live completion session.
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      final diagnostics = <ActivityRouteThumbnailDiagnostic>[];
      final image = MemoryImage(Uint8List.fromList(const [13, 14, 15]));
      final generator = _FakeSnapshotThumbnailGenerator((request) async {
        return ActivityRouteThumbnailResult.readyImage(image);
      });
      final provider = CachedActivityRouteThumbnailProvider(
        cache: cache,
        generator: generator,
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
        onDiagnostic: diagnostics.add,
      );
      final request = _request(
        route: _routeFixture(),
        isDemoRoute: false,
        isCurrentSessionRoute: false,
        isTrustedPersistedRoutePreview: true,
      );

      // When: the provider evaluates the non-demo request.
      final resolved = await provider.resolve(request);

      // Then: trusted persisted provenance independently authorizes generation
      // and remains distinct in diagnostics and cache policy.
      expect(resolved.state, ActivityRouteThumbnailState.readyImage);
      expect(generator.requestCount, 1);
      expect(cache.length, 1);
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.isCurrentSessionRoute, isFalse);
      expect(diagnostics.single.isTrustedPersistedRoutePreview, isTrue);
      expect(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(request).privacyMode,
        'trusted-persisted-preview-allowed',
      );
    },
  );

  test(
    'snapshot provider never generates non-current real user route thumbnails',
    () async {
      // Given: static thumbnails are enabled and a valid token is available.
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      final diagnostics = <ActivityRouteThumbnailDiagnostic>[];
      final generator = _FakeSnapshotThumbnailGenerator((request) async {
        return ActivityRouteThumbnailResult.readyImage(
          MemoryImage(Uint8List.fromList(const [10, 11, 12])),
        );
      });
      final provider = CachedActivityRouteThumbnailProvider(
        cache: cache,
        generator: generator,
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
        onDiagnostic: diagnostics.add,
      );

      // When: a non-demo route asks for a static thumbnail.
      final resolved = await provider.resolve(
        _request(
          route: _routeFixture(),
          isDemoRoute: false,
          isCurrentSessionRoute: false,
        ),
      );

      // Then: the provider refuses before any external generator can see it.
      expect(resolved, const ActivityRouteThumbnailResult.privacyDisabled());
      expect(generator.requestCount, 0);
      expect(cache.length, 0);
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.fallbackReason, 'privacyDisabled');
      expect(
        diagnostics.single.source,
        ActivityRouteThumbnailDiagnosticSource.policy,
      );
      expect(diagnostics.single.snapshotThumbnailsEnabled, isTrue);
      expect(diagnostics.single.hasValidMapboxToken, isTrue);
      expect(diagnostics.single.allowExternalStaticMap, isTrue);
      expect(diagnostics.single.isCurrentSessionRoute, isFalse);
      expect(diagnostics.single.isTrustedPersistedRoutePreview, isFalse);
    },
  );

  test(
    'snapshot provider reports disabled flag and missing token states',
    () async {
      final diagnostics = <ActivityRouteThumbnailDiagnostic>[];
      final disabledProvider = CachedActivityRouteThumbnailProvider(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        generator: _FakeSnapshotThumbnailGenerator((request) async {
          return const ActivityRouteThumbnailResult.unavailable();
        }),
        snapshotThumbnailsEnabled: false,
        hasValidMapboxToken: true,
        onDiagnostic: diagnostics.add,
      );
      final missingTokenProvider = CachedActivityRouteThumbnailProvider(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        generator: _FakeSnapshotThumbnailGenerator((request) async {
          return const ActivityRouteThumbnailResult.unavailable();
        }),
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: false,
        onDiagnostic: diagnostics.add,
      );

      expect(
        await disabledProvider.resolve(_request(route: _routeFixture())),
        const ActivityRouteThumbnailResult.privacyDisabled(),
      );
      expect(
        await missingTokenProvider.resolve(_request(route: _routeFixture())),
        const ActivityRouteThumbnailResult.tokenMissing(),
      );
      expect(diagnostics.map((diagnostic) => diagnostic.fallbackReason), [
        'privacyDisabled',
        'tokenMissing',
      ]);
    },
  );

  test('snapshot provider coalesces duplicate in-flight requests', () async {
    // Given: a generator that has not completed yet.
    final completer = Completer<ActivityRouteThumbnailResult>();
    final generator = _FakeSnapshotThumbnailGenerator((request) {
      return completer.future;
    });
    final provider = CachedActivityRouteThumbnailProvider(
      cache: ActivityRouteSnapshotThumbnailMemoryCache(),
      generator: generator,
      snapshotThumbnailsEnabled: true,
      hasValidMapboxToken: true,
    );
    final request = _request(route: _routeFixture());

    // When: two identical requests are made before the first one completes.
    final first = provider.resolve(request);
    final second = provider.resolve(request);
    completer.complete(
      ActivityRouteThumbnailResult.readyImage(
        MemoryImage(Uint8List.fromList(const [13, 14, 15])),
      ),
    );

    // Then: only one external generation is performed.
    expect(await first, await second);
    expect(generator.requestCount, 1);
  });

  test(
    'snapshot provider exposes timed out state without caching loading',
    () async {
      final provider = CachedActivityRouteThumbnailProvider(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        generator: _FakeSnapshotThumbnailGenerator((request) {
          return Completer<ActivityRouteThumbnailResult>().future;
        }),
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
        generationTimeout: const Duration(milliseconds: 1),
      );

      final resolved = await provider.resolve(_request(route: _routeFixture()));

      expect(resolved, const ActivityRouteThumbnailResult.timedOut());
      expect(provider.cache.length, 0);
    },
  );

  test(
    'snapshot provider keeps timed out generation in flight for duplicate requests',
    () async {
      final completer = Completer<ActivityRouteThumbnailResult>();
      final image = MemoryImage(Uint8List.fromList(const [22, 23, 24]));
      final generator = _FakeSnapshotThumbnailGenerator((request) {
        return completer.future;
      });
      final provider = CachedActivityRouteThumbnailProvider(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        generator: generator,
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
        generationTimeout: const Duration(milliseconds: 1),
      );
      final request = _request(route: _routeFixture());

      final timedOut = await provider.resolve(request);
      final second = provider.resolve(request);

      expect(timedOut, const ActivityRouteThumbnailResult.timedOut());
      expect(generator.requestCount, 1);

      completer.complete(ActivityRouteThumbnailResult.readyImage(image));
      final resolved = await second;

      expect(resolved.state, ActivityRouteThumbnailState.readyImage);
      expect(resolved.imageProvider, same(image));
      expect(generator.requestCount, 1);
      expect(provider.cache.length, 1);
    },
  );

  test(
    'snapshot provider resolves stationary current-session location thumbnails',
    () async {
      final startedAt = DateTime.utc(2026, 6, 18, 8, 10);
      final stationaryRoute = RunRouteSnapshot(
        segments: [
          [
            RunLocationSample(
              recordedAt: startedAt,
              latitude: 1.301000,
              longitude: 103.801000,
            ),
            RunLocationSample(
              recordedAt: startedAt.add(const Duration(seconds: 30)),
              latitude: 1.301001,
              longitude: 103.801001,
            ),
          ],
        ],
        lastKnownLocation: RunLocationSample(
          recordedAt: startedAt.add(const Duration(seconds: 30)),
          latitude: 1.301001,
          longitude: 103.801001,
        ),
      );
      final image = MemoryImage(Uint8List.fromList(const [16, 17, 18]));
      final generator = _FakeSnapshotThumbnailGenerator((request) async {
        return ActivityRouteThumbnailResult.readyImage(image);
      });
      final provider = CachedActivityRouteThumbnailProvider(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        generator: generator,
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
      );

      final resolved = await provider.resolve(
        _request(
          route: stationaryRoute,
          isDemoRoute: false,
          isCurrentSessionRoute: true,
        ),
      );

      expect(resolved.state, ActivityRouteThumbnailState.readyImage);
      expect(resolved.imageProvider, same(image));
      expect(generator.requestCount, 1);
      expect(
        generator.lastRequest!.camera.centerLatitude,
        closeTo(1.301001, 0.000001),
      );
      expect(
        generator.lastRequest!.camera.centerLongitude,
        closeTo(103.801001, 0.000001),
      );
    },
  );

  test(
    'snapshot provider resolves single-point current-session location thumbnails',
    () async {
      final image = MemoryImage(Uint8List.fromList(const [19, 20, 21]));
      final generator = _FakeSnapshotThumbnailGenerator((request) async {
        return ActivityRouteThumbnailResult.readyImage(image);
      });
      final provider = CachedActivityRouteThumbnailProvider(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        generator: generator,
        snapshotThumbnailsEnabled: true,
        hasValidMapboxToken: true,
      );

      final resolved = await provider.resolve(
        _request(
          route: _singlePointRouteFixture(),
          isDemoRoute: false,
          isCurrentSessionRoute: true,
        ),
      );

      expect(resolved.state, ActivityRouteThumbnailState.readyImage);
      expect(generator.requestCount, 1);
      expect(
        generator.lastRequest!.camera.centerLatitude,
        closeTo(1.301, 0.000001),
      );
      expect(
        generator.lastRequest!.camera.centerLongitude,
        closeTo(103.801, 0.000001),
      );
    },
  );
}
