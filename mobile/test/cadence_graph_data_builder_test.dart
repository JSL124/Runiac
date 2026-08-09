import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/services/cadence_graph_data_builder.dart';

import 'cadence_graph_test_helpers.dart';

void main() {
  registerCadenceGraphSnapshotModelTests();

  group('CadenceGraphDataBuilder', () {
    const builder = CadenceGraphDataBuilder();

    test(
      'builds sample-backed cadence graph from eligible timestamped samples',
      () {
        final graph = builder.build(
          series: localAcceptedCadenceSeries(),
          durationSeconds: sampleCadenceGraphDurationSeconds,
        );

        expectSampleBackedCadenceGraph(graph);
      },
    );

    test(
      'builds high-confidence wearable cadence graph without relabeling source',
      () {
        final series = CadenceAnalysisSeries(
          source: CadenceAnalysisSource.garminWearable,
          confidence: CadenceAnalysisConfidence.high,
          samples: wearableCadenceSamples(),
        );

        final graph = builder.build(series: series, durationSeconds: 240);

        expect(graph.isAvailable, isTrue);
        expect(series.source, CadenceAnalysisSource.garminWearable);
        expect(series.confidence, CadenceAnalysisConfidence.high);
        expect(series.isLocalAcceptedSource, isFalse);
        expect(series.isProductionAnalysisEligible, isTrue);
      },
    );

    test('keeps static demo cadence graph unavailable', () {
      final staticDemo = builder.build(
        series: CadenceAnalysisSeries.staticDemo(
          samples: acceptedCadenceSamples(),
        ),
        durationSeconds: sampleCadenceGraphDurationSeconds,
      );
      final unavailable = builder.build(
        series: CadenceAnalysisSeries.unavailable(),
        durationSeconds: sampleCadenceGraphDurationSeconds,
      );

      expect(staticDemo.unavailableReason, 'static_demo_cadence_graph');
      expect(unavailable.unavailableReason, 'unavailable_cadence_source');
    });

    test('keeps insufficient cadence graph unavailable', () {
      final graph = builder.build(
        series: localAcceptedCadenceSeries(
          samples: insufficientCadenceSamples(),
        ),
        durationSeconds: sampleCadenceGraphDurationSeconds,
      );

      expect(graph.unavailableReason, 'insufficient_cadence_graph_samples');
    });

    test('ignores invalid and rejected samples via validAcceptedSamples', () {
      final graph = builder.build(
        series: localAcceptedCadenceSeries(
          samples: invalidAndRejectedCadenceSamples(),
        ),
        durationSeconds: sampleCadenceGraphDurationSeconds,
      );

      expect(graph.isAvailable, isFalse);
      expect(graph.unavailableReason, 'insufficient_cadence_graph_samples');
    });

    test('keeps non-positive duration cadence graph unavailable', () {
      for (final durationSeconds in <int>[0, -1]) {
        final graph = builder.build(
          series: localAcceptedCadenceSeries(),
          durationSeconds: durationSeconds,
        );

        expect(graph.unavailableReason, 'invalid_cadence_graph_duration');
      }
    });

    test('keeps original-order non-monotonic cadence graph unavailable', () {
      final graph = builder.build(
        series: localAcceptedCadenceSeries(
          samples: nonMonotonicCadenceSamples(),
        ),
        durationSeconds: sampleCadenceGraphDurationSeconds,
      );

      expect(graph.unavailableReason, 'non_monotonic_cadence_graph_samples');
    });

    test('drops out-of-duration samples before deciding availability', () {
      final availableGraph = builder.build(
        series: localAcceptedCadenceSeries(
          samples: cadenceSamplesWithOutOfDurationSample(),
        ),
        durationSeconds: sampleCadenceGraphDurationSeconds,
      );
      final unavailableGraph = builder.build(
        series: localAcceptedCadenceSeries(
          samples: insufficientInDurationCadenceSamples(),
        ),
        durationSeconds: sampleCadenceGraphDurationSeconds,
      );

      expect(availableGraph.points.map((point) => point.elapsedSeconds), <int>[
        60,
        120,
        240,
      ]);
      expect(
        unavailableGraph.unavailableReason,
        'insufficient_in_duration_cadence_graph_samples',
      );
    });

    test('applies cadence range padding and minimum visible range', () {
      final graph = builder.build(
        series: localAcceptedCadenceSeries(samples: tightRangeCadenceSamples()),
        durationSeconds: 240,
      );

      expect(graph.yAxisLabels, <String>['160', '170', '180']);
    });

    test(
      'keeps missing early cadence data truthful while target spans chart range',
      () {
        final graph = builder.build(
          series: localAcceptedCadenceSeries(
            samples: const [
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 120,
                cadenceSpm: 182,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 240,
                cadenceSpm: 184,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 360,
                cadenceSpm: 186,
              ),
            ],
          ),
          durationSeconds: 480,
        );

        expect(graph.isAvailable, isTrue);
        expect(graph.xAxisLabels.first, '0:00');
        expect(graph.xAxisLabels.last, '8:00');
        expect(graph.points.first.elapsedSeconds, 120);
        expect(graph.points.first.progressFraction, 0.25);
        expect(graph.cadenceRangeMinSpm, lessThanOrEqualTo(160));
        expect(graph.cadenceRangeMaxSpm, greaterThanOrEqualTo(175));
        expect(graph.targetLabel, 'Demo Target 160-175');
      },
    );

    test('uses a real 0:00 cadence sample when one is present', () {
      final graph = builder.build(
        series: localAcceptedCadenceSeries(
          samples: const [
            CadenceAnalysisSample.accepted(elapsedSeconds: 0, cadenceSpm: 170),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cadenceSpm: 172,
            ),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 240,
              cadenceSpm: 174,
            ),
          ],
        ),
        durationSeconds: 240,
      );

      expect(graph.isAvailable, isTrue);
      expect(graph.points.first.elapsedSeconds, 0);
      expect(graph.points.first.progressFraction, 0);
    });

    test(
      'does not change cadence source confidence or scalar eligibility rules',
      () {
        final local = localAcceptedCadenceSeries();
        final backend = CadenceAnalysisSeries(
          source: CadenceAnalysisSource.backendDerived,
          confidence: CadenceAnalysisConfidence.medium,
          samples: acceptedCadenceSamples(),
        );
        final phone = CadenceAnalysisSeries(
          source: CadenceAnalysisSource.phoneSensorEstimated,
          confidence: CadenceAnalysisConfidence.low,
          samples: acceptedCadenceSamples(),
        );

        expect(
          builder.build(series: local, durationSeconds: 300).isAvailable,
          isTrue,
        );
        expect(
          builder.build(series: backend, durationSeconds: 300).isAvailable,
          isTrue,
        );
        expect(
          builder.build(series: phone, durationSeconds: 300).isAvailable,
          isTrue,
        );
        expect(local.confidence, CadenceAnalysisConfidence.medium);
        expect(backend.source, CadenceAnalysisSource.backendDerived);
        expect(phone.source, CadenceAnalysisSource.phoneSensorEstimated);
      },
    );
  });
}
