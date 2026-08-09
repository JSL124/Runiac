import '../../domain/models/run_tracking_startup_readiness.dart';
import '../../domain/models/run_tracking_state.dart';
import '../domain/models/run_voice_snapshot.dart';

class RunVoiceSnapshotMapper {
  static RunVoiceSnapshot fromState(RunTrackingState state) {
    final paused =
        state.isPaused || state.isAutoPaused || state.isAbnormalPaused;
    final pace =
        (state.averagePaceSecondsPerKm > 0 &&
            state.distanceMeters >= livePaceReadinessThresholdMeters)
        ? Duration(seconds: state.averagePaceSecondsPerKm)
        : null;
    final currentPace =
        (state.currentPaceSecondsPerKm > 0 &&
            state.distanceMeters >= livePaceReadinessThresholdMeters)
        ? Duration(seconds: state.currentPaceSecondsPerKm)
        : null;
    return RunVoiceSnapshot(
      distanceMeters: state.distanceMeters,
      elapsed: Duration(seconds: state.elapsedSeconds),
      averagePace: pace,
      isActive: state.phase == RunTrackingPhase.active && !paused,
      isPaused: paused,
      currentPace: currentPace,
    );
  }
}
