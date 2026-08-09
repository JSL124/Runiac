import 'package:flutter/foundation.dart';

import '../models/run_location_sample.dart';
import '../models/run_map_view_state.dart';
import '../models/run_motion_evidence.dart';
import '../models/run_cadence_sample.dart';
import '../models/elevation_analysis_series.dart';
import '../models/run_tracking_diagnostics.dart';
import '../models/run_tracking_state.dart';
import '../models/cadence_analysis_series.dart';
import 'local_pace_graph_sample_deriver.dart';
import 'pace_graph_data_builder.dart';
import 'run_distance_calculator.dart';
import 'run_movement_classifier.dart';

/// Accumulates one run in progress from raw GPS and motion samples.
///
/// This is the single place that decides what a location sample is allowed to
/// contribute to. A sample can be accepted for distance, for the drawn route,
/// for moving time, or for none of those, and the four decisions are
/// independent — GPS drift while the runner stands still must not add distance,
/// but it should still keep the map centred.
///
/// The session also owns auto-pause and auto-resume. It pauses when the runner
/// stops (or stops sending samples) for longer than the matching dwell, and
/// resumes on sustained real movement. `RunMovementClassifier` makes the
/// per-sample judgement; this class holds the state across samples — anchors,
/// candidate streaks and dwell timers — that a single sample cannot express.
///
/// All thresholds are constructor parameters so tests can drive the state
/// machine deterministically instead of waiting on real time or real GPS.
class LocalRunTrackingSession {
  LocalRunTrackingSession({
    required this.startedAt,
    this.source = 'local_simulation',
    this.distanceCalculator = const RunDistanceCalculator(),
    this.maxAcceptedSpeedMetersPerSecond = 12,
    this.maxAcceptedHorizontalAccuracyMeters = 100,
    this.preMovementAutoPauseDwell = const Duration(seconds: 5),
    this.noSampleAutoPauseDwell = const Duration(seconds: 5),
    this.movingToStoppedAutoPauseDwell = const Duration(seconds: 7),
    this.stationaryDriftDistanceMeters = 3,
    this.resumeMovementDistanceMeters = 6,
    this.resumeSpeedMetersPerSecond = 1,
    this.stationarySpeedMetersPerSecond = 0.5,
    this.suspiciousSpeedMetersPerSecond = 4.5,
    this.abnormalTransportSpeedMetersPerSecond = 6.5,
    this.abnormalSustainedWindow = const Duration(seconds: 10),
    this.abnormalSustainedSampleCount = 3,
    this.normalResumeMinSpeedMetersPerSecond = 0.8,
    this.normalResumeMaxSpeedMetersPerSecond = 4.0,
    this.maxNoSampleStationaryAnchorAge = const Duration(seconds: 30),
    this.movementClassifier = const RunMovementClassifier(),
  }) : _activeTimelineStartedAt = startedAt;

  final DateTime startedAt;
  final String source;
  final double maxAcceptedSpeedMetersPerSecond;
  final double maxAcceptedHorizontalAccuracyMeters;
  final Duration preMovementAutoPauseDwell;
  final Duration noSampleAutoPauseDwell;
  final Duration movingToStoppedAutoPauseDwell;
  final double stationaryDriftDistanceMeters;
  final double resumeMovementDistanceMeters;
  final double resumeSpeedMetersPerSecond;
  final double stationarySpeedMetersPerSecond;
  final double suspiciousSpeedMetersPerSecond;
  final double abnormalTransportSpeedMetersPerSecond;
  final Duration abnormalSustainedWindow;
  final int abnormalSustainedSampleCount;
  final double normalResumeMinSpeedMetersPerSecond;
  final double normalResumeMaxSpeedMetersPerSecond;
  final Duration maxNoSampleStationaryAnchorAge;
  final RunDistanceCalculator distanceCalculator;
  final RunMovementClassifier movementClassifier;

  static const double _preMovementJitterCandidateMaxMeters = 25;
  static const String _autoPauseQaLogPrefix = 'RUNIAC_AUTOPAUSE_QA';
  static const bool _autoPauseQaLogsEnabled = bool.fromEnvironment(
    'RUNIAC_AUTOPAUSE_QA_LOGS',
  );
  static const String _gpsAcceptanceQaLogPrefix = 'RUNIAC_GPS_ACCEPTANCE_QA';
  static const bool runiacGpsAcceptanceQaLogsEnabled = bool.fromEnvironment(
    'RUNIAC_GPS_ACCEPTANCE_QA_LOGS',
  );

  bool _isActive = true;
  bool _needsAnchorSample = false;
  bool _suppressedMovementNeedsAnchor = false;
  Duration _movingDuration = Duration.zero;
  Duration _trackingDuration = Duration.zero;
  double _distanceMeters = 0;
  int _currentPaceSecondsPerKm = 0;
  RunMovementStatus _movementStatus = RunMovementStatus.moving;
  RunTrackingDiagnostics _diagnostics = const RunTrackingDiagnostics.initial();
  RunLocationSample? _currentPositionSample;
  RunLocationSample? _lastAcceptedSample;
  RunLocationSample? _lastRouteSample;
  RunLocationSample? _autoResumeCandidateSample;
  RunLocationSample? _preMovementCandidateSample;
  RunLocationSample? _abnormalCandidateStartedSample;
  int _abnormalCandidateCount = 0;
  RunLocationSample? _abnormalResumeAnchorSample;
  int _abnormalResumeCandidateCount = 0;
  DateTime? _stationaryStartedAt;
  double _stationaryCumulativeMovementMeters = 0;
  bool _suppressedMovingTimeInCurrentAdvance = false;
  DateTime _activeTimelineStartedAt;
  Duration _activeTimelineOffsetAtStart = Duration.zero;
  final List<List<RunLocationSample>> _acceptedSampleSegments =
      <List<RunLocationSample>>[];
  final List<List<LocalPaceGraphSamplePoint>> _acceptedGraphSampleSegments =
      <List<LocalPaceGraphSamplePoint>>[];
  final List<({CadenceAnalysisSample analysis, DateTime recordedAt})>
  _cadenceAnalysisSamples =
      <({CadenceAnalysisSample analysis, DateTime recordedAt})>[];

  Duration get trackingDuration => _trackingDuration;
  int get activeDurationSeconds => _movingDuration.inSeconds;
  int get trackingDurationSeconds => _trackingDuration.inSeconds;
  int get distanceMeters => _distanceMeters.round();
  int get currentPaceSecondsPerKm => _currentPaceSecondsPerKm;
  int get acceptedSampleCount => _diagnostics.acceptedSampleCount;
  int get rejectedSampleCount => _diagnostics.rejectedSampleCount;
  RunMovementStatus get movementStatus => _movementStatus;
  RunTrackingDiagnostics get diagnostics => _diagnostics;
  List<PaceGraphSample> paceGraphSamples() {
    final graphSamples =
        LocalPaceGraphSampleDeriver(
          distanceCalculator: distanceCalculator,
        ).deriveFromActiveElapsedSegments(
          acceptedSampleSegments: _acceptedGraphSampleSegments,
        );
    return List<PaceGraphSample>.unmodifiable(graphSamples);
  }

  CadenceAnalysisSeries? cadenceAnalysisSeries({DateTime? completedAt}) {
    final durationBoundedSamples = _cadenceAnalysisSamples
        .where(
          (sample) =>
              sample.analysis.elapsedSeconds <= trackingDurationSeconds &&
              (completedAt == null || !sample.recordedAt.isAfter(completedAt)),
        )
        .map((sample) => sample.analysis)
        .toList(growable: false);
    if (durationBoundedSamples.isEmpty) {
      return null;
    }
    return CadenceAnalysisSeries.phoneMotionEstimated(
      samples: durationBoundedSamples,
    );
  }

