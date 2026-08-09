import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../run/domain/models/run_route_snapshot.dart';
import 'activity_route_preview.dart';
import 'activity_route_thumbnail_viewport.dart';

/// Caches the little route thumbnails drawn on activity-history cards.
///
/// Rendering a route image is expensive and the history scrolls, so thumbnails
/// are cached and their in-flight renders de-duplicated — [_InFlightArtifactKey]
/// is what stops the same route being rendered several times while the first
/// render is still running.
///
/// Every cache key includes the owning account ([_OwnedArtifactKey]). Signing
/// out and back in as someone else must not surface the previous account's
/// route images, and the lifecycle drops the owner's artifacts on sign-out.
class ActivityRouteSnapshotThumbnailCacheKey {
  const ActivityRouteSnapshotThumbnailCacheKey({
    required this.activityIdentity,
    required this.routeFingerprint,
    required this.styleId,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatioBucket,
    required this.privacyMode,
  });

  factory ActivityRouteSnapshotThumbnailCacheKey.fromRequest(
    ActivityRouteThumbnailRequest request, {
    String styleId = _defaultStyleId,
  }) {
    return ActivityRouteSnapshotThumbnailCacheKey(
      activityIdentity: request.activityId,
      routeFingerprint: _routeFingerprint(request.route),
      styleId: styleId,
      logicalWidth: request.logicalSize.width.round(),
      logicalHeight: request.logicalSize.height.round(),
      devicePixelRatioBucket: request.canonicalDevicePixelRatio,
      privacyMode: _privacyMode(request),
    );
  }

  final String? activityIdentity;
  final int routeFingerprint;
  final String styleId;
  final int logicalWidth;
  final int logicalHeight;
  final int devicePixelRatioBucket;
  final String privacyMode;

  @override
  bool operator ==(Object other) {
    return other is ActivityRouteSnapshotThumbnailCacheKey &&
        other.activityIdentity == activityIdentity &&
        other.routeFingerprint == routeFingerprint &&
        other.styleId == styleId &&
        other.logicalWidth == logicalWidth &&
        other.logicalHeight == logicalHeight &&
        other.devicePixelRatioBucket == devicePixelRatioBucket &&
        other.privacyMode == privacyMode;
  }

  @override
  int get hashCode {
    return Object.hash(
      activityIdentity,
      routeFingerprint,
      styleId,
      logicalWidth,
      logicalHeight,
      devicePixelRatioBucket,
      privacyMode,
    );
  }
}

class ActivityRouteSnapshotThumbnailMemoryCache {
  final Map<_OwnedArtifactKey, ActivityRouteThumbnailResult> _entries =
      <_OwnedArtifactKey, ActivityRouteThumbnailResult>{};

  int get length => _entries.length;

  ActivityRouteThumbnailResult? resolve(
    ActivityRouteSnapshotThumbnailCacheKey key, {
    String? ownerUid,
  }) {
    final ownedKey = _OwnedArtifactKey(ownerUid ?? '', key);
    return _entries[ownedKey] ?? _historyArtifactEntries[ownedKey];
  }

  void store(
    ActivityRouteSnapshotThumbnailCacheKey key,
    ActivityRouteThumbnailResult result, {
    String? ownerUid,
  }) {
    final ownedKey = _OwnedArtifactKey(ownerUid ?? '', key);
    _entries[ownedKey] = result;
    if (result.pngBytes != null && ownerUid != null && ownerUid.isNotEmpty) {
      _historyArtifactEntries[ownedKey] = result;
    }
  }

  void clear() {
    _entries.clear();
  }

  void clearOwner(String ownerUid) {
    _entries.removeWhere((key, _) => key.ownerUid == ownerUid);
    _historyArtifactEntries.removeWhere((key, _) => key.ownerUid == ownerUid);
  }
}

class _OwnedArtifactKey {
  const _OwnedArtifactKey(this.ownerUid, this.key);
  final String ownerUid;
  final ActivityRouteSnapshotThumbnailCacheKey key;
  @override
  bool operator ==(Object other) =>
      other is _OwnedArtifactKey &&
      other.ownerUid == ownerUid &&
      other.key == key;
  @override
  int get hashCode => Object.hash(ownerUid, key);
}

