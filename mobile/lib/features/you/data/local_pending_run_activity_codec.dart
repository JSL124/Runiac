part of 'local_pending_run_activity_store.dart';

// JSON encoding for runs that finished while the device was offline and are
// waiting to be synced.
//
// This is persisted data, so it has to survive app updates: decoding is written
// to tolerate records written by older versions rather than assuming the
// current shape. The `_legacy*` constants below are the sanity bounds applied
// to values from those older records — a stored run whose cadence falls outside
// them is treated as unusable rather than trusted.
//
// A decode failure must never lose the run. Prefer dropping a single suspect
// field over rejecting the whole record.

const _legacyCompleteRunMinCadenceSpm = 90;
const _legacyCompleteRunMaxCadenceSpm = 220;

Map<String, Object?> _localPendingRunActivityToJson(
  LocalPendingRunActivity activity,
) {
  return <String, Object?>{
    'ownerUid': activity.ownerUid,
    'clientRunSessionId': activity.clientRunSessionId,
    'activityId': activity.result.activityId,
    'summaryId': activity.result.summaryId,
    'progressionEventId': activity.result.progressionEventId,
    'validationStatus': activity.result.validationStatus,
    'message': activity.result.message,
    'planCompletion': <String, Object?>{
      'completed': activity.result.planCompletion.completed,
      if (activity.result.planCompletion.planEnrollmentId != null)
        'planEnrollmentId': activity.result.planCompletion.planEnrollmentId,
      if (activity.result.planCompletion.scheduledWorkoutId != null)
        'scheduledWorkoutId': activity.result.planCompletion.scheduledWorkoutId,
    },
    'syncAccepted': activity.syncAccepted,
    'syncState': activity.syncState.name,
    'syncAttemptCount': activity.syncAttemptCount,
    if (activity.lastSyncAttemptedAt != null)
      'lastSyncAttemptedAt': activity.lastSyncAttemptedAt!
          .toUtc()
          .toIso8601String(),
    if (activity.lastSyncFailureCode != null)
      'lastSyncFailureCode': activity.lastSyncFailureCode,
    if (activity.lastSyncFailureMessage != null)
      'lastSyncFailureMessage': activity.lastSyncFailureMessage,
    'summary': <String, Object?>{
      'title': activity.result.summary.title,
      'dateLabel': activity.result.summary.dateLabel,
      'timeLabel': activity.result.summary.timeLabel,
      'distanceKm': activity.result.summary.distanceKm,
      'avgPace': activity.result.summary.avgPace,
      'duration': activity.result.summary.duration,
      'avgHeartRate': activity.result.summary.avgHeartRate,
      'calories': activity.result.summary.calories,
      'routeName': activity.result.summary.routeName,
      'hasSufficientData': activity.result.summary.hasSufficientData,
      if (activity.result.summary.paceAnalysisSeries != null)
        'paceAnalysisSeries': _paceAnalysisSeriesToJson(
          activity.result.summary.paceAnalysisSeries!,
        ),
      if (activity.result.summary.cadenceAnalysisSeries != null)
        'cadenceAnalysisSeries': _cadenceAnalysisSeriesToJson(
          activity.result.summary.cadenceAnalysisSeries!,
        ),
      'elevationSeries': _elevationAnalysisSeriesToJson(
        activity.result.summary.elevationSeries,
      ),
      'route': _routeToJson(activity.result.summary.route),
    },
    'payload': <String, Object?>{
      'clientRunSessionId': activity.payload.clientRunSessionId,
      'startedAt': activity.payload.startedAt.toUtc().toIso8601String(),
      'completedAt': activity.payload.completedAt.toUtc().toIso8601String(),
      'durationSeconds': activity.payload.durationSeconds,
      'activeDurationSeconds': activity.payload.activeDurationSeconds,
      'elapsedWallSeconds': activity.payload.elapsedWallSeconds,
      'pausedDurationSeconds': activity.payload.pausedDurationSeconds,
      'distanceMeters': activity.payload.distanceMeters,
      'avgPaceSecondsPerKm': activity.payload.avgPaceSecondsPerKm,
      'source': activity.payload.source,
      'routePrivacy': activity.payload.routePrivacy,
      'routeSnapshot': _routeToJson(activity.payload.routeSnapshot),
      if (activity.payload.userConfirmedLowDataSave)
        'userConfirmedLowDataSave': true,
      if (activity.payload.activityTitle != null)
        'activityTitle': activity.payload.activityTitle,
      if (activity.payload.routeLabel != null)
        'routeLabel': activity.payload.routeLabel,
      if (activity.payload.clientAppVersion != null)
        'clientAppVersion': activity.payload.clientAppVersion,
      if (activity.payload.planEnrollmentId != null)
        'planEnrollmentId': activity.payload.planEnrollmentId,
      if (activity.payload.scheduledWorkoutId != null)
        'scheduledWorkoutId': activity.payload.scheduledWorkoutId,
      if (activity.payload.paceGraphSamples.isNotEmpty)
        'paceGraphSamples': [
          for (final sample in activity.payload.paceGraphSamples)
            _paceGraphSampleToJson(sample),
        ],
      if (activity.payload.cadenceAnalysisSeries != null)
        'cadenceAnalysisSeries': _cadenceAnalysisSeriesToJson(
          activity.payload.cadenceAnalysisSeries!,
        ),
      if (activity.payload.elevationAnalysisSeries != null)
        'elevationAnalysisSeries': _elevationAnalysisSeriesToJson(
          activity.payload.elevationAnalysisSeries!,
        ),
      'elevationUnavailableReason':
          activity.payload.elevationUnavailableReason.name,
    },
  };
}

