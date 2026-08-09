import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/run_source_display.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';
import 'package:runiac_app/features/run/presentation/widgets/advanced_analysis/advanced_analysis_charts.dart';
import 'package:runiac_app/features/run/presentation/widgets/advanced_analysis/advanced_analysis_route_form_sections.dart';

import 'cadence_graph_advanced_contract_helpers.dart';
import 'cadence_graph_test_helpers.dart';

void main() {
  registerCadenceGraphDataContractTests();

  group('Advanced cadence graph snapshot wiring', () {
    const builder = AdvancedAnalysisSnapshotBuilder();

    test('parses supported and rejected duration labels explicitly', () {
      const validDurations = <String, int>{
        '5:00': 300,
        '05:00': 300,
        '1:05:00': 3900,
      };
      const invalidDurations = <String>[
        '',
        '   ',
        '--',
        'abc',
        '-1:00',
        '0:00',
        '1:2',
        '1:60',
        '1:00:60',
        '1:2:03',
        '5',
      ];

      for (final entry in validDurations.entries) {
        final metric = builder
            .fromRunSummary(
              cadenceGraphRunSummary(
                title: 'Duration ${entry.key}',
                duration: entry.key,
                series: localAcceptedCadenceSeries(),
              ),
            )
            .formCadence
            .cadenceGraph;

        expect(metric.isAvailable, isTrue, reason: entry.key);
        expect(metric.value?.totalDurationSeconds, entry.value);
      }

      for (final duration in invalidDurations) {
        final metric = builder
            .fromRunSummary(
              cadenceGraphRunSummary(
                title: 'Duration $duration',
                duration: duration,
                series: localAcceptedCadenceSeries(),
              ),
            )
            .formCadence
            .cadenceGraph;

        expectUnavailableAdvancedCadenceGraph(metric, duration);
      }
    });

    test('preserves source mapping and rejects ineligible graph sources', () {
      final availableCases = <_CadenceGraphSourceCase>[
        _CadenceGraphSourceCase(
          name: 'local',
          sourceType: RunSourceType.runiacGps,
          series: localAcceptedCadenceSeries(),
          expectedSource: AdvancedAnalysisMetricSource.localGpsDerived,
        ),
        _CadenceGraphSourceCase(
          name: 'apple',
          sourceType: RunSourceType.appleHealth,
          series: _cadenceSeries(
            CadenceAnalysisSource.healthKitAppleWatch,
            CadenceAnalysisConfidence.high,
          ),
          expectedSource: AdvancedAnalysisMetricSource.healthKitAppleWatch,
        ),
        _CadenceGraphSourceCase(
          name: 'health connect',
          sourceType: RunSourceType.healthConnect,
          series: _cadenceSeries(
            CadenceAnalysisSource.healthConnect,
            CadenceAnalysisConfidence.high,
          ),
          expectedSource: AdvancedAnalysisMetricSource.healthConnect,
        ),
        _CadenceGraphSourceCase(
          name: 'garmin',
          sourceType: RunSourceType.garminViaHealth,
          series: _cadenceSeries(
            CadenceAnalysisSource.garminWearable,
            CadenceAnalysisConfidence.high,
          ),
          expectedSource: AdvancedAnalysisMetricSource.garminWearable,
        ),
        _CadenceGraphSourceCase(
          name: 'phone motion',
          sourceType: RunSourceType.runiacGps,
          series: _cadenceSeries(
            CadenceAnalysisSource.phoneSensorEstimated,
            CadenceAnalysisConfidence.low,
          ),
          expectedSource: AdvancedAnalysisMetricSource.phoneSensorEstimated,
          expectedConfidence: AdvancedAnalysisMetricConfidence.estimated,
        ),
        _CadenceGraphSourceCase(
          name: 'backend',
          sourceType: RunSourceType.runiacGps,
          series: _cadenceSeries(
            CadenceAnalysisSource.backendDerived,
            CadenceAnalysisConfidence.medium,
          ),
          expectedSource: AdvancedAnalysisMetricSource.backendDerived,
        ),
      ];

      for (final testCase in availableCases) {
        final metric = builder
            .fromRunSummary(
              cadenceGraphRunSummary(
                title: testCase.name,
                sourceType: testCase.sourceType,
                series: testCase.series,
              ),
            )
            .formCadence
            .cadenceGraph;

        expect(metric.isAvailable, isTrue, reason: testCase.name);
        expect(metric.source, testCase.expectedSource, reason: testCase.name);
        expect(
          metric.confidence,
          testCase.expectedConfidence,
          reason: testCase.name,
        );
        expect(metric.isTrustedProduction, isFalse);
      }

      final unavailableCases = <UnavailableCadenceGraphCase>[
        UnavailableCadenceGraphCase(
          name: 'source mismatch',
          sourceType: RunSourceType.appleHealth,
          series: localAcceptedCadenceSeries(),
        ),
      ];
      for (final testCase in unavailableCases) {
        final metric = builder
            .fromRunSummary(
              cadenceGraphRunSummary(
                title: testCase.name,
                sourceType: testCase.sourceType,
                series: testCase.series,
              ),
            )
            .formCadence
            .cadenceGraph;

        expectUnavailableAdvancedCadenceGraph(metric, testCase.name);
      }
    });

    testWidgets(
      'does not enable demo cadence chart fallback when production graph is unavailable',
      (tester) async {
        final cadence = builder
            .fromRunSummary(
              cadenceGraphRunSummary(
                title: 'Insufficient cadence production run',
                series: localAcceptedCadenceSeries(
                  samples: insufficientCadenceSamples(),
                ),
              ),
            )
            .formCadence;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: AdvancedAnalysisCadenceSection(analysis: cadence),
          ),
        );

        expect(cadence.cadenceGraph.isAvailable, isFalse);
        expect(cadence.cadenceGraph.value, isNull);
        final cadencePainter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<AdvancedAnalysisCadenceChartPainter>()
            .single;
        expect(cadencePainter.graph, isNull);
        expect(cadencePainter.showDemoFallback, isFalse);
      },
    );
  });
}

CadenceAnalysisSeries _cadenceSeries(
  CadenceAnalysisSource source,
  CadenceAnalysisConfidence confidence,
) {
  return CadenceAnalysisSeries(
    source: source,
    confidence: confidence,
    samples: acceptedCadenceSamples(),
  );
}

class _CadenceGraphSourceCase {
  const _CadenceGraphSourceCase({
    required this.name,
    required this.sourceType,
    required this.series,
    required this.expectedSource,
    this.expectedConfidence = AdvancedAnalysisMetricConfidence.derived,
  });

  final String name;
  final RunSourceType sourceType;
  final CadenceAnalysisSeries series;
  final AdvancedAnalysisMetricSource expectedSource;
  final AdvancedAnalysisMetricConfidence expectedConfidence;
}
