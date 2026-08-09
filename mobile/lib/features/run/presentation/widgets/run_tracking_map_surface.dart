import 'package:flutter/material.dart';

import '../../domain/models/run_map_view_state.dart';
import 'mapbox_runtime_config.dart';
import 'run_map_placeholder.dart';
import 'run_mapbox_follow_qa_overlay.dart';
import 'run_mapbox_run_map.dart';
import 'run_mapbox_surface_config.dart';

const _mapboxSurfaceSelectedKey = Key('run_mapbox_surface_selected');
const _mapboxPlaceholderSelectedKey = Key('run_mapbox_placeholder_selected');

class RunTrackingMapSurface extends StatelessWidget {
  const RunTrackingMapSurface({
    super.key,
    this.mapViewState = const RunMapViewState.empty(),
    this.isFollowingRunner = true,
    this.onManualPan,
    this.onRecenter,
    this.showRecenterButton = true,
    this.recenterButtonBottom = 176,
    this.recenterRequestId = 0,
    this.mapboxAccessToken,
    this.mapboxBuilder,
    this.followQaDiagnostics,
  });

  final RunMapViewState mapViewState;
  final bool isFollowingRunner;
  final VoidCallback? onManualPan;
  final VoidCallback? onRecenter;
  final bool showRecenterButton;
  final double recenterButtonBottom;
  final int recenterRequestId;
  final String? mapboxAccessToken;
  final RunMapboxSurfaceBuilder? mapboxBuilder;
  final RunMapboxFollowQaDiagnostics? followQaDiagnostics;

  @override
  Widget build(BuildContext context) {
    final runtimeConfig = mapboxAccessToken == null
        ? MapboxRuntimeConfig.fromEnvironment()
        : MapboxRuntimeConfig(accessToken: mapboxAccessToken!.trim());
    if (runtimeConfig.accessToken.isEmpty) {
      _debugLogMapboxBranch('placeholder fallback selected');
      _updateDiagnostics(mapPath: 'placeholder');
      return KeyedSubtree(
        key: _mapboxPlaceholderSelectedKey,
        child: RunMapboxFollowQaOverlay(
          diagnostics: followQaDiagnostics,
          child: RunMapPlaceholder(
            mapViewState: mapViewState,
            isFollowingRunner: isFollowingRunner,
            onManualPan: onManualPan,
            onRecenter: onRecenter,
            showRecenterButton: showRecenterButton,
            recenterButtonBottom: recenterButtonBottom,
          ),
        ),
      );
    }

    if (!runtimeConfig.hasPublicAccessToken) {
      _debugLogMapboxBranch('invalid token fallback selected');
      _updateDiagnostics(mapPath: 'placeholder');
      return KeyedSubtree(
        key: _mapboxPlaceholderSelectedKey,
        child: RunMapboxFollowQaOverlay(
          diagnostics: followQaDiagnostics,
          child: RunMapPlaceholder(
            mapViewState: mapViewState,
            isFollowingRunner: isFollowingRunner,
            onManualPan: onManualPan,
            onRecenter: onRecenter,
            showRecenterButton: showRecenterButton,
            recenterButtonBottom: recenterButtonBottom,
          ),
        ),
      );
    }

    _debugLogMapboxBranch('mapbox path selected');
    _updateDiagnostics(mapPath: 'mapbox');
    final builder = mapboxBuilder ?? _defaultMapboxBuilder;
    final config = RunMapboxSurfaceConfig(
      accessToken: runtimeConfig.accessToken,
      mapViewState: mapViewState,
      isFollowingRunner: isFollowingRunner,
      recenterRequestId: recenterRequestId,
      onManualPan: onManualPan,
      onRecenter: onRecenter,
      followQaDiagnostics: followQaDiagnostics,
      showRecenterButton: showRecenterButton,
      recenterButtonBottom: recenterButtonBottom,
    );
    return KeyedSubtree(
      key: _mapboxSurfaceSelectedKey,
      child: RunMapboxFollowQaOverlay(
        diagnostics: followQaDiagnostics,
        child: builder(context, config),
      ),
    );
  }

  void _updateDiagnostics({required String mapPath}) {
    final diagnostics = followQaDiagnostics;
    if (diagnostics == null || !diagnostics.enabled) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      diagnostics.updateMapState(
        mapPath: mapPath,
        isFollowingRunner: isFollowingRunner,
        recenterRequestId: recenterRequestId,
      );
    });
  }

  void _debugLogMapboxBranch(String branch) {
    assert(() {
      debugPrint('Runiac Mapbox QA: $branch');
      return true;
    }());
  }
}

Widget _defaultMapboxBuilder(
  BuildContext context,
  RunMapboxSurfaceConfig config,
) {
  return RunMapboxRunMap(config: config);
}
