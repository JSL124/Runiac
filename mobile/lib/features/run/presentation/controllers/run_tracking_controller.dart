import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/elevation_analysis_series.dart';
import '../../domain/models/local_run_completion_payload.dart';
import '../../domain/models/run_cadence_diagnostics.dart';
import '../../domain/models/run_cadence_sample.dart';
import '../../domain/models/run_location_sample.dart';
import '../../domain/models/run_location_permission_status.dart';
import '../../domain/models/run_map_view_state.dart';
import '../../domain/models/run_route_snapshot.dart';
import '../../domain/models/run_tracking_diagnostics.dart';
import '../../domain/models/run_tracking_notification_copy.dart';
import '../../domain/models/run_tracking_state.dart';
import '../../domain/repositories/run_foreground_service.dart';
import '../../domain/repositories/run_cadence_provider.dart';
import '../../domain/repositories/run_location_permission_service.dart';
import '../../domain/repositories/run_location_provider.dart';
import '../../domain/repositories/run_motion_provider.dart';
import '../../domain/repositories/run_notification_permission_service.dart';
import '../../domain/services/completed_run_title_formatter.dart';
import '../../domain/services/local_run_tracking_session.dart';
import '../../voice/application/run_voice_snapshot_mapper.dart';
import '../../voice/domain/models/run_voice_session_config.dart';
import '../../voice/domain/ports/run_voice_coach.dart';
import '../widgets/display_route_smoother.dart';

class RunTrackingController extends ChangeNotifier {
  RunTrackingController({
    double metersPerSecond = 2.4,
    RunLocationProvider? locationProvider,
    RunCadenceProvider? cadenceProvider,
    RunMotionProvider? motionProvider,
    RunForegroundService? foregroundService,
    this.permissionService,
    this.notificationPermissionService,
    RunTrackingLocationStatus locationStatus = RunTrackingLocationStatus.demo,
    RunLocationSample? initialPreviewCurrentPosition,
    RunVoiceCoach voiceCoach = const NoopRunVoiceCoach(),
  }) : metersPerSecond = metersPerSecond,
       _locationProvider =
           locationProvider ??
           ConstantSpeedRunLocationProvider(metersPerSecond: metersPerSecond),
       _cadenceProvider =
           cadenceProvider ?? const UnavailableRunCadenceProvider(),
       _motionProvider = motionProvider ?? const NoopRunMotionProvider(),
       _foregroundService =
           foregroundService ?? const NoopRunForegroundService(),
       _initialLocationStatus = locationStatus,
       _previewCurrentPosition = initialPreviewCurrentPosition,
       // ignore: prefer_initializing_formals
       _voiceCoach = voiceCoach;

  final double metersPerSecond;
  final RunLocationProvider _locationProvider;
  final RunCadenceProvider _cadenceProvider;
  final RunMotionProvider _motionProvider;
  final RunForegroundService _foregroundService;
  final RunLocationPermissionService? permissionService;
  final RunNotificationPermissionService? notificationPermissionService;
  final RunTrackingLocationStatus _initialLocationStatus;
  final RunVoiceCoach _voiceCoach;
  RunVoiceSessionConfig? _voiceConfig;

  RunTrackingState _state = const RunTrackingState.idle();
  RunLocationPermissionStatus _locationPermissionStatus =
      RunLocationPermissionStatus.checking;
  LocalRunTrackingSession? _trackingSession;
  RunMapViewState _mapViewState = const RunMapViewState.empty();
  RunLocationSample? _previewCurrentPosition;
  DateTime? _lastAdvancedAt;
  RunTrackingNotificationCopy? _lastForegroundCopy;
  StreamSubscription<RunCadenceSample>? _cadenceSubscription;
  StreamSubscription<RunCadenceDiagnostics>? _cadenceDiagnosticsSubscription;
  bool _foregroundServiceStarted = false;
  bool _foregroundServiceStarting = false;
  bool _foregroundServiceStopRequested = false;
  bool _disposed = false;
  static int _defaultSessionSequence = 0;
  RunTrackingLocationStatus _latestLocationStatus =
      RunTrackingLocationStatus.demo;

  static const String _autoPauseQaLogPrefix = 'RUNIAC_AUTOPAUSE_QA';
  static const bool _autoPauseQaLogsEnabled = bool.fromEnvironment(
    'RUNIAC_AUTOPAUSE_QA_LOGS',
  );