  ElevationAnalysisSeries? elevationAnalysisSeries() {
    final samples = _elevationAnalysisSamples();

    if (samples.length < defaultMinimumElevationAnalysisSamples) {
      return null;
    }
    return ElevationAnalysisSeries.localAccepted(samples: samples);
  }

  ElevationUnavailableReason elevationUnavailableReason() {
    var acceptedSampleCount = 0;
    var acceptedAltitudeSampleCount = 0;

    for (final segment in _acceptedSampleSegments) {
      for (final sample in segment) {
        acceptedSampleCount += 1;
        final altitude = sample.altitudeMeters;
        if (altitude != null && altitude.isFinite) {
          acceptedAltitudeSampleCount += 1;
        }
      }
    }

    if (acceptedSampleCount == 0) {
      return ElevationUnavailableReason.noAcceptedMovementSamples;
    }
    if (acceptedAltitudeSampleCount == 0) {
      return ElevationUnavailableReason.noAcceptedAltitudeSamples;
    }
    if (_elevationAnalysisSamples().length <
        defaultMinimumElevationAnalysisSamples) {
      return ElevationUnavailableReason.tooFewValidAltitudeSamples;
    }
    return ElevationUnavailableReason.none;
  }

  List<ElevationAnalysisSample> _elevationAnalysisSamples() {
    final samples = <ElevationAnalysisSample>[];
    var cumulativeDistanceMeters = 0.0;

    for (final segment in _acceptedSampleSegments) {
      if (segment.isEmpty) {
        continue;
      }
      final first = segment.first;
      final firstAltitude = first.altitudeMeters;
      if (firstAltitude != null && firstAltitude.isFinite) {
        _addElevationSample(
          samples,
          distanceMeters: cumulativeDistanceMeters,
          elevationMeters: firstAltitude,
        );
      }

      for (var index = 1; index < segment.length; index += 1) {
        final previous = segment[index - 1];
        final current = segment[index];
        final segmentMeters = distanceCalculator.distanceMeters(
          previous,
          current,
        );
        if (!segmentMeters.isFinite || segmentMeters <= 0) {
          continue;
        }
        cumulativeDistanceMeters += segmentMeters;

        final altitude = current.altitudeMeters;
        if (altitude == null || !altitude.isFinite) {
          continue;
        }
        _addElevationSample(
          samples,
          distanceMeters: cumulativeDistanceMeters,
          elevationMeters: altitude,
        );
      }
    }

    return samples;
  }

  void _addElevationSample(
    List<ElevationAnalysisSample> samples, {
    required double distanceMeters,
    required double elevationMeters,
  }) {
    final distanceKm = distanceMeters / 1000;
    if (samples.isNotEmpty && distanceKm <= samples.last.distanceKm) {
      return;
    }
    samples.add(
      ElevationAnalysisSample(
        distanceKm: distanceKm,
        elevationMeters: elevationMeters,
      ),
    );
  }

  RunMapViewState get mapViewState {
    return RunMapViewState(
      currentPosition: _currentPositionSample,
      acceptedRouteSegments: _acceptedSampleSegments,
    );
  }

  int get averagePaceSecondsPerKm {
    if (_distanceMeters <= 0) {
      return 0;
    }
    return (activeDurationSeconds / (_distanceMeters / 1000)).floor();
  }

  void advanceBy(
    Duration delta, {
    Iterable<RunLocationSample> samples = const <RunLocationSample>[],
    Iterable<RunMotionEvidence> motionEvidence = const <RunMotionEvidence>[],
  }) {
    if (!_isActive || delta <= Duration.zero) {
      return;
    }

    final movementStatusBeforeAdvance = _movementStatus;
    final distanceBeforeAdvance = _distanceMeters;
    final sampleList = samples.toList();
    final motionEvidenceList = motionEvidence.toList();
    _suppressedMovingTimeInCurrentAdvance = false;
    _trackingDuration += delta;
    for (final sample in sampleList) {
      _acceptSample(sample, motionEvidenceList);
    }
    if (sampleList.isEmpty) {
      _recordNoSampleDwell(motionEvidenceList);
    }

    final becameAutoPausedWithoutDistance =
        movementStatusBeforeAdvance == RunMovementStatus.moving &&
        _movementStatus == RunMovementStatus.autoPaused &&
        _distanceMeters == distanceBeforeAdvance;
    if (movementStatusBeforeAdvance == RunMovementStatus.moving &&
        _movementStatus == RunMovementStatus.moving &&
        !becameAutoPausedWithoutDistance &&
        !_suppressedMovingTimeInCurrentAdvance) {
      _movingDuration += delta;
    }
    _logAdvance(delta, sampleList.isEmpty);
  }

  void addCadenceSample(RunCadenceSample sample) {
    if (!_isActive ||
        sample.source != CadenceSource.phoneMotion ||
        !sample.isUsable ||
        sample.recordedAt.isBefore(_activeTimelineStartedAt)) {
      return;
    }
    final calculatedElapsedSeconds = _activeElapsedSecondsForTime(
      sample.recordedAt,
    );
    final lastCadenceSample = _cadenceAnalysisSamples.lastOrNull;
    if (lastCadenceSample != null &&
        !sample.recordedAt.isAfter(lastCadenceSample.recordedAt)) {
      return;
    }
    if (lastCadenceSample != null &&
        calculatedElapsedSeconds < lastCadenceSample.analysis.elapsedSeconds) {
      return;
    }
    final cadenceSample = CadenceAnalysisSample.accepted(
      elapsedSeconds: calculatedElapsedSeconds,
      cadenceSpm: sample.stepsPerMinute.round(),
    );
    final storedSample = (
      analysis: cadenceSample,
      recordedAt: sample.recordedAt,
    );
    if (lastCadenceSample?.analysis.elapsedSeconds ==
        calculatedElapsedSeconds) {
      _cadenceAnalysisSamples[_cadenceAnalysisSamples.length - 1] =
          storedSample;
      return;
    }
    _cadenceAnalysisSamples.add(storedSample);
  }

  void pause() {
    _isActive = false;
  }

  void resume({required DateTime resumedAt, required Duration activeOffset}) {
    _isActive = true;
    _activeTimelineStartedAt = resumedAt;
    _activeTimelineOffsetAtStart = activeOffset;
    _needsAnchorSample = true;
    _suppressedMovementNeedsAnchor = false;
    _setMovementStatus(RunMovementStatus.moving, 'sessionResume');
    _autoResumeCandidateSample = null;
    _preMovementCandidateSample = null;
    _resetAbnormalCandidate();
    _resetAbnormalResumeCandidate();
    _stationaryStartedAt = null;
    _stationaryCumulativeMovementMeters = 0;
  }

  void updateLocationAccuracyStatus(
    RunTrackingLocationAccuracyStatus locationAccuracyStatus,
  ) {
    _diagnostics = _diagnostics.withLocationAccuracyStatus(
      locationAccuracyStatus,
    );
  }

