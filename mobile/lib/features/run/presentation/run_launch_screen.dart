import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/haptics/runiac_haptics_scope.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_bottom_sheet_handle.dart';
import '../../settings/data/shared_preferences_app_settings_repository.dart';
import '../../settings/domain/models/app_settings.dart';
import '../../settings/domain/repositories/app_settings_repository.dart';
import '../data/android_run_notification_permission_service.dart';
import '../data/geolocator_run_location_permission_service.dart';
import '../data/phone_motion_run_cadence_provider.dart';
import '../data/platform_run_foreground_service.dart';
import '../data/real_foreground_run_location_provider.dart';
import '../data/sensors_plus_run_motion_provider.dart';
import '../domain/models/run_location_permission_status.dart';
import '../domain/models/run_location_sample.dart';
import '../domain/models/run_tracking_state.dart';
import '../domain/repositories/run_foreground_service.dart';
import '../domain/repositories/run_cadence_provider.dart';
import '../domain/repositories/run_location_permission_service.dart';
import '../domain/repositories/run_location_preview_provider.dart';
import '../domain/repositories/run_location_provider.dart';
import '../domain/repositories/run_motion_provider.dart';
import '../domain/repositories/run_notification_permission_service.dart';
import '../domain/repositories/run_repository.dart';
import '../voice/application/run_voice_coaching_coordinator.dart';
import '../voice/data/shared_preferences_run_voice_settings_repository.dart';
import '../voice/domain/models/run_voice_coaching_settings.dart';
import '../voice/domain/models/run_voice_session_config.dart';
import '../voice/domain/ports/run_voice_coach.dart';
import '../voice/domain/repositories/run_voice_settings_repository.dart';
import '../voice/domain/services/run_voice_announcement_policy.dart';
import '../voice/domain/services/run_voice_announcement_selector.dart';
import '../voice/domain/services/run_voice_message_formatter.dart';
import '../voice/infrastructure/flutter_tts_run_speech_output.dart';
import '../voice/presentation/run_voice_settings_page.dart';
import 'active_run_session_coordinator.dart';
import 'controllers/run_tracking_controller.dart';
import 'cool_down_screen.dart';
import 'data/run_launch_demo_snapshots.dart';
import 'models/planned_run_context.dart';
import 'run_repository_scope.dart';
import 'run_completion_coordinator.dart';
import 'widgets/run_map_placeholder.dart';
import 'widgets/run_mapbox_follow_qa_overlay.dart';
import 'widgets/run_mapbox_surface_config.dart';
import 'widgets/run_status_pill.dart';
import 'widgets/run_tracking_map_surface.dart';
import 'widgets/run_tracking_sheet_content.dart';
import '../../you/presentation/current_session_activity_history.dart';

part 'run_launch_map_controls.dart';
part 'run_launch_bottom_sheet.dart';
part 'run_launch_pre_run_content.dart';

const _sportOrange = Color(0xFFFF7A1A);
const _orangeShadow = Color(0x33FF7A1A);
const _screenBackground = Color(0xFF3153C9);
const _panelTextBlue = Color(0xFF3151C8);
const _mutedBlue = Color(0xFF8296E8);
const _controlPressHold = Duration(milliseconds: 90);
const _sheetAnimationDuration = Duration(milliseconds: 280);
const _sheetExtentAnimationDuration = Duration(milliseconds: 220);
const _expandedRunSheetHeight = 405.0;
const _collapsedRunSheetHeight = 46.0;
const _sheetCollapseVelocityThreshold = 260.0;
const _recenterButtonSize = 48.0;
const _sheetAdjacentRecenterGap = 10.0;
const _launchRecenterRightPadding = 28.0;
const _defaultRunLaunchSnapshot = runLaunchDemoSnapshot;

enum RunSheetMode { preRun, running, paused }

enum RunLaunchSheetExtent { expanded, collapsed }

enum _RunPreviewLocationStatus {
  inactive,
  checkingPermission,
  permissionRequired,
  findingLocation,
  locationReady,
  serviceDisabled,
  permissionBlocked,
  unavailable,
}

RunLocationPermissionService? _resolveRunLaunchPermissionService({
  required bool enableForegroundGps,
  required RunLocationPermissionService? permissionService,
}) {
  if (!enableForegroundGps) {
    return permissionService;
  }
  return permissionService ?? const GeolocatorRunLocationPermissionService();
}

