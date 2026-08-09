import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_diagnostics.dart';
import 'package:runiac_app/features/run/domain/models/run_notification_display_model.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_notification_copy.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_state.dart';

void main() {
  group('RunTrackingNotificationCopy', () {
    RunTrackingState state({
      RunTrackingPhase phase = RunTrackingPhase.active,
      RunMovementStatus movementStatus = RunMovementStatus.moving,
      RunTrackingLocationStatus locationStatus =
          RunTrackingLocationStatus.gpsActive,
      int elapsedSeconds = 125,
      int distanceMeters = 620,
      int averagePaceSecondsPerKm = 432,
      int currentPaceSecondsPerKm = 415,
    }) {
      return RunTrackingState(
        phase: phase,
        clientRunSessionId: 'notification-copy-run',
        startedAt: DateTime.utc(2026, 6, 17, 8),
        completedAt: null,
        elapsedSeconds: elapsedSeconds,
        distanceMeters: distanceMeters,
        averagePaceSecondsPerKm: averagePaceSecondsPerKm,
        currentPaceSecondsPerKm: currentPaceSecondsPerKm,
        routePrivacy: 'private',
        source: 'local_gps',
        locationStatus: locationStatus,
        diagnostics: const RunTrackingDiagnostics.initial(),
        movementStatus: movementStatus,
      );
    }

    test('formats active GPS copy with elapsed time and distance', () {
      final copy = RunTrackingNotificationCopy.fromState(state());

      expect(copy.title, 'Runiac is tracking your run');
      expect(copy.body, '02:05 • 6:55 /km • 0.62 km');
    });

    test('formats waiting and weak GPS copy without shaming language', () {
      final waiting = RunTrackingNotificationCopy.fromState(
        state(locationStatus: RunTrackingLocationStatus.waitingForGps),
      );
      final weak = RunTrackingNotificationCopy.fromState(
        state(locationStatus: RunTrackingLocationStatus.gpsWeak),
      );

      expect(waiting.title, 'Runiac is tracking your run');
      expect(waiting.body, '02:05 • 6:55 /km • 0.62 km');
      expect(weak.title, 'Runiac is tracking your run');
      expect(weak.body, '02:05 • 6:55 /km • 0.62 km');
    });

    test('formats manual auto and abnormal paused states', () {
      final manual = RunTrackingNotificationCopy.fromState(
        state(phase: RunTrackingPhase.paused),
      );
      final autoPaused = RunTrackingNotificationCopy.fromState(
        state(movementStatus: RunMovementStatus.autoPaused),
      );
      final abnormalPaused = RunTrackingNotificationCopy.fromState(
        state(movementStatus: RunMovementStatus.abnormalPaused),
      );

      expect(manual.title, 'Run paused');
      expect(manual.body, '02:05 • 6:55 /km • 0.62 km');
      expect(autoPaused.title, 'Tracking paused');
      expect(autoPaused.body, '02:05 • 6:55 /km • 0.62 km');
      expect(abnormalPaused.title, 'Tracking paused');
      expect(abnormalPaused.body, '02:05 • 6:55 /km • 0.62 km');
    });

    test('formats approximate location copy', () {
      final copy = RunTrackingNotificationCopy.fromState(
        state(locationStatus: RunTrackingLocationStatus.approximateLocation),
      );

      expect(copy.title, 'Runiac is tracking your run');
      expect(copy.body, '02:05 • 6:55 /km • 0.62 km');
    });
  });

  group('RunNotificationDisplayModel', () {
    RunNotificationDisplayModel model({
      RunTrackingPhase phase = RunTrackingPhase.active,
      RunMovementStatus movementStatus = RunMovementStatus.moving,
      RunTrackingLocationStatus locationStatus =
          RunTrackingLocationStatus.gpsActive,
      int elapsedSeconds = 754,
      int distanceMeters = 1250,
      int averagePaceSecondsPerKm = 432,
      int currentPaceSecondsPerKm = 415,
    }) {
      return RunNotificationDisplayModel.fromState(
        RunTrackingState(
          phase: phase,
          clientRunSessionId: 'notification-display-run',
          startedAt: DateTime.utc(2026, 6, 17, 8),
          completedAt: null,
          elapsedSeconds: elapsedSeconds,
          distanceMeters: distanceMeters,
          averagePaceSecondsPerKm: averagePaceSecondsPerKm,
          currentPaceSecondsPerKm: currentPaceSecondsPerKm,
          routePrivacy: 'private',
          source: 'local_gps',
          locationStatus: locationStatus,
          diagnostics: const RunTrackingDiagnostics.initial(),
          movementStatus: movementStatus,
        ),
      );
    }

    test(
      'formats tracking metrics for collapsed and expanded notification',
      () {
        final display = model();

        expect(display.title, 'Runiac is tracking your run');
        expect(display.collapsedBody, '12:34 • 6:55 /km • 1.25 km');
        expect(display.statusLabel, 'GPS active');
        expect(display.elapsedTimeLabel, '12:34');
        expect(display.currentPaceLabel, '6:55 /km');
        expect(display.distanceLabel, '1.25 km');
        expect(display.supportCopy, isNull);
      },
    );

    test('uses unavailable pace until enough distance is available', () {
      final display = model(
        distanceMeters: 20,
        averagePaceSecondsPerKm: 0,
        currentPaceSecondsPerKm: 0,
      );

      expect(display.collapsedBody, '12:34 • --:-- /km • 0.02 km');
      expect(display.currentPaceLabel, '--:-- /km');
    });

    test(
      'covers getting GPS ready with metrics and state-safe support copy',
      () {
        final display = model(
          locationStatus: RunTrackingLocationStatus.waitingForGps,
          elapsedSeconds: 25,
          distanceMeters: 0,
          averagePaceSecondsPerKm: 0,
          currentPaceSecondsPerKm: 0,
        );

        expect(display.title, 'Runiac is tracking your run');
        expect(display.collapsedBody, '00:25 • --:-- /km • 0.00 km');
        expect(display.statusLabel, 'Getting GPS ready');
        expect(display.supportCopy, 'Keep moving in an open area.');
      },
    );

    test('covers GPS weak support copy without shaming language', () {
      final display = model(locationStatus: RunTrackingLocationStatus.gpsWeak);

      expect(display.title, 'Runiac is tracking your run');
      expect(display.statusLabel, 'GPS weak');
      expect(display.supportCopy, 'GPS signal weak. Keep the app nearby.');
    });

    test('covers approximate location support copy', () {
      final display = model(
        locationStatus: RunTrackingLocationStatus.approximateLocation,
      );

      expect(display.title, 'Runiac is tracking your run');
      expect(display.statusLabel, 'Approximate location');
      expect(
        display.supportCopy,
        'Approximate location. Distance may be less precise.',
      );
    });

    test('covers manual auto and abnormal paused states', () {
      final manual = model(phase: RunTrackingPhase.paused);
      final autoPaused = model(movementStatus: RunMovementStatus.autoPaused);
      final abnormalPaused = model(
        movementStatus: RunMovementStatus.abnormalPaused,
      );

      expect(manual.title, 'Run paused');
      expect(manual.statusLabel, 'Paused');
      expect(manual.supportCopy, 'Tracking is paused until you resume.');
      expect(autoPaused.title, 'Tracking paused');
      expect(autoPaused.statusLabel, 'Auto-paused');
      expect(autoPaused.supportCopy, 'Move again to continue tracking.');
      expect(abnormalPaused.title, 'Tracking paused');
      expect(abnormalPaused.statusLabel, 'Tracking paused');
      expect(
        abnormalPaused.supportCopy,
        'Unusual movement detected. Resume when ready.',
      );
    });
  });
}