  void _acceptSample(
    RunLocationSample sample,
    Iterable<RunMotionEvidence> motionEvidence,
  ) {
    _logGpsAcceptanceSample(sample);
    _diagnostics = _diagnostics.recordSampleReceived(sample);

    final rejectionReason = _sampleRejectionReason(sample);
    if (rejectionReason != RunLocationRejectionReason.none) {
      _rejectSample(sample, rejectionReason);
      return;
    }

    final previous = _lastAcceptedSample;
    if (previous == null) {
      _addAcceptedSampleSegment(<RunLocationSample>[sample]);
      _recordAcceptedCurrentSample(
        sample,
        reason: 'firstAcceptedSample',
        acceptedForDistanceOrRoute: true,
      );
      _lastRouteSample = sample;
      _autoResumeCandidateSample = null;
      _preMovementCandidateSample = null;
      _resetAbnormalCandidate();
      _resetAbnormalResumeCandidate();
      _stationaryCumulativeMovementMeters = 0;
      return;
    }

    if (_suppressedMovementNeedsAnchor) {
      if (_isSameSample(previous, sample)) {
        _logGpsAcceptanceRejected(
          sample: sample,
          reason: 'duplicateSuppressedAnchorSample',
        );
        _logLocationSample(
          sample: sample,
          acceptedSample: false,
          reason: 'duplicateSuppressedAnchorSample',
        );
        return;
      }
      if (_isSuppressedCandidateFromPrevious(previous, sample)) {
        _acceptMovementSample(sample, motionEvidence);
        return;
      }

      _addAcceptedSampleSegment(<RunLocationSample>[sample]);
      _suppressedMovementNeedsAnchor = false;
      _lastRouteSample = sample;
      _autoResumeCandidateSample = null;
      _preMovementCandidateSample = null;
      _resetAbnormalCandidate();
      _resetAbnormalResumeCandidate();
      _stationaryCumulativeMovementMeters = 0;
      _recordAcceptedCurrentSample(
        sample,
        reason: 'suppressedAnchorReset',
        acceptedForDistanceOrRoute: true,
      );
      return;
    }

    if (_needsAnchorSample) {
      if (_isSameSample(previous, sample)) {
        _logGpsAcceptanceRejected(
          sample: sample,
          reason: 'duplicateResumeAnchorSample',
        );
        _logLocationSample(
          sample: sample,
          acceptedSample: false,
          reason: 'duplicateResumeAnchorSample',
        );
        return;
      }

      _addAcceptedSampleSegment(<RunLocationSample>[sample]);
      _needsAnchorSample = false;
      _lastRouteSample = sample;
      _autoResumeCandidateSample = null;
      _preMovementCandidateSample = null;
      _resetAbnormalCandidate();
      _resetAbnormalResumeCandidate();
      _stationaryCumulativeMovementMeters = 0;
      _recordAcceptedCurrentSample(
        sample,
        reason: 'resumeAnchorSample',
        acceptedForDistanceOrRoute: true,
      );
      return;
    }

    _acceptMovementSample(sample, motionEvidence);
  }

  bool _acceptMovementSample(
    RunLocationSample sample,
    Iterable<RunMotionEvidence> motionEvidence,
  ) {
    final previousAccepted = _lastAcceptedSample;
    if (previousAccepted != null &&
        !sample.recordedAt.isAfter(previousAccepted.recordedAt)) {
      _rejectSample(
        sample,
        RunLocationRejectionReason.duplicateOrOutOfOrderTimestamp,
      );
      return false;
    }

    final previousRouteSample = _lastRouteSample ?? previousAccepted;
    final resumeCandidateSample =
        _movementStatus == RunMovementStatus.autoPaused
        ? _autoResumeCandidateSample
        : null;
    final movementAnchorSample = resumeCandidateSample ?? previousRouteSample;
    if (previousRouteSample == null) {
      _addAcceptedSampleSegment(<RunLocationSample>[sample]);
      _lastRouteSample = sample;
      _autoResumeCandidateSample = null;
      _preMovementCandidateSample = null;
      _resetAbnormalCandidate();
      _resetAbnormalResumeCandidate();
      _stationaryCumulativeMovementMeters = 0;
      _recordAcceptedCurrentSample(
        sample,
        reason: 'noRouteAnchor',
        acceptedForDistanceOrRoute: true,
      );
      return true;
    }
    if (movementAnchorSample == null) {
      _recordAcceptedCurrentSample(
        sample,
        reason: 'resumeCandidateAnchor',
        acceptedForDistanceOrRoute: false,
      );
      _autoResumeCandidateSample = sample;
      return true;
    }

    final elapsedSeconds =
        sample.recordedAt
            .difference(movementAnchorSample.recordedAt)
            .inMilliseconds /
        1000;
    if (elapsedSeconds <= 0) {
      _rejectSample(
        sample,
        RunLocationRejectionReason.duplicateOrOutOfOrderTimestamp,
      );
      return false;
    }
    final segmentDistanceMeters = distanceCalculator.distanceMeters(
      movementAnchorSample,
      sample,
    );
    if (!segmentDistanceMeters.isFinite) {
      _rejectSample(sample, RunLocationRejectionReason.nonFiniteDistance);
      return false;
    }
    final previousAcceptedDistanceMeters = distanceCalculator.distanceMeters(
      previousAccepted ?? previousRouteSample,
      sample,
    );
    if (!previousAcceptedDistanceMeters.isFinite) {
      _rejectSample(sample, RunLocationRejectionReason.nonFiniteDistance);
      return false;
    }
    final previousAcceptedElapsedSeconds =
        sample.recordedAt
            .difference((previousAccepted ?? previousRouteSample).recordedAt)
            .inMilliseconds /
        1000;
    final usablePreviousAcceptedDistanceMeters =
        previousAcceptedElapsedSeconds > 0 &&
            previousAcceptedDistanceMeters / previousAcceptedElapsedSeconds <=
                maxAcceptedSpeedMetersPerSecond
        ? previousAcceptedDistanceMeters
        : 0;

    final calculatedSpeedMetersPerSecond =
        segmentDistanceMeters / elapsedSeconds;
    final hardRejectSpeedMetersPerSecond = _hardRejectSpeedMetersPerSecond(
      sample: sample,
      calculatedSpeedMetersPerSecond: calculatedSpeedMetersPerSecond,
    );
    if (hardRejectSpeedMetersPerSecond > maxAcceptedSpeedMetersPerSecond) {
      _rejectSample(sample, RunLocationRejectionReason.impossibleJump);
      return false;
    }
    final speedMetersPerSecond = _classificationSpeedMetersPerSecond(
      sample: sample,
      calculatedSpeedMetersPerSecond: calculatedSpeedMetersPerSecond,
    );

    final speedBand = movementClassifier.classifyMovementSpeed(
      speedMetersPerSecond: speedMetersPerSecond,
      suspiciousSpeedMetersPerSecond: suspiciousSpeedMetersPerSecond,
      abnormalSpeedMetersPerSecond: abnormalTransportSpeedMetersPerSecond,
      hardRejectSpeedMetersPerSecond: maxAcceptedSpeedMetersPerSecond,
      normalResumeMinSpeedMetersPerSecond: normalResumeMinSpeedMetersPerSecond,
      normalResumeMaxSpeedMetersPerSecond: normalResumeMaxSpeedMetersPerSecond,
    );
    if (speedBand == RunMovementSpeedBand.suspiciousCandidate ||
        speedBand == RunMovementSpeedBand.abnormalCandidate ||
        _movementStatus == RunMovementStatus.abnormalPaused) {
      _logClassifierResult(
        previousMovementStatus: _movementStatus,
        nextMovementStatus: _movementStatus,
        movingEvidence: false,
        stationaryEvidence: false,
        abnormalEvidence:
            speedBand == RunMovementSpeedBand.abnormalCandidate ||
            _movementStatus == RunMovementStatus.abnormalPaused,
        reason: 'speedBand.${speedBand.name}',
      );
      _handleSuppressedMovementSample(
        sample: sample,
        speedBand: speedBand,
        segmentDistanceMeters: segmentDistanceMeters,
      );
      return true;
    }

    if (_shouldHoldPreMovementCandidate(
      sample: sample,
      segmentDistanceMeters: segmentDistanceMeters,
      speedMetersPerSecond: speedMetersPerSecond,
      motionEvidence: motionEvidence,
    )) {
      _handlePreMovementCandidate(
        sample: sample,
        routeAnchorSample: previousRouteSample,
        segmentDistanceMeters: segmentDistanceMeters,
        motionEvidence: motionEvidence,
      );
      return true;
    }

    final stationaryStartedAt =
        _stationaryStartedAt ?? previousRouteSample.recordedAt;
    final autoPauseDwell = _distanceMeters <= 0
        ? preMovementAutoPauseDwell
        : movingToStoppedAutoPauseDwell;
    final stationaryDwell = sample.recordedAt.difference(stationaryStartedAt);
    final cumulativeGpsMovementMeters =
        _stationaryCumulativeMovementMeters +
        usablePreviousAcceptedDistanceMeters;
    final previousMovementStatus = _movementStatus;
    final classification = movementClassifier.classifyGpsSample(
      sample: sample,
      distanceFromRouteAnchorMeters: segmentDistanceMeters,
      stationaryDwell: stationaryDwell,
      stationaryAutoPauseDwell: autoPauseDwell,
      stationaryDriftDistanceMeters: stationaryDriftDistanceMeters,
      cumulativeGpsMovementMeters: cumulativeGpsMovementMeters,
      movementSpeedMetersPerSecond: speedMetersPerSecond,
      resumeMovementDistanceMeters: resumeMovementDistanceMeters,
      resumeSpeedMetersPerSecond: resumeSpeedMetersPerSecond,
      stationarySpeedMetersPerSecond: stationarySpeedMetersPerSecond,
      requiresSustainedGpsMovement:
          _movementStatus == RunMovementStatus.autoPaused &&
          resumeCandidateSample == null,
      motionEvidence: motionEvidence,
    );
    _logClassifierResult(
      previousMovementStatus: previousMovementStatus,
      nextMovementStatus: _nextMovementStatusForClassification(
        previousMovementStatus,
        classification,
      ),
      movingEvidence:
          classification.shouldAutoResume ||
          classification.type ==
              RunMovementClassificationType.gpsMeaningfulMovement ||
          classification.type ==
              RunMovementClassificationType.gpsResumeCandidate,
      stationaryEvidence:
          classification.shouldAutoPause ||
          classification.type ==
              RunMovementClassificationType.gpsStationaryDrift,
      abnormalEvidence: false,
      reason: classification.type.name,
    );
    _logAutoPauseDecision(
      candidate: classification.shouldAutoPause,
      dwell: stationaryDwell,
      threshold: autoPauseDwell,
      blockedBy: _gpsAutoPauseBlockedBy(
        classification: classification,
        dwell: stationaryDwell,
        threshold: autoPauseDwell,
      ),
      reason: classification.type.name,
    );

    if (classification.shouldAutoResume) {
      if (_movementStatus == RunMovementStatus.autoPaused) {
        final resumeAnchor = resumeCandidateSample ?? sample;
        _addAcceptedSampleSegment(<RunLocationSample>[resumeAnchor, sample]);
        _recordCurrentPaceFromSegment(
          previousSample: resumeAnchor,
          currentSample: sample,
          segmentDistanceMeters: segmentDistanceMeters,
        );
        _distanceMeters += segmentDistanceMeters;
        _lastRouteSample = sample;
      } else {
        _appendRouteSample(sample, segmentDistanceMeters);
      }
      _setMovementStatus(
        RunMovementStatus.moving,
        'gps.${classification.type.name}',
      );
      _autoResumeCandidateSample = null;
      _preMovementCandidateSample = null;
      _resetAbnormalCandidate();
      _resetAbnormalResumeCandidate();
      _stationaryStartedAt = null;
      _stationaryCumulativeMovementMeters = 0;
      _recordAcceptedCurrentSample(
        sample,
        reason: 'autoResumeAccepted',
        acceptedForDistanceOrRoute: true,
      );
      return true;
    }

    if (_movementStatus == RunMovementStatus.autoPaused &&
        classification.type ==
            RunMovementClassificationType.gpsResumeCandidate) {
      _recordAcceptedCurrentSample(
        sample,
        reason: 'gpsResumeCandidate',
        acceptedForDistanceOrRoute: false,
      );
      _autoResumeCandidateSample = sample;
      return true;
    }

    _recordStationarySample(
      sample,
      classification,
      cumulativeGpsMovementMeters,
    );
    return true;
  }

