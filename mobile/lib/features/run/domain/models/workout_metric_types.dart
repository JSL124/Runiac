enum WorkoutMetricKind {
  distance,
  elapsedDuration,
  movingDuration,
  pauseDuration,
  averagePace,
  paceSamples,
  routeSamples,
  gpsQuality,
  cadenceSummary,
  cadenceSamples,
  strideLength,
  calories,
}

enum WorkoutMetricUnit {
  meters,
  seconds,
  secondsPerKilometer,
  stepsPerMinute,
  kilocalories,
  coordinate,
  qualityEvent,
}

enum WorkoutMetricSource {
  runiacLocalGps,
  healthKitAppleWatch,
  healthConnect,
  garminWearable,
  phoneSensorEstimated,
  backendDerived,
  staticDemo,
  unavailableUnknown,
}

enum WorkoutMetricConfidence { high, medium, low, demo, unavailable }

enum WorkoutMetricEvidenceKind { summaryOnly, sampleBased, unavailable }

enum WorkoutMetricAvailabilityReason {
  notProvidedBySource,
  notSharedByUser,
  unsupportedMetric,
  insufficientSamples,
  invalidSource,
  unavailableUnknown,
}

enum WorkoutSampleRejectionReason {
  none,
  invalidElapsedSeconds,
  invalidTimestamp,
  invalidValue,
  outOfRange,
  rejectedBySourceQuality,
}

enum WorkoutPausePolicy {
  none,
  manualOnly,
  autoOnly,
  mixedManualAndAuto,
  unknown,
}

enum WorkoutPauseIntervalKind { manual, auto }

class WorkoutMetricProvenance {
  const WorkoutMetricProvenance({
    required this.source,
    required this.confidence,
    required this.evidenceKind,
    this.sourceAppName,
    this.sourceDeviceName,
    this.sourceExternalId,
    this.importedAt,
    this.adapterVersion,
    this.derivedLocally = false,
  });

  final WorkoutMetricSource source;
  final WorkoutMetricConfidence confidence;
  final WorkoutMetricEvidenceKind evidenceKind;
  final String? sourceAppName;
  final String? sourceDeviceName;
  final String? sourceExternalId;
  final DateTime? importedAt;
  final String? adapterVersion;
  final bool derivedLocally;

  bool get isImportedOrWearable {
    return switch (source) {
      WorkoutMetricSource.healthKitAppleWatch ||
      WorkoutMetricSource.healthConnect ||
      WorkoutMetricSource.garminWearable => true,
      _ => false,
    };
  }

  bool get isProductionTrusted {
    return switch ((source, confidence)) {
      (
        WorkoutMetricSource.runiacLocalGps,
        WorkoutMetricConfidence.medium || WorkoutMetricConfidence.high,
      ) ||
      (
        WorkoutMetricSource.healthKitAppleWatch ||
            WorkoutMetricSource.healthConnect ||
            WorkoutMetricSource.garminWearable,
        WorkoutMetricConfidence.high,
      ) ||
      (
        WorkoutMetricSource.backendDerived,
        WorkoutMetricConfidence.medium || WorkoutMetricConfidence.high,
      ) => true,
      _ => false,
    };
  }

  WorkoutMetricProvenance copyWith({
    WorkoutMetricSource? source,
    WorkoutMetricConfidence? confidence,
    WorkoutMetricEvidenceKind? evidenceKind,
    String? sourceAppName,
    String? sourceDeviceName,
    String? sourceExternalId,
    DateTime? importedAt,
    String? adapterVersion,
    bool? derivedLocally,
  }) {
    return WorkoutMetricProvenance(
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      evidenceKind: evidenceKind ?? this.evidenceKind,
      sourceAppName: sourceAppName ?? this.sourceAppName,
      sourceDeviceName: sourceDeviceName ?? this.sourceDeviceName,
      sourceExternalId: sourceExternalId ?? this.sourceExternalId,
      importedAt: importedAt ?? this.importedAt,
      adapterVersion: adapterVersion ?? this.adapterVersion,
      derivedLocally: derivedLocally ?? this.derivedLocally,
    );
  }
}
