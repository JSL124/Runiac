import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/domain/models/run_tracking_state.dart';
import 'package:runiac_app/features/run/presentation/controllers/run_tracking_controller.dart';

// Characterization tests: use the DEFAULT NoopRunVoiceCoach (no explicit
// voiceCoach injected) to prove the voice seam is fully non-breaking for the
// existing run tracking behavior.
void main() {
  group('RunTrackingController voice lifecycle characterization', () {
    test('start moves the controller into the active phase', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-characterization-start',
      );

      expect(controller.state.phase, RunTrackingPhase.active);
    });

    test('pause freezes active elapsed time', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-characterization-pause',
      );
      controller.advanceBy(const Duration(seconds: 60));
      controller.pause();
      final elapsedAtPause = controller.state.elapsedSeconds;
      controller.advanceBy(const Duration(seconds: 60));

      expect(controller.state.phase, RunTrackingPhase.paused);
      expect(controller.state.elapsedSeconds, elapsedAtPause);
    });

    test('resume preserves clientRunSessionId and returns to active', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-characterization-resume',
      );
      controller.advanceBy(const Duration(seconds: 30));
      controller.pause();
      controller.resume();

      expect(controller.state.phase, RunTrackingPhase.active);
      expect(
        controller.state.clientRunSessionId,
        'voice-characterization-resume',
      );
    });

    test('advanceBy while paused does not change distance or elapsed', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-characterization-paused-advance',
      );
      controller.advanceBy(const Duration(seconds: 60));
      controller.pause();
      final distanceAtPause = controller.state.distanceMeters;
      final elapsedAtPause = controller.state.elapsedSeconds;

      controller.advanceBy(const Duration(seconds: 60));

      expect(controller.state.distanceMeters, distanceAtPause);
      expect(controller.state.elapsedSeconds, elapsedAtPause);
    });

    test('finish moves phase to finished and returns a payload', () {
      final controller = RunTrackingController(metersPerSecond: 2.5);

      controller.start(
        startedAt: DateTime.utc(2026, 6, 14, 7),
        clientRunSessionId: 'voice-characterization-finish',
      );
      controller.advanceBy(const Duration(seconds: 60));

      final payload = controller.finish(
        completedAt: DateTime.utc(2026, 6, 14, 7, 1),
      );

      expect(controller.state.phase, RunTrackingPhase.finished);
      expect(payload.clientRunSessionId, 'voice-characterization-finish');
    });
  });
}