  void _appendRouteSample(
    RunLocationSample sample,
    double segmentDistanceMeters,
  ) {
    _recordCurrentPaceFromSegment(
      previousSample: _lastRouteSample,
      currentSample: sample,
      segmentDistanceMeters: segmentDistanceMeters,
    );
    _distanceMeters += segmentDistanceMeters;
    if (_acceptedSampleSegments.isEmpty) {
      final previousRouteSample = _lastRouteSample;
      if (previousRouteSample != null) {
        _addAcceptedSampleSegment(<RunLocationSample>[previousRouteSample]);
      } else {
        _addAcceptedSampleSegment(<RunLocationSample>[]);
      }
      _appendAcceptedSample(sample);
    } else {
      _appendAcceptedSample(sample);
    }
    _lastRouteSample = sample;
    _autoResumeCandidateSample = null;
    _preMovementCandidateSample = null;
    _resetAbnormalCandidate();
    _resetAbnormalResumeCandidate();
    _stationaryCumulativeMovementMeters = 0;
  }

  void _addAcceptedSampleSegment(List<RunLocationSample> samples) {
    _acceptedSampleSegments.add(List<RunLocationSample>.of(samples));
    _acceptedGraphSampleSegments.add(
      samples.map(_graphPointFor).toList(growable: true),
    );
  }

  void _appendAcceptedSample(RunLocationSample sample) {
    if (_acceptedSampleSegments.isEmpty) {
      _addAcceptedSampleSegment(<RunLocationSample>[sample]);
      return;
    }
    _acceptedSampleSegments.last.add(sample);
    _acceptedGraphSampleSegments.last.add(_graphPointFor(sample));
  }

  void _recordCurrentPaceFromSegment({
    required RunLocationSample? previousSample,
    required RunLocationSample currentSample,
    required double segmentDistanceMeters,
  }) {
    if (previousSample == null ||
        !segmentDistanceMeters.isFinite ||
        segmentDistanceMeters <= 0) {
      return;
    }

    final segmentSeconds =
        currentSample.recordedAt
            .difference(previousSample.recordedAt)
            .inMilliseconds /
        Duration.millisecondsPerSecond;
    if (!segmentSeconds.isFinite || segmentSeconds <= 0) {
      return;
    }

    final paceSecondsPerKm = (segmentSeconds / (segmentDistanceMeters / 1000))
        .round();
    if (paceSecondsPerKm < minGraphPaceSecondsPerKm ||
        paceSecondsPerKm > maxGraphPaceSecondsPerKm) {
      return;
    }

    _currentPaceSecondsPerKm = paceSecondsPerKm;
  }

  LocalPaceGraphSamplePoint _graphPointFor(RunLocationSample sample) {
    return (
      sample: sample,
      activeElapsedSeconds: _activeElapsedSecondsFor(sample),
    );
  }

  int _activeElapsedSecondsFor(RunLocationSample sample) {
    return _activeElapsedSecondsForTime(sample.recordedAt);
  }

