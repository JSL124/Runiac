// Unit tests for RunVoiceSnapshotMapper.fromState: the single translation
// point between the run-tracking domain state and the voice-coaching
// snapshot. These assert the pace-readiness threshold gate, the three
// paused-derivation sources, and the active/inactive derivation — none of
// which had dedicated coverage before this suite.

import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/domain/models/run_tracking_state.dart';
import 'package:runiac_app/features/run/voice/application/run_voice_snapshot_mapper.dart';

RunTrackingState _state({
  RunTrackingPhase phase = RunTrackingPhase.active,
  RunMovementStatus movementStatus = RunMovementStatus.moving,
  int distanceMeters = 1000,
  int elapsedSeconds = 300,
  int averagePaceSecondsPerKm = 300,
  int currentPaceSecondsPerKm = 300,
}) {
  return const RunTrackingState.idle().copyWith(
    phase: phase,
    movementStatus: movementStatus,
    distanceMeters: distanceMeters,
    elapsedSeconds: elapsedSeconds,
    averagePaceSecondsPerKm: averagePaceSecondsPerKm,
    currentPaceSecondsPerKm: currentPaceSecondsPerKm,
  );
}

void main() {
  group('RunVoiceSnapshotMapper.fromState', () {
    test('copies distance and elapsed straight through', () {
      final snapshot = RunVoiceSnapshotMapper.fromState(
        _state(distanceMeters: 2345, elapsedSeconds: 678),
      );

      expect(snapshot.distanceMeters, 2345);
      expect(snapshot.elapsed, const Duration(seconds: 678));
    });

    group('averagePace readiness gate', () {
      test('surfaces the pace once distance reaches the 50m threshold', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(distanceMeters: 50, averagePaceSecondsPerKm: 330),
        );

        expect(snapshot.averagePace, const Duration(seconds: 330));
      });

      test('suppresses the pace below the 50m readiness threshold', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(distanceMeters: 49, averagePaceSecondsPerKm: 330),
        );

        expect(snapshot.averagePace, isNull);
      });

      test('suppresses the pace when average pace is zero (not yet known)', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(distanceMeters: 1000, averagePaceSecondsPerKm: 0),
        );

        expect(snapshot.averagePace, isNull);
      });
    });

    group('currentPace readiness gate', () {
      test('surfaces the current pace once distance reaches the 50m threshold', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(distanceMeters: 50, currentPaceSecondsPerKm: 280),
        );

        expect(snapshot.currentPace, const Duration(seconds: 280));
      });

      test('suppresses the current pace below the 50m readiness threshold', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(distanceMeters: 49, currentPaceSecondsPerKm: 280),
        );

        expect(snapshot.currentPace, isNull);
      });

      test(
        'suppresses the current pace when current pace is zero (not yet known)',
        () {
          final snapshot = RunVoiceSnapshotMapper.fromState(
            _state(distanceMeters: 1000, currentPaceSecondsPerKm: 0),
          );

          expect(snapshot.currentPace, isNull);
        },
      );
    });

    group('active / paused derivation', () {
      test('an active moving state maps to active and not paused', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(phase: RunTrackingPhase.active),
        );

        expect(snapshot.isActive, isTrue);
        expect(snapshot.isPaused, isFalse);
      });

      test('an explicitly paused phase maps to paused and inactive', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(phase: RunTrackingPhase.paused),
        );

        expect(snapshot.isActive, isFalse);
        expect(snapshot.isPaused, isTrue);
      });

      test('an auto-paused active state maps to paused and inactive', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(
            phase: RunTrackingPhase.active,
            movementStatus: RunMovementStatus.autoPaused,
          ),
        );

        expect(snapshot.isActive, isFalse);
        expect(snapshot.isPaused, isTrue);
      });

      test('an abnormal-paused active state maps to paused and inactive', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(
            phase: RunTrackingPhase.active,
            movementStatus: RunMovementStatus.abnormalPaused,
          ),
        );

        expect(snapshot.isActive, isFalse);
        expect(snapshot.isPaused, isTrue);
      });

      test('a finished state is neither active nor paused', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          _state(phase: RunTrackingPhase.finished),
        );

        expect(snapshot.isActive, isFalse);
        expect(snapshot.isPaused, isFalse);
      });

      test('an idle state is neither active nor paused', () {
        final snapshot = RunVoiceSnapshotMapper.fromState(
          const RunTrackingState.idle(),
        );

        expect(snapshot.isActive, isFalse);
        expect(snapshot.isPaused, isFalse);
      });
    });
  });
}
