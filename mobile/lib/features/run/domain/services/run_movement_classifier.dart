import '../models/run_location_sample.dart';
import '../models/run_motion_evidence.dart';

/// Judges a single GPS sample: is this the runner moving, GPS drift, or a
/// reading that should be thrown away entirely?
///
/// Deliberately stateless — it sees one sample against one anchor and returns a
/// verdict. `LocalRunTrackingSession` holds everything that spans samples
/// (dwell timers, candidate streaks), so this file stays testable in isolation
/// and the accept/reject rules live in one readable place.
enum RunMovementClassificationType {
  gpsMeaningfulMovement,
  gpsResumeCandidate,
  gpsStationaryDrift,
  noSampleStationaryDwell,
  noSampleWaiting,
}

enum RunMovementSpeedBand {
  belowNormalResume,
  normalResume,
  normal,
  suspiciousCandidate,
  abnormalCandidate,
  impossibleJump,
}

class RunMovementClassification {
  const RunMovementClassification({
    required this.type,
    required this.acceptForDistance,
    required this.acceptForRoute,
    required this.countsAsMovingTime,
    required this.shouldAutoPause,
    required this.shouldAutoResume,
  });

  final RunMovementClassificationType type;
  final bool acceptForDistance;
  final bool acceptForRoute;
  final bool countsAsMovingTime;
  final bool shouldAutoPause;
  final bool shouldAutoResume;
}

class RunMovementClassifier {
  const RunMovementClassifier();

  static const double _motionConfidenceThreshold = 0.6;
  static const double _gpsCumulativeMovementConfirmationMeters = 8;
  static const Duration _motionMovingWithoutGpsGrace = Duration(seconds: 3);

  RunMovementSpeedBand classifyMovementSpeed({
    required double speedMetersPerSecond,
    double suspiciousSpeedMetersPerSecond = 4.5,
    double abnormalSpeedMetersPerSecond = 6.5,
    double hardRejectSpeedMetersPerSecond = 12,
    double normalResumeMinSpeedMetersPerSecond = 0.8,
    double normalResumeMaxSpeedMetersPerSecond = 4.0,
  }) {
    if (!speedMetersPerSecond.isFinite || speedMetersPerSecond < 0) {
      return RunMovementSpeedBand.belowNormalResume;
    }
    if (speedMetersPerSecond > hardRejectSpeedMetersPerSecond) {
      return RunMovementSpeedBand.impossibleJump;
    }
    if (speedMetersPerSecond < normalResumeMinSpeedMetersPerSecond) {
      return RunMovementSpeedBand.belowNormalResume;
    }
    if (speedMetersPerSecond >= abnormalSpeedMetersPerSecond) {
      return RunMovementSpeedBand.abnormalCandidate;
    }
    if (speedMetersPerSecond >= suspiciousSpeedMetersPerSecond) {
      return RunMovementSpeedBand.suspiciousCandidate;
    }
    if (speedMetersPerSecond >= normalResumeMinSpeedMetersPerSecond &&
        speedMetersPerSecond <= normalResumeMaxSpeedMetersPerSecond) {
      return RunMovementSpeedBand.normalResume;
    }
    return RunMovementSpeedBand.normal;
  }

  RunMovementClassification classifyGpsSample({
    required RunLocationSample sample,
    required double distanceFromRouteAnchorMeters,
    required Duration stationaryDwell,
    required Duration stationaryAutoPauseDwell,
    required double stationaryDriftDistanceMeters,
    double cumulativeGpsMovementMeters = 0,
    double? movementSpeedMetersPerSecond,
    required double resumeMovementDistanceMeters,
    required double resumeSpeedMetersPerSecond,
    required double stationarySpeedMetersPerSecond,
    bool requiresSustainedGpsMovement = false,
    Iterable<RunMotionEvidence> motionEvidence = const <RunMotionEvidence>[],
  }) {
    if (_hasMeaningfulMovement(
      sample: sample,
      distanceFromRouteAnchorMeters: distanceFromRouteAnchorMeters,
      movementSpeedMetersPerSecond: movementSpeedMetersPerSecond,
      resumeMovementDistanceMeters: resumeMovementDistanceMeters,
      resumeSpeedMetersPerSecond: resumeSpeedMetersPerSecond,
    )) {
      if (requiresSustainedGpsMovement) {
        return const RunMovementClassification(
          type: RunMovementClassificationType.gpsResumeCandidate,
          acceptForDistance: false,
          acceptForRoute: false,
          countsAsMovingTime: false,
          shouldAutoPause: false,
          shouldAutoResume: false,
        );
      }
      return const RunMovementClassification(
        type: RunMovementClassificationType.gpsMeaningfulMovement,
        acceptForDistance: true,
        acceptForRoute: true,
        countsAsMovingTime: true,
        shouldAutoPause: false,
        shouldAutoResume: true,
      );
    }

    if (cumulativeGpsMovementMeters >=
            _gpsCumulativeMovementConfirmationMeters &&
        _hasStationaryExitSpeedSignal(
          sample: sample,
          movementSpeedMetersPerSecond: movementSpeedMetersPerSecond,
          stationarySpeedMetersPerSecond: stationarySpeedMetersPerSecond,
        )) {
      if (requiresSustainedGpsMovement) {
        return const RunMovementClassification(
          type: RunMovementClassificationType.gpsResumeCandidate,
          acceptForDistance: false,
          acceptForRoute: false,
          countsAsMovingTime: false,
          shouldAutoPause: false,
          shouldAutoResume: false,
        );
      }
      return const RunMovementClassification(
        type: RunMovementClassificationType.gpsMeaningfulMovement,
        acceptForDistance: true,
        acceptForRoute: true,
        countsAsMovingTime: true,
        shouldAutoPause: false,
        shouldAutoResume: true,
      );
    }

    final motionSummary = _summarizeMotion(motionEvidence);
    final motionStationary = motionSummary.isStationary;
    final motionMoving = motionSummary.isMoving;
    final hasMovingSpeedSignal = _hasMovingSpeedSignal(
      sample,
      stationarySpeedMetersPerSecond,
    );
    final effectiveHasMovingSpeedSignal =
        hasMovingSpeedSignal && !motionStationary;
    final motionMovingStillInGrace =
        motionMoving &&
        stationaryDwell <
            stationaryAutoPauseDwell + _motionMovingWithoutGpsGrace;
    final shouldAutoPause =
        !effectiveHasMovingSpeedSignal &&
        !motionMovingStillInGrace &&
        stationaryDwell >= stationaryAutoPauseDwell;
    return RunMovementClassification(
      type: RunMovementClassificationType.gpsStationaryDrift,
      acceptForDistance: false,
      acceptForRoute: false,
      countsAsMovingTime: motionMoving || !shouldAutoPause,
      shouldAutoPause: shouldAutoPause,
      shouldAutoResume: false,
    );
  }