  int _activeElapsedSecondsForTime(DateTime recordedAt) {
    final elapsed =
        _activeTimelineOffsetAtStart +
        recordedAt.difference(_activeTimelineStartedAt);
    if (elapsed.isNegative) {
      return _activeTimelineOffsetAtStart.inSeconds;
    }
    return elapsed.inSeconds;
  }

  void _handleSuppressedMovementSample({
    required RunLocationSample sample,
    required RunMovementSpeedBand speedBand,
    required double segmentDistanceMeters,
  }) {
    _suppressedMovingTimeInCurrentAdvance = true;
    _recordAcceptedCurrentSample(
      sample,
      reason: 'suppressedMovementSample',
      acceptedForDistanceOrRoute: false,
    );
    _autoResumeCandidateSample = null;
    _preMovementCandidateSample = null;
    _stationaryStartedAt = null;
    _stationaryCumulativeMovementMeters = 0;

    if (_movementStatus == RunMovementStatus.abnormalPaused) {
      _handleAbnormalResumeCandidate(sample: sample, speedBand: speedBand);
      return;
    }

    _suppressedMovementNeedsAnchor = true;
    if (speedBand != RunMovementSpeedBand.abnormalCandidate) {
      _resetAbnormalCandidate();
      return;
    }

    _abnormalCandidateStartedSample ??= sample;
    _abnormalCandidateCount += 1;
    final startedAt = _abnormalCandidateStartedSample!.recordedAt;
    final sustainedByTime =
        sample.recordedAt.difference(startedAt) >= abnormalSustainedWindow;
    final sustainedBySamples =
        _abnormalCandidateCount >= abnormalSustainedSampleCount;
    if (sustainedByTime || sustainedBySamples) {
      _setMovementStatus(
        RunMovementStatus.abnormalPaused,
        'abnormalSustainedMovement',
      );
      _suppressedMovementNeedsAnchor = false;
      _resetAbnormalResumeCandidate();
    }
  }

  void _handleAbnormalResumeCandidate({
    required RunLocationSample sample,
    required RunMovementSpeedBand speedBand,
  }) {
    if (speedBand != RunMovementSpeedBand.normalResume) {
      _resetAbnormalResumeCandidate();
      if (speedBand != RunMovementSpeedBand.abnormalCandidate) {
        _resetAbnormalCandidate();
      }
      return;
    }

    final resumeAnchor = _abnormalResumeAnchorSample;
    if (resumeAnchor == null) {
      _abnormalResumeAnchorSample = sample;
      _abnormalResumeCandidateCount = 1;
      return;
    }

    final resumeDistanceMeters = distanceCalculator.distanceMeters(
      resumeAnchor,
      sample,
    );
    if (!resumeDistanceMeters.isFinite) {
      _rejectSample(sample, RunLocationRejectionReason.nonFiniteDistance);
      return;
    }

    _abnormalResumeCandidateCount += 1;
    if (_abnormalResumeCandidateCount < 2 ||
        resumeDistanceMeters < resumeMovementDistanceMeters) {
      return;
    }

    _addAcceptedSampleSegment(<RunLocationSample>[resumeAnchor, sample]);
    _recordCurrentPaceFromSegment(
      previousSample: resumeAnchor,
      currentSample: sample,
      segmentDistanceMeters: resumeDistanceMeters,
    );
    _distanceMeters += resumeDistanceMeters;
    _lastRouteSample = sample;
    _setMovementStatus(RunMovementStatus.moving, 'abnormalResumeConfirmed');
    _logGpsAcceptanceDecision(
      sample: sample,
      acceptedSample: true,
      reason: 'abnormalResumeConfirmed',
      distanceDeltaMeters: resumeDistanceMeters,
      timeDelta: _timeDeltaFromSample(resumeAnchor, sample),
    );
    _logGpsAcceptanceRoute(reason: 'abnormalResumeConfirmed');
    _suppressedMovingTimeInCurrentAdvance = false;
    _suppressedMovementNeedsAnchor = false;
    _preMovementCandidateSample = null;
    _resetAbnormalCandidate();
    _resetAbnormalResumeCandidate();
  }

  bool _shouldHoldPreMovementCandidate({
    required RunLocationSample sample,
    required double segmentDistanceMeters,
    required double speedMetersPerSecond,
    required Iterable<RunMotionEvidence> motionEvidence,
  }) {
    if (_distanceMeters > 0 || _movementStatus != RunMovementStatus.moving) {
      return false;
    }
    if (segmentDistanceMeters <= stationaryDriftDistanceMeters ||
        segmentDistanceMeters > _preMovementJitterCandidateMaxMeters) {
      return false;
    }
    if (speedMetersPerSecond.isFinite &&
        speedMetersPerSecond >= resumeSpeedMetersPerSecond) {
      return false;
    }
    final reportedSpeed = sample.speedMetersPerSecond;
    if (reportedSpeed != null && reportedSpeed.isFinite && reportedSpeed >= 0) {
      return reportedSpeed < resumeSpeedMetersPerSecond;
    }
    return _hasStationaryMotionEvidence(motionEvidence);
  }

  void _handlePreMovementCandidate({
    required RunLocationSample sample,
    required RunLocationSample routeAnchorSample,
    required double segmentDistanceMeters,
    required Iterable<RunMotionEvidence> motionEvidence,
  }) {
    _suppressedMovingTimeInCurrentAdvance = true;
    final candidate = _preMovementCandidateSample;
    if (candidate != null) {
      final candidateDistanceMeters = distanceCalculator.distanceMeters(
        candidate,
        sample,
      );
      final anchorToCandidateMeters = distanceCalculator.distanceMeters(
        routeAnchorSample,
        candidate,
      );
      if (!candidateDistanceMeters.isFinite ||
          !anchorToCandidateMeters.isFinite) {
        _rejectSample(sample, RunLocationRejectionReason.nonFiniteDistance);
        return;
      }

      final hasConsistentDisplacement =
          candidateDistanceMeters >= resumeMovementDistanceMeters &&
          segmentDistanceMeters >=
              anchorToCandidateMeters + resumeMovementDistanceMeters;
      if (hasConsistentDisplacement) {
        _addAcceptedSampleSegment(<RunLocationSample>[candidate, sample]);
        _recordCurrentPaceFromSegment(
          previousSample: candidate,
          currentSample: sample,
          segmentDistanceMeters: candidateDistanceMeters,
        );
        _distanceMeters += candidateDistanceMeters;
        _lastRouteSample = sample;
        _autoResumeCandidateSample = null;
        _preMovementCandidateSample = null;
        _resetAbnormalCandidate();
        _resetAbnormalResumeCandidate();
        _stationaryStartedAt = null;
        _stationaryCumulativeMovementMeters = 0;
        _recordAcceptedCurrentSample(
          sample,
          reason: 'preMovementConfirmed',
          acceptedForDistanceOrRoute: true,
        );
        return;
      }
    }

    _preMovementCandidateSample = sample;
    _autoResumeCandidateSample = null;
    _recordAcceptedCurrentSample(
      sample,
      reason: 'preMovementCandidate',
      acceptedForDistanceOrRoute: false,
    );
    _stationaryStartedAt ??= routeAnchorSample.recordedAt;
    _stationaryCumulativeMovementMeters = 0;

    final dwell = sample.recordedAt.difference(_stationaryStartedAt!);
    final hasMovingMotionEvidence = _hasMovingMotionEvidence(motionEvidence);
    final shouldAutoPause =
        dwell >= preMovementAutoPauseDwell && !hasMovingMotionEvidence;
    _logAutoPauseDecision(
      candidate: shouldAutoPause,
      dwell: dwell,
      threshold: preMovementAutoPauseDwell,
      blockedBy: _preMovementAutoPauseBlockedBy(
        dwell: dwell,
        threshold: preMovementAutoPauseDwell,
        hasMovingMotionEvidence: hasMovingMotionEvidence,
      ),
      reason: 'preMovementCandidate',
    );
    if (shouldAutoPause) {
      _setMovementStatus(RunMovementStatus.autoPaused, 'preMovementDwell');
      _preMovementCandidateSample = null;
      _resetAbnormalCandidate();
      _resetAbnormalResumeCandidate();
    }
  }