RunLocationPreviewProvider? _resolveRunLaunchPreviewProvider({
  required bool enableForegroundGps,
  required RunLocationPreviewProvider? locationPreviewProvider,
}) {
  if (!enableForegroundGps) {
    return locationPreviewProvider;
  }
  return locationPreviewProvider ??
      const RealForegroundRunLocationPreviewProvider();
}

RunNotificationPermissionService?
_resolveRunLaunchNotificationPermissionService({
  required bool enableForegroundGps,
  required RunNotificationPermissionService? notificationPermissionService,
}) {
  if (!enableForegroundGps) {
    return notificationPermissionService;
  }
  return notificationPermissionService ??
      const AndroidRunNotificationPermissionService();
}

Future<RunLocationSample?> prewarmRunLaunchPreviewCurrentPosition({
  required bool enableForegroundGps,
  RunLocationPermissionService? permissionService,
  RunLocationPreviewProvider? locationPreviewProvider,
}) async {
  final effectivePermissionService = _resolveRunLaunchPermissionService(
    enableForegroundGps: enableForegroundGps,
    permissionService: permissionService,
  );
  final effectivePreviewProvider = _resolveRunLaunchPreviewProvider(
    enableForegroundGps: enableForegroundGps,
    locationPreviewProvider: locationPreviewProvider,
  );
  if (effectivePermissionService == null || effectivePreviewProvider == null) {
    return null;
  }

  try {
    final permissionStatus = await effectivePermissionService.checkStatus();
    if (permissionStatus != RunLocationPermissionStatus.granted) {
      return null;
    }
    return await effectivePreviewProvider.currentLocation();
  } on Object {
    return null;
  }
}

class RunLaunchScreen extends StatefulWidget {
  const RunLaunchScreen({
    super.key,
    this.repository,
    this.locationProvider,
    this.cadenceProvider,
    this.motionProvider,
    this.locationPreviewProvider,
    this.permissionService,
    this.notificationPermissionService,
    this.foregroundService,
    this.enableForegroundGps = true,
    this.mapboxAccessToken,
    this.mapboxBuilder,
    this.enableMapboxFollowQa = runMapboxFollowQaEnabled,
    this.initialPreviewCurrentPosition,
    this.activeRunSessionCoordinator,
    this.plannedWorkout,
    this.settingsRepository = const SharedPreferencesAppSettingsRepository(),
    this.voiceSettingsRepository =
        const SharedPreferencesRunVoiceSettingsRepository(),
    this.voiceCoach,
  });

  final RunRepository? repository;
  final RunLocationProvider? locationProvider;
  final RunCadenceProvider? cadenceProvider;
  final RunMotionProvider? motionProvider;
  final RunLocationPreviewProvider? locationPreviewProvider;
  final RunLocationPermissionService? permissionService;
  final RunNotificationPermissionService? notificationPermissionService;
  final RunForegroundService? foregroundService;
  final bool enableForegroundGps;
  final String? mapboxAccessToken;
  final RunMapboxSurfaceBuilder? mapboxBuilder;
  final bool enableMapboxFollowQa;
  final RunLocationSample? initialPreviewCurrentPosition;
  final ActiveRunSessionCoordinator? activeRunSessionCoordinator;
  final PlannedRunContext? plannedWorkout;
  final AppSettingsRepository settingsRepository;
  final RunVoiceSettingsRepository voiceSettingsRepository;
  final RunVoiceCoach? voiceCoach;

  @override
  State<RunLaunchScreen> createState() => _RunLaunchScreenState();
}