class _InFlightArtifactKey {
  const _InFlightArtifactKey({
    required this.artifactKey,
    required this.ownerGeneration,
    required this.historyArtifactGeneration,
  });

  final _OwnedArtifactKey artifactKey;
  final int ownerGeneration;
  final int historyArtifactGeneration;

  @override
  bool operator ==(Object other) =>
      other is _InFlightArtifactKey &&
      other.artifactKey == artifactKey &&
      other.ownerGeneration == ownerGeneration &&
      other.historyArtifactGeneration == historyArtifactGeneration;

  @override
  int get hashCode {
    return Object.hash(artifactKey, ownerGeneration, historyArtifactGeneration);
  }
}

final Map<_OwnedArtifactKey, ActivityRouteThumbnailResult>
_historyArtifactEntries = <_OwnedArtifactKey, ActivityRouteThumbnailResult>{};
int _historyArtifactGeneration = 0;

class ActivityRouteSnapshotThumbnailArtifactLifecycle {
  ActivityRouteSnapshotThumbnailArtifactLifecycle({String? initialOwnerUid})
    : _ownerUid = initialOwnerUid;

  String? _ownerUid;

  void syncOwner(String? ownerUid) {
    if (_ownerUid == ownerUid) {
      return;
    }
    _historyArtifactEntries.clear();
    _historyArtifactGeneration += 1;
    _ownerUid = ownerUid;
  }
}

abstract interface class ActivityRouteSnapshotThumbnailGenerator {
  Future<ActivityRouteThumbnailResult> generate(
    ActivityRouteSnapshotThumbnailGenerationRequest request,
  );
}

class ActivityRouteSnapshotThumbnailGenerationRequest {
  const ActivityRouteSnapshotThumbnailGenerationRequest({
    required this.logicalSize,
    required this.devicePixelRatio,
    required this.styleId,
    required this.camera,
    required this.route,
    required this.viewport,
    this.projectedStart = Offset.zero,
    this.projectedEnd = Offset.zero,
    this.activityId,
  });

  static ActivityRouteSnapshotThumbnailGenerationRequest? fromThumbnailRequest(
    ActivityRouteThumbnailRequest request, {
    required String styleId,
  }) {
    final viewport = ActivityRouteThumbnailViewport.fromRoute(
      request.route,
      logicalSize: request.logicalSize,
    );
    final camera = ActivityRouteSnapshotCamera.fromViewport(viewport);
    if (camera == null) {
      return null;
    }
    return ActivityRouteSnapshotThumbnailGenerationRequest(
      logicalSize: request.logicalSize,
      devicePixelRatio: request.canonicalDevicePixelRatio.toDouble(),
      styleId: styleId,
      camera: camera,
      route: request.route,
      viewport: viewport,
      activityId: request.activityId,
    );
  }

  final Size logicalSize;
  final double devicePixelRatio;
  final String styleId;
  final ActivityRouteSnapshotCamera camera;
  final RunRouteSnapshot route;
  final ActivityRouteThumbnailViewport viewport;
  final Offset projectedStart;
  final Offset projectedEnd;
  final String? activityId;

  int get outputPixels => (logicalSize.width * devicePixelRatio).round();
  int get outputWidthPixels => (logicalSize.width * devicePixelRatio).round();
  int get outputHeightPixels => (logicalSize.height * devicePixelRatio).round();
}

class ActivityRouteSnapshotCamera {
  const ActivityRouteSnapshotCamera({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.zoom,
  });

  static ActivityRouteSnapshotCamera? fromViewport(
    ActivityRouteThumbnailViewport viewport,
  ) {
    if (viewport.mode == ActivityRouteThumbnailViewportMode.noRoute) {
      return null;
    }
    return ActivityRouteSnapshotCamera(
      centerLatitude: viewport.centerLatitude,
      centerLongitude: viewport.centerLongitude,
      zoom: viewport.cameraZoom,
    );
  }

