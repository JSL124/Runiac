import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_motion_evidence.dart';
import 'package:runiac_app/features/run/domain/services/run_movement_classifier.dart';

void main() {
  group('RunMovementClassifier speed policy', () {
    const classifier = RunMovementClassifier();

    test('classifies threshold boundaries for transport detection', () {
      expect(
        classifier.classifyMovementSpeed(speedMetersPerSecond: 0.79),
        RunMovementSpeedBand.belowNormalResume,
      );
      expect(
        classifier.classifyMovementSpeed(speedMetersPerSecond: 0.8),
        RunMovementSpeedBand.normalResume,
      );
      expect(
        classifier.classifyMovementSpeed(speedMetersPerSecond: 4.0),
        RunMovementSpeedBand.normalResume,
      );
      expect(
        classifier.classifyMovementSpeed(speedMetersPerSecond: 4.01),
        RunMovementSpeedBand.normal,
      );
      expect(
        classifier.classifyMovementSpeed(speedMetersPerSecond: 4.5),
        RunMovementSpeedBand.suspiciousCandidate,
      );
      expect(
        classifier.classifyMovementSpeed(speedMetersPerSecond: 6.5),
        RunMovementSpeedBand.abnormalCandidate,
      );
      expect(
        classifier.classifyMovementSpeed(speedMetersPerSecond: 12),
        RunMovementSpeedBand.abnormalCandidate,
      );
      expect(
        classifier.classifyMovementSpeed(speedMetersPerSecond: 12.01),
        RunMovementSpeedBand.impossibleJump,
      );
    });
  });

  group('RunMovementClassifier motion fusion', () {
    const classifier = RunMovementClassifier();
    final recordedAt = DateTime.utc(2026, 6, 14, 7);

    test('strong GPS movement wins over stationary motion evidence', () {
      final classification = classifier.classifyGpsSample(
        sample: _sample(recordedAt),
        distanceFromRouteAnchorMeters: 8,
        stationaryDwell: const Duration(seconds: 8),
        stationaryAutoPauseDwell: const Duration(seconds: 7),
        stationaryDriftDistanceMeters: 3,
        resumeMovementDistanceMeters: 6,
        resumeSpeedMetersPerSecond: 1,
        stationarySpeedMetersPerSecond: 0.5,
        motionEvidence: [_motion(recordedAt, RunMotionSignal.stationary)],
      );

      expect(
        classification.type,
        RunMovementClassificationType.gpsMeaningfulMovement,
      );
      expect(classification.acceptForDistance, isTrue);
      expect(classification.acceptForRoute, isTrue);
      expect(classification.shouldAutoResume, isTrue);
    });

    test('stationary motion suppresses borderline GPS speed jitter', () {
      final classification = classifier.classifyGpsSample(
        sample: _sample(recordedAt, speedMetersPerSecond: 0.7),
        distanceFromRouteAnchorMeters: 1.2,
        cumulativeGpsMovementMeters: 1.2,
        stationaryDwell: const Duration(seconds: 8),
        stationaryAutoPauseDwell: const Duration(seconds: 7),
        stationaryDriftDistanceMeters: 3,
        resumeMovementDistanceMeters: 6,
        resumeSpeedMetersPerSecond: 1,
        stationarySpeedMetersPerSecond: 0.5,
        motionEvidence: [_motion(recordedAt, RunMotionSignal.stationary)],
      );

      expect(
        classification.type,
        RunMovementClassificationType.gpsStationaryDrift,
      );
      expect(classification.acceptForDistance, isFalse);
      expect(classification.acceptForRoute, isFalse);
      expect(classification.shouldAutoPause, isTrue);
    });

    test('stationary motion blocks a single GPS displacement resume', () {
      final classification = classifier.classifyGpsSample(
        sample: _sample(recordedAt),
        distanceFromRouteAnchorMeters: 40,
        stationaryDwell: const Duration(seconds: 8),
        stationaryAutoPauseDwell: const Duration(seconds: 7),
        stationaryDriftDistanceMeters: 3,
        resumeMovementDistanceMeters: 6,
        resumeSpeedMetersPerSecond: 1,
        stationarySpeedMetersPerSecond: 0.5,
        requiresSustainedGpsMovement: true,
        motionEvidence: [_motion(recordedAt, RunMotionSignal.stationary)],
      );

      expect(
        classification.type,
        RunMovementClassificationType.gpsResumeCandidate,
      );
      expect(classification.acceptForDistance, isFalse);
      expect(classification.acceptForRoute, isFalse);
      expect(classification.shouldAutoResume, isFalse);
    });

    test('stationary motion blocks a single GPS speed spike resume', () {
      final classification = classifier.classifyGpsSample(
        sample: _sample(recordedAt, speedMetersPerSecond: 1.2),
        distanceFromRouteAnchorMeters: 0.8,
        stationaryDwell: const Duration(seconds: 8),
        stationaryAutoPauseDwell: const Duration(seconds: 7),
        stationaryDriftDistanceMeters: 3,
        resumeMovementDistanceMeters: 6,
        resumeSpeedMetersPerSecond: 1,
        stationarySpeedMetersPerSecond: 0.5,
        requiresSustainedGpsMovement: true,
        motionEvidence: [_motion(recordedAt, RunMotionSignal.stationary)],
      );

      expect(
        classification.type,
        RunMovementClassificationType.gpsResumeCandidate,
      );
      expect(classification.acceptForDistance, isFalse);
      expect(classification.acceptForRoute, isFalse);
      expect(classification.shouldAutoResume, isFalse);
    });

    test('cumulative GPS movement wins over stationary motion evidence', () {
      final classification = classifier.classifyGpsSample(
        sample: _sample(recordedAt, speedMetersPerSecond: 0.7),
        distanceFromRouteAnchorMeters: 2.4,
        cumulativeGpsMovementMeters: 8.4,
        stationaryDwell: const Duration(seconds: 8),
        stationaryAutoPauseDwell: const Duration(seconds: 7),
        stationaryDriftDistanceMeters: 3,
        resumeMovementDistanceMeters: 6,
        resumeSpeedMetersPerSecond: 1,
        stationarySpeedMetersPerSecond: 0.5,
        motionEvidence: [_motion(recordedAt, RunMotionSignal.stationary)],
      );

      expect(
        classification.type,
        RunMovementClassificationType.gpsMeaningfulMovement,
      );
      expect(classification.acceptForDistance, isTrue);
      expect(classification.acceptForRoute, isTrue);
      expect(classification.shouldAutoPause, isFalse);
      expect(classification.shouldAutoResume, isTrue);
    });

    test('moving motion alone briefly delays GPS stationary auto pause', () {
      final classification = classifier.classifyGpsSample(
        sample: _sample(recordedAt),
        distanceFromRouteAnchorMeters: 1.2,
        stationaryDwell: const Duration(seconds: 8),
        stationaryAutoPauseDwell: const Duration(seconds: 7),
        stationaryDriftDistanceMeters: 3,
        resumeMovementDistanceMeters: 6,
        resumeSpeedMetersPerSecond: 1,
        stationarySpeedMetersPerSecond: 0.5,
        motionEvidence: [_motion(recordedAt, RunMotionSignal.moving)],
      );

      expect(classification.acceptForDistance, isFalse);
      expect(classification.acceptForRoute, isFalse);
      expect(classification.shouldAutoPause, isFalse);
      expect(classification.countsAsMovingTime, isTrue);
    });

    test(
      'moving motion alone stops delaying after grace without GPS movement',
      () {
        final classification = classifier.classifyGpsSample(
          sample: _sample(recordedAt),
          distanceFromRouteAnchorMeters: 1.2,
          stationaryDwell: const Duration(seconds: 10),
          stationaryAutoPauseDwell: const Duration(seconds: 7),
          stationaryDriftDistanceMeters: 3,
          resumeMovementDistanceMeters: 6,
          resumeSpeedMetersPerSecond: 1,
          stationarySpeedMetersPerSecond: 0.5,
          motionEvidence: [_motion(recordedAt, RunMotionSignal.moving)],
        );

        expect(classification.acceptForDistance, isFalse);
        expect(classification.acceptForRoute, isFalse);
        expect(classification.shouldAutoPause, isTrue);
        expect(classification.shouldAutoResume, isFalse);
      },
    );

    test('unavailable motion preserves GPS-only no-sample auto pause', () {
      final classification = classifier.classifyNoSampleWindow(
        dwell: const Duration(seconds: 6),
        noSampleAutoPauseDwell: const Duration(seconds: 5),
        anchorAge: const Duration(seconds: 6),
        maxAnchorAge: const Duration(seconds: 30),
        hasAcceptedAnchor: true,
        gpsStatusAllowsDwell: true,
        motionEvidence: [_motion(recordedAt, RunMotionSignal.unavailable)],
      );

      expect(classification.shouldAutoPause, isTrue);
      expect(
        classification.type,
        RunMovementClassificationType.noSampleStationaryDwell,
      );
    });

    test('moving motion briefly delays no-sample auto pause', () {
      final classification = classifier.classifyNoSampleWindow(
        dwell: const Duration(seconds: 6),
        noSampleAutoPauseDwell: const Duration(seconds: 5),
        anchorAge: const Duration(seconds: 6),
        maxAnchorAge: const Duration(seconds: 30),
        hasAcceptedAnchor: true,
        gpsStatusAllowsDwell: true,
        motionEvidence: [_motion(recordedAt, RunMotionSignal.moving)],
      );

      expect(classification.shouldAutoPause, isFalse);
      expect(classification.shouldAutoResume, isFalse);
      expect(classification.acceptForDistance, isFalse);
      expect(classification.acceptForRoute, isFalse);
    });

    test('moving motion no-sample delay expires without GPS confirmation', () {
      final classification = classifier.classifyNoSampleWindow(
        dwell: const Duration(seconds: 8),
        noSampleAutoPauseDwell: const Duration(seconds: 5),
        anchorAge: const Duration(seconds: 8),
        maxAnchorAge: const Duration(seconds: 30),
        hasAcceptedAnchor: true,
        gpsStatusAllowsDwell: true,
        motionEvidence: [_motion(recordedAt, RunMotionSignal.moving)],
      );

      expect(classification.shouldAutoPause, isTrue);
      expect(classification.shouldAutoResume, isFalse);
      expect(classification.acceptForDistance, isFalse);
      expect(classification.acceptForRoute, isFalse);
    });
  });
}

RunLocationSample _sample(DateTime recordedAt, {double? speedMetersPerSecond}) {
  return RunLocationSample(
    recordedAt: recordedAt,
    latitude: 1.3,
    longitude: 103.8,
    speedMetersPerSecond: speedMetersPerSecond,
  );
}

RunMotionEvidence _motion(DateTime recordedAt, RunMotionSignal signal) {
  return RunMotionEvidence(
    recordedAt: recordedAt,
    signal: signal,
    confidence: 1,
  );
}
