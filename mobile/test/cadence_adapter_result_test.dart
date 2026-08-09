import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/cadence_adapter_result.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_derivation.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/services/cadence_analysis_deriver.dart';

void main() {
  group('CadenceAdapterResult', () {
    const deriver = CadenceAnalysisDeriver();

    test('trusted timestamped samples normalize into cadence series', () {
      final result = CadenceAdapterResult(
        source: CadenceAnalysisSource.healthKitAppleWatch,
        confidence: CadenceAnalysisConfidence.high,
        samples: const <CadenceAnalysisSample>[
          CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
          CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 164),
          CadenceAnalysisSample.accepted(elapsedSeconds: 240, cadenceSpm: 166),
        ],
      );

      final series = result.toAnalysisSeries();
      final derivation = deriver.derive(series);

      expect(series.source, CadenceAnalysisSource.healthKitAppleWatch);
      expect(series.confidence, CadenceAnalysisConfidence.high);
      expect(series.isLocalAcceptedSource, isFalse);
      expect(series.validAcceptedSamples, hasLength(3));
      expect(derivation.isAvailable, isTrue);
      expect(derivation.averageCadenceSpm, 164);
      expect(result.affectsBackendOwnedProgression, isFalse);
    });

    test('summary-only cadence does not produce trend or stability', () {
      final result = CadenceAdapterResult(
        source: CadenceAnalysisSource.healthConnect,
        confidence: CadenceAnalysisConfidence.high,
        samples: const <CadenceAnalysisSample>[],
        summaryCadenceSpm: 166,
      );

      final derivation = deriver.derive(result.toAnalysisSeries());

      expect(derivation.isAvailable, isFalse);
      expect(
        derivation.unavailableReason,
        CadenceAnalysisUnavailableReason.insufficientSamples,
      );
      expect(derivation.trend, CadenceTrend.insufficientData);
      expect(derivation.stability, CadenceStability.insufficientData);
    });

    test('too few timestamped samples remain insufficient', () {
      final result = CadenceAdapterResult(
        source: CadenceAnalysisSource.garminWearable,
        confidence: CadenceAnalysisConfidence.high,
        samples: const <CadenceAnalysisSample>[
          CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
          CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 164),
        ],
      );

      final derivation = deriver.derive(result.toAnalysisSeries());

      expect(derivation.isAvailable, isFalse);
      expect(
        derivation.unavailableReason,
        CadenceAnalysisUnavailableReason.insufficientSamples,
      );
    });

    test('static demo cadence cannot enter production analysis', () {
      final result = CadenceAdapterResult(
        source: CadenceAnalysisSource.staticDemo,
        confidence: CadenceAnalysisConfidence.demo,
        samples: const <CadenceAnalysisSample>[
          CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
          CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 164),
          CadenceAnalysisSample.accepted(elapsedSeconds: 240, cadenceSpm: 166),
        ],
      );

      final series = result.toAnalysisSeries();
      final derivation = deriver.derive(series);

      expect(series.isProductionAnalysisEligible, isFalse);
      expect(derivation.isAvailable, isFalse);
      expect(
        derivation.unavailableReason,
        CadenceAnalysisUnavailableReason.staticDemoSource,
      );
    });

    test('rejects summary-only cadence mixed with samples', () {
      expect(
        () => CadenceAdapterResult(
          source: CadenceAnalysisSource.healthConnect,
          confidence: CadenceAnalysisConfidence.high,
          samples: const <CadenceAnalysisSample>[
            CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
          ],
          summaryCadenceSpm: 166,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects unavailable cadence mixed with data', () {
      expect(
        () => CadenceAdapterResult(
          source: CadenceAnalysisSource.healthConnect,
          confidence: CadenceAnalysisConfidence.high,
          samples: const <CadenceAnalysisSample>[
            CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
          ],
          unavailableReason: 'not shared',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CadenceAdapterResult(
          source: CadenceAnalysisSource.healthConnect,
          confidence: CadenceAnalysisConfidence.high,
          samples: const <CadenceAnalysisSample>[],
          summaryCadenceSpm: 166,
          unavailableReason: 'not shared',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