LocalPendingRunActivity? _localPendingRunActivityFromJson(
  Map<String, Object?> source,
) {
  final clientRunSessionId = _readString(source, 'clientRunSessionId');
  final ownerUid = _readString(source, 'ownerUid');
  final summary = _readMap(source, 'summary');
  final payload = _readMap(source, 'payload');
  if (ownerUid == null ||
      clientRunSessionId == null ||
      summary == null ||
      payload == null) {
    return null;
  }

  final restoredPayload = _payloadFromJson(payload, clientRunSessionId);
  final planCompletion =
      _readMap(source, 'planCompletion') ?? const <String, Object?>{};
  final syncAccepted = _readBool(source, 'syncAccepted') ?? false;
  final persistedSyncState =
      _enumByName(RunSyncState.values, _readString(source, 'syncState')) ??
      (syncAccepted ? RunSyncState.syncAccepted : RunSyncState.localSaved);
  final lastSyncFailureCode = _readString(source, 'lastSyncFailureCode');
  final cadenceSamples =
      restoredPayload.cadenceAnalysisSeries?.validAcceptedSamples ??
      const <CadenceAnalysisSample>[];
  int? previousCadenceElapsedSeconds;
  final hasCadenceTimingMismatch = cadenceSamples.any((sample) {
    final elapsedSeconds = sample.elapsedSeconds;
    final previousElapsedSeconds = previousCadenceElapsedSeconds;
    final isInvalid =
        elapsedSeconds > restoredPayload.durationSeconds ||
        (previousElapsedSeconds != null &&
            elapsedSeconds <= previousElapsedSeconds);
    previousCadenceElapsedSeconds = elapsedSeconds;
    return isInvalid;
  });
  final hasLegacyCadenceRangeMismatch = cadenceSamples.any(
    (sample) =>
        sample.cadenceSpmValue < _legacyCompleteRunMinCadenceSpm ||
        sample.cadenceSpmValue > _legacyCompleteRunMaxCadenceSpm,
  );
  final shouldRetryCadenceContractFailure =
      persistedSyncState == RunSyncState.syncNonRetryableFailure &&
      lastSyncFailureCode == 'invalid-argument' &&
      (hasCadenceTimingMismatch || hasLegacyCadenceRangeMismatch);
  return LocalPendingRunActivity(
    ownerUid: ownerUid,
    clientRunSessionId: clientRunSessionId,
    result: CompleteRunResult(
      clientRunSessionId: clientRunSessionId,
      activityId:
          _readString(source, 'activityId') ?? 'local-$clientRunSessionId',
      summaryId:
          _readString(source, 'summaryId') ??
          'local-summary-$clientRunSessionId',
      progressionEventId:
          _readString(source, 'progressionEventId') ??
          'local-progression-$clientRunSessionId',
      validationStatus: _readString(source, 'validationStatus') ?? 'validated',
      planCompletion: PlanCompletionResult(
        completed: _readBool(planCompletion, 'completed') ?? false,
        planEnrollmentId: _readString(planCompletion, 'planEnrollmentId'),
        scheduledWorkoutId: _readString(planCompletion, 'scheduledWorkoutId'),
      ),
      summary: _summaryFromJson(summary, restoredPayload),
      progressionDisplay: const ProgressionDisplayModel(
        xpDelta: 0,
        countsTowardLeaderboard: false,
        status: 'deferred',
        reason: 'progression_formula_deferred',
      ),
      xpUpdate: const XpUpdateDisplayModel(
        runnerName: 'Runiac Runner',
        earnedXpLabel: '+0 XP',
        totalXpLabel: 'Saved on this device',
        levelLabel: '--',
        nextLevelLabel: '--',
        progressTargetLabel: 'Sync pending',
        xpRemainingLabel: 'XP updates after sync',
        previousProgressFraction: 0,
        currentProgressFraction: 0,
        streakChangeLabel: 'Not updated yet',
        streakNote: 'We’ll retry when the service is available.',
        didLevelUp: false,
        xpAwardState: XpAwardState.syncPending,
        heroMessage: 'This run is saved locally. XP updates after sync.',
      ),
      message: _readString(source, 'message') ?? 'Saved locally.',
    ),
    payload: restoredPayload,
    syncAccepted: syncAccepted,
    syncState: shouldRetryCadenceContractFailure
        ? RunSyncState.syncRetryableFailure
        : persistedSyncState,
    syncAttemptCount: _readInt(source, 'syncAttemptCount') ?? 0,
    lastSyncAttemptedAt: _readDate(source, 'lastSyncAttemptedAt'),
    lastSyncFailureCode: lastSyncFailureCode,
    lastSyncFailureMessage: _readString(source, 'lastSyncFailureMessage'),
  );
}

