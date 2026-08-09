// Named pace-sample fixtures, one per case the pace graph has to survive:
// a clean run, a GPS spike, thin data, too few valid points, and a walk.
//
// Shared by the static/offline app mode and by the tests, on purpose — the
// screens a reviewer sees without a backend are driven by the same data the
// assertions run against, so a fixture that stops being realistic breaks a test
// rather than quietly making the demo look better than the real thing.

import '../../domain/models/pace_graph_snapshot.dart';
import '../../domain/services/pace_graph_data_builder.dart';

const normalEasyRunPaceSamples = [
  PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 405),
  PaceGraphSample(elapsedSeconds: 300, paceSecondsPerKm: 398),
  PaceGraphSample(elapsedSeconds: 600, paceSecondsPerKm: 392),
  PaceGraphSample(elapsedSeconds: 900, paceSecondsPerKm: 388),
  PaceGraphSample(elapsedSeconds: 1200, paceSecondsPerKm: 394),
  PaceGraphSample(elapsedSeconds: 1500, paceSecondsPerKm: 386),
  PaceGraphSample(elapsedSeconds: 1770, paceSecondsPerKm: 382),
];

const gpsSpikeRunPaceSamples = [
  PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 440),
  PaceGraphSample(elapsedSeconds: 240, paceSecondsPerKm: 432),
  PaceGraphSample(elapsedSeconds: 360, paceSecondsPerKm: 80),
  PaceGraphSample(elapsedSeconds: 600, paceSecondsPerKm: 426),
  PaceGraphSample(elapsedSeconds: 840, paceSecondsPerKm: 2700),
  PaceGraphSample(elapsedSeconds: 1080, paceSecondsPerKm: 420),
  PaceGraphSample(elapsedSeconds: 1320, paceSecondsPerKm: 414),
  PaceGraphSample(elapsedSeconds: 1410, paceSecondsPerKm: 410),
];

const lowDataRunPaceSamples = [
  PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 540),
  PaceGraphSample(elapsedSeconds: 30, paceSecondsPerKm: 560),
];

const tooFewValidPointsRunPaceSamples = [
  PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 90),
  PaceGraphSample(elapsedSeconds: 80, paceSecondsPerKm: 510),
  PaceGraphSample(elapsedSeconds: 160, paceSecondsPerKm: 2600),
  PaceGraphSample(elapsedSeconds: 240, paceSecondsPerKm: 520),
  PaceGraphSample(elapsedSeconds: 320, paceSecondsPerKm: 70),
];

const slowWalkOrPauseRunPaceSamples = [
  PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 1180),
  PaceGraphSample(elapsedSeconds: 180, paceSecondsPerKm: 1320),
  PaceGraphSample(elapsedSeconds: 360, paceSecondsPerKm: 1900),
  PaceGraphSample(elapsedSeconds: 540, paceSecondsPerKm: 1500),
  PaceGraphSample(elapsedSeconds: 720, paceSecondsPerKm: 1810),
  PaceGraphSample(elapsedSeconds: 900, paceSecondsPerKm: 1580),
];

const progressiveRunPaceSamples = [
  PaceGraphSample(elapsedSeconds: 0, paceSecondsPerKm: 520),
  PaceGraphSample(elapsedSeconds: 360, paceSecondsPerKm: 508),
  PaceGraphSample(elapsedSeconds: 720, paceSecondsPerKm: 496),
  PaceGraphSample(elapsedSeconds: 1080, paceSecondsPerKm: 484),
  PaceGraphSample(elapsedSeconds: 1440, paceSecondsPerKm: 472),
  PaceGraphSample(elapsedSeconds: 1800, paceSecondsPerKm: 466),
  PaceGraphSample(elapsedSeconds: 2370, paceSecondsPerKm: 460),
];

const normalEasyRunPaceGraph = PaceGraphSnapshot(
  isAvailable: true,
  points: [
    PaceGraphPoint(
      elapsedSeconds: 0,
      progressFraction: 0,
      paceSecondsPerKm: 405,
      distanceProgressFraction: 0,
      displayLabel: '6:45',
    ),
    PaceGraphPoint(
      elapsedSeconds: 300,
      progressFraction: 0.1652892561983471,
      paceSecondsPerKm: 398,
      distanceProgressFraction: 0.1870967741935484,
      displayLabel: '6:38',
    ),
    PaceGraphPoint(
      elapsedSeconds: 600,
      progressFraction: 0.3305785123966942,
      paceSecondsPerKm: 392,
      distanceProgressFraction: 0.3769230769230769,
      displayLabel: '6:32',
    ),
    PaceGraphPoint(
      elapsedSeconds: 900,
      progressFraction: 0.49586776859504134,
      paceSecondsPerKm: 388,
      distanceProgressFraction: 0.5687344913151365,
      displayLabel: '6:28',
    ),
    PaceGraphPoint(
      elapsedSeconds: 1200,
      progressFraction: 0.6611570247933884,
      paceSecondsPerKm: 394,
      distanceProgressFraction: 0.7578163771712159,
      displayLabel: '6:34',
    ),
    PaceGraphPoint(
      elapsedSeconds: 1500,
      progressFraction: 0.8264462809917356,
      paceSecondsPerKm: 386,
      distanceProgressFraction: 0.9506203473945409,
      displayLabel: '6:26',
    ),
    PaceGraphPoint(
      elapsedSeconds: 1770,
      progressFraction: 0.9752066115702479,
      paceSecondsPerKm: 382,
      distanceProgressFraction: 1,
      displayLabel: '6:22',
    ),
  ],
  yAxisLabels: ['6:00', '6:40', '7:20'],
  xAxisLabels: ['0:00', '10:00', '20:00', '30:15'],
  distanceAxisLabels: ['0 km', '1.3 km', '2.6 km', '4.03 km'],
  totalDurationSeconds: 1815,
  averagePaceSecondsPerKm: 390,
  bestPacePoint: PaceGraphPoint(
    elapsedSeconds: 1770,
    progressFraction: 0.9752066115702479,
    paceSecondsPerKm: 382,
    distanceProgressFraction: 1,
    displayLabel: '6:22',
  ),
  slowestPacePoint: PaceGraphPoint(
    elapsedSeconds: 0,
    progressFraction: 0,
    paceSecondsPerKm: 405,
    distanceProgressFraction: 0,
    displayLabel: '6:45',
  ),
  paceRangeMinSecondsPerKm: 360,
  paceRangeMaxSecondsPerKm: 440,
);

