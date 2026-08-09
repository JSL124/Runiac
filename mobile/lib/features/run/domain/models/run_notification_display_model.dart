import 'run_tracking_snapshot.dart';
import 'run_tracking_state.dart';

class RunNotificationDisplayModel {
  const RunNotificationDisplayModel({
    required this.title,
    required this.collapsedBody,
    required this.statusLabel,
    required this.elapsedTimeLabel,
    required this.currentPaceLabel,
    required this.distanceLabel,
    required this.supportCopy,
  });

  factory RunNotificationDisplayModel.fromState(RunTrackingState state) {
    final snapshot = RunTrackingSnapshot.fromState(state);
    final currentPaceLabel = _notificationPaceLabel(snapshot.currentPaceLabel);
    final title = _titleFor(state);

    return RunNotificationDisplayModel(
      title: title,
      collapsedBody:
          '${snapshot.elapsedTimeLabel} • $currentPaceLabel • '
          '${snapshot.distanceLabel}',
      statusLabel: _statusLabelFor(state),
      elapsedTimeLabel: snapshot.elapsedTimeLabel,
      currentPaceLabel: currentPaceLabel,
      distanceLabel: snapshot.distanceLabel,
      supportCopy: _supportCopyFor(state),
    );
  }

  final String title;
  final String collapsedBody;
  final String statusLabel;
  final String elapsedTimeLabel;
  final String currentPaceLabel;
  final String distanceLabel;
  final String? supportCopy;
}

String _titleFor(RunTrackingState state) {
  if (state.isPaused) {
    return 'Run paused';
  }
  if (state.isAutoPaused || state.isAbnormalPaused) {
    return 'Tracking paused';
  }
  if (state.locationStatus == RunTrackingLocationStatus.demo) {
    return 'Runiac demo run';
  }
  return 'Runiac is tracking your run';
}

String _statusLabelFor(RunTrackingState state) {
  if (state.isAbnormalPaused) {
    return 'Tracking paused';
  }
  if (state.isAutoPaused) {
    return 'Auto-paused';
  }
  if (state.isPaused) {
    return 'Paused';
  }
  return switch (state.locationStatus) {
    RunTrackingLocationStatus.waitingForGps => 'Getting GPS ready',
    RunTrackingLocationStatus.gpsActive => 'GPS active',
    RunTrackingLocationStatus.gpsWeak => 'GPS weak',
    RunTrackingLocationStatus.approximateLocation => 'Approximate location',
    RunTrackingLocationStatus.demo => 'Demo mode',
  };
}

String? _supportCopyFor(RunTrackingState state) {
  if (state.isAbnormalPaused) {
    return 'Unusual movement detected. Resume when ready.';
  }
  if (state.isAutoPaused) {
    return 'Move again to continue tracking.';
  }
  if (state.isPaused) {
    return 'Tracking is paused until you resume.';
  }
  return switch (state.locationStatus) {
    RunTrackingLocationStatus.waitingForGps => 'Keep moving in an open area.',
    RunTrackingLocationStatus.gpsWeak =>
      'GPS signal weak. Keep the app nearby.',
    RunTrackingLocationStatus.approximateLocation =>
      'Approximate location. Distance may be less precise.',
    RunTrackingLocationStatus.gpsActive => null,
    RunTrackingLocationStatus.demo => 'Demo mode is active.',
  };
}

String _notificationPaceLabel(String snapshotPaceLabel) {
  if (snapshotPaceLabel == '--:--/km') {
    return '--:-- /km';
  }
  if (!snapshotPaceLabel.endsWith('/km')) {
    return snapshotPaceLabel;
  }

  final pace = snapshotPaceLabel.substring(
    0,
    snapshotPaceLabel.length - '/km'.length,
  );
  final displayPace = pace.startsWith('0') ? pace.substring(1) : pace;
  return '$displayPace /km';
}
