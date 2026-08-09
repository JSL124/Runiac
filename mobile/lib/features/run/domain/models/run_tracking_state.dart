import 'run_tracking_diagnostics.dart';

enum RunTrackingPhase { idle, active, paused, finished }

enum RunMovementStatus { moving, autoPaused, abnormalPaused }

enum RunTrackingLocationStatus {
  demo('Demo mode'),
  waitingForGps('Waiting for GPS'),
  gpsActive('GPS active'),
  gpsWeak('GPS weak'),
  approximateLocation('Approximate location');

  const RunTrackingLocationStatus(this.label);

  final String label;
}

class RunTrackingState {
  const RunTrackingState({
    required this.phase,
    required this.clientRunSessionId,
    required this.startedAt,
    required this.completedAt,
    required this.elapsedSeconds,
    required this.distanceMeters,
    required this.averagePaceSecondsPerKm,
    required this.currentPaceSecondsPerKm,
    required this.routePrivacy,
    required this.source,
    required this.locationStatus,
    required this.diagnostics,
    this.movementStatus = RunMovementStatus.moving,
    this.routeLabel,
  });

  const RunTrackingState.idle()
    : phase = RunTrackingPhase.idle,
      clientRunSessionId = '',
      startedAt = null,
      completedAt = null,
      elapsedSeconds = 0,
      distanceMeters = 0,
      averagePaceSecondsPerKm = 0,
      currentPaceSecondsPerKm = 0,
      routePrivacy = 'private',
      source = 'local_simulation',
      locationStatus = RunTrackingLocationStatus.demo,
      diagnostics = const RunTrackingDiagnostics.initial(),
      movementStatus = RunMovementStatus.moving,
      routeLabel = null;

  final RunTrackingPhase phase;
  final String clientRunSessionId;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int elapsedSeconds;
  final int distanceMeters;
  final int averagePaceSecondsPerKm;
  final int currentPaceSecondsPerKm;
  final String routePrivacy;
  final String source;
  final RunTrackingLocationStatus locationStatus;
  final RunTrackingDiagnostics diagnostics;
  final RunMovementStatus movementStatus;
  final String? routeLabel;

  bool get isPaused => phase == RunTrackingPhase.paused;
  bool get isActive => phase == RunTrackingPhase.active;
  bool get isAutoPaused =>
      phase == RunTrackingPhase.active &&
      movementStatus == RunMovementStatus.autoPaused;
  bool get isAbnormalPaused =>
      phase == RunTrackingPhase.active &&
      movementStatus == RunMovementStatus.abnormalPaused;

  RunTrackingState copyWith({
    RunTrackingPhase? phase,
    String? clientRunSessionId,
    DateTime? startedAt,
    DateTime? completedAt,
    int? elapsedSeconds,
    int? distanceMeters,
    int? averagePaceSecondsPerKm,
    int? currentPaceSecondsPerKm,
    String? routePrivacy,
    String? source,
    RunTrackingLocationStatus? locationStatus,
    RunTrackingDiagnostics? diagnostics,
    RunMovementStatus? movementStatus,
    String? routeLabel,
  }) {
    return RunTrackingState(
      phase: phase ?? this.phase,
      clientRunSessionId: clientRunSessionId ?? this.clientRunSessionId,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      averagePaceSecondsPerKm:
          averagePaceSecondsPerKm ?? this.averagePaceSecondsPerKm,
      currentPaceSecondsPerKm:
          currentPaceSecondsPerKm ?? this.currentPaceSecondsPerKm,
      routePrivacy: routePrivacy ?? this.routePrivacy,
      source: source ?? this.source,
      locationStatus: locationStatus ?? this.locationStatus,
      diagnostics: diagnostics ?? this.diagnostics,
      movementStatus: movementStatus ?? this.movementStatus,
      routeLabel: routeLabel ?? this.routeLabel,
    );
  }
}
