const defaultMinimumElevationAnalysisSamples = 2;
const elevationGainNoiseThresholdMeters = 1.5;

enum ElevationUnavailableReason {
  none,
  noElevationSeries,
  lowDataSummary,
  noAcceptedMovementSamples,
  noAcceptedAltitudeSamples,
  tooFewValidAltitudeSamples,
  nonIncreasingDistance,
  graphUnavailable,
}

enum ElevationAnalysisSource {
  runiacLocalAccepted,
  backendDerived,
  staticDemo,
  unavailableUnknown,
}

enum ElevationAnalysisConfidence { medium, demo, unavailable }

class ElevationAnalysisSeries {
  ElevationAnalysisSeries({
    required this.source,
    required this.confidence,
    required List<ElevationAnalysisSample> samples,
    this.unavailableReason = ElevationUnavailableReason.none,
  }) : samples = List<ElevationAnalysisSample>.unmodifiable(samples) {
    _validateSourceConfidence(
      source,
      confidence,
      this.samples,
      unavailableReason,
    );
  }

  ElevationAnalysisSeries.localAccepted({
    required List<ElevationAnalysisSample> samples,
  }) : this(
         source: ElevationAnalysisSource.runiacLocalAccepted,
         confidence: ElevationAnalysisConfidence.medium,
         samples: samples,
       );

  ElevationAnalysisSeries.backendDerived({
    required List<ElevationAnalysisSample> samples,
  }) : this(
         source: ElevationAnalysisSource.backendDerived,
         confidence: ElevationAnalysisConfidence.medium,
         samples: samples,
       );

  ElevationAnalysisSeries.staticDemo({
    required List<ElevationAnalysisSample> samples,
  }) : this(
         source: ElevationAnalysisSource.staticDemo,
         confidence: ElevationAnalysisConfidence.demo,
         samples: samples,
       );

  const ElevationAnalysisSeries.unavailable({
    ElevationUnavailableReason reason =
        ElevationUnavailableReason.noElevationSeries,
  }) : unavailableReason = reason,
       source = ElevationAnalysisSource.unavailableUnknown,
       confidence = ElevationAnalysisConfidence.unavailable,
       samples = const <ElevationAnalysisSample>[];

  final ElevationAnalysisSource source;
  final ElevationAnalysisConfidence confidence;
  final List<ElevationAnalysisSample> samples;
  final ElevationUnavailableReason unavailableReason;

  bool get isStaticDemoSource => source == ElevationAnalysisSource.staticDemo;
  bool get isUnavailable =>
      source == ElevationAnalysisSource.unavailableUnknown;
  bool get isProductionAnalysisEligible {
    return switch ((source, confidence)) {
      (
        ElevationAnalysisSource.runiacLocalAccepted,
        ElevationAnalysisConfidence.medium,
      ) ||
      (
        ElevationAnalysisSource.backendDerived,
        ElevationAnalysisConfidence.medium,
      ) => true,
      _ => false,
    };
  }

  List<ElevationAnalysisSample> get validSamples {
    return List<ElevationAnalysisSample>.unmodifiable(
      samples.where((sample) => sample.isValidSample),
    );
  }

  bool hasMinimumValidSamples({
    int minimumSampleCount = defaultMinimumElevationAnalysisSamples,
  }) {
    return validSamples.length >= minimumSampleCount;
  }

  static void _validateSourceConfidence(
    ElevationAnalysisSource source,
    ElevationAnalysisConfidence confidence,
    List<ElevationAnalysisSample> samples,
    ElevationUnavailableReason unavailableReason,
  ) {
    final expectedConfidence = switch (source) {
      ElevationAnalysisSource.runiacLocalAccepted ||
      ElevationAnalysisSource.backendDerived =>
        ElevationAnalysisConfidence.medium,
      ElevationAnalysisSource.staticDemo => ElevationAnalysisConfidence.demo,
      ElevationAnalysisSource.unavailableUnknown =>
        ElevationAnalysisConfidence.unavailable,
    };
    if (confidence != expectedConfidence) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'expected $expectedConfidence for $source',
      );
    }
    if (source == ElevationAnalysisSource.unavailableUnknown &&
        samples.isNotEmpty) {
      throw ArgumentError.value(
        samples,
        'samples',
        'expected empty samples when the elevation analysis source is unavailable',
      );
    }
    if (source == ElevationAnalysisSource.unavailableUnknown &&
        unavailableReason == ElevationUnavailableReason.none) {
      throw ArgumentError.value(
        unavailableReason,
        'unavailableReason',
        'expected a reason when the elevation analysis source is unavailable',
      );
    }
    if (source != ElevationAnalysisSource.unavailableUnknown &&
        unavailableReason != ElevationUnavailableReason.none) {
      throw ArgumentError.value(
        unavailableReason,
        'unavailableReason',
        'expected no unavailable reason when elevation analysis is available',
      );
    }
  }
}

class ElevationAnalysisSample {
  const ElevationAnalysisSample({
    required this.distanceKm,
    required this.elevationMeters,
  });

  final double distanceKm;
  final double elevationMeters;

  bool get isValidSample {
    return distanceKm.isFinite && distanceKm >= 0 && elevationMeters.isFinite;
  }
}
