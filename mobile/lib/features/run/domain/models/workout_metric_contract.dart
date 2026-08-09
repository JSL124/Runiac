import 'workout_metric_types.dart';

export 'workout_metric_types.dart';

/// A metric imported from an external workout source, in a shape the rest of
/// the app can trust.
///
/// Health platforms hand over data of wildly varying quality — a full sample
/// series, a single summary number, or nothing at all — so every instance is
/// built through a named constructor that states which of those it is, and
/// [_validate] rejects contradictory combinations at construction time. An
/// invalid contract cannot exist, so no consumer needs a defensive check.
///
/// [provenance] travels with the value on purpose: the analysis screens present
/// an imported metric differently from one Runiac measured itself.
class ImportedWorkoutMetricContract {
  ImportedWorkoutMetricContract._({
    required this.metric,
    required this.unit,
    required this.provenance,
    required List<WorkoutMetricSample> samples,
    this.summaryValue,
    this.unavailableReason,
  }) : samples = List<WorkoutMetricSample>.unmodifiable(samples) {
    _validate();
  }

  ImportedWorkoutMetricContract.summaryOnly({
    required WorkoutMetricKind metric,
    required WorkoutMetricUnit unit,
    required WorkoutMetricProvenance provenance,
    required num summaryValue,
  }) : this._(
         metric: metric,
         unit: unit,
         provenance: provenance,
         samples: const <WorkoutMetricSample>[],
         summaryValue: summaryValue,
       );

  ImportedWorkoutMetricContract.sampleBased({
    required WorkoutMetricKind metric,
    required WorkoutMetricUnit unit,
    required WorkoutMetricProvenance provenance,
    required List<WorkoutMetricSample> samples,
  }) : this._(
         metric: metric,
         unit: unit,
         provenance: provenance,
         samples: samples,
       );

  ImportedWorkoutMetricContract.unavailable({
    required WorkoutMetricKind metric,
    required WorkoutMetricUnit unit,
    required WorkoutMetricProvenance provenance,
    required WorkoutMetricAvailabilityReason unavailableReason,
  }) : this._(
         metric: metric,
         unit: unit,
         provenance: provenance,
         samples: const <WorkoutMetricSample>[],
         unavailableReason: unavailableReason,
       );

  final WorkoutMetricKind metric;
  final WorkoutMetricUnit unit;
  final WorkoutMetricProvenance provenance;
  final List<WorkoutMetricSample> samples;
  final num? summaryValue;
  final WorkoutMetricAvailabilityReason? unavailableReason;

  bool get isAvailable => unavailableReason == null;
  bool get isSummaryOnly =>
      provenance.evidenceKind == WorkoutMetricEvidenceKind.summaryOnly;
  bool get isSampleBased =>
      provenance.evidenceKind == WorkoutMetricEvidenceKind.sampleBased;
  bool get affectsBackendOwnedProgression => false;
  bool get supportsRouteSamples =>
      isSampleBased &&
      provenance.isProductionTrusted &&
      metric == WorkoutMetricKind.routeSamples;

  bool get supportsTrendAnalysis {
    return isSampleBased &&
        provenance.isProductionTrusted &&
        switch (metric) {
          WorkoutMetricKind.paceSamples ||
          WorkoutMetricKind.cadenceSamples => true,
          _ => false,
        };
  }

  List<WorkoutMetricSample> get acceptedSamples {
    return List<WorkoutMetricSample>.unmodifiable(
      samples.where((sample) => sample.isAccepted),
    );
  }

  List<WorkoutMetricSample> get rejectedSamples {
    return List<WorkoutMetricSample>.unmodifiable(
      samples.where((sample) => !sample.isAccepted),
    );
  }

  void _validate() {
    if (isSummaryOnly) {
      if (summaryValue == null) {
        throw ArgumentError.value(summaryValue, 'summaryValue');
      }
      if (samples.isNotEmpty) {
        throw ArgumentError.value(samples, 'samples');
      }
      if (unavailableReason != null) {
        throw ArgumentError.value(unavailableReason, 'unavailableReason');
      }
    }
    if (isSampleBased) {
      if (samples.isEmpty) {
        throw ArgumentError.value(samples, 'samples');
      }
      if (summaryValue != null || unavailableReason != null) {
        throw ArgumentError.value('$summaryValue/$unavailableReason');
      }
    }
    if (provenance.evidenceKind == WorkoutMetricEvidenceKind.unavailable) {
      if (unavailableReason == null) {
        throw ArgumentError.value(unavailableReason, 'unavailableReason');
      }
      if (samples.isNotEmpty || summaryValue != null) {
        throw ArgumentError.value('$samples/$summaryValue');
      }
    }
  }
}

