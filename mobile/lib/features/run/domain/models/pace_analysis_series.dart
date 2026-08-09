// A validated pace series — the pace counterpart of `cadence_analysis_series.dart`,
// and it follows the same rules deliberately.
//
// Samples are validated on the way in (plausible pace, non-decreasing elapsed
// time and distance) and rejected samples are retained with a reason rather
// than silently dropped. A run that is too short or too slow to say anything
// meaningful about is refused up front by the minimum duration and distance
// constants below, so the analysis screens never present a trend inferred from
// a 20-second walk.

const minPaceAnalysisPaceSecondsPerKm = 150;
const maxPaceAnalysisPaceSecondsPerKm = 1800;
const defaultMinimumPaceAnalysisSamples = 3;
const minPaceAnalysisDurationSeconds = 60;
const minPaceAnalysisDistanceMeters = 50;

enum PaceAnalysisSource { localAccepted, staticDemo, unavailableUnknown }

enum PaceAnalysisConfidence { derived, demo, unavailable }

enum PaceAnalysisSampleStatus { accepted, rejected }

enum PaceAnalysisSampleRejectionReason {
  none,
  gpsRejected,
  invalidElapsedTime,
  invalidDistance,
  invalidPace,
  nonMonotonicElapsed,
  nonMonotonicDistance,
}

class RunPaceAnalysisInput {
  const RunPaceAnalysisInput({
    required this.durationSeconds,
    required this.distanceMeters,
    required this.series,
  });

  final int durationSeconds;
  final int distanceMeters;
  final PaceAnalysisSeries series;

  bool get hasMinimumDurationAndDistance {
    return durationSeconds >= minPaceAnalysisDurationSeconds &&
        distanceMeters >= minPaceAnalysisDistanceMeters;
  }

  bool get hasSufficientLocalSeries {
    return hasMinimumDurationAndDistance &&
        series.isLocalAcceptedSource &&
        series.hasMinimumValidSamples() &&
        series.hasMonotonicValidSamples;
  }
}

class PaceAnalysisSeries {
  PaceAnalysisSeries({
    required this.source,
    required this.confidence,
    required List<PaceAnalysisSample> samples,
  }) : samples = List<PaceAnalysisSample>.unmodifiable(samples) {
    _validateSourceConfidence(source, confidence, this.samples);
  }

  PaceAnalysisSeries.localAccepted({required List<PaceAnalysisSample> samples})
    : this(
        source: PaceAnalysisSource.localAccepted,
        confidence: PaceAnalysisConfidence.derived,
        samples: samples,
      );

  PaceAnalysisSeries.staticDemo({required List<PaceAnalysisSample> samples})
    : this(
        source: PaceAnalysisSource.staticDemo,
        confidence: PaceAnalysisConfidence.demo,
        samples: samples,
      );

  PaceAnalysisSeries.unavailable()
    : this(
        source: PaceAnalysisSource.unavailableUnknown,
        confidence: PaceAnalysisConfidence.unavailable,
        samples: const <PaceAnalysisSample>[],
      );

  final PaceAnalysisSource source;
  final PaceAnalysisConfidence confidence;
  final List<PaceAnalysisSample> samples;

  bool get isLocalAcceptedSource => source == PaceAnalysisSource.localAccepted;
  bool get isStaticDemoSource => source == PaceAnalysisSource.staticDemo;
  bool get isUnavailable => source == PaceAnalysisSource.unavailableUnknown;

  List<PaceAnalysisSample> get validAcceptedSamples {
    return List<PaceAnalysisSample>.unmodifiable(
      samples.where((sample) => sample.isValidAcceptedSample),
    );
  }

  bool hasMinimumValidSamples({
    int minimumSampleCount = defaultMinimumPaceAnalysisSamples,
  }) {
    return validAcceptedSamples.length >= minimumSampleCount;
  }

  bool get hasMonotonicValidSamples {
    int? lastElapsedSeconds;
    double? lastCumulativeDistanceMeters;

    for (final sample in validAcceptedSamples) {
      final elapsedSeconds = sample.elapsedSeconds;
      final cumulativeDistanceMeters = sample.cumulativeDistanceMeters;
      if (lastElapsedSeconds != null && elapsedSeconds <= lastElapsedSeconds) {
        return false;
      }
      if (lastCumulativeDistanceMeters != null &&
          cumulativeDistanceMeters < lastCumulativeDistanceMeters) {
        return false;
      }
      lastElapsedSeconds = elapsedSeconds;
      lastCumulativeDistanceMeters = cumulativeDistanceMeters;
    }

    return true;
  }