final gpsSpikeRunPaceGraph = const PaceGraphDataBuilder().build(
  samples: gpsSpikeRunPaceSamples,
  durationSeconds: 1450,
  distanceMeters: 3200,
  averagePaceSecondsPerKm: 425,
);

// Manual QA fixture for snapshot-backed Advanced Analysis Pace graph rendering.
// It includes a steady opening, slight middle slowdown, recovery, and a final
// endpoint label at the graph edge.
const paceGraphManualQaAvailableGraph = PaceGraphSnapshot(
  isAvailable: true,
  points: [
    PaceGraphPoint(
      elapsedSeconds: 0,
      progressFraction: 0,
      paceSecondsPerKm: 430,
      distanceProgressFraction: 0,
      displayLabel: '7:10',
    ),
    PaceGraphPoint(
      elapsedSeconds: 60,
      progressFraction: 0.125,
      paceSecondsPerKm: 428,
      distanceProgressFraction: 0.09090909090909091,
      displayLabel: '7:08',
    ),
    PaceGraphPoint(
      elapsedSeconds: 120,
      progressFraction: 0.25,
      paceSecondsPerKm: 432,
      distanceProgressFraction: 0.22727272727272727,
      displayLabel: '7:12',
    ),
    PaceGraphPoint(
      elapsedSeconds: 180,
      progressFraction: 0.375,
      paceSecondsPerKm: 444,
      distanceProgressFraction: 0.4090909090909091,
      displayLabel: '7:24',
    ),
    PaceGraphPoint(
      elapsedSeconds: 240,
      progressFraction: 0.5,
      paceSecondsPerKm: 456,
      distanceProgressFraction: 0.6363636363636364,
      displayLabel: '7:36',
    ),
    PaceGraphPoint(
      elapsedSeconds: 300,
      progressFraction: 0.625,
      paceSecondsPerKm: 448,
      distanceProgressFraction: 0.7090909090909091,
      displayLabel: '7:28',
    ),
    PaceGraphPoint(
      elapsedSeconds: 360,
      progressFraction: 0.75,
      paceSecondsPerKm: 438,
      distanceProgressFraction: 0.7727272727272727,
      displayLabel: '7:18',
    ),
    PaceGraphPoint(
      elapsedSeconds: 420,
      progressFraction: 0.875,
      paceSecondsPerKm: 430,
      distanceProgressFraction: 0.8909090909090909,
      displayLabel: '7:10',
    ),
    PaceGraphPoint(
      elapsedSeconds: 480,
      progressFraction: 1,
      paceSecondsPerKm: 425,
      distanceProgressFraction: 1,
      displayLabel: '7:05',
    ),
  ],
  yAxisLabels: ['7:00', '7:30', '8:00'],
  xAxisLabels: ['0:00', '2:00', '4:00', '6:00', '8:00'],
  distanceAxisLabels: ['0 km', '0.5 km', '1.1 km'],
  totalDurationSeconds: 480,
  averagePaceSecondsPerKm: 436,
  bestPacePoint: PaceGraphPoint(
    elapsedSeconds: 480,
    progressFraction: 1,
    paceSecondsPerKm: 425,
    distanceProgressFraction: 1,
    displayLabel: '7:05',
  ),
  slowestPacePoint: PaceGraphPoint(
    elapsedSeconds: 240,
    progressFraction: 0.5,
    paceSecondsPerKm: 456,
    distanceProgressFraction: 0.6363636363636364,
    displayLabel: '7:36',
  ),
  paceRangeMinSecondsPerKm: 420,
  paceRangeMaxSecondsPerKm: 480,
);

PaceGraphSnapshot buildDemoPaceGraph({
  required List<PaceGraphSample> samples,
  required int durationSeconds,
  required int distanceMeters,
  int? averagePaceSecondsPerKm,
}) {
  return const PaceGraphDataBuilder().build(
    samples: samples,
    durationSeconds: durationSeconds,
    distanceMeters: distanceMeters,
    averagePaceSecondsPerKm: averagePaceSecondsPerKm,
  );
}

final saturdayNightRecentPaceGraph = normalEasyRunPaceGraph;

final morningEasyRecentPaceGraph = gpsSpikeRunPaceGraph;

final recoveryJogPaceGraph = buildDemoPaceGraph(
  samples: progressiveRunPaceSamples,
  durationSeconds: 2378,
  distanceMeters: 5170,
  averagePaceSecondsPerKm: 460,
);

final saturdayNightHistoryPaceGraph = buildDemoPaceGraph(
  samples: normalEasyRunPaceSamples,
  durationSeconds: 2072,
  distanceMeters: 5120,
  averagePaceSecondsPerKm: 405,
);

final easyMorningHistoryPaceGraph = buildDemoPaceGraph(
  samples: gpsSpikeRunPaceSamples,
  durationSeconds: 1815,
  distanceMeters: 4030,
  averagePaceSecondsPerKm: 390,
);

const unavailablePaceGraph = PaceGraphSnapshot.unavailable();
