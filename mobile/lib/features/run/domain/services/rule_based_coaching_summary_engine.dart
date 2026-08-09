import '../models/cadence_analysis_derivation.dart';
import '../models/coaching_summary_snapshot.dart';
import '../models/elevation_graph_snapshot.dart';
import '../models/pace_graph_snapshot.dart';
import '../models/run_source_display.dart';
import '../models/run_summary_snapshot.dart';
import 'cadence_analysis_deriver.dart';
import 'elevation_analysis_graph_builder.dart';

const int _veryShortRunDurationSeconds = 2 * 60;
const double _veryShortRunDistanceKm = 0.25;
const int _shortRunDurationSeconds = 6 * 60;
const double _shortRunDistanceKm = 0.8;
const int _longerRunDurationSeconds = 35 * 60;
const double _longerRunDistanceKm = 5.0;
const int _minimumUsableGraphPoints = 3;
const int _minimumUsablePaceSecondsPerKm = 150;
const int _maximumUsablePaceSecondsPerKm = 1800;
const int _unevenPaceSpreadSeconds = 60;
const int _steadyPaceSpreadSeconds = 35;
const int _fastStartFadeSeconds = 55;
const int _strongFinishSeconds = 35;

/// Writes the post-run Coaching Summary and Next Focus **without** calling an
/// LLM.
///
/// The run is first reduced to a handful of coarse signals (`_Coaching*` enums
/// below: how long it was, whether the pace data is trustworthy, the pace
/// pattern, cadence, elevation), and the copy is then chosen from those. Two
/// consequences worth knowing before editing:
///
/// * It is deterministic. The same run always produces the same words, so the
///   tests assert on exact copy.
/// * It degrades instead of guessing. When the data is too thin to support a
///   claim the engine says less rather than inventing a trend — which is why
///   the thresholds above are conservative.
///
/// The LLM-backed feedback is a separate, Premium-only path
/// (`cloud_function_activity_feedback_agent.dart`); this engine is what every
/// runner gets.
class RuleBasedCoachingSummaryEngine {
  const RuleBasedCoachingSummaryEngine();

  CoachingSummarySnapshot build(RunSummarySnapshot summary) {
    final signals = _CoachingSignals.fromSummary(summary);

    if (signals.dataConfidence == _CoachingDataConfidence.low) {
      return signals.elevationSignal == _CoachingElevationSignal.unavailable
          ? _lowDataInterpretation
          : _lowDataElevationInterpretation;
    }

    if (signals.runScale == _CoachingRunScale.veryShort) {
      return _veryShortInterpretation;
    }

    if (signals.pacePattern == _CoachingPacePattern.graphUnavailable) {
      return signals.hasDisplayAveragePace
          ? _scalarOnlyInterpretation
          : _basicCompletionInterpretation;
    }

    if (signals.pacePattern == _CoachingPacePattern.dataQualityFallback) {
      return _dataQualityFallbackInterpretation;
    }

    if (signals.sourceSignal == _CoachingSourceSignal.importedOrDemo) {
      return _importedGraphInterpretation;
    }

    if (signals.runScale == _CoachingRunScale.shortValid) {
      return switch (signals.pacePattern) {
        _CoachingPacePattern.steady => _shortSteadyNoHrInterpretation,
        _CoachingPacePattern.uneven ||
        _CoachingPacePattern.fastStartFade => _shortUnevenNoHrInterpretation,
        _ => _shortValidInterpretation,
      };
    }

    if (signals.elevationSignal != _CoachingElevationSignal.unavailable &&
        signals.pacePattern == _CoachingPacePattern.steady) {
      return signals.elevationSignal == _CoachingElevationSignal.mostlyFlat
          ? _steadyMostlyFlatElevationInterpretation
          : _steadyChangingElevationInterpretation;
    }

    if (signals.elevationSignal != _CoachingElevationSignal.unavailable &&
        signals.pacePattern == _CoachingPacePattern.fastStartFade) {
      return signals.elevationSignal == _CoachingElevationSignal.mostlyFlat
          ? _fadeMostlyFlatElevationInterpretation
          : _fadeChangingElevationInterpretation;
    }

    if (signals.cadencePattern == _CoachingCadencePattern.stable &&
        signals.pacePattern == _CoachingPacePattern.steady) {
      return _steadyPaceStableCadenceInterpretation;
    }

    if (signals.cadencePattern == _CoachingCadencePattern.dropping &&
        signals.pacePattern == _CoachingPacePattern.fastStartFade) {
      return _paceFadeCadenceDropInterpretation;
    }

    if (signals.runScale == _CoachingRunScale.longerBeginner &&
        signals.pacePattern == _CoachingPacePattern.fastStartFade) {
      return _longerFadeNoHrInterpretation;
    }

    return switch (signals.pacePattern) {
      _CoachingPacePattern.fastStartFade => _fastStartFadeNoHrInterpretation,
      _CoachingPacePattern.strongFinish => _strongFinishNoHrInterpretation,
      _CoachingPacePattern.uneven => _unevenNoHrInterpretation,
      _CoachingPacePattern.steady => _normalSteadyHrUnavailableInterpretation,
      _ => _gpsGraphInterpretation,
    };
  }
}