  RunMovementClassification classifyNoSampleWindow({
    required Duration dwell,
    required Duration noSampleAutoPauseDwell,
    required Duration anchorAge,
    required Duration maxAnchorAge,
    required bool hasAcceptedAnchor,
    required bool gpsStatusAllowsDwell,
    Iterable<RunMotionEvidence> motionEvidence = const <RunMotionEvidence>[],
  }) {
    final motionSummary = _summarizeMotion(motionEvidence);
    final motionMovingStillInGrace =
        motionSummary.isMoving &&
        dwell < noSampleAutoPauseDwell + _motionMovingWithoutGpsGrace;
    final shouldAutoPause =
        hasAcceptedAnchor &&
        gpsStatusAllowsDwell &&
        anchorAge <= maxAnchorAge &&
        !motionMovingStillInGrace &&
        dwell >= noSampleAutoPauseDwell;
    return RunMovementClassification(
      type: shouldAutoPause
          ? RunMovementClassificationType.noSampleStationaryDwell
          : RunMovementClassificationType.noSampleWaiting,
      acceptForDistance: false,
      acceptForRoute: false,
      countsAsMovingTime: !shouldAutoPause,
      shouldAutoPause: shouldAutoPause,
      shouldAutoResume: false,
    );
  }

  bool _hasMeaningfulMovement({
    required RunLocationSample sample,
    required double distanceFromRouteAnchorMeters,
    required double? movementSpeedMetersPerSecond,
    required double resumeMovementDistanceMeters,
    required double resumeSpeedMetersPerSecond,
  }) {
    final reportedSpeed =
        movementSpeedMetersPerSecond ?? sample.speedMetersPerSecond;
    final hasSpeedSignal =
        reportedSpeed != null &&
        reportedSpeed.isFinite &&
        reportedSpeed >= resumeSpeedMetersPerSecond;
    final hasDistanceSignal =
        movementSpeedMetersPerSecond == null &&
        distanceFromRouteAnchorMeters >= resumeMovementDistanceMeters;
    return hasDistanceSignal || hasSpeedSignal;
  }

  bool _hasStationaryExitSpeedSignal({
    required RunLocationSample sample,
    required double? movementSpeedMetersPerSecond,
    required double stationarySpeedMetersPerSecond,
  }) {
    final speedMetersPerSecond =
        movementSpeedMetersPerSecond ?? sample.speedMetersPerSecond;
    return speedMetersPerSecond == null ||
        speedMetersPerSecond.isFinite &&
            speedMetersPerSecond >= stationarySpeedMetersPerSecond;
  }

  bool _hasMovingSpeedSignal(
    RunLocationSample sample,
    double stationarySpeedMetersPerSecond,
  ) {
    final reportedSpeed = sample.speedMetersPerSecond;
    return reportedSpeed != null &&
        reportedSpeed.isFinite &&
        reportedSpeed >= stationarySpeedMetersPerSecond;
  }

  _RunMotionSummary _summarizeMotion(Iterable<RunMotionEvidence> evidence) {
    RunMotionEvidence? latest;
    for (final entry in evidence) {
      if (latest == null || entry.recordedAt.isAfter(latest.recordedAt)) {
        latest = entry;
      }
    }
    final motion = latest;
    if (motion == null) {
      return const _RunMotionSummary(
        signal: RunMotionSignal.unavailable,
        confidence: 0,
      );
    }
    return _RunMotionSummary(
      signal: motion.signal,
      confidence: motion.confidence.clamp(0, 1).toDouble(),
    );
  }
}

class _RunMotionSummary {
  const _RunMotionSummary({required this.signal, required this.confidence});

  final RunMotionSignal signal;
  final double confidence;

  bool get isStationary =>
      signal == RunMotionSignal.stationary &&
      confidence >= RunMovementClassifier._motionConfidenceThreshold;

  bool get isMoving =>
      signal == RunMotionSignal.moving &&
      confidence >= RunMovementClassifier._motionConfidenceThreshold;
}