  void _recordStationarySample(
    RunLocationSample sample,
    RunMovementClassification classification,
    double cumulativeGpsMovementMeters,
  ) {
    _recordAcceptedCurrentSample(
      sample,
      reason: classification.type.name,
      acceptedForDistanceOrRoute:
          classification.type ==
          RunMovementClassificationType.gpsMeaningfulMovement,
    );
    if (_movementStatus == RunMovementStatus.autoPaused) {
      return;
    }

    _stationaryStartedAt ??= _lastRouteSample?.recordedAt ?? sample.recordedAt;
    _stationaryCumulativeMovementMeters = cumulativeGpsMovementMeters;
    if (classification.shouldAutoPause) {
      _setMovementStatus(
        RunMovementStatus.autoPaused,
        'gps.${classification.type.name}',
      );
      _autoResumeCandidateSample = null;
      _preMovementCandidateSample = null;
      _resetAbnormalCandidate();
      _resetAbnormalResumeCandidate();
    }
  }

  void _recordNoSampleDwell(Iterable<RunMotionEvidence> motionEvidence) {
    final lastAcceptedSample = _lastAcceptedSample;
    if (_movementStatus == RunMovementStatus.autoPaused ||
        lastAcceptedSample == null) {
      _logAutoPauseDecision(
        candidate: false,
        dwell: null,
        threshold: noSampleAutoPauseDwell,
        blockedBy: lastAcceptedSample == null
            ? 'noAcceptedAnchor'
            : 'alreadyAutoPaused',
        reason: 'noSampleSkipped',
      );
      return;
    }

    final currentTrackingAt = startedAt.add(_trackingDuration);
    _stationaryStartedAt ??= lastAcceptedSample.recordedAt;
    final dwell = currentTrackingAt.difference(_stationaryStartedAt!);
    final anchorAge = currentTrackingAt.difference(
      lastAcceptedSample.recordedAt,
    );
    final gpsStatusAllowsDwell =
        _diagnostics.lastRejectedSampleSequence <=
        _diagnostics.lastAcceptedSampleSequence;
    final previousMovementStatus = _movementStatus;
    final classification = movementClassifier.classifyNoSampleWindow(
      dwell: dwell,
      noSampleAutoPauseDwell: noSampleAutoPauseDwell,
      anchorAge: anchorAge,
      maxAnchorAge: maxNoSampleStationaryAnchorAge,
      hasAcceptedAnchor: _diagnostics.hasAcceptedSample,
      gpsStatusAllowsDwell: gpsStatusAllowsDwell,
      motionEvidence: motionEvidence,
    );
    _logClassifierResult(
      previousMovementStatus: previousMovementStatus,
      nextMovementStatus: _nextMovementStatusForClassification(
        previousMovementStatus,
        classification,
      ),
      movingEvidence: classification.countsAsMovingTime,
      stationaryEvidence: classification.shouldAutoPause,
      abnormalEvidence: false,
      reason: classification.type.name,
    );
    _logAutoPauseDecision(
      candidate: classification.shouldAutoPause,
      dwell: dwell,
      threshold: noSampleAutoPauseDwell,
      blockedBy: _noSampleAutoPauseBlockedBy(
        classification: classification,
        dwell: dwell,
        threshold: noSampleAutoPauseDwell,
        anchorAge: anchorAge,
        gpsStatusAllowsDwell: gpsStatusAllowsDwell,
      ),
      reason: classification.type.name,
    );
    if (!classification.shouldAutoPause) {
      return;
    }
    _setMovementStatus(
      RunMovementStatus.autoPaused,
      'noSample.${classification.type.name}',
    );
    _autoResumeCandidateSample = null;
    _preMovementCandidateSample = null;
    _resetAbnormalCandidate();
    _resetAbnormalResumeCandidate();
  }

  void _recordAcceptedCurrentSample(
    RunLocationSample sample, {
    required String reason,
    required bool acceptedForDistanceOrRoute,
  }) {
    final previousAccepted = _lastAcceptedSample;
    final distanceDeltaMeters = _autoPauseQaLogsEnabled
        ? _distanceDeltaFromLastAccepted(sample)
        : null;
    final gpsAcceptanceDistanceDeltaMeters = runiacGpsAcceptanceQaLogsEnabled
        ? _distanceDeltaFromSample(previousAccepted, sample)
        : null;
    final gpsAcceptanceTimeDelta = runiacGpsAcceptanceQaLogsEnabled
        ? _timeDeltaFromSample(previousAccepted, sample)
        : null;
    _currentPositionSample = sample;
    _lastAcceptedSample = sample;
    _diagnostics = _diagnostics.recordAcceptedSample(sample);
    _logGpsAcceptanceDecision(
      sample: sample,
      acceptedSample: acceptedForDistanceOrRoute,
      reason: reason,
      distanceDeltaMeters: gpsAcceptanceDistanceDeltaMeters,
      timeDelta: gpsAcceptanceTimeDelta,
    );
    if (acceptedForDistanceOrRoute) {
      _logGpsAcceptanceRoute(reason: reason);
    }
    _logLocationSample(
      sample: sample,
      acceptedSample: true,
      reason: reason,
      distanceDeltaMeters: distanceDeltaMeters,
    );
  }

  bool _isSameSample(RunLocationSample? left, RunLocationSample right) {
    return left != null &&
        left.recordedAt == right.recordedAt &&
        left.latitude == right.latitude &&
        left.longitude == right.longitude;
  }

  bool _isSuppressedCandidateFromPrevious(
    RunLocationSample previous,
    RunLocationSample sample,
  ) {
    final elapsedSeconds =
        sample.recordedAt.difference(previous.recordedAt).inMilliseconds / 1000;
    if (elapsedSeconds <= 0) {
      return false;
    }
    final distanceMeters = distanceCalculator.distanceMeters(previous, sample);
    if (!distanceMeters.isFinite) {
      return false;
    }
    final speedMetersPerSecond = _hardRejectSpeedMetersPerSecond(
      sample: sample,
      calculatedSpeedMetersPerSecond: distanceMeters / elapsedSeconds,
    );
    return speedMetersPerSecond >= suspiciousSpeedMetersPerSecond &&
        speedMetersPerSecond <= maxAcceptedSpeedMetersPerSecond;
  }

  void _rejectSample(
    RunLocationSample sample,
    RunLocationRejectionReason reason,
  ) {
    _diagnostics = _diagnostics.recordRejectedSample(sample, reason);
    _logGpsAcceptanceRejected(sample: sample, reason: reason.name);
    _logLocationSample(
      sample: sample,
      acceptedSample: false,
      reason: reason.name,
    );
  }

