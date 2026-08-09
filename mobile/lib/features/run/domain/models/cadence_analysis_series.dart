// A validated cadence series, plus the audit trail of how it was validated.
//
// Cadence can arrive from very different places — the phone's own sensors, an
// Apple Watch, Health Connect, a Garmin, or static demo data — and they are not
// equally trustworthy. Every series therefore carries its [CadenceAnalysisSource]
// and a [CadenceAnalysisConfidence] derived from it, and downstream code is
// expected to weaken or hide its claims accordingly rather than treat all
// cadence alike.
//
// Rejected samples are kept rather than dropped, each with a rejection reason,
// so an unexpectedly empty graph can be explained instead of just being blank.

const minCadenceAnalysisSpm = 40;
const maxCadenceAnalysisSpm = 240;
const defaultMinimumCadenceAnalysisSamples = 3;

enum CadenceAnalysisSource {
  runiacLocalAccepted,
  healthKitAppleWatch,
  healthConnect,
  garminWearable,
  phoneSensorEstimated,
  backendDerived,
  staticDemo,
  unavailableUnknown,
}

enum CadenceAnalysisConfidence { high, medium, low, demo, unavailable }

enum CadenceAnalysisSampleStatus { accepted, rejected }

enum CadenceAnalysisSampleRejectionReason {
  none,
  invalidElapsedTime,
  invalidCadence,
  outOfRangeCadence,
  nonMonotonicElapsed,
}

class CadenceAnalysisSeries {
  CadenceAnalysisSeries({
    required this.source,
    required this.confidence,
    required List<CadenceAnalysisSample> samples,
  }) : samples = List<CadenceAnalysisSample>.unmodifiable(samples) {
    _validateSourceConfidence(source, confidence, this.samples);
  }

  CadenceAnalysisSeries.localAccepted({
    required List<CadenceAnalysisSample> samples,
  }) : this(
         source: CadenceAnalysisSource.runiacLocalAccepted,
         confidence: CadenceAnalysisConfidence.medium,
         samples: samples,
       );

  CadenceAnalysisSeries.phoneMotionEstimated({
    required List<CadenceAnalysisSample> samples,
  }) : this(
         source: CadenceAnalysisSource.phoneSensorEstimated,
         confidence: CadenceAnalysisConfidence.low,
         samples: samples,
       );

  CadenceAnalysisSeries.staticDemo({
    required List<CadenceAnalysisSample> samples,
  }) : this(
         source: CadenceAnalysisSource.staticDemo,
         confidence: CadenceAnalysisConfidence.demo,
         samples: samples,
       );

  CadenceAnalysisSeries.unavailable()
    : this(
        source: CadenceAnalysisSource.unavailableUnknown,
        confidence: CadenceAnalysisConfidence.unavailable,
        samples: const <CadenceAnalysisSample>[],
      );

  final CadenceAnalysisSource source;
  final CadenceAnalysisConfidence confidence;
  final List<CadenceAnalysisSample> samples;

  bool get isRuniacLocalAcceptedSource =>
      source == CadenceAnalysisSource.runiacLocalAccepted;
  bool get isLocalAcceptedSource => isRuniacLocalAcceptedSource;
  bool get isStaticDemoSource => source == CadenceAnalysisSource.staticDemo;
  bool get isUnavailable => source == CadenceAnalysisSource.unavailableUnknown;
  bool get isProductionAnalysisEligible {
    return switch ((source, confidence)) {
      (
        CadenceAnalysisSource.runiacLocalAccepted,
        CadenceAnalysisConfidence.medium,
      ) ||
      (
        CadenceAnalysisSource.healthKitAppleWatch ||
            CadenceAnalysisSource.healthConnect ||
            CadenceAnalysisSource.garminWearable,
        CadenceAnalysisConfidence.high,
      ) ||
      (
        CadenceAnalysisSource.backendDerived,
        CadenceAnalysisConfidence.medium,
      ) ||
      (
        CadenceAnalysisSource.phoneSensorEstimated,
        CadenceAnalysisConfidence.low,
      ) => true,
      _ => false,
    };
  }

  List<CadenceAnalysisSample> get validAcceptedSamples {
    return List<CadenceAnalysisSample>.unmodifiable(
      samples.where((sample) => sample.isValidAcceptedSample),
    );
  }

  bool hasMinimumValidSamples({
    int minimumSampleCount = defaultMinimumCadenceAnalysisSamples,
  }) {
    return validAcceptedSamples.length >= minimumSampleCount;
  }

  bool get hasMonotonicValidSamples {
    int? lastElapsedSeconds;

    for (final sample in validAcceptedSamples) {
      final elapsedSeconds = sample.elapsedSeconds;
      if (lastElapsedSeconds != null && elapsedSeconds <= lastElapsedSeconds) {
        return false;
      }
      lastElapsedSeconds = elapsedSeconds;
    }

    return true;
  }