  final double centerLatitude;
  final double centerLongitude;
  final double zoom;
}

class CachedActivityRouteThumbnailProvider
    implements ActivityRouteThumbnailProvider {
  CachedActivityRouteThumbnailProvider({
    required this.cache,
    this.generator,
    this.snapshotThumbnailsEnabled = false,
    this.hasValidMapboxToken = false,
    this.generationTimeout = const Duration(seconds: 4),
    this.styleId = _defaultStyleId,
    String? Function()? ownerUidProvider,
    this.onDiagnostic,
  }) : ownerUidProvider = ownerUidProvider ?? _currentOwnerUid;

  final ActivityRouteSnapshotThumbnailMemoryCache cache;
  final ActivityRouteSnapshotThumbnailGenerator? generator;
  final bool snapshotThumbnailsEnabled;
  final bool hasValidMapboxToken;
  final Duration generationTimeout;
  final String styleId;
  final String? Function() ownerUidProvider;
  String? _lastOwnerUid;
  int _ownerGeneration = 0;
  final ActivityRouteThumbnailDiagnosticSink? onDiagnostic;
  final Map<_InFlightArtifactKey, Future<ActivityRouteThumbnailResult>>
  _inFlight = <_InFlightArtifactKey, Future<ActivityRouteThumbnailResult>>{};

  @override
  Future<ActivityRouteThumbnailResult> resolve(
    ActivityRouteThumbnailRequest request,
  ) async {
    final key = ActivityRouteSnapshotThumbnailCacheKey.fromRequest(
      request,
      styleId: styleId,
    );
    final ownerUid = ownerUidProvider();
    final ownerGeneration = _syncOwner(ownerUid);
    final historyArtifactGeneration = _historyArtifactGeneration;
    final ownedKey = _OwnedArtifactKey(ownerUid ?? '', key);
    final inFlightKey = _InFlightArtifactKey(
      artifactKey: ownedKey,
      ownerGeneration: ownerGeneration,
      historyArtifactGeneration: historyArtifactGeneration,
    );
    final generator = this.generator;
    if (generator == null) {
      final cached = cache.resolve(key, ownerUid: ownerUid);
      final result = cached ?? const ActivityRouteThumbnailResult.unavailable();
      _reportDiagnostic(
        request: request,
        result: result,
        source: cached == null
            ? ActivityRouteThumbnailDiagnosticSource.generatorMissing
            : ActivityRouteThumbnailDiagnosticSource.memoryCache,
      );
      return result;
    }

    final policyResult = _resolvePolicy(request);
    if (policyResult != null) {
      _reportDiagnostic(
        request: request,
        result: policyResult,
        source: ActivityRouteThumbnailDiagnosticSource.policy,
      );
      return policyResult;
    }

    final cached = cache.resolve(key, ownerUid: ownerUid);
    if (cached != null) {
      _reportDiagnostic(
        request: request,
        result: cached,
        source: ActivityRouteThumbnailDiagnosticSource.memoryCache,
      );
      return cached;
    }

    final pending = _inFlight[inFlightKey];
    if (pending != null) {
      return _resolveWithTimeout(pending);
    }

    final generation = _generateAndCache(
      key: key,
      request: request,
      generator: generator,
      ownerUid: ownerUid,
      ownerGeneration: ownerGeneration,
      historyArtifactGeneration: historyArtifactGeneration,
    );
    _inFlight[inFlightKey] = generation;
    unawaited(
      generation.whenComplete(() {
        if (identical(_inFlight[inFlightKey], generation)) {
          _inFlight.remove(inFlightKey);
        }
      }),
    );
    final result = await _resolveWithTimeout(generation);
    _reportDiagnostic(
      request: request,
      result: result,
      source: ActivityRouteThumbnailDiagnosticSource.generator,
    );
    return result;
  }

  Future<ActivityRouteThumbnailResult> _resolveWithTimeout(
    Future<ActivityRouteThumbnailResult> generation,
  ) async {
    try {
      return await generation.timeout(
        generationTimeout,
        onTimeout: () {
          return const ActivityRouteThumbnailResult.timedOut();
        },
      );
    } on TimeoutException {
      return const ActivityRouteThumbnailResult.timedOut();
    } on Object {
      return const ActivityRouteThumbnailResult.requestFailed();
    }
  }

  ActivityRouteThumbnailResult? _resolvePolicy(
    ActivityRouteThumbnailRequest request,
  ) {
    if (!request.allowExternalStaticMap || !snapshotThumbnailsEnabled) {
      return const ActivityRouteThumbnailResult.privacyDisabled();
    }
    if (!request.isDemoRoute &&
        !request.isCurrentSessionRoute &&
        !request.isTrustedPersistedRoutePreview) {
      return const ActivityRouteThumbnailResult.privacyDisabled();
    }
    if (!hasValidMapboxToken) {
      return const ActivityRouteThumbnailResult.tokenMissing();
    }
    return null;
  }

  Future<ActivityRouteThumbnailResult> _generateAndCache({
    required ActivityRouteSnapshotThumbnailCacheKey key,
    required ActivityRouteThumbnailRequest request,
    required ActivityRouteSnapshotThumbnailGenerator generator,
    required String? ownerUid,
    required int ownerGeneration,
    required int historyArtifactGeneration,
  }) async {
    final generationRequest =
        ActivityRouteSnapshotThumbnailGenerationRequest.fromThumbnailRequest(
          request,
          styleId: styleId,
        );
    if (generationRequest == null) {
      return const ActivityRouteThumbnailResult.unavailable();
    }
    final result = await _generate(generator, generationRequest);
    if (!_isCurrentGeneration(
      ownerUid: ownerUid,
      ownerGeneration: ownerGeneration,
      historyArtifactGeneration: historyArtifactGeneration,
    )) {
      return const ActivityRouteThumbnailResult.unavailable();
    }
    if (result.hasReadyImage) {
      cache.store(key, result, ownerUid: ownerUid);
    }
    return result;
  }

  int _syncOwner(String? ownerUid) {
    final previousOwnerUid = _lastOwnerUid;
    if (previousOwnerUid != null && previousOwnerUid != ownerUid) {
      cache.clearOwner(previousOwnerUid);
      _ownerGeneration += 1;
    }
    _lastOwnerUid = ownerUid;
    return _ownerGeneration;
  }

  bool _isCurrentGeneration({
    required String? ownerUid,
    required int ownerGeneration,
    required int historyArtifactGeneration,
  }) {
    return ownerUidProvider() == ownerUid &&
        _ownerGeneration == ownerGeneration &&
        _historyArtifactGeneration == historyArtifactGeneration;
  }

  Future<ActivityRouteThumbnailResult> _generate(
    ActivityRouteSnapshotThumbnailGenerator generator,
    ActivityRouteSnapshotThumbnailGenerationRequest request,
  ) async {
    try {
      return await generator.generate(request);
    } on Object {
      return const ActivityRouteThumbnailResult.requestFailed();
    }
  }

  void _reportDiagnostic({
    required ActivityRouteThumbnailRequest request,
    required ActivityRouteThumbnailResult result,
    required ActivityRouteThumbnailDiagnosticSource source,
  }) {
    final onDiagnostic = this.onDiagnostic;
    if (onDiagnostic == null) {
      return;
    }
    onDiagnostic(
      ActivityRouteThumbnailDiagnostic(
        activityId: request.activityId,
        resultState: result.state,
        source: source,
        allowExternalStaticMap: request.allowExternalStaticMap,
        isDemoRoute: request.isDemoRoute,
        isCurrentSessionRoute: request.isCurrentSessionRoute,
        isTrustedPersistedRoutePreview: request.isTrustedPersistedRoutePreview,
        snapshotThumbnailsEnabled: snapshotThumbnailsEnabled,
        hasValidMapboxToken: hasValidMapboxToken,
        hasKnownLocation: ActivityRouteThumbnailViewport.fromRoute(
          request.route,
          logicalSize: request.logicalSize,
        ).hasKnownLocation,
      ),
    );
  }
}