  RunLocationRejectionReason _sampleRejectionReason(RunLocationSample sample) {
    if (sample.recordedAt.isBefore(startedAt)) {
      return RunLocationRejectionReason.staleTimestamp;
    }
    if (!sample.latitude.isFinite || !sample.longitude.isFinite) {
      return RunLocationRejectionReason.invalidCoordinate;
    }
    if (sample.latitude < -90 || sample.latitude > 90) {
      return RunLocationRejectionReason.invalidCoordinate;
    }
    if (sample.longitude < -180 || sample.longitude > 180) {
      return RunLocationRejectionReason.invalidCoordinate;
    }

    final horizontalAccuracyMeters = sample.horizontalAccuracyMeters;
    if (horizontalAccuracyMeters == null) {
      return RunLocationRejectionReason.none;
    }
    if (!horizontalAccuracyMeters.isFinite ||
        horizontalAccuracyMeters < 0 ||
        horizontalAccuracyMeters > maxAcceptedHorizontalAccuracyMeters) {
      return RunLocationRejectionReason.poorAccuracy;
    }
    return RunLocationRejectionReason.none;
  }

  double _classificationSpeedMetersPerSecond({
    required RunLocationSample sample,
    required double calculatedSpeedMetersPerSecond,
  }) {
    final reportedSpeed = sample.speedMetersPerSecond;
    if (reportedSpeed != null && reportedSpeed.isFinite && reportedSpeed >= 0) {
      return reportedSpeed;
    }
    return calculatedSpeedMetersPerSecond;
  }

  double _hardRejectSpeedMetersPerSecond({
    required RunLocationSample sample,
    required double calculatedSpeedMetersPerSecond,
  }) {
    final reportedSpeed = sample.speedMetersPerSecond;
    if (reportedSpeed == null || !reportedSpeed.isFinite || reportedSpeed < 0) {
      return calculatedSpeedMetersPerSecond;
    }
    if (!calculatedSpeedMetersPerSecond.isFinite ||
        calculatedSpeedMetersPerSecond < 0) {
      return reportedSpeed;
    }
    return reportedSpeed > calculatedSpeedMetersPerSecond
        ? reportedSpeed
        : calculatedSpeedMetersPerSecond;
  }

  bool _hasMovingMotionEvidence(Iterable<RunMotionEvidence> motionEvidence) {
    RunMotionEvidence? latest;
    for (final evidence in motionEvidence) {
      if (latest == null || evidence.recordedAt.isAfter(latest.recordedAt)) {
        latest = evidence;
      }
    }
    return latest?.signal == RunMotionSignal.moving &&
        (latest?.confidence ?? 0) >= 0.6;
  }

  bool _hasStationaryMotionEvidence(
    Iterable<RunMotionEvidence> motionEvidence,
  ) {
    RunMotionEvidence? latest;
    for (final evidence in motionEvidence) {
      if (latest == null || evidence.recordedAt.isAfter(latest.recordedAt)) {
        latest = evidence;
      }
    }
    return latest?.signal == RunMotionSignal.stationary &&
        (latest?.confidence ?? 0) >= 0.6;
  }

  void _resetAbnormalCandidate() {
    _abnormalCandidateStartedSample = null;
    _abnormalCandidateCount = 0;
  }

  void _resetAbnormalResumeCandidate() {
    _abnormalResumeAnchorSample = null;
    _abnormalResumeCandidateCount = 0;
  }

  void _setMovementStatus(RunMovementStatus next, String reason) {
    final previous = _movementStatus;
    if (previous == next) {
      return;
    }
    _movementStatus = next;
    _logStateTransition(from: previous, to: next, reason: reason);
  }

  RunMovementStatus _nextMovementStatusForClassification(
    RunMovementStatus previous,
    RunMovementClassification classification,
  ) {
    if (classification.shouldAutoResume) {
      return RunMovementStatus.moving;
    }
    if (classification.shouldAutoPause) {
      return RunMovementStatus.autoPaused;
    }
    return previous;
  }

  void _logGpsAcceptanceSample(RunLocationSample sample) {
    if (!runiacGpsAcceptanceQaLogsEnabled) {
      return;
    }
    _logGpsAcceptanceQa(
      'phase=sample '
      'accuracyM=${_qaDouble(sample.horizontalAccuracyMeters)} '
      'speedMps=${_qaDouble(sample.speedMetersPerSecond)} '
      'movementStatus=${_movementStatus.name} '
      'autoPaused=${_movementStatus == RunMovementStatus.autoPaused} '
      'abnormalPaused=${_movementStatus == RunMovementStatus.abnormalPaused}',
    );
  }

  void _logGpsAcceptanceDecision({
    required RunLocationSample sample,
    required bool acceptedSample,
    required String reason,
    required double? distanceDeltaMeters,
    required Duration? timeDelta,
  }) {
    if (!runiacGpsAcceptanceQaLogsEnabled) {
      return;
    }
    final reasonKey = acceptedSample ? 'acceptReason' : 'rejectReason';
    _logGpsAcceptanceQa(
      'phase=decision '
      'acceptedSample=$acceptedSample '
      '$reasonKey=$reason '
      'distanceDeltaM=${_qaDouble(distanceDeltaMeters)} '
      'timeDeltaMs=${_qaDurationMs(timeDelta)} '
      'impliedSpeedMps=${_qaDouble(_impliedSpeedMetersPerSecond(distanceDeltaMeters, timeDelta))} '
      'accuracyM=${_qaDouble(sample.horizontalAccuracyMeters)} '
      'speedMps=${_qaDouble(sample.speedMetersPerSecond)} '
      'movementStatus=${_movementStatus.name} '
      'autoPaused=${_movementStatus == RunMovementStatus.autoPaused} '
      'abnormalPaused=${_movementStatus == RunMovementStatus.abnormalPaused}',
    );
  }

  void _logGpsAcceptanceRejected({
    required RunLocationSample sample,
    required String reason,
  }) {
    if (!runiacGpsAcceptanceQaLogsEnabled) {
      return;
    }
    final previousAccepted = _lastAcceptedSample;
    final distanceDeltaMeters = _distanceDeltaFromSample(
      previousAccepted,
      sample,
    );
    final timeDelta = _timeDeltaFromSample(previousAccepted, sample);
    _logGpsAcceptanceDecision(
      sample: sample,
      acceptedSample: false,
      reason: reason,
      distanceDeltaMeters: distanceDeltaMeters,
      timeDelta: timeDelta,
    );
    _logGpsAcceptanceQa(
      'phase=rejected '
      'acceptedSample=false '
      'rejectReason=$reason '
      'distanceDeltaM=${_qaDouble(distanceDeltaMeters)} '
      'timeDeltaMs=${_qaDurationMs(timeDelta)} '
      'impliedSpeedMps=${_qaDouble(_impliedSpeedMetersPerSecond(distanceDeltaMeters, timeDelta))} '
      'accuracyM=${_qaDouble(sample.horizontalAccuracyMeters)} '
      'speedMps=${_qaDouble(sample.speedMetersPerSecond)} '
      'movementStatus=${_movementStatus.name}',
    );
  }

  void _logGpsAcceptanceRoute({required String reason}) {
    if (!runiacGpsAcceptanceQaLogsEnabled) {
      return;
    }
    _logGpsAcceptanceQa(
      'phase=route '
      'acceptedSample=true '
      'acceptReason=$reason '
      'acceptedDistanceM=${_qaDouble(_distanceMeters)} '
      'routePointCount=${_routePointCount()} '
      'segmentCount=${_acceptedSampleSegments.length} '
      'movementStatus=${_movementStatus.name}',
    );
  }

  void _logGpsAcceptanceQa(String message) {
    if (!runiacGpsAcceptanceQaLogsEnabled) {
      return;
    }
    debugPrint('$_gpsAcceptanceQaLogPrefix $message');
  }

