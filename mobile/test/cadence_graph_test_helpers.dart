import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/cadence_graph_snapshot.dart';

const sampleCadenceGraphDurationSeconds = 300;

void registerCadenceGraphSnapshotModelTests() {
  group('Cadence graph snapshot model', () {
    test('represents unavailable cadence graph without chart metadata', () {
      const graph = CadenceGraphSnapshot.unavailable(
        unavailableReason: 'static_demo_cadence_graph',
      );

      expectUnavailableCadenceGraphModel(graph);
    });

    test('exposes explicit demo target metadata for available graphs', () {
      const lowestPoint = CadenceGraphPoint(
        elapsedSeconds: 60,
        progressFraction: 0.2,
        cadenceSpm: 168,
        displayLabel: '168 spm',
      );
      const highestPoint = CadenceGraphPoint(
        elapsedSeconds: 240,
        progressFraction: 0.8,
        cadenceSpm: 176,
        displayLabel: '176 spm',
      );
      const graph = CadenceGraphSnapshot(
        isAvailable: true,
        points: <CadenceGraphPoint>[lowestPoint, highestPoint],
        yAxisLabels: <String>['160', '170', '180'],
        xAxisLabels: <String>['0:00', '2:30', '5:00'],
        totalDurationSeconds: 300,
        averageCadenceSpm: 172,
        lowestCadencePoint: lowestPoint,
        highestCadencePoint: highestPoint,
        cadenceRangeMinSpm: 158,
        cadenceRangeMaxSpm: 182,
        targetMinCadenceSpm: demoCadenceGraphTargetMinSpm,
        targetMaxCadenceSpm: demoCadenceGraphTargetMaxSpm,
        targetLabel: demoCadenceGraphTargetLabel,
        targetKind: CadenceGraphTargetKind.demo,
      );

      expectDemoTargetCadenceGraphModel(graph);
    });
  });
}

List<CadenceAnalysisSample> acceptedCadenceSamples() {
  return const <CadenceAnalysisSample>[
    CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 168),
    CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 172),
    CadenceAnalysisSample.accepted(elapsedSeconds: 240, cadenceSpm: 176),
  ];
}

List<CadenceAnalysisSample> wearableCadenceSamples() {
  return const <CadenceAnalysisSample>[
    CadenceAnalysisSample.accepted(elapsedSeconds: 30, cadenceSpm: 166),
    CadenceAnalysisSample.accepted(elapsedSeconds: 90, cadenceSpm: 169),
    CadenceAnalysisSample.accepted(elapsedSeconds: 180, cadenceSpm: 171),
  ];
}

List<CadenceAnalysisSample> insufficientCadenceSamples() {
  return const <CadenceAnalysisSample>[
    CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 168),
    CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 172),
  ];
}

List<CadenceAnalysisSample> invalidAndRejectedCadenceSamples() {
  return <CadenceAnalysisSample>[
    CadenceAnalysisSample(
      elapsedSeconds: -1,
      cadenceSpm: 168,
      status: CadenceAnalysisSampleStatus.accepted,
    ),
    CadenceAnalysisSample.rejected(
      elapsedSeconds: 30,
      cadenceSpm: 160,
      rejectionReason: CadenceAnalysisSampleRejectionReason.invalidCadence,
    ),
    CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 168),
    CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 172),
    CadenceAnalysisSample(
      elapsedSeconds: 180,
      cadenceSpm: double.nan,
      status: CadenceAnalysisSampleStatus.accepted,
    ),
  ];
}

List<CadenceAnalysisSample> nonMonotonicCadenceSamples() {
  return const <CadenceAnalysisSample>[
    CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 168),
    CadenceAnalysisSample.accepted(elapsedSeconds: 240, cadenceSpm: 176),
    CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 172),
  ];
}

