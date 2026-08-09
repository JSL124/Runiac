import 'package:flutter/material.dart';

// A developer overlay that exposes what the run map's camera-follow logic is
// doing — follow state, camera centre, and why follow was released or resumed.
//
// Camera follow misbehaves in ways that are almost impossible to diagnose from
// a video of a device: the fix is usually to see the state at the moment it
// went wrong. Compiled out unless `RUNIAC_MAPBOX_FOLLOW_QA` is passed at build
// time, so it costs shipped builds nothing.

const runMapboxFollowQaEnabled = bool.fromEnvironment(
  'RUNIAC_MAPBOX_FOLLOW_QA',
);

class RunMapboxFollowQaDiagnostics extends ChangeNotifier {
  RunMapboxFollowQaDiagnostics({
    required this.enabled,
    required this.screenPath,
  });

  final bool enabled;
  final String screenPath;
  String mapPath = 'unknown';
  bool isFollowingRunner = true;
  bool? shouldMoveCamera;
  int manualGestureCount = 0;
  int mapboxGestureCallbackCount = 0;
  int pointerObserverMoveCount = 0;
  int onManualPanCount = 0;
  int cameraMoveCount = 0;
  int cameraCancelCount = 0;
  int cameraStateSampleCount = 0;
  int cameraCenterChangedCount = 0;
  int unknownNativeCameraChangeCount = 0;
  int routeSyncCount = 0;
  int markerSyncCount = 0;
  int cameraMoveSkippedCount = 0;
  int followOffRouteSyncCount = 0;
  int followOffMarkerSyncCount = 0;
  int followOffCameraMoveSkippedCount = 0;
  int cameraGeneration = 0;
  int cameraInterruptGeneration = 0;
  int followOffGeneration = 0;
  int recenterRequestId = 0;
  int resumeCount = 0;
  bool cameraCenterChanged = false;
  bool appCameraMoveRequested = false;
  bool? lastCameraMoveShouldMoveCamera;
  String lastCameraMovementSource = 'n/a';
  String lastCameraMoveRequestReason = 'n/a';
  _RunMapboxFollowQaCameraCenter? _lastCameraCenter;