  void _logLocationSample({
    required RunLocationSample sample,
    required bool acceptedSample,
    required String reason,
    double? distanceDeltaMeters,
  }) {
    if (!_autoPauseQaLogsEnabled) {
      return;
    }
    final resolvedDistanceDeltaMeters =
        distanceDeltaMeters ??
        (acceptedSample ? null : _distanceDeltaFromLastAccepted(sample));
    _logAutoPauseQa(
      'phase=sample '
      'accuracyM=${_qaDouble(sample.horizontalAccuracyMeters)} '
      'speedMps=${_qaDouble(sample.speedMetersPerSecond)} '
      'distanceDeltaM=${_qaDouble(resolvedDistanceDeltaMeters)} '
      'acceptedSample=$acceptedSample '
      'reason=$reason '
      'movementStatus=${_movementStatus.name}',
    );
  }

  void _logClassifierResult({
    required RunMovementStatus previousMovementStatus,
    required RunMovementStatus nextMovementStatus,
    required bool movingEvidence,
    required bool stationaryEvidence,
    required bool abnormalEvidence,
    required String reason,
  }) {
    if (!_autoPauseQaLogsEnabled) {
      return;
    }
    _logAutoPauseQa(
      'phase=classify '
      'previousMovementStatus=${previousMovementStatus.name} '
      'nextMovementStatus=${nextMovementStatus.name} '
      'movingEvidence=$movingEvidence '
      'stationaryEvidence=$stationaryEvidence '
      'abnormalEvidence=$abnormalEvidence '
      'reason=$reason',
    );
  }

  void _logAdvance(Duration delta, bool noSampleWindow) {
    if (!_autoPauseQaLogsEnabled) {
      return;
    }
    final trackingAt = startedAt.add(_trackingDuration);
    _logAutoPauseQa(
      'phase=advance '
      'dtMs=${delta.inMilliseconds} '
      'movementStatus=${_movementStatus.name} '
      'manualPaused=${!_isActive} '
      'autoPaused=${_movementStatus == RunMovementStatus.autoPaused} '
      'abnormalPaused=${_movementStatus == RunMovementStatus.abnormalPaused} '
      'movingDurationMs=${_movingDuration.inMilliseconds} '
      'trackingDurationMs=${_trackingDuration.inMilliseconds} '
      'stationaryDwellMs=${_qaDurationMs(_stationaryDwellAt(trackingAt))} '
      'noSampleDwellMs=${_qaDurationMs(noSampleWindow ? _noSampleDwellAt(trackingAt) : null)}',
    );
  }

  void _logAutoPauseDecision({
    required bool candidate,
    required Duration? dwell,
    required Duration threshold,
    required String blockedBy,
    required String reason,
  }) {
    if (!_autoPauseQaLogsEnabled) {
      return;
    }
    _logAutoPauseQa(
      'phase=decision '
      'candidate=$candidate '
      'dwellMs=${_qaDurationMs(dwell)} '
      'thresholdMs=${threshold.inMilliseconds} '
      'blockedBy=$blockedBy '
      'reason=$reason',
    );
  }

  void _logStateTransition({
    required RunMovementStatus from,
    required RunMovementStatus to,
    required String reason,
  }) {
    if (!_autoPauseQaLogsEnabled) {
      return;
    }
    _logAutoPauseQa(
      'phase=transition from=${from.name} to=${to.name} reason=$reason',
    );
  }

  void _logAutoPauseQa(String message) {
    if (!_autoPauseQaLogsEnabled) {
      return;
    }
    debugPrint('$_autoPauseQaLogPrefix $message');
  }

  double? _distanceDeltaFromLastAccepted(RunLocationSample sample) {
    final previous = _lastAcceptedSample;
    return _distanceDeltaFromSample(previous, sample);
  }

  double? _distanceDeltaFromSample(
    RunLocationSample? previous,
    RunLocationSample sample,
  ) {
    if (previous == null) {
      return null;
    }
    final distanceMeters = distanceCalculator.distanceMeters(previous, sample);
    return distanceMeters.isFinite ? distanceMeters : null;
  }

  Duration? _timeDeltaFromSample(
    RunLocationSample? previous,
    RunLocationSample sample,
  ) {
    if (previous == null) {
      return null;
    }
    final delta = sample.recordedAt.difference(previous.recordedAt);
    return delta.isNegative ? Duration.zero : delta;
  }

  double? _impliedSpeedMetersPerSecond(
    double? distanceMeters,
    Duration? timeDelta,
  ) {
    if (distanceMeters == null || timeDelta == null) {
      return null;
    }
    final elapsedSeconds = timeDelta.inMilliseconds / 1000;
    if (elapsedSeconds <= 0) {
      return null;
    }
    final impliedSpeed = distanceMeters / elapsedSeconds;
    return impliedSpeed.isFinite ? impliedSpeed : null;
  }

  int _routePointCount() {
    var count = 0;
    for (final segment in _acceptedSampleSegments) {
      count += segment.length;
    }
    return count;
  }

  Duration? _stationaryDwellAt(DateTime trackingAt) {
    final stationaryStartedAt = _stationaryStartedAt;
    if (stationaryStartedAt == null) {
      return null;
    }
    final dwell = trackingAt.difference(stationaryStartedAt);
    return dwell.isNegative ? Duration.zero : dwell;
  }

  Duration? _noSampleDwellAt(DateTime trackingAt) {
    final lastAcceptedSample = _lastAcceptedSample;
    if (lastAcceptedSample == null) {
      return null;
    }
    final dwell = trackingAt.difference(lastAcceptedSample.recordedAt);
    return dwell.isNegative ? Duration.zero : dwell;
  }

  String _gpsAutoPauseBlockedBy({
    required RunMovementClassification classification,
    required Duration dwell,
    required Duration threshold,
  }) {
    if (classification.shouldAutoPause) {
      return 'none';
    }
    if (classification.shouldAutoResume) {
      return 'movingEvidence';
    }
    if (classification.countsAsMovingTime) {
      return 'movingTimeEvidence';
    }
    if (dwell < threshold) {
      return 'dwellBelowThreshold';
    }
    return 'classification.${classification.type.name}';
  }

  String _noSampleAutoPauseBlockedBy({
    required RunMovementClassification classification,
    required Duration dwell,
    required Duration threshold,
    required Duration anchorAge,
    required bool gpsStatusAllowsDwell,
  }) {
    if (classification.shouldAutoPause) {
      return 'none';
    }
    if (dwell < threshold) {
      return 'dwellBelowThreshold';
    }
    if (anchorAge > maxNoSampleStationaryAnchorAge) {
      return 'anchorTooOld';
    }
    if (!gpsStatusAllowsDwell) {
      return 'latestSampleRejected';
    }
    if (classification.countsAsMovingTime) {
      return 'movingTimeEvidence';
    }
    return 'classification.${classification.type.name}';
  }

  String _preMovementAutoPauseBlockedBy({
    required Duration dwell,
    required Duration threshold,
    required bool hasMovingMotionEvidence,
  }) {
    if (dwell < threshold) {
      return 'dwellBelowThreshold';
    }
    if (hasMovingMotionEvidence) {
      return 'movingMotionEvidence';
    }
    return 'none';
  }

  String _qaDouble(double? value) {
    if (value == null) {
      return 'null';
    }
    if (!value.isFinite) {
      return value.toString();
    }
    return value.toStringAsFixed(2);
  }

  String _qaDurationMs(Duration? duration) {
    if (duration == null) {
      return 'null';
    }
    return duration.inMilliseconds.toString();
  }
}
