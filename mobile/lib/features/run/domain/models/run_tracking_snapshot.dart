import 'run_tracking_state.dart';
import 'run_tracking_startup_readiness.dart';

const abnormalMovementGuidance =
    'Unusual movement detected. Tracking is paused. Resume when you are running again, or end this run.';

class RunTrackingSnapshot {
  const RunTrackingSnapshot({
    required this.elapsedTimeLabel,
    required this.distanceLabel,
    required this.distanceValueLabel,
    required this.distanceUnitLabel,
    required this.averagePaceLabel,
    required this.currentPaceLabel,
    required this.planProgressLabel,
    required this.planProgressPercentLabel,
    required this.planProgressValue,
    required this.guidance,
    required this.startupReadiness,
    required this.startupReadinessMessage,
  });

  factory RunTrackingSnapshot.fromState(RunTrackingState state) {
    const targetDistanceMeters = 4500;
    final planProgressValue = (state.distanceMeters / targetDistanceMeters)
        .clamp(0.0, 1.0);
    final startupReadiness = startupReadinessForState(state);

    return RunTrackingSnapshot(
      elapsedTimeLabel: _formatElapsed(state.elapsedSeconds),
      distanceLabel: _formatDistance(state.distanceMeters),
      distanceValueLabel: _formatDistanceValue(state.distanceMeters),
      distanceUnitLabel: 'km',
      averagePaceLabel: state.distanceMeters < livePaceReadinessThresholdMeters
          ? '--:--/km'
          : _formatPace(state.averagePaceSecondsPerKm),
      currentPaceLabel: state.distanceMeters < livePaceReadinessThresholdMeters
          ? '--:--/km'
          : _formatPace(state.currentPaceSecondsPerKm),
      planProgressLabel:
          '${_formatDistanceValue(state.distanceMeters)} of 4.50 km',
      planProgressPercentLabel: '${(planProgressValue * 100).round()}%',
      planProgressValue: planProgressValue,
      guidance: state.isAbnormalPaused
          ? abnormalMovementGuidance
          : state.isPaused || state.isAutoPaused
          ? 'You can pause anytime.'
          : state.elapsedSeconds < 30
          ? 'Easy effort is enough.'
          : 'Keep it comfortable.',
      startupReadiness: startupReadiness,
      startupReadinessMessage: startupReadiness.beginnerMessage,
    );
  }

  final String elapsedTimeLabel;
  final String distanceLabel;
  final String distanceValueLabel;
  final String distanceUnitLabel;
  final String averagePaceLabel;
  final String currentPaceLabel;
  final String planProgressLabel;
  final String planProgressPercentLabel;
  final double planProgressValue;
  final String guidance;
  final RunTrackingStartupReadiness startupReadiness;
  final String? startupReadinessMessage;
}

String _formatElapsed(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainder.toString().padLeft(2, '0')}';
}

String _formatDistance(int meters) {
  return '${_formatDistanceValue(meters)} km';
}

String _formatDistanceValue(int meters) {
  final kilometers = meters / 1000;
  return kilometers.toStringAsFixed(2);
}

String _formatPace(int secondsPerKm) {
  if (secondsPerKm <= 0) {
    return '--:--/km';
  }

  final minutes = secondsPerKm ~/ 60;
  final seconds = secondsPerKm % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}/km';
}