  static void _validateSourceConfidence(
    CadenceAnalysisSource source,
    CadenceAnalysisConfidence confidence,
    List<CadenceAnalysisSample> samples,
  ) {
    final expectedConfidence = switch (source) {
      CadenceAnalysisSource.runiacLocalAccepted =>
        CadenceAnalysisConfidence.medium,
      CadenceAnalysisSource.healthKitAppleWatch ||
      CadenceAnalysisSource.healthConnect ||
      CadenceAnalysisSource.garminWearable => CadenceAnalysisConfidence.high,
      CadenceAnalysisSource.phoneSensorEstimated =>
        CadenceAnalysisConfidence.low,
      CadenceAnalysisSource.backendDerived => CadenceAnalysisConfidence.medium,
      CadenceAnalysisSource.staticDemo => CadenceAnalysisConfidence.demo,
      CadenceAnalysisSource.unavailableUnknown =>
        CadenceAnalysisConfidence.unavailable,
    };
    if (confidence != expectedConfidence) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'expected $expectedConfidence for $source',
      );
    }
    if (source == CadenceAnalysisSource.unavailableUnknown &&
        samples.isNotEmpty) {
      throw ArgumentError.value(
        samples,
        'samples',
        'expected empty samples when the cadence analysis source is unavailable',
      );
    }
  }
}

class CadenceAnalysisSample {
  const CadenceAnalysisSample._({
    required this.elapsedSeconds,
    required this.cadenceSpmValue,
    required this.status,
    this.rejectionReason = CadenceAnalysisSampleRejectionReason.none,
  });

  factory CadenceAnalysisSample({
    required int elapsedSeconds,
    required double cadenceSpm,
    required CadenceAnalysisSampleStatus status,
    CadenceAnalysisSampleRejectionReason rejectionReason =
        CadenceAnalysisSampleRejectionReason.none,
  }) {
    _validateStatusReason(status, rejectionReason);
    return CadenceAnalysisSample._(
      elapsedSeconds: elapsedSeconds,
      cadenceSpmValue: cadenceSpm,
      status: status,
      rejectionReason: rejectionReason,
    );
  }

  const CadenceAnalysisSample.accepted({
    required int elapsedSeconds,
    required int cadenceSpm,
  }) : this._(
         elapsedSeconds: elapsedSeconds,
         cadenceSpmValue: cadenceSpm,
         status: CadenceAnalysisSampleStatus.accepted,
       );

  factory CadenceAnalysisSample.rejected({
    required int elapsedSeconds,
    required int cadenceSpm,
    required CadenceAnalysisSampleRejectionReason rejectionReason,
  }) {
    _validateStatusReason(
      CadenceAnalysisSampleStatus.rejected,
      rejectionReason,
    );
    return CadenceAnalysisSample._(
      elapsedSeconds: elapsedSeconds,
      cadenceSpmValue: cadenceSpm.toDouble(),
      status: CadenceAnalysisSampleStatus.rejected,
      rejectionReason: rejectionReason,
    );
  }

  final int elapsedSeconds;
  final num cadenceSpmValue;
  final CadenceAnalysisSampleStatus status;
  final CadenceAnalysisSampleRejectionReason rejectionReason;

  bool get isAccepted => status == CadenceAnalysisSampleStatus.accepted;

  int? get cadenceSpm {
    if (!cadenceSpmValue.isFinite) {
      return null;
    }
    return cadenceSpmValue.round();
  }

  bool get hasValidElapsedSeconds => elapsedSeconds >= 0;

  bool get hasValidCadence {
    return cadenceSpmValue.isFinite &&
        cadenceSpmValue >= minCadenceAnalysisSpm &&
        cadenceSpmValue <= maxCadenceAnalysisSpm;
  }

  bool get isValidAcceptedSample {
    return isAccepted &&
        rejectionReason == CadenceAnalysisSampleRejectionReason.none &&
        hasValidElapsedSeconds &&
        hasValidCadence;
  }

  static void _validateStatusReason(
    CadenceAnalysisSampleStatus status,
    CadenceAnalysisSampleRejectionReason rejectionReason,
  ) {
    if (status == CadenceAnalysisSampleStatus.accepted &&
        rejectionReason != CadenceAnalysisSampleRejectionReason.none) {
      throw ArgumentError.value(
        rejectionReason,
        'rejectionReason',
        'expected none for an accepted cadence analysis sample',
      );
    }
    if (status == CadenceAnalysisSampleStatus.rejected &&
        rejectionReason == CadenceAnalysisSampleRejectionReason.none) {
      throw ArgumentError.value(
        rejectionReason,
        'rejectionReason',
        'expected a rejection reason for a rejected cadence analysis sample',
      );
    }
  }
}