  void updateMapState({
    required String mapPath,
    required bool isFollowingRunner,
    required int recenterRequestId,
  }) {
    if (!enabled) {
      return;
    }
    var changed = false;
    if (this.mapPath != mapPath) {
      this.mapPath = mapPath;
      changed = true;
    }
    if (this.isFollowingRunner != isFollowingRunner) {
      this.isFollowingRunner = isFollowingRunner;
      changed = true;
    }
    if (this.recenterRequestId != recenterRequestId) {
      this.recenterRequestId = recenterRequestId;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void recordMapboxGestureCallback() {
    _increment(() => mapboxGestureCallbackCount++);
  }

  void recordPointerObserverMove() {
    _increment(() => pointerObserverMoveCount++);
  }

  void recordManualGesture() {
    _increment(() => manualGestureCount++);
  }

  void recordOnManualPan() {
    _increment(() {
      onManualPanCount++;
      followOffGeneration++;
      lastCameraMovementSource = 'user gesture';
    });
  }

  void recordCameraMoveRequest({
    required bool shouldMoveCamera,
    required String reason,
    required int generation,
  }) {
    if (!enabled) {
      return;
    }
    this.shouldMoveCamera = shouldMoveCamera;
    lastCameraMoveShouldMoveCamera = shouldMoveCamera;
    lastCameraMoveRequestReason = reason;
    cameraGeneration = generation;
    if (shouldMoveCamera) {
      appCameraMoveRequested = true;
    }
    notifyListeners();
  }

  void recordShouldMoveCamera(bool value) {
    recordCameraMoveRequest(
      shouldMoveCamera: value,
      reason: value ? 'follow' : 'skipped',
      generation: cameraGeneration,
    );
  }

  void recordCameraMove({
    required bool shouldMoveCamera,
    required int generation,
  }) {
    _increment(() {
      cameraMoveCount++;
      lastCameraMoveShouldMoveCamera = shouldMoveCamera;
      cameraGeneration = generation;
      lastCameraMovementSource = 'app move';
      appCameraMoveRequested = true;
    });
  }

  void recordCameraMoveSkipped({
    required bool shouldMoveCamera,
    required int generation,
    required bool isFollowingRunner,
  }) {
    _increment(() {
      cameraMoveSkippedCount++;
      lastCameraMoveShouldMoveCamera = shouldMoveCamera;
      lastCameraMoveRequestReason = 'skipped';
      cameraGeneration = generation;
      if (!isFollowingRunner) {
        followOffCameraMoveSkippedCount++;
      }
    });
  }

  void recordCameraCancel({required int interruptGeneration}) {
    _increment(() {
      cameraCancelCount++;
      cameraInterruptGeneration = interruptGeneration;
      lastCameraMovementSource = 'user gesture';
      appCameraMoveRequested = false;
    });
  }

  void recordRouteSync({required bool isFollowingRunner}) {
    _increment(() {
      routeSyncCount++;
      if (!isFollowingRunner) {
        followOffRouteSyncCount++;
      }
    });
  }

  void recordMarkerSync({required bool isFollowingRunner}) {
    _increment(() {
      markerSyncCount++;
      if (!isFollowingRunner) {
        followOffMarkerSyncCount++;
      }
    });
  }

  void recordCameraStateSample({
    required double latitude,
    required double longitude,
    required bool isFollowingRunner,
  }) {
    if (!enabled) {
      return;
    }

    final currentCenter = _RunMapboxFollowQaCameraCenter(
      latitude: latitude,
      longitude: longitude,
    );
    final lastCenter = _lastCameraCenter;
    final changed = lastCenter != null && !lastCenter.sameAs(currentCenter);
    _lastCameraCenter = currentCenter;
    cameraStateSampleCount++;
    cameraCenterChanged = changed;
    if (changed) {
      cameraCenterChangedCount++;
      if (!isFollowingRunner && !appCameraMoveRequested) {
        unknownNativeCameraChangeCount++;
        lastCameraMovementSource = 'unknown/native';
      }
    }
    appCameraMoveRequested = false;
    notifyListeners();
  }

  void recordRecenterRequest(int value) {
    if (!enabled) {
      return;
    }
    if (recenterRequestId == value) {
      return;
    }
    recenterRequestId = value;
    notifyListeners();
  }

  void recordResume() {
    _increment(() => resumeCount++);
  }

  void _increment(VoidCallback update) {
    if (!enabled) {
      return;
    }
    update();
    notifyListeners();
  }
}

class _RunMapboxFollowQaCameraCenter {
  const _RunMapboxFollowQaCameraCenter({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  bool sameAs(_RunMapboxFollowQaCameraCenter other) {
    const tolerance = 0.000001;
    return (latitude - other.latitude).abs() < tolerance &&
        (longitude - other.longitude).abs() < tolerance;
  }
}

class RunMapboxFollowQaOverlay extends StatelessWidget {
  const RunMapboxFollowQaOverlay({
    super.key,
    required this.diagnostics,
    required this.child,
  });

  final RunMapboxFollowQaDiagnostics? diagnostics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final diagnostics = this.diagnostics;
    if (diagnostics == null || !diagnostics.enabled) {
      return child;
    }

    return Stack(
      children: [
        child,
        Positioned(
          top: 72,
          left: 12,
          child: SafeArea(
            bottom: false,
            child: AnimatedBuilder(
              animation: diagnostics,
              builder: (context, _) {
                return _RunMapboxFollowQaPanel(diagnostics: diagnostics);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _RunMapboxFollowQaPanel extends StatelessWidget {
  const _RunMapboxFollowQaPanel({required this.diagnostics});

  final RunMapboxFollowQaDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final shouldMoveCamera = diagnostics.shouldMoveCamera;
    final labels = <String>[
      'Runiac Mapbox QA',
      'map: ${diagnostics.mapPath}',
      'screen: ${diagnostics.screenPath}',
      'follow: ${diagnostics.isFollowingRunner ? 'ON' : 'OFF'}',
      'manual gesture: ${diagnostics.manualGestureCount}',
      'mapbox cb: ${diagnostics.mapboxGestureCallbackCount}',
      'pointer move: ${diagnostics.pointerObserverMoveCount}',
      'onManualPan: ${diagnostics.onManualPanCount}',
      'shouldMoveCamera: ${shouldMoveCamera ?? 'n/a'}',
      'camera move: ${diagnostics.cameraMoveCount} should: ${diagnostics.lastCameraMoveShouldMoveCamera ?? 'n/a'}',
      'camera cancel: ${diagnostics.cameraCancelCount}',
      'camera sample: ${diagnostics.cameraStateSampleCount}',
      'center changed: ${diagnostics.cameraCenterChanged ? 'yes' : 'no'}',
      'center change count: ${diagnostics.cameraCenterChangedCount}',
      'camera source: ${diagnostics.lastCameraMovementSource}',
      'camera reason: ${diagnostics.lastCameraMoveRequestReason}',
      'unknown/native: ${diagnostics.unknownNativeCameraChangeCount}',
      'route sync: ${diagnostics.routeSyncCount}',
      'marker sync: ${diagnostics.markerSyncCount}',
      'camera skipped: ${diagnostics.cameraMoveSkippedCount}',
      'follow-off route sync: ${diagnostics.followOffRouteSyncCount}',
      'follow-off marker sync: ${diagnostics.followOffMarkerSyncCount}',
      'follow-off skipped: ${diagnostics.followOffCameraMoveSkippedCount}',
      'camera gen: ${diagnostics.cameraGeneration}',
      'interrupt gen: ${diagnostics.cameraInterruptGeneration}',
      'follow-off gen: ${diagnostics.followOffGeneration}',
      'recenter id: ${diagnostics.recenterRequestId}',
      'resume: ${diagnostics.resumeCount}',
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD9000000),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x99FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.22,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
          child: Column(
            key: const Key('run_mapbox_follow_qa_overlay'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: labels.map(Text.new).toList(growable: false),
          ),
        ),
      ),
    );
  }
}