  RunTrackingState get state => _state;
  RunMapViewState get mapViewState {
    final activeCurrentPosition = _mapViewState.currentPosition;
    if (activeCurrentPosition != null || _previewCurrentPosition == null) {
      return _mapViewState;
    }
    return RunMapViewState(
      previewPosition: _previewCurrentPosition,
      currentPosition: _mapViewState.currentPosition,
      acceptedRouteSegments: _mapViewState.acceptedRouteSegments,
      displayRouteSegments: _mapViewState.displayRouteSegments,
    );
  }

  RunLocationSample? get previewCurrentPosition => _previewCurrentPosition;
  RunLocationPermissionStatus get locationPermissionStatus =>
      _locationPermissionStatus;
  String get locationPermissionMessage => _locationPermissionStatus.message;

  void setPreviewCurrentPosition(RunLocationSample sample) {
    _previewCurrentPosition = sample;
    notifyListeners();
  }

  void start({
    DateTime? startedAt,
    String? clientRunSessionId,
    String routePrivacy = 'private',
    String? routeLabel,
    RunVoiceSessionConfig? voiceConfig,
  }) {
    final effectiveStartedAt = _startSession(
      startedAt: startedAt,
      clientRunSessionId: clientRunSessionId,
      routePrivacy: routePrivacy,
      routeLabel: routeLabel,
    );
    unawaited(_startForegroundService());
    unawaited(_locationProvider.start(startedAt: effectiveStartedAt));
    unawaited(_startCadenceProvider());
    unawaited(_motionProvider.start(startedAt: effectiveStartedAt));
    _voiceConfig = voiceConfig;
    _startVoiceSessionIfEnabled();
    _publishVoiceSnapshot();
    notifyListeners();
  }

  Future<bool> requestStart({
    DateTime? startedAt,
    String? clientRunSessionId,
    String routePrivacy = 'private',
    String? routeLabel,
    RunVoiceSessionConfig? voiceConfig,
  }) async {
    final service = permissionService;
    if (service == null) {
      start(
        startedAt: startedAt,
        clientRunSessionId: clientRunSessionId,
        routePrivacy: routePrivacy,
        routeLabel: routeLabel,
        voiceConfig: voiceConfig,
      );
      return true;
    }

    _locationPermissionStatus = RunLocationPermissionStatus.checking;
    notifyListeners();

    var permissionStatus = await service.checkStatus();
    if (permissionStatus == RunLocationPermissionStatus.denied) {
      permissionStatus = await service.requestPermission();
    }

    _locationPermissionStatus = permissionStatus;
    if (!permissionStatus.canStartRun) {
      notifyListeners();
      return false;
    }

    final notificationService = notificationPermissionService;
    if (notificationService != null) {
      final notificationStatus = await notificationService.requestPermission();
      if (notificationStatus == RunNotificationPermissionStatus.denied) {
        _locationPermissionStatus =
            RunLocationPermissionStatus.notificationDenied;
        notifyListeners();
        return false;
      }
    }

    final effectiveStartedAt = _startSession(
      startedAt: startedAt,
      clientRunSessionId: clientRunSessionId,
      routePrivacy: routePrivacy,
      routeLabel: routeLabel,
    );
    final startedProviders = await _startRunProviders(
      startedAt: effectiveStartedAt,
    );
    if (!startedProviders) {
      _voiceConfig = null;
      unawaited(_safeVoice(_voiceCoach.stopSession));
      if (!_disposed) {
        _locationPermissionStatus = RunLocationPermissionStatus.unavailable;
        notifyListeners();
      }
      return false;
    }
    _voiceConfig = voiceConfig;
    _startVoiceSessionIfEnabled();
    _publishVoiceSnapshot();
    notifyListeners();
    return true;
  }

  void _startVoiceSessionIfEnabled() {
    final cfg = _voiceConfig;
    if (cfg != null && cfg.enabled) {
      unawaited(_safeVoice(() => _voiceCoach.startSession(cfg)));
    }
  }