enum _CoachingDataConfidence { low, usable }

enum _CoachingRunScale { veryShort, shortValid, normalBeginner, longerBeginner }

enum _CoachingPacePattern {
  graphUnavailable,
  dataQualityFallback,
  steady,
  uneven,
  fastStartFade,
  strongFinish,
  generalGraph,
}

enum _CoachingSourceSignal { liveGps, importedOrDemo }

enum _CoachingCadencePattern { unavailable, stable, dropping, otherAvailable }

enum _CoachingElevationSignal { unavailable, mostlyFlat, changingRoute }

class _CoachingSignals {
  const _CoachingSignals({
    required this.dataConfidence,
    required this.runScale,
    required this.pacePattern,
    required this.sourceSignal,
    required this.hasDisplayAveragePace,
    required this.cadencePattern,
    required this.elevationSignal,
  });

  final _CoachingDataConfidence dataConfidence;
  final _CoachingRunScale runScale;
  final _CoachingPacePattern pacePattern;
  final _CoachingSourceSignal sourceSignal;
  final bool hasDisplayAveragePace;
  final _CoachingCadencePattern cadencePattern;
  final _CoachingElevationSignal elevationSignal;

  factory _CoachingSignals.fromSummary(RunSummarySnapshot summary) {
    final distanceKm = _parseDistanceKm(summary.distanceKm);
    final durationSeconds = _parseDurationSeconds(summary.duration);
    final graphPoints = _usableGraphPoints(summary.paceGraph);

    return _CoachingSignals(
      dataConfidence: summary.hasSufficientData
          ? _CoachingDataConfidence.usable
          : _CoachingDataConfidence.low,
      runScale: _classifyRunScale(
        distanceKm: distanceKm,
        durationSeconds: durationSeconds,
      ),
      pacePattern: _classifyPacePattern(
        graph: summary.paceGraph,
        graphPoints: graphPoints,
      ),
      sourceSignal: _classifySource(summary.sourceType),
      hasDisplayAveragePace: _hasDisplayAveragePace(summary.avgPace),
      cadencePattern: _classifyCadencePattern(summary),
      elevationSignal: _classifyElevationSignal(summary),
    );
  }
}

_CoachingRunScale _classifyRunScale({
  required double? distanceKm,
  required int? durationSeconds,
}) {
  if ((distanceKm != null && distanceKm < _veryShortRunDistanceKm) ||
      (durationSeconds != null &&
          durationSeconds < _veryShortRunDurationSeconds)) {
    return _CoachingRunScale.veryShort;
  }

  if ((distanceKm != null && distanceKm < _shortRunDistanceKm) ||
      (durationSeconds != null && durationSeconds < _shortRunDurationSeconds)) {
    return _CoachingRunScale.shortValid;
  }

  if ((distanceKm != null && distanceKm >= _longerRunDistanceKm) ||
      (durationSeconds != null &&
          durationSeconds >= _longerRunDurationSeconds)) {
    return _CoachingRunScale.longerBeginner;
  }

  return _CoachingRunScale.normalBeginner;
}

_CoachingPacePattern _classifyPacePattern({
  required PaceGraphSnapshot graph,
  required List<PaceGraphPoint> graphPoints,
}) {
  if (!graph.isAvailable) {
    return _CoachingPacePattern.graphUnavailable;
  }

  if (graphPoints.length < _minimumUsableGraphPoints) {
    return _CoachingPacePattern.dataQualityFallback;
  }

  final spread = _paceSpreadSeconds(graphPoints);
  if (_isFastStartFade(graphPoints)) {
    return _CoachingPacePattern.fastStartFade;
  }
  if (_isStrongFinish(graphPoints)) {
    return _CoachingPacePattern.strongFinish;
  }
  if (spread <= _steadyPaceSpreadSeconds) {
    return _CoachingPacePattern.steady;
  }
  if (spread >= _unevenPaceSpreadSeconds) {
    return _CoachingPacePattern.uneven;
  }

  return _CoachingPacePattern.generalGraph;
}