RunSummarySnapshot _summaryFromJson(
  Map<String, Object?> source,
  LocalRunCompletionPayload payload,
) {
  final elevationSeries =
      _elevationAnalysisSeriesFromJson(_readMap(source, 'elevationSeries')) ??
      payload.elevationAnalysisSeries ??
      ElevationAnalysisSeries.unavailable(
        reason: payload.elevationUnavailableReason,
      );
  return RunSummarySnapshot(
    title: _readString(source, 'title') ?? 'Completed Run',
    dateLabel: _readString(source, 'dateLabel') ?? 'Today',
    timeLabel: _readString(source, 'timeLabel') ?? '--',
    distanceKm: _readString(source, 'distanceKm') ?? '0.00',
    avgPace: _readString(source, 'avgPace') ?? '--',
    duration: _readString(source, 'duration') ?? '--',
    avgHeartRate: _readString(source, 'avgHeartRate') ?? '--',
    calories: _readString(source, 'calories') ?? '--',
    routeName: _readString(source, 'routeName') ?? 'Private route',
    hasSufficientData: _readBool(source, 'hasSufficientData') ?? false,
    paceAnalysisSeries: _paceAnalysisSeriesFromJson(
      _readMap(source, 'paceAnalysisSeries'),
    ),
    cadenceAnalysisSeries:
        _cadenceAnalysisSeriesFromJson(
          _readMap(source, 'cadenceAnalysisSeries'),
        ) ??
        payload.cadenceAnalysisSeries,
    elevationSeries: elevationSeries,
    paceGraph: const PaceGraphDataBuilder().build(
      samples: payload.paceGraphSamples,
      durationSeconds: payload.durationSeconds,
      distanceMeters: payload.distanceMeters,
      averagePaceSecondsPerKm: payload.avgPaceSecondsPerKm > 0
          ? payload.avgPaceSecondsPerKm
          : null,
    ),
    route: _routeFromJson(_readMap(source, 'route')),
  );
}