  DateTime _startSession({
    DateTime? startedAt,
    String? clientRunSessionId,
    String routePrivacy = 'private',
    String? routeLabel,
  }) {
    final effectiveStartedAt = startedAt ?? DateTime.now();
    final session = LocalRunTrackingSession(startedAt: effectiveStartedAt);
    _trackingSession = session;
    unawaited(_cadenceSubscription?.cancel());
    unawaited(_cadenceDiagnosticsSubscription?.cancel());
    _mapViewState = const RunMapViewState.empty();
    _lastAdvancedAt = effectiveStartedAt;
    _lastForegroundCopy = null;
    _foregroundServiceStarted = false;
    _foregroundServiceStarting = false;
    _foregroundServiceStopRequested = false;
    _latestLocationStatus = _initialLocationStatus;
    _state = RunTrackingState(
      phase: RunTrackingPhase.active,
      clientRunSessionId:
          clientRunSessionId ?? _defaultClientRunSessionId(effectiveStartedAt),
      startedAt: effectiveStartedAt,
      completedAt: null,
      elapsedSeconds: 0,
      distanceMeters: 0,
      averagePaceSecondsPerKm: 0,
      currentPaceSecondsPerKm: 0,
      routePrivacy: routePrivacy,
      routeLabel: routeLabel,
      source: session.source,
      locationStatus: _initialLocationStatus,
      diagnostics: session.diagnostics,
    );
    _cadenceSubscription = _cadenceProvider.cadenceStream.listen(
      _recordCadenceSample,
    );
    _cadenceDiagnosticsSubscription = _cadenceProvider.diagnosticsStream.listen(
      _recordCadenceDiagnostics,
    );
    _logPhaseTransition(
      from: RunTrackingPhase.idle,
      to: RunTrackingPhase.active,
      reason: 'start',
    );
    return effectiveStartedAt;
  }

  static String _defaultClientRunSessionId(DateTime startedAt) {
    _defaultSessionSequence += 1;
    final startedMicros = startedAt.toUtc().microsecondsSinceEpoch;
    final generatedMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'local-run-$startedMicros-$generatedMicros-$_defaultSessionSequence';
  }

  void syncTo(DateTime now) {
    final lastAdvancedAt = _lastAdvancedAt;
    if (lastAdvancedAt == null) {
      return;
    }

    if (_state.isPaused) {
      _lastAdvancedAt = now;
      return;
    }

    final delta = now.difference(lastAdvancedAt);
    if (delta <= Duration.zero) {
      return;
    }

    advanceBy(delta);
    _lastAdvancedAt = now;
  }

  void advanceBy(Duration delta) {
    if (!_state.isActive || delta <= Duration.zero) {
      return;
    }

    final session = _trackingSession;
    final startedAt = _state.startedAt;
    if (session == null || startedAt == null) {
      return;
    }

    final fromActiveOffset = session.trackingDuration;
    final toActiveOffset = fromActiveOffset + delta;
    final samples = _locationProvider
        .samplesBetween(
          fromActiveOffset: fromActiveOffset,
          toActiveOffset: toActiveOffset,
          startedAt: startedAt,
        )
        .toList();
    final motionEvidence = _motionProvider
        .evidenceBetween(
          fromTrackingOffset: fromActiveOffset,
          toTrackingOffset: toActiveOffset,
          startedAt: startedAt,
        )
        .toList();
    session.updateLocationAccuracyStatus(
      _locationProvider.locationAccuracyStatus,
    );
    session.advanceBy(delta, samples: samples, motionEvidence: motionEvidence);
    _latestLocationStatus = _locationStatusFor(session.diagnostics);

    final diagnostics = session.diagnostics.withCadence(
      _state.diagnostics.cadence,
    );
    _state = _state.copyWith(
      elapsedSeconds: session.activeDurationSeconds,
      distanceMeters: session.distanceMeters,
      averagePaceSecondsPerKm: session.averagePaceSecondsPerKm,
      currentPaceSecondsPerKm: session.currentPaceSecondsPerKm,
      locationStatus: _latestLocationStatus,
      diagnostics: diagnostics,
      movementStatus: session.movementStatus,
    );
    _mapViewState = _withSmoothedDisplayRoute(session.mapViewState);
    _updateForegroundService();
    _publishVoiceSnapshot();
    notifyListeners();
  }

  void _publishVoiceSnapshot() {
    if (_voiceConfig?.enabled ?? false) {
      unawaited(
        _safeVoice(
          () =>
              _voiceCoach.onSnapshot(RunVoiceSnapshotMapper.fromState(_state)),
        ),
      );
    }
  }

