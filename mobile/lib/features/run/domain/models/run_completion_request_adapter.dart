import 'cadence_analysis_series.dart';
import 'local_run_completion_payload.dart';
import 'run_completion_request_payload_serializer.dart';

class RunCompletionRequestAdapter {
  const RunCompletionRequestAdapter._();

  static const int _maxBackendCadenceAnalysisSamples = 720;

  static Map<String, Object?> toBackendRequest(
    LocalRunCompletionPayload payload,
  ) {
    final routePreview =
        RunCompletionRequestPayloadSerializer.routePreviewToBackendMap(
          payload.routeSnapshot,
        );
    final paceAnalysisSeries =
        RunCompletionRequestPayloadSerializer.paceAnalysisSeriesToBackendMap(
          payload.paceGraphSamples,
          durationSeconds: payload.durationSeconds,
          distanceMeters: payload.distanceMeters,
        );
    final cadenceAnalysisSeries = payload.cadenceAnalysisSeries;
    final cadenceSamples = cadenceAnalysisSeries == null
        ? const <CadenceAnalysisSample>[]
        : _cadenceSamplesForBackend(
            cadenceAnalysisSeries.validAcceptedSamples,
            durationSeconds: payload.durationSeconds,
          );
    return <String, Object?>{
      'clientRunSessionId': payload.clientRunSessionId,
      'startedAt': _toBackendIsoString(payload.startedAt),
      'completedAt': _toBackendIsoString(payload.completedAt),
      'durationSeconds': payload.durationSeconds,
      'activeDurationSeconds': payload.activeDurationSeconds,
      'elapsedWallSeconds': payload.elapsedWallSeconds,
      'pausedDurationSeconds': payload.pausedDurationSeconds,
      'distanceMeters': payload.distanceMeters,
      'avgPaceSecondsPerKm': payload.avgPaceSecondsPerKm,
      'source': 'mobile',
      'routePrivacy': payload.routePrivacy,
      if (payload.userConfirmedLowDataSave) 'userConfirmedLowDataSave': true,
      if (payload.activityTitle != null) 'activityTitle': payload.activityTitle,
      if (payload.routeLabel != null) 'routeLabel': payload.routeLabel,
      if (payload.clientAppVersion != null)
        'clientAppVersion': payload.clientAppVersion,
      if (payload.planEnrollmentId != null)
        'planEnrollmentId': payload.planEnrollmentId,
      if (payload.scheduledWorkoutId != null)
        'scheduledWorkoutId': payload.scheduledWorkoutId,
      ...RunCompletionRequestPayloadSerializer.optionalField(
        'routePreview',
        routePreview,
      ),
      ...RunCompletionRequestPayloadSerializer.optionalField(
        'paceAnalysisSeries',
        paceAnalysisSeries,
      ),
      if (payload.elevationAnalysisSeries case final elevationSeries?
          when elevationSeries.validSamples.isNotEmpty)
        'elevationSeries':
            RunCompletionRequestPayloadSerializer.elevationAnalysisSeriesToBackendMap(
              elevationSeries,
            ),
      if (cadenceAnalysisSeries != null && cadenceSamples.isNotEmpty)
        'cadenceAnalysisSeries': _cadenceAnalysisSeriesToBackendMap(
          cadenceAnalysisSeries,
          cadenceSamples,
        ),
    };
  }

  static Map<String, Object?> _cadenceAnalysisSeriesToBackendMap(
    CadenceAnalysisSeries cadenceAnalysisSeries,
    List<CadenceAnalysisSample> samples,
  ) {
    return <String, Object?>{
      'source': cadenceAnalysisSeries.source.name,
      'confidence': cadenceAnalysisSeries.confidence.name,
      'samples': [
        for (final sample in samples)
          <String, Object?>{
            'elapsedSeconds': sample.elapsedSeconds,
            'cadenceSpm': sample.cadenceSpm,
            'status': sample.status.name,
            if (sample.rejectionReason !=
                CadenceAnalysisSampleRejectionReason.none)
              'rejectionReason': sample.rejectionReason.name,
          },
      ],
    };
  }

  static List<CadenceAnalysisSample> _cadenceSamplesForBackend(
    List<CadenceAnalysisSample> source, {
    required int durationSeconds,
  }) {
    final samples = <CadenceAnalysisSample>[];
    int? previousElapsedSeconds;
    for (final sample in source) {
      if (sample.elapsedSeconds > durationSeconds ||
          (previousElapsedSeconds != null &&
              sample.elapsedSeconds <= previousElapsedSeconds)) {
        continue;
      }
      samples.add(sample);
      previousElapsedSeconds = sample.elapsedSeconds;
    }
    if (samples.length <= _maxBackendCadenceAnalysisSamples) {
      return samples;
    }
    return <CadenceAnalysisSample>[
      for (var index = 0; index < _maxBackendCadenceAnalysisSamples; index += 1)
        samples[(_sourceCadenceSampleIndex(index, samples.length))],
    ];
  }

  static int _sourceCadenceSampleIndex(int targetIndex, int sourceLength) {
    if (_maxBackendCadenceAnalysisSamples == 1) {
      return 0;
    }
    return (targetIndex *
            (sourceLength - 1) /
            (_maxBackendCadenceAnalysisSamples - 1))
        .round();
  }

  static String _toBackendIsoString(DateTime value) {
    final utc = value.toUtc();
    final millisecondDate = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
    );
    return millisecondDate.toIso8601String();
  }
}