typedef ActivityRouteThumbnailDiagnosticSink =
    void Function(ActivityRouteThumbnailDiagnostic diagnostic);

enum ActivityRouteThumbnailDiagnosticSource {
  policy,
  generatorMissing,
  generator,
  memoryCache,
}

class ActivityRouteThumbnailDiagnostic {
  const ActivityRouteThumbnailDiagnostic({
    required this.activityId,
    required this.resultState,
    required this.source,
    required this.allowExternalStaticMap,
    required this.isDemoRoute,
    required this.isCurrentSessionRoute,
    required this.isTrustedPersistedRoutePreview,
    required this.snapshotThumbnailsEnabled,
    required this.hasValidMapboxToken,
    required this.hasKnownLocation,
  });

  final String? activityId;
  final ActivityRouteThumbnailState resultState;
  final ActivityRouteThumbnailDiagnosticSource source;
  final bool allowExternalStaticMap;
  final bool isDemoRoute;
  final bool isCurrentSessionRoute;
  final bool isTrustedPersistedRoutePreview;
  final bool snapshotThumbnailsEnabled;
  final bool hasValidMapboxToken;
  final bool hasKnownLocation;

  String get fallbackReason {
    return switch (resultState) {
      ActivityRouteThumbnailState.readyImage => 'readyImage',
      ActivityRouteThumbnailState.loading => 'loading',
      ActivityRouteThumbnailState.privacyDisabled => 'privacyDisabled',
      ActivityRouteThumbnailState.tokenMissing => 'tokenMissing',
      ActivityRouteThumbnailState.requestFailed => 'requestFailed',
      ActivityRouteThumbnailState.timedOut => 'timedOut',
      ActivityRouteThumbnailState.unavailable => 'unavailable',
    };
  }
}

