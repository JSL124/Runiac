import 'run_cadence_diagnostics.dart';
import 'run_location_sample.dart';

enum RunLocationRejectionReason {
  none,
  staleTimestamp,
  invalidCoordinate,
  poorAccuracy,
  duplicateOrOutOfOrderTimestamp,
  nonFiniteDistance,
  impossibleJump,
  unknown,
}

enum RunLocationAccuracyBucket { unknown, good, weak, unusable }

enum RunTrackingLocationAccuracyStatus { precise, reduced, unknown, notChecked }

class RunTrackingDiagnostics {
  const RunTrackingDiagnostics({
    required this.lastSampleReceivedAt,
    required this.lastAcceptedSampleAt,
    required this.lastRejectedSampleAt,
    required this.latestRejectionReason,
    required this.acceptedSampleCount,
    required this.rejectedSampleCount,
    required this.lastAcceptedSampleSequence,
    required this.lastRejectedSampleSequence,
    required this.latestHorizontalAccuracyMeters,
    required this.latestAccuracyBucket,
    required this.locationAccuracyStatus,
    this.cadence = const RunCadenceDiagnostics.initial(),
  });

  const RunTrackingDiagnostics.initial()
    : lastSampleReceivedAt = null,
      lastAcceptedSampleAt = null,
      lastRejectedSampleAt = null,
      latestRejectionReason = RunLocationRejectionReason.none,
      acceptedSampleCount = 0,
      rejectedSampleCount = 0,
      lastAcceptedSampleSequence = 0,
      lastRejectedSampleSequence = 0,
      latestHorizontalAccuracyMeters = null,
      latestAccuracyBucket = RunLocationAccuracyBucket.unknown,
      locationAccuracyStatus = RunTrackingLocationAccuracyStatus.notChecked,
      cadence = const RunCadenceDiagnostics.initial();

  final DateTime? lastSampleReceivedAt;
  final DateTime? lastAcceptedSampleAt;
  final DateTime? lastRejectedSampleAt;
  final RunLocationRejectionReason latestRejectionReason;
  final int acceptedSampleCount;
  final int rejectedSampleCount;
  final int lastAcceptedSampleSequence;
  final int lastRejectedSampleSequence;
  final double? latestHorizontalAccuracyMeters;
  final RunLocationAccuracyBucket latestAccuracyBucket;
  final RunTrackingLocationAccuracyStatus locationAccuracyStatus;
  final RunCadenceDiagnostics cadence;

  bool get hasReceivedSample => lastSampleReceivedAt != null;
  bool get hasAcceptedSample => acceptedSampleCount > 0;

  RunTrackingDiagnostics recordSampleReceived(RunLocationSample sample) {
    final horizontalAccuracyMeters = sample.horizontalAccuracyMeters;
    return RunTrackingDiagnostics(
      lastSampleReceivedAt: sample.recordedAt,
      lastAcceptedSampleAt: lastAcceptedSampleAt,
      lastRejectedSampleAt: lastRejectedSampleAt,
      latestRejectionReason: latestRejectionReason,
      acceptedSampleCount: acceptedSampleCount,
      rejectedSampleCount: rejectedSampleCount,
      lastAcceptedSampleSequence: lastAcceptedSampleSequence,
      lastRejectedSampleSequence: lastRejectedSampleSequence,
      latestHorizontalAccuracyMeters: horizontalAccuracyMeters,
      latestAccuracyBucket: bucketForAccuracy(horizontalAccuracyMeters),
      locationAccuracyStatus: locationAccuracyStatus,
      cadence: cadence,
    );
  }