List<CadenceAnalysisSample> cadenceSamplesWithOutOfDurationSample() {
  return const <CadenceAnalysisSample>[
    CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 168),
    CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 172),
    CadenceAnalysisSample.accepted(elapsedSeconds: 240, cadenceSpm: 176),
    CadenceAnalysisSample.accepted(elapsedSeconds: 360, cadenceSpm: 178),
  ];
}

List<CadenceAnalysisSample> insufficientInDurationCadenceSamples() {
  return const <CadenceAnalysisSample>[
    CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 168),
    CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 172),
    CadenceAnalysisSample.accepted(elapsedSeconds: 360, cadenceSpm: 178),
  ];
}

List<CadenceAnalysisSample> tightRangeCadenceSamples() {
  return const <CadenceAnalysisSample>[
    CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 170),
    CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 171),
    CadenceAnalysisSample.accepted(elapsedSeconds: 180, cadenceSpm: 172),
  ];
}

CadenceAnalysisSeries localAcceptedCadenceSeries({
  List<CadenceAnalysisSample>? samples,
}) {
  return CadenceAnalysisSeries.localAccepted(
    samples: samples ?? acceptedCadenceSamples(),
  );
}

void expectUnavailableCadenceGraphModel(CadenceGraphSnapshot graph) {
  expect(graph.isAvailable, isFalse);
  expect(graph.points, isEmpty);
  expect(graph.yAxisLabels, isEmpty);
  expect(graph.xAxisLabels, isEmpty);
  expect(graph.unavailableReason, 'static_demo_cadence_graph');
  expect(graph.totalDurationSeconds, isNull);
  expect(graph.averageCadenceSpm, isNull);
  expect(graph.lowestCadencePoint, isNull);
  expect(graph.highestCadencePoint, isNull);
  expect(graph.cadenceRangeMinSpm, isNull);
  expect(graph.cadenceRangeMaxSpm, isNull);
  expect(graph.targetMinCadenceSpm, isNull);
  expect(graph.targetMaxCadenceSpm, isNull);
  expect(graph.targetLabel, isNull);
  expect(graph.targetKind, isNull);
}

void expectDemoTargetCadenceGraphModel(CadenceGraphSnapshot graph) {
  expect(graph.isAvailable, isTrue);
  expect(graph.points, hasLength(2));
  expect(graph.lowestCadencePoint, same(graph.points.first));
  expect(graph.highestCadencePoint, same(graph.points.last));
  expect(graph.targetLabel, 'Demo Target 160-175');
  expect(graph.targetMinCadenceSpm, 160);
  expect(graph.targetMaxCadenceSpm, 175);
  expect(graph.targetKind, CadenceGraphTargetKind.demo);
}

void expectSampleBackedCadenceGraph(CadenceGraphSnapshot graph) {
  expect(graph.isAvailable, isTrue);
  expect(graph.unavailableReason, isNull);
  expect(graph.points.map((point) => point.elapsedSeconds), <int>[
    60,
    120,
    240,
  ]);
  expect(graph.points.map((point) => point.cadenceSpm), <int>[168, 172, 176]);
  expect(graph.points.map((point) => point.progressFraction), <double>[
    0.2,
    0.4,
    0.8,
  ]);
  expect(graph.points.map((point) => point.displayLabel), <String>[
    '168 spm',
    '172 spm',
    '176 spm',
  ]);
  expect(graph.xAxisLabels, <String>['0:00', '2:00', '5:00']);
  expect(graph.yAxisLabels, <String>['160', '170', '180']);
  expect(graph.totalDurationSeconds, 300);
  expect(graph.averageCadenceSpm, 172);
  expect(graph.lowestCadencePoint?.cadenceSpm, 168);
  expect(graph.highestCadencePoint?.cadenceSpm, 176);
  expect(graph.cadenceRangeMinSpm, 160);
  expect(graph.cadenceRangeMaxSpm, 180);
  expect(graph.targetLabel, 'Demo Target 160-175');
  expect(graph.targetMinCadenceSpm, 160);
  expect(graph.targetMaxCadenceSpm, 175);
  expect(graph.targetKind, CadenceGraphTargetKind.demo);
}