LocalRunCompletionPayload _payloadFromJson(
  Map<String, Object?> source,
  String clientRunSessionId,
) {
  return LocalRunCompletionPayload(
    clientRunSessionId:
        _readString(source, 'clientRunSessionId') ?? clientRunSessionId,
    startedAt:
        _readDate(source, 'startedAt') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    completedAt:
        _readDate(source, 'completedAt') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    durationSeconds: _readInt(source, 'durationSeconds') ?? 0,
    distanceMeters: _readInt(source, 'distanceMeters') ?? 0,
    avgPaceSecondsPerKm: _readInt(source, 'avgPaceSecondsPerKm') ?? 0,
    source: _readString(source, 'source') ?? 'mobile',
    routePrivacy: _readString(source, 'routePrivacy') ?? 'private',
    routeSnapshot: _routeFromJson(_readMap(source, 'routeSnapshot')),
    userConfirmedLowDataSave:
        _readBool(source, 'userConfirmedLowDataSave') ?? false,
    activityTitle: _readString(source, 'activityTitle'),
    routeLabel: _readString(source, 'routeLabel'),
    clientAppVersion: _readString(source, 'clientAppVersion'),
    planEnrollmentId: _readString(source, 'planEnrollmentId'),
    scheduledWorkoutId: _readString(source, 'scheduledWorkoutId'),
    paceGraphSamples: [
      for (final rawSample in _readList(source, 'paceGraphSamples'))
        ?_paceGraphSampleFromJson(_readObjectMap(rawSample)),
    ],
    cadenceAnalysisSeries: _cadenceAnalysisSeriesFromJson(
      _readMap(source, 'cadenceAnalysisSeries'),
    ),
    elevationAnalysisSeries: _elevationAnalysisSeriesFromJson(
      _readMap(source, 'elevationAnalysisSeries'),
    ),
    elevationUnavailableReason:
        _enumByName(
          ElevationUnavailableReason.values,
          _readString(source, 'elevationUnavailableReason'),
        ) ??
        ElevationUnavailableReason.noElevationSeries,
  );
}

Map<String, Object?> _paceGraphSampleToJson(PaceGraphSample sample) {
  return <String, Object?>{
    'elapsedSeconds': sample.elapsedSeconds,
    'paceSecondsPerKm': sample.paceSecondsPerKm,
    if (sample.cumulativeDistanceMeters != null)
      'cumulativeDistanceMeters': sample.cumulativeDistanceMeters,
  };
}

PaceGraphSample? _paceGraphSampleFromJson(Map<String, Object?>? source) {
  if (source == null) {
    return null;
  }
  final elapsedSeconds = _readInt(source, 'elapsedSeconds');
  final paceSecondsPerKm = _readInt(source, 'paceSecondsPerKm');
  if (elapsedSeconds == null || paceSecondsPerKm == null) {
    return null;
  }
  return PaceGraphSample(
    elapsedSeconds: elapsedSeconds,
    paceSecondsPerKm: paceSecondsPerKm,
    cumulativeDistanceMeters: _readInt(source, 'cumulativeDistanceMeters'),
  );
}

Map<String, Object?> _paceAnalysisSeriesToJson(PaceAnalysisSeries series) {
  return <String, Object?>{
    'source': series.source.name,
    'confidence': series.confidence.name,
    'samples': [
      for (final sample in series.samples) _paceAnalysisSampleToJson(sample),
    ],
  };
}

