import 'dart:async';

import '../domain/models/run_tracking_state.dart';
import 'controllers/run_tracking_controller.dart';

typedef RunTrackingControllerFactory = RunTrackingController Function();
typedef RunTrackingClock = DateTime Function();

class ActiveRunSessionCoordinator {
  ActiveRunSessionCoordinator({
    RunTrackingController? controller,
    RunTrackingClock? clock,
    Duration? foregroundTickStep,
    bool disposeController = true,
  }) : _clock = clock ?? DateTime.now {
    _controller = controller;
    _foregroundTickStep = foregroundTickStep;
    _disposeController = disposeController;
  }

  RunTrackingController? _controller;
  final RunTrackingClock _clock;
  late final Duration? _foregroundTickStep;
  late final bool _disposeController;
  Timer? _ticker;
  DateTime? _lastTickAt;

  RunTrackingController controllerFor(RunTrackingControllerFactory create) {
    final controller = _controller;
    if (controller != null &&
        controller.state.phase != RunTrackingPhase.finished) {
      return controller;
    }

    final nextController = create();
    _controller = nextController;
    return nextController;
  }

  void startForegroundTicker() {
    _lastTickAt ??= _clock();
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final tickStep = _foregroundTickStep;
      if (tickStep != null) {
        final tickedAt = (_lastTickAt ?? _clock()).add(tickStep);
        syncTo(tickedAt);
        return;
      }
      syncNow();
    });
  }

  DateTime now() => _clock();

  bool get hasOpenRun {
    final phase = _controller?.state.phase;
    return phase == RunTrackingPhase.active || phase == RunTrackingPhase.paused;
  }

  void syncNow() {
    syncTo(_clock());
  }

  void syncTo(DateTime now) {
    _lastTickAt = now;
    _controller?.syncTo(now);
  }

  void stopForegroundTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTickAt = null;
  }

  void dispose() {
    stopForegroundTicker();
    if (_disposeController) {
      _controller?.dispose();
    }
    _controller = null;
  }
}