  static void _validateSourceConfidence(
    PaceAnalysisSource source,
    PaceAnalysisConfidence confidence,
    List<PaceAnalysisSample> samples,
  ) {
    final expectedConfidence = switch (source) {
      PaceAnalysisSource.localAccepted => PaceAnalysisConfidence.derived,
      PaceAnalysisSource.staticDemo => PaceAnalysisConfidence.demo,
      PaceAnalysisSource.unavailableUnknown =>
        PaceAnalysisConfidence.unavailable,
    };
    if (confidence != expectedConfidence) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'must be $expectedConfidence for $source',
      );
    }
    if (source == PaceAnalysisSource.unavailableUnknown && samples.isNotEmpty) {
      throw ArgumentError.value(
        samples,
        'samples',
        'must be empty when the pace analysis source is unavailable',
      );
    }
  }
}

class PaceAnalysisSample {
  const PaceAnalysisSample._({
    required this.elapsedSeconds,
    required this.cumulativeDistanceMeters,
    required this.paceSecondsPerKm,
    required this.status,
    this.rejectionReason = PaceAnalysisSampleRejectionReason.none,
  });

  factory PaceAnalysisSample({
    required int elapsedSeconds,
    required double cumulativeDistanceMeters,
    required int paceSecondsPerKm,
    required PaceAnalysisSampleStatus status,
    PaceAnalysisSampleRejectionReason rejectionReason =
        PaceAnalysisSampleRejectionReason.none,
  }) {
    _validateStatusReason(status, rejectionReason);
    return PaceAnalysisSample._(
      elapsedSeconds: elapsedSeconds,
      cumulativeDistanceMeters: cumulativeDistanceMeters,
      paceSecondsPerKm: paceSecondsPerKm,
      status: status,
      rejectionReason: rejectionReason,
    );
  }

  const PaceAnalysisSample.accepted({
    required int elapsedSeconds,
    required double cumulativeDistanceMeters,
    required int paceSecondsPerKm,
  }) : this._(
         elapsedSeconds: elapsedSeconds,
         cumulativeDistanceMeters: cumulativeDistanceMeters,
         paceSecondsPerKm: paceSecondsPerKm,
         status: PaceAnalysisSampleStatus.accepted,
       );

  factory PaceAnalysisSample.rejected({
    required int elapsedSeconds,
    required double cumulativeDistanceMeters,
    required int paceSecondsPerKm,
    required PaceAnalysisSampleRejectionReason rejectionReason,
  }) {
    _validateStatusReason(PaceAnalysisSampleStatus.rejected, rejectionReason);
    return PaceAnalysisSample._(
      elapsedSeconds: elapsedSeconds,
      cumulativeDistanceMeters: cumulativeDistanceMeters,
      paceSecondsPerKm: paceSecondsPerKm,
      status: PaceAnalysisSampleStatus.rejected,
      rejectionReason: rejectionReason,
    );
  }

  final int elapsedSeconds;
  final double cumulativeDistanceMeters;
  final int paceSecondsPerKm;
  final PaceAnalysisSampleStatus status;
  final PaceAnalysisSampleRejectionReason rejectionReason;

  bool get isAccepted => status == PaceAnalysisSampleStatus.accepted;

  bool get hasValidElapsedSeconds => elapsedSeconds >= 0;

  bool get hasValidDistance {
    return cumulativeDistanceMeters.isFinite && cumulativeDistanceMeters >= 0;
  }

  bool get hasValidPace {
    return paceSecondsPerKm >= minPaceAnalysisPaceSecondsPerKm &&
        paceSecondsPerKm <= maxPaceAnalysisPaceSecondsPerKm;
  }

  bool get isValidAcceptedSample {
    return isAccepted &&
        rejectionReason == PaceAnalysisSampleRejectionReason.none &&
        hasValidElapsedSeconds &&
        hasValidDistance &&
        hasValidPace;
  }

  static void _validateStatusReason(
    PaceAnalysisSampleStatus status,
    PaceAnalysisSampleRejectionReason rejectionReason,
  ) {
    if (status == PaceAnalysisSampleStatus.accepted &&
        rejectionReason != PaceAnalysisSampleRejectionReason.none) {
      throw ArgumentError.value(
        rejectionReason,
        'rejectionReason',
        'must be none for an accepted pace analysis sample',
      );
    }
    if (status == PaceAnalysisSampleStatus.rejected &&
        rejectionReason == PaceAnalysisSampleRejectionReason.none) {
      throw ArgumentError.value(
        rejectionReason,
        'rejectionReason',
        'must explain why a rejected pace analysis sample was rejected',
      );
    }
  }
}