  RunTrackingDiagnostics recordAcceptedSample(RunLocationSample sample) {
    return RunTrackingDiagnostics(
      lastSampleReceivedAt: lastSampleReceivedAt,
      lastAcceptedSampleAt: sample.recordedAt,
      lastRejectedSampleAt: lastRejectedSampleAt,
      latestRejectionReason: latestRejectionReason,
      acceptedSampleCount: acceptedSampleCount + 1,
      rejectedSampleCount: rejectedSampleCount,
      lastAcceptedSampleSequence: acceptedSampleCount + rejectedSampleCount + 1,
      lastRejectedSampleSequence: lastRejectedSampleSequence,
      latestHorizontalAccuracyMeters: latestHorizontalAccuracyMeters,
      latestAccuracyBucket: latestAccuracyBucket,
      locationAccuracyStatus: locationAccuracyStatus,
      cadence: cadence,
    );
  }

  RunTrackingDiagnostics recordRejectedSample(
    RunLocationSample sample,
    RunLocationRejectionReason reason,
  ) {
    return RunTrackingDiagnostics(
      lastSampleReceivedAt: lastSampleReceivedAt,
      lastAcceptedSampleAt: lastAcceptedSampleAt,
      lastRejectedSampleAt: sample.recordedAt,
      latestRejectionReason: reason,
      acceptedSampleCount: acceptedSampleCount,
      rejectedSampleCount: rejectedSampleCount + 1,
      lastAcceptedSampleSequence: lastAcceptedSampleSequence,
      lastRejectedSampleSequence: acceptedSampleCount + rejectedSampleCount + 1,
      latestHorizontalAccuracyMeters: latestHorizontalAccuracyMeters,
      latestAccuracyBucket: reason == RunLocationRejectionReason.poorAccuracy
          ? RunLocationAccuracyBucket.unusable
          : latestAccuracyBucket,
      locationAccuracyStatus: locationAccuracyStatus,
      cadence: cadence,
    );
  }

  RunTrackingDiagnostics withLocationAccuracyStatus(
    RunTrackingLocationAccuracyStatus status,
  ) {
    return RunTrackingDiagnostics(
      lastSampleReceivedAt: lastSampleReceivedAt,
      lastAcceptedSampleAt: lastAcceptedSampleAt,
      lastRejectedSampleAt: lastRejectedSampleAt,
      latestRejectionReason: latestRejectionReason,
      acceptedSampleCount: acceptedSampleCount,
      rejectedSampleCount: rejectedSampleCount,
      lastAcceptedSampleSequence: lastAcceptedSampleSequence,
      lastRejectedSampleSequence: lastRejectedSampleSequence,
      latestHorizontalAccuracyMeters: latestHorizontalAccuracyMeters,
      latestAccuracyBucket: latestAccuracyBucket,
      locationAccuracyStatus: status,
      cadence: cadence,
    );
  }

  RunTrackingDiagnostics withCadence(RunCadenceDiagnostics diagnostics) {
    return RunTrackingDiagnostics(
      lastSampleReceivedAt: lastSampleReceivedAt,
      lastAcceptedSampleAt: lastAcceptedSampleAt,
      lastRejectedSampleAt: lastRejectedSampleAt,
      latestRejectionReason: latestRejectionReason,
      acceptedSampleCount: acceptedSampleCount,
      rejectedSampleCount: rejectedSampleCount,
      lastAcceptedSampleSequence: lastAcceptedSampleSequence,
      lastRejectedSampleSequence: lastRejectedSampleSequence,
      latestHorizontalAccuracyMeters: latestHorizontalAccuracyMeters,
      latestAccuracyBucket: latestAccuracyBucket,
      locationAccuracyStatus: locationAccuracyStatus,
      cadence: diagnostics,
    );
  }

  static RunLocationAccuracyBucket bucketForAccuracy(
    double? horizontalAccuracyMeters,
  ) {
    if (horizontalAccuracyMeters == null) {
      return RunLocationAccuracyBucket.unknown;
    }
    if (!horizontalAccuracyMeters.isFinite || horizontalAccuracyMeters < 0) {
      return RunLocationAccuracyBucket.unusable;
    }
    if (horizontalAccuracyMeters <= 25) {
      return RunLocationAccuracyBucket.good;
    }
    if (horizontalAccuracyMeters <= 100) {
      return RunLocationAccuracyBucket.weak;
    }
    return RunLocationAccuracyBucket.unusable;
  }
}