int _routeFingerprint(RunRouteSnapshot route) {
  var hash = _fnvOffsetBasis;
  for (final segment in route.segments) {
    hash = _combineHash(hash, _segmentSeparator);
    for (final point in segment) {
      if (!point.latitude.isFinite || !point.longitude.isFinite) {
        continue;
      }
      hash = _combineHash(hash, _quantizeCoordinate(point.latitude));
      hash = _combineHash(hash, _quantizeCoordinate(point.longitude));
    }
  }
  final lastKnownLocation = route.lastKnownLocation;
  if (lastKnownLocation != null &&
      lastKnownLocation.latitude.isFinite &&
      lastKnownLocation.longitude.isFinite) {
    hash = _combineHash(hash, _lastKnownLocationSeparator);
    hash = _combineHash(hash, _quantizeCoordinate(lastKnownLocation.latitude));
    hash = _combineHash(hash, _quantizeCoordinate(lastKnownLocation.longitude));
  }
  return hash;
}

int _quantizeCoordinate(double coordinate) {
  return (coordinate * _coordinatePrecision).round();
}

String _privacyMode(ActivityRouteThumbnailRequest request) {
  if (!request.allowExternalStaticMap) {
    return 'privacy-disabled';
  }
  if (request.isDemoRoute) {
    return 'demo-static-allowed';
  }
  if (request.isCurrentSessionRoute) {
    return 'current-session-runtime-allowed';
  }
  if (request.isTrustedPersistedRoutePreview) {
    return 'trusted-persisted-preview-allowed';
  }
  return 'real-route-disabled';
}

int _combineHash(int hash, int value) {
  var next = hash;
  for (var shift = 0; shift < 64; shift += 8) {
    next ^= (value >> shift) & 0xff;
    next = (next * _fnvPrime) & _hashMask;
  }
  return next;
}

const _defaultStyleId = 'runiac-card-static-v1';
const _coordinatePrecision = 1000000;
const _segmentSeparator = 0x9e3779b9;
const _lastKnownLocationSeparator = 0x85ebca6b;
const _fnvOffsetBasis = 0xcbf29ce484222325;
const _fnvPrime = 0x100000001b3;
const _hashMask = 0x7fffffffffffffff;

String? _currentOwnerUid() {
  try {
    return FirebaseAuth.instance.currentUser?.uid;
  } on Object {
    return null;
  }
}