  Future<void> _safeVoice(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('RUNIAC_VOICE nonfatal: $error');
    }
  }

  RunMapViewState _withSmoothedDisplayRoute(RunMapViewState viewState) {
    return RunMapViewState(
      previewPosition: viewState.previewPosition,
      currentPosition: viewState.currentPosition,
      acceptedRouteSegments: viewState.acceptedRouteSegments,
      displayRouteSegments: DisplayRouteSmoother.smoothSegments(
        viewState.acceptedRouteSegments,
      ),
    );
  }

  RunTrackingLocationStatus _locationStatusFor(
    RunTrackingDiagnostics diagnostics,
  ) {
    if (_initialLocationStatus == RunTrackingLocationStatus.demo) {
      return RunTrackingLocationStatus.demo;
    }

    if (diagnostics.locationAccuracyStatus ==
        RunTrackingLocationAccuracyStatus.reduced) {
      return RunTrackingLocationStatus.approximateLocation;
    }

    final latestAcceptedAt = diagnostics.lastAcceptedSampleAt;
    final latestRejectedAt = diagnostics.lastRejectedSampleAt;
    if (latestAcceptedAt == null && latestRejectedAt == null) {
      return RunTrackingLocationStatus.waitingForGps;
    }
    if (diagnostics.lastRejectedSampleSequence >
        diagnostics.lastAcceptedSampleSequence) {
      return RunTrackingLocationStatus.gpsWeak;
    }
    return RunTrackingLocationStatus.gpsActive;
  }

  void pause({DateTime? pausedAt}) {
    if (!_state.isActive) {
      return;
    }

    final previousPhase = _state.phase;
    _lastAdvancedAt = pausedAt ?? DateTime.now();
    _trackingSession?.pause();
    unawaited(_locationProvider.pause());
    unawaited(_pauseCadenceProvider());
    unawaited(_motionProvider.pause());
    _state = _state.copyWith(phase: RunTrackingPhase.paused);
    _logPhaseTransition(
      from: previousPhase,
      to: RunTrackingPhase.paused,
      reason: 'manualPause',
    );
    unawaited(_updateForegroundService());
    _publishVoiceSnapshot();
    notifyListeners();
  }

  void resume({DateTime? resumedAt}) {
    if (!_state.isPaused && !_state.isAutoPaused && !_state.isAbnormalPaused) {
      return;
    }

    final effectiveResumedAt = resumedAt ?? DateTime.now();
    final activeOffset =
        _trackingSession?.trackingDuration ??
        Duration(seconds: _state.elapsedSeconds);
    final previousPhase = _state.phase;
    final previousMovementStatus = _state.movementStatus;
    _lastAdvancedAt = effectiveResumedAt;
    _trackingSession?.resume(
      resumedAt: effectiveResumedAt,
      activeOffset: activeOffset,
    );
    unawaited(_resumeCadenceProvider());
    unawaited(
      _locationProvider.resume(
        resumedAt: effectiveResumedAt,
        activeOffset: activeOffset,
      ),
    );
    unawaited(
      _motionProvider.resume(
        resumedAt: effectiveResumedAt,
        trackingOffset: activeOffset,
      ),
    );
    _state = _state.copyWith(
      phase: RunTrackingPhase.active,
      movementStatus: RunMovementStatus.moving,
    );
    _logPhaseTransition(
      from: previousPhase,
      to: RunTrackingPhase.active,
      reason: 'manualResume',
    );
    _logMovementTransition(
      from: previousMovementStatus,
      to: RunMovementStatus.moving,
      reason: 'manualResume',
    );
    unawaited(_updateForegroundService());
    _publishVoiceSnapshot();
    notifyListeners();
  }

  LocalRunCompletionPayload completionPayload({
    DateTime? completedAt,
    String? planEnrollmentId,
    String? scheduledWorkoutId,
  }) {
    final startedAt = _state.startedAt;
    if (startedAt == null || _state.phase == RunTrackingPhase.idle) {
      throw StateError('Cannot finish a run before it starts.');
    }

    final finishedAt = completedAt ?? DateTime.now();
    return LocalRunCompletionPayload(
      clientRunSessionId: _state.clientRunSessionId,
      startedAt: startedAt,
      completedAt: finishedAt,
      durationSeconds: _state.elapsedSeconds,
      distanceMeters: _state.distanceMeters,
      avgPaceSecondsPerKm: _state.averagePaceSecondsPerKm,
      source: _state.source,
      routePrivacy: _state.routePrivacy,
      activityTitle: const CompletedRunTitleFormatter().format(
        completedAt: finishedAt,
      ),
      routeLabel: _state.routeLabel,
      planEnrollmentId: planEnrollmentId,
      scheduledWorkoutId: scheduledWorkoutId,
      routeSnapshot: RunRouteSnapshot.fromMapViewState(mapViewState),
      paceGraphSamples: _trackingSession?.paceGraphSamples() ?? const [],
      cadenceAnalysisSeries: _trackingSession?.cadenceAnalysisSeries(
        completedAt: finishedAt,
      ),
      elevationAnalysisSeries: _trackingSession?.elevationAnalysisSeries(),
      elevationUnavailableReason:
          _trackingSession?.elevationUnavailableReason() ??
          ElevationUnavailableReason.noElevationSeries,
    );
  }

  LocalRunCompletionPayload finish({
    DateTime? completedAt,
    String? planEnrollmentId,
    String? scheduledWorkoutId,
  }) {
    final payload = completionPayload(
      completedAt: completedAt,
      planEnrollmentId: planEnrollmentId,
      scheduledWorkoutId: scheduledWorkoutId,
    );
    final previousPhase = _state.phase;
    unawaited(_locationProvider.stop());
    unawaited(_stopCadenceProvider());
    unawaited(_cadenceSubscription?.cancel());
    _cadenceSubscription = null;
    unawaited(_cadenceDiagnosticsSubscription?.cancel());
    _cadenceDiagnosticsSubscription = null;
    unawaited(_motionProvider.stop());
    unawaited(_stopForegroundService());
    unawaited(_safeVoice(_voiceCoach.stopSession));
    _voiceConfig = null;
    _mapViewState = const RunMapViewState.empty();
    _previewCurrentPosition = null;
    _lastAdvancedAt = null;
    _state = _state.copyWith(
      phase: RunTrackingPhase.finished,
      completedAt: payload.completedAt,
    );
    _logPhaseTransition(
      from: previousPhase,
      to: RunTrackingPhase.finished,
      reason: 'finish',
    );
    notifyListeners();

    return payload;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_locationProvider.stop());
    unawaited(_stopCadenceProvider());
    unawaited(_cadenceSubscription?.cancel());
    unawaited(_cadenceDiagnosticsSubscription?.cancel());
    unawaited(_motionProvider.stop());
    unawaited(_stopForegroundService());
    unawaited(_safeVoice(_voiceCoach.stopSession));
    _voiceConfig = null;
    super.dispose();
  }

  Future<bool> _startRunProviders({required DateTime startedAt}) async {
    try {
      await _startForegroundService();
      if (_disposed) {
        return false;
      }

      await _locationProvider.start(startedAt: startedAt);
      if (_disposed) {
        await _locationProvider.stop();
        return false;
      }

      await _startCadenceProvider();
      if (_disposed) {
        await _locationProvider.stop();
        await _stopCadenceProvider();
        return false;
      }

      await _motionProvider.start(startedAt: startedAt);
      if (_disposed) {
        await _locationProvider.stop();
        await _motionProvider.stop();
        return false;
      }

      return true;
    } catch (error, stackTrace) {
      // Report before the cleanup below, not after: a `stop()` call in that
      // cleanup can itself throw, which would discard the original cause and
      // leave a run that refused to start with no trace anywhere.
      _reportRunProviderStartFailure(error, stackTrace);
      await _locationProvider.stop();
      await _stopCadenceProvider();
      await _motionProvider.stop();
      await _stopForegroundService();
      if (!_disposed) {
        _resetAfterFailedStart();
      }
      return false;
    }
  }

  /// Records why the location / cadence / motion / foreground-service startup
  /// failed. The `catch` above previously swallowed the cause outright, so
  /// "the run would not start" was unanswerable after the fact.
  ///
  /// This is diagnostics only: it reports through the same
  /// `FlutterError.reportError` seam the run completion and activity history
  /// paths already use (which `main.dart` wires into `RuniacErrorReporter`),
  /// changes no control flow, and mutates no run state. `clientRunSessionId`
  /// is the correlation key already carried through completion, so a failed
  /// start can be tied to the rest of that run's flow; it is a locally
  /// generated identifier, never a coordinate, token, or account value.
  void _reportRunProviderStartFailure(Object error, StackTrace stackTrace) {
    try {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac run tracking',
          context: ErrorDescription(
            'starting run tracking providers '
            '(runSessionId=${_state.clientRunSessionId})',
          ),
        ),
      );
    } catch (_) {
      // Diagnostics are best effort. A reporting failure must never turn a
      // recoverable start failure into an unhandled one, and must never stop
      // the provider cleanup that follows this call.
    }
  }

  void _resetAfterFailedStart() {
    _trackingSession = null;
    unawaited(_cadenceSubscription?.cancel());
    _cadenceSubscription = null;
    unawaited(_cadenceDiagnosticsSubscription?.cancel());
    _cadenceDiagnosticsSubscription = null;
    _mapViewState = const RunMapViewState.empty();
    _lastAdvancedAt = null;
    _previewCurrentPosition = null;
    _state = const RunTrackingState.idle();
  }

  Future<void> _startCadenceProvider() async {
    try {
      await _cadenceProvider.start();
    } catch (error) {
      _recordCadenceLifecycleError('start', error);
      return;
    }
  }

  Future<void> _pauseCadenceProvider() async {
    try {
      await _cadenceProvider.pause();
    } catch (error) {
      _recordCadenceLifecycleError('pause', error);
      return;
    }
  }

  Future<void> _resumeCadenceProvider() async {
    try {
      await _cadenceProvider.resume();
    } catch (error) {
      _recordCadenceLifecycleError('resume', error);
      return;
    }
  }

  Future<void> _stopCadenceProvider() async {
    try {
      await _cadenceProvider.stop();
    } catch (error) {
      _recordCadenceLifecycleError('stop', error);
      return;
    }
  }

  void _recordCadenceSample(RunCadenceSample sample) {
    if (!_state.isActive) {
      return;
    }
    _trackingSession?.addCadenceSample(sample);
  }

  void _recordCadenceDiagnostics(RunCadenceDiagnostics diagnostics) {
    if (_disposed || _state.phase == RunTrackingPhase.idle) {
      return;
    }
    _state = _state.copyWith(
      diagnostics: _state.diagnostics.withCadence(diagnostics),
    );
    notifyListeners();
  }

  void _recordCadenceLifecycleError(String operation, Object error) {
    if (_disposed) {
      return;
    }
    final current = _state.diagnostics.cadence;
    _recordCadenceDiagnostics(
      current.copyWith(
        latestReason: RunCadenceDiagnosticReason.lifecycleError,
        lifecycleErrorCount: current.lifecycleErrorCount + 1,
        latestNativeErrorCode: 'cadenceProvider.$operation',
        latestNativeErrorMessage: '$error',
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _startForegroundService() async {
    if (_foregroundServiceStarted || _foregroundServiceStarting) {
      return;
    }

    final copy = RunTrackingNotificationCopy.fromState(_state);
    _lastForegroundCopy = copy;
    _foregroundServiceStarting = true;
    _foregroundServiceStopRequested = false;
    try {
      await _foregroundService.start(copy);
      _foregroundServiceStarted = true;
    } finally {
      _foregroundServiceStarting = false;
    }

    if (_foregroundServiceStopRequested) {
      await _stopForegroundService();
    }
  }

  Future<void> _updateForegroundService() async {
    if (!_foregroundServiceStarted) {
      return;
    }
    if (_state.phase == RunTrackingPhase.idle ||
        _state.phase == RunTrackingPhase.finished) {
      return;
    }

    final copy = RunTrackingNotificationCopy.fromState(_state);
    if (_lastForegroundCopy == copy) {
      return;
    }

    _lastForegroundCopy = copy;
    await _foregroundService.update(copy);
  }

  Future<void> _stopForegroundService() async {
    if (_foregroundServiceStarting) {
      _foregroundServiceStopRequested = true;
      return;
    }
    if (!_foregroundServiceStarted) {
      return;
    }
    _foregroundServiceStarted = false;
    _foregroundServiceStopRequested = false;
    _lastForegroundCopy = null;
    await _foregroundService.stop();
  }

  void _logPhaseTransition({
    required RunTrackingPhase from,
    required RunTrackingPhase to,
    required String reason,
  }) {
    if (!_autoPauseQaLogsEnabled) {
      return;
    }
    _logAutoPauseQa(
      'phase=transition from=${from.name} to=${to.name} reason=$reason',
    );
  }

  void _logMovementTransition({
    required RunMovementStatus from,
    required RunMovementStatus to,
    required String reason,
  }) {
    if (!_autoPauseQaLogsEnabled) {
      return;
    }
    if (from == to) {
      return;
    }
    _logAutoPauseQa(
      'phase=transition from=${from.name} to=${to.name} reason=$reason',
    );
  }

  void _logAutoPauseQa(String message) {
    if (!_autoPauseQaLogsEnabled) {
      return;
    }
    debugPrint('$_autoPauseQaLogPrefix $message');
  }
}