class WorkoutMetricSample {
  const WorkoutMetricSample._({
    required this.elapsedSeconds,
    required this.recordedAt,
    required this.value,
    required this.rejectionReason,
  });

  factory WorkoutMetricSample.accepted({
    required int elapsedSeconds,
    required DateTime? recordedAt,
    required num value,
  }) {
    if (elapsedSeconds < 0) {
      throw ArgumentError.value(elapsedSeconds, 'elapsedSeconds');
    }
    return WorkoutMetricSample._(
      elapsedSeconds: elapsedSeconds,
      recordedAt: recordedAt,
      value: value,
      rejectionReason: WorkoutSampleRejectionReason.none,
    );
  }

  factory WorkoutMetricSample.rejected({
    required int elapsedSeconds,
    required DateTime? recordedAt,
    required num value,
    required WorkoutSampleRejectionReason rejectionReason,
  }) {
    if (rejectionReason == WorkoutSampleRejectionReason.none) {
      throw ArgumentError.value(rejectionReason, 'rejectionReason');
    }
    return WorkoutMetricSample._(
      elapsedSeconds: elapsedSeconds,
      recordedAt: recordedAt,
      value: value,
      rejectionReason: rejectionReason,
    );
  }

  final int elapsedSeconds;
  final DateTime? recordedAt;
  final num value;
  final WorkoutSampleRejectionReason rejectionReason;

  bool get isAccepted => rejectionReason == WorkoutSampleRejectionReason.none;
}

class WorkoutDurationBreakdown {
  WorkoutDurationBreakdown({
    required this.elapsedDurationSeconds,
    required this.activeDurationSeconds,
    required this.movingDurationSeconds,
    required this.pausedDurationSeconds,
    required this.pausePolicy,
    required List<WorkoutPauseInterval> pauseIntervals,
  }) : pauseIntervals = List<WorkoutPauseInterval>.unmodifiable(
         pauseIntervals,
       ) {
    _validate();
  }

  final int elapsedDurationSeconds;
  final int activeDurationSeconds;
  final int? movingDurationSeconds;
  final int? pausedDurationSeconds;
  final WorkoutPausePolicy pausePolicy;
  final List<WorkoutPauseInterval> pauseIntervals;

  bool get hasKnownMovingDuration => movingDurationSeconds != null;
  bool get hasKnownPauseIntervals =>
      pausePolicy != WorkoutPausePolicy.unknown && pauseIntervals.isNotEmpty;

  void _validate() {
    if (elapsedDurationSeconds < 0 || activeDurationSeconds < 0) {
      throw ArgumentError.value(
        '$elapsedDurationSeconds/$activeDurationSeconds',
      );
    }
    if (activeDurationSeconds > elapsedDurationSeconds) {
      throw ArgumentError.value(activeDurationSeconds, 'activeDurationSeconds');
    }
    final movingSeconds = movingDurationSeconds;
    if (movingSeconds != null &&
        (movingSeconds < 0 || movingSeconds > elapsedDurationSeconds)) {
      throw ArgumentError.value(movingSeconds, 'movingDurationSeconds');
    }
    final pausedSeconds = pausedDurationSeconds;
    if (pausedSeconds != null &&
        (pausedSeconds < 0 || pausedSeconds > elapsedDurationSeconds)) {
      throw ArgumentError.value(pausedSeconds, 'pausedDurationSeconds');
    }
  }
}

class WorkoutPauseInterval {
  const WorkoutPauseInterval._({
    required this.kind,
    required this.startElapsedSeconds,
    required this.endElapsedSeconds,
  });

  factory WorkoutPauseInterval.manual({
    required int startElapsedSeconds,
    required int endElapsedSeconds,
  }) {
    _validateBounds(startElapsedSeconds, endElapsedSeconds);
    return WorkoutPauseInterval._(
      kind: WorkoutPauseIntervalKind.manual,
      startElapsedSeconds: startElapsedSeconds,
      endElapsedSeconds: endElapsedSeconds,
    );
  }

  factory WorkoutPauseInterval.auto({
    required int startElapsedSeconds,
    required int endElapsedSeconds,
  }) {
    _validateBounds(startElapsedSeconds, endElapsedSeconds);
    return WorkoutPauseInterval._(
      kind: WorkoutPauseIntervalKind.auto,
      startElapsedSeconds: startElapsedSeconds,
      endElapsedSeconds: endElapsedSeconds,
    );
  }

  final WorkoutPauseIntervalKind kind;
  final int startElapsedSeconds;
  final int endElapsedSeconds;

  static void _validateBounds(int startElapsedSeconds, int endElapsedSeconds) {
    if (startElapsedSeconds < 0 || endElapsedSeconds <= startElapsedSeconds) {
      throw ArgumentError.value('$startElapsedSeconds/$endElapsedSeconds');
    }
  }
}