_CoachingSourceSignal _classifySource(RunSourceType sourceType) {
  return switch (sourceType) {
    RunSourceType.runiacGps => _CoachingSourceSignal.liveGps,
    RunSourceType.appleHealth ||
    RunSourceType.healthConnect ||
    RunSourceType.garminViaHealth ||
    RunSourceType.demoImport => _CoachingSourceSignal.importedOrDemo,
  };
}

_CoachingCadencePattern _classifyCadencePattern(RunSummarySnapshot summary) {
  final cadenceSeries = summary.cadenceAnalysisSeries;
  if (cadenceSeries == null) {
    return _CoachingCadencePattern.unavailable;
  }

  final cadenceAnalysis = const CadenceAnalysisDeriver().derive(cadenceSeries);
  if (!cadenceAnalysis.isAvailable) {
    return _CoachingCadencePattern.unavailable;
  }

  if (cadenceAnalysis.stability == CadenceStability.stable &&
      cadenceAnalysis.trend == CadenceTrend.stable) {
    return _CoachingCadencePattern.stable;
  }

  if (cadenceAnalysis.trend == CadenceTrend.dropping) {
    return _CoachingCadencePattern.dropping;
  }

  return _CoachingCadencePattern.otherAvailable;
}

_CoachingElevationSignal _classifyElevationSignal(RunSummarySnapshot summary) {
  final graph = const ElevationAnalysisGraphBuilder().build(
    summary.elevationSeries,
  );
  if (!graph.isAvailable) {
    return _CoachingElevationSignal.unavailable;
  }

  return switch (graph.difficulty) {
    ElevationDifficulty.mostlyFlat => _CoachingElevationSignal.mostlyFlat,
    ElevationDifficulty.rolling ||
    ElevationDifficulty.hilly => _CoachingElevationSignal.changingRoute,
    ElevationDifficulty.unavailable => _CoachingElevationSignal.unavailable,
  };
}

List<PaceGraphPoint> _usableGraphPoints(PaceGraphSnapshot graph) {
  final points =
      graph.points
          .where(
            (point) =>
                point.progressFraction.isFinite &&
                point.progressFraction >= 0 &&
                point.progressFraction <= 1 &&
                point.paceSecondsPerKm >= _minimumUsablePaceSecondsPerKm &&
                point.paceSecondsPerKm <= _maximumUsablePaceSecondsPerKm,
          )
          .toList()
        ..sort((a, b) => a.elapsedSeconds.compareTo(b.elapsedSeconds));

  if (!_hasIncreasingGraphOrder(points)) {
    return const [];
  }

  return points;
}

bool _hasIncreasingGraphOrder(List<PaceGraphPoint> points) {
  for (var index = 1; index < points.length; index += 1) {
    final previous = points[index - 1];
    final current = points[index];

    if (current.elapsedSeconds <= previous.elapsedSeconds ||
        current.progressFraction <= previous.progressFraction) {
      return false;
    }
  }

  return true;
}

bool _isFastStartFade(List<PaceGraphPoint> points) {
  if (points.length < 4) {
    return false;
  }

  final firstPace = points.first.paceSecondsPerKm;
  final finalPace = points.last.paceSecondsPerKm;
  final laterAverage = _averagePace(points.skip(points.length ~/ 2));

  return finalPace - firstPace >= _fastStartFadeSeconds &&
      laterAverage - firstPace > _fastStartFadeSeconds;
}

bool _isStrongFinish(List<PaceGraphPoint> points) {
  if (points.length < 4) {
    return false;
  }

  final firstAverage = _averagePace(points.take((points.length / 2).ceil()));
  final finalPace = points.last.paceSecondsPerKm;

  return firstAverage - finalPace >= _strongFinishSeconds;
}

int _averagePace(Iterable<PaceGraphPoint> points) {
  final values = points.map((point) => point.paceSecondsPerKm).toList();
  if (values.isEmpty) {
    return 0;
  }
  return (values.reduce((a, b) => a + b) / values.length).round();
}

int _paceSpreadSeconds(List<PaceGraphPoint> points) {
  var minimumPace = points.first.paceSecondsPerKm;
  var maximumPace = points.first.paceSecondsPerKm;

  for (final point in points.skip(1)) {
    if (point.paceSecondsPerKm < minimumPace) {
      minimumPace = point.paceSecondsPerKm;
    }
    if (point.paceSecondsPerKm > maximumPace) {
      maximumPace = point.paceSecondsPerKm;
    }
  }

  return maximumPace - minimumPace;
}