class _RunLaunchScreenState extends State<RunLaunchScreen> {
  late final RunTrackingController _controller;
  late final ActiveRunSessionCoordinator _activeRunSessionCoordinator;
  late final bool _ownsActiveRunSessionCoordinator;
  late final RunLocationPermissionService? _permissionService;
  late final RunLocationPreviewProvider? _locationPreviewProvider;
  RunSheetMode _sheetMode = RunSheetMode.preRun;
  RunLaunchSheetExtent _sheetExtent = RunLaunchSheetExtent.expanded;
  double _sheetProgress = 1;
  bool _isCompletingRun = false;
  bool _isFollowingRunner = true;
  int _mapRecenterRequestId = 0;
  int _previewRequestId = 0;
  late final RunMapboxFollowQaDiagnostics? _followQaDiagnostics =
      widget.enableMapboxFollowQa
      ? RunMapboxFollowQaDiagnostics(enabled: true, screenPath: 'launch')
      : null;
  _RunPreviewLocationStatus _previewLocationStatus =
      _RunPreviewLocationStatus.inactive;
  AppSettings _settings = AppSettings.defaults;
  RunVoiceCoachingSettings _voiceSettings = RunVoiceCoachingSettings.defaults;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_loadVoiceSettings());
    final useForegroundGps = widget.enableForegroundGps;
    _permissionService = _resolveRunLaunchPermissionService(
      enableForegroundGps: useForegroundGps,
      permissionService: widget.permissionService,
    );
    _locationPreviewProvider = _resolveRunLaunchPreviewProvider(
      enableForegroundGps: useForegroundGps,
      locationPreviewProvider: widget.locationPreviewProvider,
    );
    _ownsActiveRunSessionCoordinator =
        widget.activeRunSessionCoordinator == null;
    _activeRunSessionCoordinator =
        widget.activeRunSessionCoordinator ?? ActiveRunSessionCoordinator();
    _controller = _activeRunSessionCoordinator.controllerFor(
      () => RunTrackingController(
        locationProvider: useForegroundGps
            ? widget.locationProvider ?? RealForegroundRunLocationProvider()
            : widget.locationProvider,
        cadenceProvider:
            widget.cadenceProvider ??
            (useForegroundGps && widget.locationProvider == null
                ? PhoneMotionRunCadenceProvider()
                : null),
        motionProvider: useForegroundGps
            ? widget.motionProvider ?? SensorsPlusRunMotionProvider()
            : widget.motionProvider,
        foregroundService: useForegroundGps
            ? widget.foregroundService ?? platformRunForegroundService()
            : null,
        permissionService: _permissionService,
        notificationPermissionService:
            _resolveRunLaunchNotificationPermissionService(
              enableForegroundGps: useForegroundGps,
              notificationPermissionService:
                  widget.notificationPermissionService,
            ),
        locationStatus: useForegroundGps
            ? RunTrackingLocationStatus.waitingForGps
            : RunTrackingLocationStatus.demo,
        initialPreviewCurrentPosition: widget.initialPreviewCurrentPosition,
        voiceCoach: widget.voiceCoach ?? _buildProductionVoiceCoach(),
      ),
    );
    _restoreSheetModeForActiveController();
    if (useForegroundGps) {
      _previewLocationStatus = widget.initialPreviewCurrentPosition == null
          ? _RunPreviewLocationStatus.checkingPermission
          : _RunPreviewLocationStatus.locationReady;
      unawaited(_refreshPreviewLocation(requestPermission: false));
    }
  }

  /// Builds the production [RunVoiceCoach].
  ///
  /// Construction itself is cheap and touches no platform channel: the
  /// underlying `flutter_tts` plugin instance inside
  /// [FlutterTtsRunSpeechOutput] is created lazily on first use, and voice
  /// coaching only runs a session when [RunVoiceCoachingSettings.enabled] is
  /// true (disabled by default).
  RunVoiceCoach _buildProductionVoiceCoach() {
    return RunVoiceCoachingCoordinator(
      policy: DefaultRunVoiceAnnouncementPolicy(),
      selector: const PriorityRunVoiceAnnouncementSelector(),
      formatter: const LocalizedRunVoiceMessageFormatter(),
      speechOutput: FlutterTtsRunSpeechOutput(),
    );
  }

  void _restoreSheetModeForActiveController() {
    final state = _controller.state;
    if (state.phase == RunTrackingPhase.idle ||
        state.phase == RunTrackingPhase.finished) {
      return;
    }

    _sheetMode = state.isPaused || state.isAutoPaused || state.isAbnormalPaused
        ? RunSheetMode.paused
        : RunSheetMode.running;
    _activeRunSessionCoordinator.startForegroundTicker();
    _activeRunSessionCoordinator.syncNow();
  }

  Future<void> _loadSettings() async {
    var settings = AppSettings.defaults;
    try {
      settings = await widget.settingsRepository.loadSettings();
    } on Object {
      settings = AppSettings.defaults;
    }
    if (mounted) {
      setState(() => _settings = settings);
    }
  }

  Future<void> _loadVoiceSettings() async {
    var voiceSettings = RunVoiceCoachingSettings.defaults;
    try {
      voiceSettings = await widget.voiceSettingsRepository.load();
    } on Object {
      voiceSettings = RunVoiceCoachingSettings.defaults;
    }
    if (mounted) {
      setState(() => _voiceSettings = voiceSettings);
    }
  }

  @override
  void dispose() {
    _activeRunSessionCoordinator.stopForegroundTicker();
    if (_ownsActiveRunSessionCoordinator) {
      _activeRunSessionCoordinator.dispose();
    }
    super.dispose();
  }

  void _updateFollowQaMapState() {
    final diagnostics = _followQaDiagnostics;
    diagnostics?.updateMapState(
      mapPath: diagnostics.mapPath,
      isFollowingRunner: _isFollowingRunner,
      recenterRequestId: _mapRecenterRequestId,
    );
  }

  Future<void> _startRun() async {
    if (_sheetMode != RunSheetMode.preRun) {
      return;
    }

    if (_controller.state.phase == RunTrackingPhase.idle ||
        _controller.state.phase == RunTrackingPhase.finished) {
      // Re-read voice settings from the repository right before starting:
      // if the user just enabled voice coaching on the settings page and
      // tapped Start immediately, `_voiceSettings` may still hold the stale
      // in-memory value because `_openVoiceSettings()` reloads it without
      // awaiting. The repository is the source of truth at Start time, so
      // this eliminates that navigation race. A failed load falls back to
      // whatever `_voiceSettings` currently holds.
      var latestVoiceSettings = _voiceSettings;
      try {
        latestVoiceSettings = await widget.voiceSettingsRepository.load();
        if (mounted) {
          setState(() => _voiceSettings = latestVoiceSettings);
        }
      } on Object {
        // Keep the current _voiceSettings value.
      }
      if (!mounted) {
        return;
      }

      final started = await _controller.requestStart(
        startedAt: _activeRunSessionCoordinator.now(),
        routeLabel: 'Easy local route',
        voiceConfig: RunVoiceSessionConfig.fromSettings(
          settings: latestVoiceSettings,
          targetDistanceMeters: widget.plannedWorkout?.targetDistanceMeters
              ?.toDouble(),
        ),
      );
      if (!mounted) {
        return;
      }
      if (!started) {
        _showPreviewMessage(_controller.locationPermissionMessage);
        return;
      }
      // Confirm the run actually began. Fired only once tracking has started,
      // so a permission-blocked Start stays silent.
      RuniacHapticsScope.maybeOf(context)?.impactMedium();
    }

    _activeRunSessionCoordinator.startForegroundTicker();

    final shouldAlignCameraOnStart = _isFollowingRunner && _hasCurrentPosition;
    setState(() {
      _sheetExtent = RunLaunchSheetExtent.expanded;
      _sheetProgress = 1;
      if (shouldAlignCameraOnStart) {
        _mapRecenterRequestId++;
      }
      _sheetMode = RunSheetMode.running;
    });
    if (shouldAlignCameraOnStart) {
      _followQaDiagnostics?.recordRecenterRequest(_mapRecenterRequestId);
    }
    _updateFollowQaMapState();
  }

  void _pauseRun() {
    if (_isCompletingRun) {
      return;
    }
    final pausedAt = _activeRunSessionCoordinator.now();
    _activeRunSessionCoordinator.syncTo(pausedAt);
    _controller.pause(pausedAt: pausedAt);
    RuniacHapticsScope.maybeOf(context)?.impactLight();
    setState(() => _sheetMode = RunSheetMode.paused);
  }

  void _resumeRun() {
    if (_isCompletingRun) {
      return;
    }
    _controller.resume(resumedAt: _activeRunSessionCoordinator.now());
    RuniacHapticsScope.maybeOf(context)?.impactLight();
    setState(() => _sheetMode = RunSheetMode.running);
    _followQaDiagnostics?.recordResume();
    _updateFollowQaMapState();
  }

  void _handleSheetDragStart(DragStartDetails details) {}

  void _handleSheetDragUpdate(DragUpdateDetails details) {
    setState(() {
      _sheetProgress =
          (_sheetProgress -
                  details.delta.dy /
                      (_expandedRunSheetHeight - _collapsedRunSheetHeight))
              .clamp(0, 1);
      _sheetExtent = _sheetProgress <= 0.01
          ? RunLaunchSheetExtent.collapsed
          : RunLaunchSheetExtent.expanded;
    });
  }

  void _handleSheetDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    setState(() {
      if (velocity > _sheetCollapseVelocityThreshold) {
        _sheetExtent = RunLaunchSheetExtent.collapsed;
        _sheetProgress = 0;
      } else if (velocity < -_sheetCollapseVelocityThreshold) {
        _sheetExtent = RunLaunchSheetExtent.expanded;
        _sheetProgress = 1;
      } else if (_sheetProgress >= 0.5) {
        _sheetExtent = RunLaunchSheetExtent.expanded;
        _sheetProgress = 1;
      } else {
        _sheetExtent = RunLaunchSheetExtent.collapsed;
        _sheetProgress = 0;
      }
    });
  }

  void _handleSheetDragCancel() {
    setState(() {
      if (_sheetProgress >= 0.5) {
        _sheetExtent = RunLaunchSheetExtent.expanded;
        _sheetProgress = 1;
      } else {
        _sheetExtent = RunLaunchSheetExtent.collapsed;
        _sheetProgress = 0;
      }
    });
  }

  void _toggleSheetExtent() {
    setState(() {
      if (_sheetExtent == RunLaunchSheetExtent.expanded) {
        _sheetExtent = RunLaunchSheetExtent.collapsed;
        _sheetProgress = 0;
      } else {
        _sheetExtent = RunLaunchSheetExtent.expanded;
        _sheetProgress = 1;
      }
    });
  }

  Future<void> _finishRun() async {
    if (_isCompletingRun) {
      return;
    }

    final completedAt = _activeRunSessionCoordinator.now();
    _activeRunSessionCoordinator.syncTo(completedAt);
    final plannedWorkout = widget.plannedWorkout;
    final planEnrollmentId = plannedWorkout?.alreadyCompletedToday == true
        ? null
        : plannedWorkout?.planEnrollmentId;
    final scheduledWorkoutId = plannedWorkout?.alreadyCompletedToday == true
        ? null
        : plannedWorkout?.scheduledWorkoutId;
    final payload = _controller.completionPayload(
      completedAt: completedAt,
      planEnrollmentId: planEnrollmentId,
      scheduledWorkoutId: scheduledWorkoutId,
    );
    setState(() => _isCompletingRun = true);

    final activityHistoryStore = CurrentSessionActivityHistoryScope.maybeOf(
      context,
    );
    final result = await const RunCompletionCoordinator().complete(
      repository: _repository,
      payload: payload,
      activityHistoryStore: activityHistoryStore,
    );
    if (!mounted) {
      return;
    }
    _activeRunSessionCoordinator.stopForegroundTicker();
    _controller.finish(completedAt: completedAt);
    RuniacHapticsScope.maybeOf(context)?.impactMedium();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => CoolDownScreen(
          completionResult: result,
          completionPayload: payload,
          repository: _repository,
        ),
      ),
    );
  }

  RunRepository get _repository {
    return widget.repository ?? RunRepositoryScope.of(context);
  }

  void _showPreviewMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openVoiceSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RunVoiceSettingsPage(
          settingsRepository: widget.voiceSettingsRepository,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadVoiceSettings();
  }

  Future<void> _refreshPreviewLocation({
    required bool requestPermission,
    bool showFailureMessage = false,
    bool recenterOnSuccess = false,
  }) async {
    final permissionService = _permissionService;
    final previewProvider = _locationPreviewProvider;
    if (!widget.enableForegroundGps ||
        permissionService == null ||
        previewProvider == null) {
      return;
    }

    final requestId = ++_previewRequestId;
    final hasSeededPreview = _controller.previewCurrentPosition != null;
    if (mounted) {
      setState(() {
        _previewLocationStatus = requestPermission
            ? _RunPreviewLocationStatus.findingLocation
            : hasSeededPreview
            ? _RunPreviewLocationStatus.locationReady
            : _RunPreviewLocationStatus.checkingPermission;
      });
    }

    var permissionStatus = await permissionService.checkStatus();
    if (requestPermission &&
        permissionStatus == RunLocationPermissionStatus.denied) {
      permissionStatus = await permissionService.requestPermission();
    }
    if (!mounted || requestId != _previewRequestId) {
      return;
    }

    if (!permissionStatus.canStartRun) {
      setState(() {
        _previewLocationStatus = _previewStatusForPermission(permissionStatus);
      });
      if (showFailureMessage) {
        _showPreviewMessage(permissionStatus.message);
      }
      return;
    }

    if (!hasSeededPreview || requestPermission) {
      setState(() {
        _previewLocationStatus = _RunPreviewLocationStatus.findingLocation;
      });
    }

    try {
      final sample = await previewProvider.currentLocation();
      if (!mounted || requestId != _previewRequestId) {
        return;
      }
      _controller.setPreviewCurrentPosition(sample);
      setState(() {
        _previewLocationStatus = _RunPreviewLocationStatus.locationReady;
        if (recenterOnSuccess) {
          _isFollowingRunner = true;
          _mapRecenterRequestId++;
        }
      });
      if (recenterOnSuccess) {
        _followQaDiagnostics?.recordRecenterRequest(_mapRecenterRequestId);
        _updateFollowQaMapState();
      }
    } on Object {
      if (!mounted || requestId != _previewRequestId) {
        return;
      }
      setState(() {
        _previewLocationStatus = _RunPreviewLocationStatus.unavailable;
      });
      if (showFailureMessage) {
        _showPreviewMessage(RunLocationPermissionStatus.unavailable.message);
      }
    }
  }

  _RunPreviewLocationStatus _previewStatusForPermission(
    RunLocationPermissionStatus status,
  ) {
    return switch (status) {
      RunLocationPermissionStatus.checking =>
        _RunPreviewLocationStatus.checkingPermission,
      RunLocationPermissionStatus.granted =>
        _RunPreviewLocationStatus.findingLocation,
      RunLocationPermissionStatus.denied =>
        _RunPreviewLocationStatus.permissionRequired,
      RunLocationPermissionStatus.deniedForever =>
        _RunPreviewLocationStatus.permissionBlocked,
      RunLocationPermissionStatus.notificationDenied =>
        _RunPreviewLocationStatus.permissionBlocked,
      RunLocationPermissionStatus.serviceDisabled =>
        _RunPreviewLocationStatus.serviceDisabled,
      RunLocationPermissionStatus.unavailable =>
        _RunPreviewLocationStatus.unavailable,
    };
  }

  String _statusLabel(RunTrackingState state) {
    if (_sheetMode == RunSheetMode.preRun) {
      if (!widget.enableForegroundGps) {
        return RunTrackingLocationStatus.demo.label;
      }
      return switch (_previewLocationStatus) {
        _RunPreviewLocationStatus.inactive => 'Checking GPS',
        _RunPreviewLocationStatus.checkingPermission => 'Checking GPS',
        _RunPreviewLocationStatus.permissionRequired => 'Tap location',
        _RunPreviewLocationStatus.findingLocation => 'Finding you',
        _RunPreviewLocationStatus.locationReady => 'GPS ready',
        _RunPreviewLocationStatus.serviceDisabled => 'GPS off',
        _RunPreviewLocationStatus.permissionBlocked => 'GPS blocked',
        _RunPreviewLocationStatus.unavailable => 'Location unavailable',
      };
    }

    if (state.isAbnormalPaused) {
      return 'Tracking paused';
    }

    if (_sheetMode == RunSheetMode.paused ||
        state.isPaused ||
        state.isAutoPaused) {
      return 'Paused';
    }

    return state.locationStatus.label;
  }

  void _recenterRunner() {
    setState(() {
      _isFollowingRunner = true;
      _mapRecenterRequestId++;
    });
    _followQaDiagnostics?.recordRecenterRequest(_mapRecenterRequestId);
    _updateFollowQaMapState();
    if (!_hasCurrentPosition && _sheetMode == RunSheetMode.preRun) {
      unawaited(
        _refreshPreviewLocation(
          requestPermission: true,
          showFailureMessage: true,
          recenterOnSuccess: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _screenBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return RunTrackingMapSurface(
                  mapViewState: _controller.mapViewState,
                  isFollowingRunner: _isFollowingRunner,
                  recenterRequestId: _mapRecenterRequestId,
                  onManualPan: () {
                    _followQaDiagnostics?.recordOnManualPan();
                    setState(() => _isFollowingRunner = false);
                    _updateFollowQaMapState();
                  },
                  onRecenter: _recenterRunner,
                  showRecenterButton: false,
                  mapboxAccessToken: widget.mapboxAccessToken,
                  mapboxBuilder: widget.mapboxBuilder,
                  followQaDiagnostics: _followQaDiagnostics,
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 24,
            right: 24,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: AnimatedSwitcher(
                        duration: _sheetAnimationDuration,
                        child: _sheetMode == RunSheetMode.preRun
                            ? _MapCircleButton(
                                key: const ValueKey('close_button'),
                                tooltip: 'Close',
                                icon: Icons.close,
                                onPressed: () => Navigator.of(context).pop(),
                              )
                            : const SizedBox(
                                key: ValueKey('close_button_hidden'),
                                width: 48,
                                height: 48,
                              ),
                      ),
                    ),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          return Center(
                            child: AnimatedSwitcher(
                              duration: _sheetAnimationDuration,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: RunStatusPill(
                                key: ValueKey(_statusLabel(_controller.state)),
                                label: _statusLabel(_controller.state),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: AnimatedSwitcher(
                        duration: _sheetAnimationDuration,
                        child: _sheetMode == RunSheetMode.preRun
                            ? _MapCircleButton(
                                key: const ValueKey('settings_button'),
                                tooltip: 'Run settings',
                                icon: Icons.settings_outlined,
                                onPressed: _openVoiceSettings,
                              )
                            : const SizedBox(
                                key: ValueKey('settings_button_hidden'),
                                width: 48,
                                height: 48,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _sheetProgress > 0.01 && _sheetProgress < 1
                ? -((_expandedRunSheetHeight - _collapsedRunSheetHeight) *
                      (1 - _sheetProgress))
                : 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        top: _recenterButtonSize + _sheetAdjacentRecenterGap,
                      ),
                      child: AnimatedSize(
                        duration: _sheetExtentAnimationDuration,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        child: _RunBottomSheetShell(
                          key: const Key('runLaunchBottomSheet'),
                          bottomInset: bottomInset,
                          mode: _sheetMode,
                          extent: _sheetExtent,
                          sheetProgress: _sheetProgress,
                          onHandleTap: _toggleSheetExtent,
                          onVerticalDragStart: _handleSheetDragStart,
                          onVerticalDragUpdate: _handleSheetDragUpdate,
                          onVerticalDragEnd: _handleSheetDragEnd,
                          onVerticalDragCancel: _handleSheetDragCancel,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final offsetAnimation =
                                  Tween<Offset>(
                                    begin: const Offset(0, 0.025),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic,
                                      reverseCurve: Curves.easeInCubic,
                                    ),
                                  );

                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: offsetAnimation,
                                  child: child,
                                ),
                              );
                            },
                            child: _sheetMode == RunSheetMode.preRun
                                ? AnimatedBuilder(
                                    key: const ValueKey('preRunSheetContent'),
                                    animation: _controller,
                                    builder: (context, _) {
                                      final permissionStatus =
                                          _controller.locationPermissionStatus;
                                      final permissionMessage =
                                          permissionStatus.canStartRun ||
                                              permissionStatus ==
                                                  RunLocationPermissionStatus
                                                      .checking
                                          ? null
                                          : permissionStatus.message;

                                      return _PreRunSheetContent(
                                        permissionMessage: permissionMessage,
                                        plannedWorkout: widget.plannedWorkout,
                                        onStart: _startRun,
                                      );
                                    },
                                  )
                                : AnimatedBuilder(
                                    key: const ValueKey('trackingSheetContent'),
                                    animation: _controller,
                                    builder: (context, _) {
                                      return RunTrackingSheetContent(
                                        state: _controller.state,
                                        plannedWorkout: widget.plannedWorkout,
                                        onPause: _pauseRun,
                                        onResume: _resumeRun,
                                        onEnd: _finishRun,
                                        isCompletingRun: _isCompletingRun,
                                        distanceUnit: _settings.distanceUnit,
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return Positioned(
                          top: 0,
                          right: _launchRecenterRightPadding,
                          child: Opacity(
                            opacity: _hasCurrentPosition ? 1 : 0.58,
                            child: RunMapRecenterButton(
                              onPressed: _recenterRunner,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasCurrentPosition {
    return _controller.mapViewState.currentPosition != null;
  }
}