PaceAnalysisSeries? _paceAnalysisSeriesFromJson(Map<String, Object?>? source) {
  if (source == null) {
    return null;
  }
  final seriesSource = _enumByName(
    PaceAnalysisSource.values,
    _readString(source, 'source'),
  );
  final confidence = _enumByName(
    PaceAnalysisConfidence.values,
    _readString(source, 'confidence'),
  );
  if (seriesSource == null || confidence == null) {
    return null;
  }
  final samples = [
    for (final rawSample in _readList(source, 'samples'))
      ?_paceAnalysisSampleFromJson(_readObjectMap(rawSample)),
  ];
  try {
    return PaceAnalysisSeries(
      source: seriesSource,
      confidence: confidence,
      samples: samples,
    );
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _paceAnalysisSampleToJson(PaceAnalysisSample sample) {
  return <String, Object?>{
    'elapsedSeconds': sample.elapsedSeconds,
    'cumulativeDistanceMeters': sample.cumulativeDistanceMeters,
    'paceSecondsPerKm': sample.paceSecondsPerKm,
    'status': sample.status.name,
    'rejectionReason': sample.rejectionReason.name,
  };
}

PaceAnalysisSample? _paceAnalysisSampleFromJson(Map<String, Object?>? source) {
  if (source == null) {
    return null;
  }
  final elapsedSeconds = _readInt(source, 'elapsedSeconds');
  final cumulativeDistanceMeters = _readDouble(
    source,
    'cumulativeDistanceMeters',
  );
  final paceSecondsPerKm = _readInt(source, 'paceSecondsPerKm');
  final status = _enumByName(
    PaceAnalysisSampleStatus.values,
    _readString(source, 'status'),
  );
  final rejectionReason =
      _enumByName(
        PaceAnalysisSampleRejectionReason.values,
        _readString(source, 'rejectionReason'),
      ) ??
      PaceAnalysisSampleRejectionReason.none;
  if (elapsedSeconds == null ||
      cumulativeDistanceMeters == null ||
      paceSecondsPerKm == null ||
      status == null) {
    return null;
  }
  try {
    return PaceAnalysisSample(
      elapsedSeconds: elapsedSeconds,
      cumulativeDistanceMeters: cumulativeDistanceMeters,
      paceSecondsPerKm: paceSecondsPerKm,
      status: status,
      rejectionReason: rejectionReason,
    );
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _cadenceAnalysisSeriesToJson(
  CadenceAnalysisSeries series,
) {
  return <String, Object?>{
    'source': series.source.name,
    'confidence': series.confidence.name,
    'samples': [
      for (final sample in series.samples) _cadenceAnalysisSampleToJson(sample),
    ],
  };
}

CadenceAnalysisSeries? _cadenceAnalysisSeriesFromJson(
  Map<String, Object?>? source,
) {
  if (source == null) {
    return null;
  }
  final seriesSource = _enumByName(
    CadenceAnalysisSource.values,
    _readString(source, 'source'),
  );
  final confidence = _enumByName(
    CadenceAnalysisConfidence.values,
    _readString(source, 'confidence'),
  );
  if (seriesSource == null || confidence == null) {
    return null;
  }
  final samples = [
    for (final rawSample in _readList(source, 'samples'))
      ?_cadenceAnalysisSampleFromJson(_readObjectMap(rawSample)),
  ];
  try {
    return CadenceAnalysisSeries(
      source: seriesSource,
      confidence: confidence,
      samples: samples,
    );
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _cadenceAnalysisSampleToJson(
  CadenceAnalysisSample sample,
) {
  return <String, Object?>{
    'elapsedSeconds': sample.elapsedSeconds,
    'cadenceSpm': sample.cadenceSpmValue,
    'status': sample.status.name,
    'rejectionReason': sample.rejectionReason.name,
  };
}

CadenceAnalysisSample? _cadenceAnalysisSampleFromJson(
  Map<String, Object?>? source,
) {
  if (source == null) {
    return null;
  }
  final elapsedSeconds = _readInt(source, 'elapsedSeconds');
  final cadenceSpm = _readDouble(source, 'cadenceSpm');
  final status = _enumByName(
    CadenceAnalysisSampleStatus.values,
    _readString(source, 'status'),
  );
  final rejectionReason =
      _enumByName(
        CadenceAnalysisSampleRejectionReason.values,
        _readString(source, 'rejectionReason'),
      ) ??
      CadenceAnalysisSampleRejectionReason.none;
  if (elapsedSeconds == null || cadenceSpm == null || status == null) {
    return null;
  }
  try {
    return CadenceAnalysisSample(
      elapsedSeconds: elapsedSeconds,
      cadenceSpm: cadenceSpm,
      status: status,
      rejectionReason: rejectionReason,
    );
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _elevationAnalysisSeriesToJson(
  ElevationAnalysisSeries series,
) {
  return <String, Object?>{
    'source': series.source.name,
    'confidence': series.confidence.name,
    'unavailableReason': series.unavailableReason.name,
    'samples': [
      for (final sample in series.samples)
        _elevationAnalysisSampleToJson(sample),
    ],
  };
}

ElevationAnalysisSeries? _elevationAnalysisSeriesFromJson(
  Map<String, Object?>? source,
) {
  if (source == null) {
    return null;
  }
  final seriesSource = _enumByName(
    ElevationAnalysisSource.values,
    _readString(source, 'source'),
  );
  final confidence = _enumByName(
    ElevationAnalysisConfidence.values,
    _readString(source, 'confidence'),
  );
  final unavailableReason =
      _enumByName(
        ElevationUnavailableReason.values,
        _readString(source, 'unavailableReason'),
      ) ??
      ElevationUnavailableReason.none;
  if (seriesSource == null || confidence == null) {
    return null;
  }
  final samples = [
    for (final rawSample in _readList(source, 'samples'))
      ?_elevationAnalysisSampleFromJson(_readObjectMap(rawSample)),
  ];
  try {
    return ElevationAnalysisSeries(
      source: seriesSource,
      confidence: confidence,
      samples: samples,
      unavailableReason: unavailableReason,
    );
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _elevationAnalysisSampleToJson(
  ElevationAnalysisSample sample,
) {
  return <String, Object?>{
    'distanceKm': sample.distanceKm,
    'elevationMeters': sample.elevationMeters,
  };
}

ElevationAnalysisSample? _elevationAnalysisSampleFromJson(
  Map<String, Object?>? source,
) {
  if (source == null) {
    return null;
  }
  final distanceKm = _readDouble(source, 'distanceKm');
  final elevationMeters = _readDouble(source, 'elevationMeters');
  if (distanceKm == null || elevationMeters == null) {
    return null;
  }
  return ElevationAnalysisSample(
    distanceKm: distanceKm,
    elevationMeters: elevationMeters,
  );
}

Map<String, Object?> _routeToJson(RunRouteSnapshot route) {
  return <String, Object?>{
    'segments': [
      for (final segment in route.segments)
        [for (final sample in segment) _locationSampleToJson(sample)],
    ],
    if (route.lastKnownLocation != null)
      'lastKnownLocation': _locationSampleToJson(route.lastKnownLocation!),
  };
}

Map<String, Object?> _locationSampleToJson(RunLocationSample sample) {
  return <String, Object?>{
    'recordedAt': sample.recordedAt.toUtc().toIso8601String(),
    'latitude': sample.latitude,
    'longitude': sample.longitude,
    if (sample.altitudeMeters != null) 'altitudeMeters': sample.altitudeMeters,
    if (sample.horizontalAccuracyMeters != null)
      'horizontalAccuracyMeters': sample.horizontalAccuracyMeters,
    if (sample.speedMetersPerSecond != null)
      'speedMetersPerSecond': sample.speedMetersPerSecond,
  };
}

RunRouteSnapshot _routeFromJson(Map<String, Object?>? source) {
  if (source == null) {
    return RunRouteSnapshot.empty;
  }

  final segments = <List<RunLocationSample>>[];
  for (final rawSegment in _readList(source, 'segments')) {
    if (rawSegment is! List) {
      continue;
    }
    final segment = <RunLocationSample>[];
    for (final rawSample in rawSegment) {
      final sample = _locationSampleFromJson(_readObjectMap(rawSample));
      if (sample != null) {
        segment.add(sample);
      }
    }
    if (segment.isNotEmpty) {
      segments.add(segment);
    }
  }

  final lastKnownLocation = _locationSampleFromJson(
    _readMap(source, 'lastKnownLocation'),
  );
  return RunRouteSnapshot(
    segments: segments,
    lastKnownLocation: lastKnownLocation ?? _lastRoutePoint(segments),
  );
}

RunLocationSample? _locationSampleFromJson(Map<String, Object?>? source) {
  if (source == null) {
    return null;
  }
  final recordedAt = _readDate(source, 'recordedAt');
  final latitude = _readDouble(source, 'latitude');
  final longitude = _readDouble(source, 'longitude');
  if (recordedAt == null || latitude == null || longitude == null) {
    return null;
  }
  return RunLocationSample(
    recordedAt: recordedAt,
    latitude: latitude,
    longitude: longitude,
    altitudeMeters: _readDouble(source, 'altitudeMeters'),
    horizontalAccuracyMeters: _readDouble(source, 'horizontalAccuracyMeters'),
    speedMetersPerSecond: _readDouble(source, 'speedMetersPerSecond'),
  );
}

RunLocationSample? _lastRoutePoint(List<List<RunLocationSample>> segments) {
  for (final segment in segments.reversed) {
    if (segment.isNotEmpty) {
      return segment.last;
    }
  }
  return null;
}

Map<String, Object?>? _readObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

Map<String, Object?>? _readMap(Map<String, Object?> source, String key) {
  return _readObjectMap(source[key]);
}

List<Object?> _readList(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

String? _readString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

int? _readInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    return value.round();
  }
  return null;
}

double? _readDouble(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  return null;
}

bool? _readBool(Map<String, Object?> source, String key) {
  final value = source[key];
  return value is bool ? value : null;
}

DateTime? _readDate(Map<String, Object?> source, String key) {
  final value = _readString(source, key);
  return value == null ? null : DateTime.tryParse(value);
}

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) {
    return null;
  }
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return null;
}
