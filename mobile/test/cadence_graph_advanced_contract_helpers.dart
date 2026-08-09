import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/run_source_display.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';

import 'cadence_graph_test_helpers.dart';

void registerCadenceGraphDataContractTests() {
  group('Cadence graph data contract', () {
    const builder = AdvancedAnalysisSnapshotBuilder();

    test(
      'exposes sample-backed ordered points labels and demo target metadata',
      () {
        final summary = cadenceGraphRunSummary(
          title: 'Local Cadence Graph Run',
          series: localAcceptedCadenceSeries(),
        );
        final cadenceGraph = builder
            .fromRunSummary(summary)
            .formCadence
            .cadenceGraph;

        expect(
          cadenceGraph.availability,
          AdvancedAnalysisMetricAvailability.available,
        );
        expect(
          cadenceGraph.source,
          AdvancedAnalysisMetricSource.localGpsDerived,
        );
        expect(
          cadenceGraph.confidence,
          AdvancedAnalysisMetricConfidence.derived,
        );
        expectAdvancedCadenceGraphContract(cadenceGraph.value);
      },
    );

    test('keeps static demo and insufficient cadence graphs unavailable', () {
      final cases = <UnavailableCadenceGraphCase>[
        UnavailableCadenceGraphCase(
          name: 'static demo',
          series: CadenceAnalysisSeries.staticDemo(
            samples: acceptedCadenceSamples(),
          ),
        ),
        UnavailableCadenceGraphCase(
          name: 'insufficient samples',
          series: localAcceptedCadenceSeries(
            samples: const <CadenceAnalysisSample>[
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 60,
                cadenceSpm: 168,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 120,
                cadenceSpm: 172,
              ),
            ],
          ),
        ),
      ];

      for (final testCase in cases) {
        final summary = cadenceGraphRunSummary(
          title: '${testCase.name} Cadence Graph Run',
          series: testCase.series,
          sourceType: testCase.sourceType,
        );
        final cadenceGraph = builder
            .fromRunSummary(summary)
            .formCadence
            .cadenceGraph;

        expectUnavailableAdvancedCadenceGraph(cadenceGraph, testCase.name);
      }
    });
  });
}

RunSummarySnapshot cadenceGraphRunSummary({
  required String title,
  required CadenceAnalysisSeries series,
  String duration = '5:00',
  RunSourceType sourceType = RunSourceType.runiacGps,
}) {
  return RunSummarySnapshot(
    title: title,
    dateLabel: 'Today',
    timeLabel: '7:06 AM',
    distanceKm: '4.03 km',
    avgPace: '6\'30" / km',
    duration: duration,
    avgHeartRate: '--',
    calories: '212 kcal',
    routeName: 'East Coast Park Loop',
    sourceType: sourceType,
    cadenceAnalysisSeries: series,
  );
}

void expectAdvancedCadenceGraphContract(Object? value) {
  if (value == null) {
    fail('Missing sample-backed cadence graph contract: value is null.');
  }

  try {
    final dynamic graph = value;
    final points = List<dynamic>.from(graph.points as Iterable<dynamic>);

    expect(points, hasLength(3));
    expect(points.map((dynamic point) => point.elapsedSeconds), <int>[
      60,
      120,
      240,
    ]);
    expect(points.map((dynamic point) => point.cadenceSpm), <int>[
      168,
      172,
      176,
    ]);
    expect(points.map((dynamic point) => point.progressFraction), <double>[
      0.2,
      0.4,
      0.8,
    ]);
    expect(graph.xAxisLabels, <String>['0:00', '2:00', '5:00']);
    expect(graph.yAxisLabels, isNotEmpty);
    expect(graph.targetLabel, 'Demo Target 160-175');
    expect(graph.targetMinCadenceSpm, 160);
    expect(graph.targetMaxCadenceSpm, 175);
  } on Object catch (error) {
    fail(
      'Missing sample-backed cadence graph contract: expected '
      'cadenceGraph.value to expose ordered points, xAxisLabels, '
      'yAxisLabels, targetLabel Demo Target 160-175, and target range '
      'metadata. Actual value type was ${value.runtimeType}; error: $error',
    );
  }
}

class UnavailableCadenceGraphCase {
  const UnavailableCadenceGraphCase({
    required this.name,
    required this.series,
    this.sourceType = RunSourceType.runiacGps,
  });

  final String name;
  final CadenceAnalysisSeries series;
  final RunSourceType sourceType;
}

void expectUnavailableAdvancedCadenceGraph<T>(
  AdvancedAnalysisMetric<T> cadenceGraph,
  String reason,
) {
  expect(cadenceGraph.isAvailable, isFalse, reason: reason);
  expect(
    cadenceGraph.reason,
    AdvancedAnalysisMetricReason.missingCadenceSource,
    reason: reason,
  );
  expect(cadenceGraph.value, isNull, reason: reason);
}
