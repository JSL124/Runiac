import 'run_tracking_diagnostics.dart';
import 'run_tracking_state.dart';

const livePaceReadinessThresholdMeters = 50;

enum RunTrackingStartupReadiness {
  demo,
  waitingForFirstSample,
  gpsWeak,
  anchoredNoMovement,
  movementBelowThreshold,
  ready,
  approximateLocation,
}

extension RunTrackingStartupReadinessCopy on RunTrackingStartupReadiness {
  String? get beginnerMessage {
    switch (this) {
      case RunTrackingStartupReadiness.demo:
        return null;
      case RunTrackingStartupReadiness.waitingForFirstSample:
        return 'Getting GPS ready. Keep the app open while we find your signal.';
      case RunTrackingStartupReadiness.gpsWeak:
        return 'GPS signal is weak. Keep moving in an open area.';
      case RunTrackingStartupReadiness.anchoredNoMovement:
        return 'GPS is ready. Start moving to measure distance.';
      case RunTrackingStartupReadiness.movementBelowThreshold:
        return 'Keep going. Pace appears after a little more movement.';
      case RunTrackingStartupReadiness.ready:
        return 'GPS active. Distance and pace are updating.';
      case RunTrackingStartupReadiness.approximateLocation:
        return 'Approximate location is on. Distance may take longer to settle.';
    }
  }
}

RunTrackingStartupReadiness startupReadinessForState(RunTrackingState state) {
  final diagnostics = state.diagnostics;

  if (state.locationStatus == RunTrackingLocationStatus.demo) {
    return RunTrackingStartupReadiness.demo;
  }

  if (diagnostics.locationAccuracyStatus ==
      RunTrackingLocationAccuracyStatus.reduced) {
    return RunTrackingStartupReadiness.approximateLocation;
  }

  if (state.distanceMeters >= livePaceReadinessThresholdMeters) {
    return RunTrackingStartupReadiness.ready;
  }

  if (!diagnostics.hasReceivedSample) {
    return RunTrackingStartupReadiness.waitingForFirstSample;
  }

  if (diagnostics.lastRejectedSampleSequence >
      diagnostics.lastAcceptedSampleSequence) {
    return RunTrackingStartupReadiness.gpsWeak;
  }

  if (diagnostics.hasAcceptedSample && state.distanceMeters == 0) {
    return RunTrackingStartupReadiness.anchoredNoMovement;
  }

  if (state.distanceMeters > 0 &&
      state.distanceMeters < livePaceReadinessThresholdMeters) {
    return RunTrackingStartupReadiness.movementBelowThreshold;
  }

  return RunTrackingStartupReadiness.waitingForFirstSample;
}
