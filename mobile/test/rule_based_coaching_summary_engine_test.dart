import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/coaching_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/pace_graph_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_source_display.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/services/rule_based_coaching_summary_engine.dart';

void main() {
  group('RuleBasedCoachingSummaryEngine diary rulebook', () {
    test('low_data_no_hr_no_graph_diary_copy', () {
      final coaching = _build(
        distanceKm: '0.03',
        avgPace: '--',
        duration: '0:25',
        calories: '--',
        hasSufficientData: false,
        paceGraph: const PaceGraphSnapshot.unavailable(),
      );

      expect(
        coaching.interpretationId,
        CoachingInterpretationId.lowDataInterpretation,
      );
      expect(coaching.message, contains('limited'));
      expect(
        coaching.message,
        contains(
          RegExp('heart-rate data was not available', caseSensitive: false),
        ),
      );
      expect(coaching.message, isNot(contains('graph shows')));
      expect(coaching.nextAction, contains('GPS ready'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('very_short_suppresses_pace_pattern_claim', () {
      final coaching = _build(
        distanceKm: '0.16',
        duration: '1:40',
        paceGraph: _strongFinishGraph(),
      );

      expect(coaching.message, contains('short check-in'));
      expect(coaching.message, isNot(contains('finished stronger')));
      expect(coaching.message, isNot(contains('pace graph shows')));
      expect(coaching.nextAction, contains('easy minutes'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('short_steady_no_hr_diary_copy', () {
      final coaching = _build(
        distanceKm: '0.72',
        duration: '5:45',
        paceGraph: _steadyGraph(),
      );

      expect(coaching.message, contains('short but useful'));
      expect(coaching.message, contains('steady'));
      expect(
        coaching.message,
        contains(
          RegExp('heart-rate data was not available', caseSensitive: false),
        ),
      );
      expect(coaching.nextAction, contains('same calm start'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('short_uneven_no_hr_diary_copy', () {
      final coaching = _build(
        distanceKm: '0.75',
        duration: '5:50',
        paceGraph: _unevenGraph(),
      );

      expect(coaching.message, contains('pace moved around'));
      expect(coaching.message, contains('normal'));
      expect(
        coaching.message,
        contains(
          RegExp('heart-rate data was not available', caseSensitive: false),
        ),
      );
      expect(coaching.nextAction, contains('first few minutes'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('normal_steady_hr_unavailable_no_effort_claim', () {
      final coaching = _build(paceGraph: _steadyGraph());

      expect(coaching.message, contains('steady rhythm'));
      expect(coaching.message, contains('avoids guessing how hard it felt'));
      expect(coaching.message, isNot(contains('comfortable effort')));
      expect(coaching.nextAction, contains('easy rhythm'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('steady_pace_elevation_available_adds_cautious_route_context', () {
      final coaching = _build(
        paceGraph: _steadyGraph(),
        elevationSeries: _rollingElevationSeries(),
      );

      expect(coaching.message, contains('steady rhythm'));
      expect(
        coaching.message,
        contains(RegExp('elevation data', caseSensitive: false)),
      );
      expect(coaching.message, contains('route context'));
      expect(coaching.message, isNot(contains('caused')));
      expect(coaching.nextAction, contains('changing ground'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('steady_pace_stable_cadence_uses_neutral_rhythm_copy', () {
      final coaching = _build(
        paceGraph: _steadyGraph(),
        cadenceAnalysisSeries: _stableCadenceSeries(),
      );

      expect(coaching.message, contains('step rhythm stayed steady'));
      expect(coaching.message, contains('controlled'));
      expect(coaching.nextAction, contains('short, light steps'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
      _expectCadenceSafeCopy(coaching);
    });

    test('fast_start_fade_no_hr_gentle_start_focus', () {
      final coaching = _build(paceGraph: _fastStartFadeGraph());

      expect(coaching.message, contains('quicker early'));
      expect(coaching.message, contains('slower later'));
      expect(
        coaching.message,
        contains(
          RegExp('heart-rate data was not available', caseSensitive: false),
        ),
      );
      expect(coaching.nextAction, contains('first 5 minutes'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('pace_fade_cadence_drop_uses_careful_late_rhythm_copy', () {
      final coaching = _build(
        paceGraph: _fastStartFadeGraph(),
        cadenceAnalysisSeries: _droppingCadenceSeries(),
      );

      expect(
        coaching.message,
        contains('pace and step rhythm eased off later'),
      );
      expect(coaching.nextAction, contains('start a little more relaxed'));
      expect(coaching.nextAction, contains('short, light steps'));
      expect(coaching.message, isNot(contains('fatigue')));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
      _expectCadenceSafeCopy(coaching);
    });

    test('pace_fade_elevation_available_does_not_blame_hills', () {
      final coaching = _build(
        paceGraph: _fastStartFadeGraph(),
        elevationSeries: _rollingElevationSeries(),
      );

      expect(coaching.message, contains('pace eased later'));
      expect(coaching.message, contains('route context'));
      expect(coaching.message, contains('not proof'));
      expect(coaching.message, isNot(contains('caused')));
      expect(coaching.nextAction, contains('route changes'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('unavailable_cadence_does_not_create_fake_rhythm_coaching', () {
      final coaching = _build(
        paceGraph: _steadyGraph(),
        cadenceAnalysisSeries: CadenceAnalysisSeries.unavailable(),
      );

      expect(coaching.message, isNot(contains('step rhythm')));
      expect(coaching.nextAction, isNot(contains('short, light steps')));
      expect(coaching.message, contains('steady rhythm'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('static_demo_cadence_does_not_create_fake_rhythm_coaching', () {
      final coaching = _build(
        paceGraph: _steadyGraph(),
        cadenceAnalysisSeries: CadenceAnalysisSeries.staticDemo(
          samples: const <CadenceAnalysisSample>[
            CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 164),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cadenceSpm: 166,
            ),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 180,
              cadenceSpm: 168,
            ),
          ],
        ),
      );

      expect(coaching.message, isNot(contains('step rhythm')));
      expect(coaching.nextAction, isNot(contains('short, light steps')));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('longer_fade_no_hr_endurance_praise_first', () {
      final coaching = _build(
        distanceKm: '5.80',
        duration: '43:20',
        paceGraph: _fastStartFadeGraph(),
      );

      expect(coaching.message, startsWith('This was a longer beginner run'));
      expect(coaching.message, contains('later pace eased'));
      expect(
        coaching.message,
        contains(
          RegExp('heart-rate data was not available', caseSensitive: false),
        ),
      );
      expect(coaching.nextAction, contains('opening third'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('low_data_elevation_available_stays_low_data_safe', () {
      final coaching = _build(
        hasSufficientData: false,
        avgPace: '--',
        paceGraph: const PaceGraphSnapshot.unavailable(),
        elevationSeries: _rollingElevationSeries(),
      );

      expect(
        coaching.interpretationId,
        CoachingInterpretationId.lowDataInterpretation,
      );
      expect(coaching.message, contains('limited data'));
      expect(
        coaching.message,
        contains(RegExp('elevation data was captured', caseSensitive: false)),
      );
      expect(coaching.message, contains('usable pace and distance data'));
      expect(coaching.message, isNot(contains('hill caused')));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('strong_finish_no_hr_controlled_finish_copy', () {
      final coaching = _build(paceGraph: _strongFinishGraph());

      expect(coaching.message, contains('finished a little stronger'));
      expect(
        coaching.message,
        contains(
          RegExp('heart-rate data was not available', caseSensitive: false),
        ),
      );
      expect(coaching.nextAction, contains('early part relaxed'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('uneven_no_hr_rhythm_practice_copy', () {
      final coaching = _build(paceGraph: _unevenGraph());

      expect(coaching.message, contains('rhythm changed'));
      expect(
        coaching.message,
        contains(
          RegExp('heart-rate data was not available', caseSensitive: false),
        ),
      );
      expect(coaching.nextAction, contains('almost too easy'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('imported_or_static_run_avoids_live_gps_claim', () {
      final coaching = _build(
        sourceType: RunSourceType.demoImport,
        paceGraph: _steadyGraph(),
      );

      expect(coaching.message, contains('imported summary'));
      expect(coaching.message, isNot(contains('tracked live')));
      expect(coaching.message, isNot(contains('Runiac GPS observed')));
      expect(coaching.nextAction, contains('Compare the rhythm'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('unavailable_elevation_does_not_change_steady_copy', () {
      final coaching = _build(
        paceGraph: _steadyGraph(),
        elevationSeries: const ElevationAnalysisSeries.unavailable(),
      );

      expect(coaching.message, contains('steady rhythm'));
      expect(coaching.message, contains('avoids guessing how hard it felt'));
      expect(coaching.message, isNot(contains('elevation data')));
      expect(coaching.message, isNot(contains('route context')));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('graph_unavailable_valid_scalars_avoids_graph_claim', () {
      final coaching = _build(paceGraph: const PaceGraphSnapshot.unavailable());

      expect(coaching.message, contains('distance, time, and average pace'));
      expect(coaching.message, isNot(contains('graph shows')));
      expect(coaching.message, isNot(contains('finished stronger')));
      expect(coaching.nextAction, contains('simple'));
      _expectDiaryShape(coaching);
      _expectSafeCopy(coaching);
    });

    test('copy_length_guard', () {
      final outputs = [
        _build(hasSufficientData: false, avgPace: '--'),
        _build(distanceKm: '0.16', duration: '1:40'),
        _build(distanceKm: '0.72', duration: '5:45', paceGraph: _steadyGraph()),
        _build(distanceKm: '0.75', duration: '5:50', paceGraph: _unevenGraph()),
        _build(paceGraph: _steadyGraph()),
        _build(
          paceGraph: _steadyGraph(),
          elevationSeries: _rollingElevationSeries(),
        ),
        _build(paceGraph: _fastStartFadeGraph()),
        _build(
          paceGraph: _fastStartFadeGraph(),
          elevationSeries: _rollingElevationSeries(),
        ),
        _build(paceGraph: _strongFinishGraph()),
        _build(paceGraph: const PaceGraphSnapshot.unavailable()),
      ];

      for (final coaching in outputs) {
        _expectDiaryShape(coaching);
        _expectSafeCopy(coaching);
      }
    });
  });
}

CoachingSummarySnapshot _build({
  String distanceKm = '4.20',
  String avgPace = '6’12”',
  String duration = '26:02',
  String calories = '245',
  bool hasSufficientData = true,
  RunSourceType sourceType = RunSourceType.runiacGps,
  CadenceAnalysisSeries? cadenceAnalysisSeries,
  ElevationAnalysisSeries elevationSeries =
      const ElevationAnalysisSeries.unavailable(),
  PaceGraphSnapshot paceGraph = const PaceGraphSnapshot(
    isAvailable: true,
    points: [
      PaceGraphPoint(
        elapsedSeconds: 0,
        progressFraction: 0,
        paceSecondsPerKm: 372,
      ),
      PaceGraphPoint(
        elapsedSeconds: 900,
        progressFraction: 0.5,
        paceSecondsPerKm: 398,
      ),
      PaceGraphPoint(
        elapsedSeconds: 1800,
        progressFraction: 1,
        paceSecondsPerKm: 410,
      ),
    ],
    yAxisLabels: ['6:00', '6:30'],
    xAxisLabels: ['0', '26'],
  ),
}) {
  return const RuleBasedCoachingSummaryEngine().build(
    RunSummarySnapshot(
      title: 'Morning Run',
      dateLabel: '19/6/26',
      timeLabel: '7:10 AM',
      distanceKm: distanceKm,
      avgPace: avgPace,
      duration: duration,
      avgHeartRate: '--',
      calories: calories,
      routeName: 'Private route',
      hasSufficientData: hasSufficientData,
      sourceType: sourceType,
      cadenceAnalysisSeries: cadenceAnalysisSeries,
      elevationSeries: elevationSeries,
      paceGraph: paceGraph,
    ),
  );
}

PaceGraphSnapshot _steadyGraph() {
  return const PaceGraphSnapshot(
    isAvailable: true,
    points: [
      PaceGraphPoint(
        elapsedSeconds: 0,
        progressFraction: 0,
        paceSecondsPerKm: 372,
      ),
      PaceGraphPoint(
        elapsedSeconds: 900,
        progressFraction: 0.5,
        paceSecondsPerKm: 386,
      ),
      PaceGraphPoint(
        elapsedSeconds: 1800,
        progressFraction: 1,
        paceSecondsPerKm: 365,
      ),
    ],
    yAxisLabels: ['6:00', '6:30', '7:00'],
    xAxisLabels: ['0', '15', '30'],
  );
}

PaceGraphSnapshot _unevenGraph() {
  return const PaceGraphSnapshot(
    isAvailable: true,
    points: [
      PaceGraphPoint(
        elapsedSeconds: 0,
        progressFraction: 0,
        paceSecondsPerKm: 390,
      ),
      PaceGraphPoint(
        elapsedSeconds: 600,
        progressFraction: 0.33,
        paceSecondsPerKm: 470,
      ),
      PaceGraphPoint(
        elapsedSeconds: 1200,
        progressFraction: 0.66,
        paceSecondsPerKm: 410,
      ),
      PaceGraphPoint(
        elapsedSeconds: 1800,
        progressFraction: 1,
        paceSecondsPerKm: 455,
      ),
    ],
    yAxisLabels: ['6:00', '7:00', '8:00'],
    xAxisLabels: ['0', '10', '20', '30'],
  );
}

PaceGraphSnapshot _fastStartFadeGraph() {
  return const PaceGraphSnapshot(
    isAvailable: true,
    points: [
      PaceGraphPoint(
        elapsedSeconds: 0,
        progressFraction: 0,
        paceSecondsPerKm: 360,
      ),
      PaceGraphPoint(
        elapsedSeconds: 600,
        progressFraction: 0.33,
        paceSecondsPerKm: 405,
      ),
      PaceGraphPoint(
        elapsedSeconds: 1200,
        progressFraction: 0.66,
        paceSecondsPerKm: 432,
      ),
      PaceGraphPoint(
        elapsedSeconds: 1800,
        progressFraction: 1,
        paceSecondsPerKm: 455,
      ),
    ],
    yAxisLabels: ['6:00', '7:00', '8:00'],
    xAxisLabels: ['0', '10', '20', '30'],
  );
}

PaceGraphSnapshot _strongFinishGraph() {
  return const PaceGraphSnapshot(
    isAvailable: true,
    points: [
      PaceGraphPoint(
        elapsedSeconds: 0,
        progressFraction: 0,
        paceSecondsPerKm: 430,
      ),
      PaceGraphPoint(
        elapsedSeconds: 600,
        progressFraction: 0.33,
        paceSecondsPerKm: 415,
      ),
      PaceGraphPoint(
        elapsedSeconds: 1200,
        progressFraction: 0.66,
        paceSecondsPerKm: 400,
      ),
      PaceGraphPoint(
        elapsedSeconds: 1800,
        progressFraction: 1,
        paceSecondsPerKm: 372,
      ),
    ],
    yAxisLabels: ['6:00', '7:00', '8:00'],
    xAxisLabels: ['0', '10', '20', '30'],
  );
}

CadenceAnalysisSeries _stableCadenceSeries() {
  return CadenceAnalysisSeries.localAccepted(
    samples: const <CadenceAnalysisSample>[
      CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 164),
      CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 166),
      CadenceAnalysisSample.accepted(elapsedSeconds: 180, cadenceSpm: 168),
      CadenceAnalysisSample.accepted(elapsedSeconds: 240, cadenceSpm: 166),
    ],
  );
}

CadenceAnalysisSeries _droppingCadenceSeries() {
  return CadenceAnalysisSeries.localAccepted(
    samples: const <CadenceAnalysisSample>[
      CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 172),
      CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 170),
      CadenceAnalysisSample.accepted(elapsedSeconds: 180, cadenceSpm: 158),
      CadenceAnalysisSample.accepted(elapsedSeconds: 240, cadenceSpm: 156),
    ],
  );
}

ElevationAnalysisSeries _rollingElevationSeries() {
  return ElevationAnalysisSeries.localAccepted(
    samples: const <ElevationAnalysisSample>[
      ElevationAnalysisSample(distanceKm: 0, elevationMeters: 22),
      ElevationAnalysisSample(distanceKm: 1.4, elevationMeters: 36),
      ElevationAnalysisSample(distanceKm: 2.8, elevationMeters: 31),
      ElevationAnalysisSample(distanceKm: 4.2, elevationMeters: 49),
    ],
  );
}

void _expectDiaryShape(CoachingSummarySnapshot coaching) {
  final wordCount = coaching.message
      .split(RegExp(r'\s+'))
      .where((word) => word.trim().isNotEmpty)
      .length;
  final sentenceCount = RegExp(r'[.!?]').allMatches(coaching.message).length;

  expect(wordCount, inInclusiveRange(35, 80), reason: coaching.message);
  expect(sentenceCount, inInclusiveRange(2, 4), reason: coaching.message);
  expect(coaching.message, isNot(contains('\n')));
  expect(coaching.bullets, isEmpty);
  expect(coaching.headline, isNotEmpty);
  expect(coaching.nextAction, isNotEmpty);
}

void _expectSafeCopy(CoachingSummarySnapshot coaching) {
  final copy = _allCopy(coaching);
  expect(copy, isNot(contains(_blockedCopyTerms())));
  expect(copy, isNot(contains(_futureServiceTerms())));
  expect(copy, isNot(contains(_medicalOrIntensityTerms())));
}

void _expectCadenceSafeCopy(CoachingSummarySnapshot coaching) {
  final copy = _allCopy(coaching);
  expect(copy, isNot(contains(_cadenceForbiddenTerms())));
}

String _allCopy(CoachingSummarySnapshot coaching) {
  return [
    coaching.sectionTitle,
    coaching.headline,
    coaching.message,
    ...coaching.bullets,
    coaching.nextAction,
  ].join('\n');
}

RegExp _cadenceForbiddenTerms() {
  return RegExp(
    [
      'good',
      'bad',
      'ideal',
      'target',
      'optimal',
      'injury',
      'overstride',
      'fatigue',
      'guarantee',
      'must',
      'wrong',
      'correct',
      '180 spm',
    ].map(RegExp.escape).join('|'),
    caseSensitive: false,
  );
}

RegExp _blockedCopyTerms() {
  return RegExp(
    [
      'sha'
          'me',
      'gu'
          'ilt',
      'fail'
          'ed',
      'bad',
      'po'
          'or',
      'burned'
          ' out',
      'over'
          'trained',
      'exhaust'
          'ed',
      'danger',
      'max'
          ' effort',
      'too'
          ' slow',
      'you should'
          ' have',
      'not good'
          ' enough',
      'we'
          'ak',
      'push'
          ' harder',
      'no'
          ' excuses',
      'must'
          ' improve',
    ].map(RegExp.escape).join('|'),
    caseSensitive: false,
  );
}

RegExp _medicalOrIntensityTerms() {
  return RegExp(
    [
      'Zone',
      'threshold',
      'fat'
          'igue',
      'medical',
      'recovery',
      'heart rate showed',
      'effort was',
      'comfortable effort',
      'high effort',
      'GPS was accurate',
    ].map(RegExp.escape).join('|'),
    caseSensitive: false,
  );
}

RegExp _futureServiceTerms() {
  return RegExp(
    [
      'Open'
          'AI',
      'API'
          ' key',
      'Bear'
          'er',
      'Prem'
          'ium',
      'subscrip'
          'tion',
      'XP',
      'leader'
          'board',
      'str'
          'eak',
      'ra'
          'nk',
      'lev'
          'el',
    ].map(RegExp.escape).join('|'),
    caseSensitive: false,
  );
}