double? _parseDistanceKm(String label) {
  final normalized = label.toLowerCase().replaceAll('km', '').trim();
  return double.tryParse(normalized);
}

int? _parseDurationSeconds(String label) {
  final parts = label.split(':');
  if (parts.length < 2 || parts.length > 3) {
    return null;
  }

  final values = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0) {
      return null;
    }
    values.add(value);
  }

  if (values.length == 2) {
    return values[0] * 60 + values[1];
  }

  return values[0] * 3600 + values[1] * 60 + values[2];
}

bool _hasDisplayAveragePace(String label) {
  final normalized = label.trim();
  return normalized.isNotEmpty && normalized != '--';
}

const _lowDataInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.lowDataInterpretation,
  headline: 'A simple check-in run',
  message:
      'This run has limited data, so the summary stays careful and simple. Completion still matters because it gives you a check-in point. Heart-rate data was not available, and the pace graph is not usable, so this note avoids effort or pacing claims.',
  nextAction: 'Try one short easy run with GPS ready.',
);

const _lowDataElevationInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.lowDataInterpretation,
  headline: 'A simple check-in run',
  message:
      'This run has limited data, so the summary stays careful and simple. Elevation data was captured, but Runiac needs more usable pace and distance data before giving route context. Completion still matters because it gives you a check-in point.',
  nextAction: 'Try one short easy run with GPS ready.',
);

const _veryShortInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.shortValidInterpretation,
  headline: 'A small check-in',
  message:
      'This was a very short check-in, so it is better treated as a start than a full pacing review. The available numbers can mark that you got moving, but they are too small for confident trend coaching. Keep the takeaway simple and useful.',
  nextAction: 'Add a few easy minutes before thinking about pace.',
);

const _shortSteadyNoHrInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.steadyEffortInterpretation,
  headline: 'A short, steady start',
  message:
      'This was a short but useful run. The available pace points suggest a steady rhythm, which is a useful sign for building consistency. Since heart-rate data was not available, the safest takeaway is your pacing rhythm rather than how hard it felt.',
  nextAction:
      'Next time, add a few easy minutes while keeping the same calm start.',
);

const _shortUnevenNoHrInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.paceControlInterpretation,
  headline: 'A short rhythm practice',
  message:
      'This short run still counts as useful practice. The pace moved around, which is normal while you are building rhythm and learning how the first minutes feel. Heart-rate data was not available, so this note only talks about rhythm, not effort.',
  nextAction: 'Make the first few minutes almost too easy.',
);

const _normalSteadyHrUnavailableInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.steadyEffortInterpretation,
  headline: 'A steady rhythm run',
  message:
      'The available pace data supports a steady rhythm today. That is a useful beginner signal because repeatable pacing is easier to build on than a single quick split. Heart-rate data was not available, so this note avoids guessing how hard it felt.',
  nextAction: 'Repeat the easy rhythm and keep the start relaxed.',
);

const _steadyMostlyFlatElevationInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.steadyEffortInterpretation,
  headline: 'A steady rhythm run',
  message:
      'The available pace data supports a steady rhythm today. Elevation data also adds route context and looks mostly flat, so the main takeaway stays simple: your rhythm was repeatable across the usable run data without needing bigger claims.',
  nextAction: 'Repeat the easy rhythm and keep the start relaxed.',
);

const _steadyChangingElevationInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.steadyEffortInterpretation,
  headline: 'A steady rhythm run',
  message:
      'The available pace data supports a steady rhythm today. Elevation data adds route context because the route had some changing ground, so the useful takeaway is steady rhythm without treating the route as the whole story.',
  nextAction: 'Keep the rhythm relaxed on changing ground.',
);

const _steadyPaceStableCadenceInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.steadyEffortInterpretation,
  headline: 'A steady rhythm run',
  message:
      'Your step rhythm stayed steady, which can help the run feel more controlled. The available pace data also stayed steady, so this is a simple rhythm note today rather than an effort or performance judgement.',
  nextAction: 'Try the same relaxed start and focus on short, light steps.',
);

const _fastStartFadeNoHrInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.paceControlInterpretation,
  headline: 'A quick start that settled',
  message:
      'The available pace data appears quicker early and slower later. That can happen while you are finding a rhythm, especially when the first minutes start a little sharp. Heart-rate data was not available, so this note keeps the focus on pacing only.',
  nextAction: 'Start the first 5 minutes easier next time.',
);

const _fadeMostlyFlatElevationInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.paceControlInterpretation,
  headline: 'A quick start that settled',
  message:
      'The pace eased later after a quicker start. Elevation data adds route context and looks mostly flat, so this stays a pacing note rather than proof of why the change happened. The useful lesson is still a calmer opening.',
  nextAction: 'Start easier and let the first few minutes settle.',
);

const _fadeChangingElevationInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.paceControlInterpretation,
  headline: 'A quick start that settled',
  message:
      'The pace eased later after a quicker start. Elevation data adds route context because the route had some changing ground, but it is not proof that hills shaped the pattern. The useful lesson is still a calmer opening.',
  nextAction: 'Start easier and let route changes settle before judging pace.',
);

const _paceFadeCadenceDropInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.paceControlInterpretation,
  headline: 'A later rhythm check',
  message:
      'Your pace and step rhythm eased off later in the run. That may suggest the opening rhythm was a little sharp, so the useful takeaway is to keep the start relaxed and notice the final minutes.',
  nextAction:
      'Next time, start a little more relaxed and focus on short, light steps near the end.',
);

const _longerFadeNoHrInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.paceControlInterpretation,
  headline: 'A longer run with patience',
  message:
      'This was a longer beginner run, so the first positive is the amount of time you kept going. The later pace eased, which makes the next lesson about patience at the start. Heart-rate data was not available, so this stays with pacing rather than effort.',
  nextAction: 'Keep the opening third easier on the next longer run.',
);

const _strongFinishNoHrInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.pacingAwarenessInterpretation,
  headline: 'A controlled finish',
  message:
      'The available pace data suggests you finished a little stronger. That is a useful pacing note, not a reason to turn every run into a push. Heart-rate data was not available, so this summary does not guess how hard the finish felt.',
  nextAction: 'Keep the early part relaxed so the finish can stay controlled.',
);

const _unevenNoHrInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.paceControlInterpretation,
  headline: 'Rhythm practice for next time',
  message:
      'Your rhythm changed across the available pace data. That is common while you are learning how to start and settle into a run. Heart-rate data was not available, so the fairest coaching point is pacing rhythm, not how hard it felt.',
  nextAction: 'Start almost too easy, then try to hold the rhythm.',
);

const _importedGraphInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.steadyEffortInterpretation,
  headline: 'Imported run with useful rhythm data',
  message:
      'This imported summary includes enough graph detail to review rhythm without pretending Runiac tracked the run live. The available data can still help you notice whether the run stayed steady. Treat it as a learning note, not an official progression judgement.',
  nextAction: 'Compare the rhythm and keep the next run easy to repeat.',
);

const _gpsGraphInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.pacingAwarenessInterpretation,
  headline: 'Useful pacing detail',
  message:
      'This Runiac GPS run has usable pacing detail, so the graph can support a simple rhythm review. It does not prove GPS accuracy or how hard the run felt by itself. The best beginner takeaway is to keep learning how the first few minutes shape the rest.',
  nextAction: 'Repeat a relaxed start and watch how the rhythm settles.',
);

const _scalarOnlyInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.scalarOnlyInterpretation,
  headline: 'A solid summary from core numbers',
  message:
      'Your distance, time, and average pace are usable, so this summary can stay focused on the overall run. The pace graph is not available, which means it should not claim a trend or finish pattern. The useful takeaway is completion and repeatability.',
  nextAction: 'Keep the next run simple and easy to repeat.',
);

const _dataQualityFallbackInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.dataQualityFallbackInterpretation,
  headline: 'A careful summary from limited graph detail',
  message:
      'The run summary is available, but the graph detail is too limited for a reliable pacing trend. Distance and time can still give you a useful check-in point. This note avoids reading too much into the graph and keeps the next step simple.',
  nextAction: 'Run easy with GPS ready and let the data settle.',
);

const _shortValidInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.shortValidInterpretation,
  headline: 'A useful short start',
  message:
      'This was a short but valid run, and that is useful for building the habit. The available data is enough for a simple note, but not a heavy performance judgement. Keep the focus on repeating calm starts before adding much more.',
  nextAction: 'Repeat a short easy run and keep it relaxed.',
);

const _basicCompletionInterpretation = CoachingSummarySnapshot(
  source: CoachingSummarySource.ruleBased,
  interpretationId: CoachingInterpretationId.basicCompletionInterpretation,
  headline: 'Run completed',
  message:
      'This run has enough distance, time, and pace data for a simple beginner summary. The safest takeaway is that you completed a measurable run and now have a starting point to repeat. Keep the next step calm and consistent rather than trying to prove anything with speed.',
  nextAction: 'Keep the next run easy and repeatable.',
);
