import 'package:flutter/material.dart';

import '../../domain/models/run_map_view_state.dart';
import 'run_mapbox_follow_qa_overlay.dart';

typedef RunMapboxSurfaceBuilder =
    Widget Function(BuildContext context, RunMapboxSurfaceConfig config);

class RunMapboxSurfaceConfig {
  const RunMapboxSurfaceConfig({
    required this.accessToken,
    required this.mapViewState,
    required this.isFollowingRunner,
    required this.showRecenterButton,
    required this.recenterButtonBottom,
    this.recenterRequestId = 0,
    this.onManualPan,
    this.onRecenter,
    this.followQaDiagnostics,
  });

  final String accessToken;
  final RunMapViewState mapViewState;
  final bool isFollowingRunner;
  final int recenterRequestId;
  final VoidCallback? onManualPan;
  final VoidCallback? onRecenter;
  final RunMapboxFollowQaDiagnostics? followQaDiagnostics;
  final bool showRecenterButton;
  final double recenterButtonBottom;
}
