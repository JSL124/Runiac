import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/pace_analysis_series.dart';
import 'package:runiac_app/features/run/domain/services/pace_analysis_deriver.dart';

void main() {
  group('PaceAnalysisDeriver', () {
    const deriver = PaceAnalysisDeriver();

    test(
      'derives fastest, slowest, and stability from valid local samples',
      () {
        final result = deriver.derive(
          PaceAnalysisSeries.localAccepted(
            samples: const <PaceAnalysisSample>[
              PaceAnalysisSample.accepted(
                elapsedSeconds: 60,
                cumulativeDistanceMeters: 250,
                paceSecondsPerKm: 420,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 120,
                cumulativeDistanceMeters: 500,
                paceSecondsPerKm: 360,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 180,
                cumulativeDistanceMeters: 750,
                paceSecondsPerKm: 480,
              ),
            ],
          ),
        );

        expect(result.isAvailable, isTrue);
        expect(result.fastestPaceSecondsPerKm, 360);
        expect(result.slowestPaceSecondsPerKm, 480);
        expect(result.paceStabilityScore, 33);
        expect(result.unavailableReason, PaceAnalysisUnavailableReason.none);
      },
    );

    test('ignores rejected, non-finite, and invalid samples', () {
      final result = deriver.derive(
        PaceAnalysisSeries.localAccepted(
          samples: <PaceAnalysisSample>[
            const PaceAnalysisSample.accepted(
              elapsedSeconds: 60,
              cumulativeDistanceMeters: 250,
              paceSecondsPerKm: 430,
            ),
            PaceAnalysisSample.rejected(
              elapsedSeconds: 120,
              cumulativeDistanceMeters: 500,
              paceSecondsPerKm: 300,
              rejectionReason: PaceAnalysisSampleRejectionReason.gpsRejected,
            ),
            const PaceAnalysisSample.accepted(
              elapsedSeconds: 180,
              cumulativeDistanceMeters: double.nan,
              paceSecondsPerKm: 350,
            ),
            const PaceAnalysisSample.accepted(
              elapsedSeconds: 240,
              cumulativeDistanceMeters: 1000,
              paceSecondsPerKm: 0,
            ),
            const PaceAnalysisSample.accepted(
              elapsedSeconds: 300,
              cumulativeDistanceMeters: 1250,
              paceSecondsPerKm: 450,
            ),
            const PaceAnalysisSample.accepted(
              elapsedSeconds: 360,
              cumulativeDistanceMeters: 1500,
              paceSecondsPerKm: 470,
            ),
          ],
        ),
      );

      expect(result.isAvailable, isTrue);
      expect(result.fastestPaceSecondsPerKm, 430);
      expect(result.slowestPaceSecondsPerKm, 470);
      expect(result.paceStabilityScore, 78);
    });

    test('returns unavailable for static demo source', () {
      final result = deriver.derive(
        PaceAnalysisSeries.staticDemo(
          samples: const <PaceAnalysisSample>[
            PaceAnalysisSample.accepted(
              elapsedSeconds: 60,
              cumulativeDistanceMeters: 250,
              paceSecondsPerKm: 400,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cumulativeDistanceMeters: 500,
              paceSecondsPerKm: 410,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 180,
              cumulativeDistanceMeters: 750,
              paceSecondsPerKm: 420,
            ),
          ],
        ),
      );

      expect(result.isAvailable, isFalse);
      expect(
        result.unavailableReason,
        PaceAnalysisUnavailableReason.staticDemoSource,
      );
    });

    test('returns unavailable for unavailable source', () {
      final result = deriver.derive(PaceAnalysisSeries.unavailable());

      expect(result.isAvailable, isFalse);
      expect(
        result.unavailableReason,
        PaceAnalysisUnavailableReason.unavailableSource,
      );
    });

    test('returns unavailable for non-monotonic local series', () {
      final result = deriver.derive(
        PaceAnalysisSeries.localAccepted(
          samples: const <PaceAnalysisSample>[
            PaceAnalysisSample.accepted(
              elapsedSeconds: 60,
              cumulativeDistanceMeters: 250,
              paceSecondsPerKm: 400,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cumulativeDistanceMeters: 200,
              paceSecondsPerKm: 410,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 180,
              cumulativeDistanceMeters: 750,
              paceSecondsPerKm: 420,
            ),
          ],
        ),
      );

      expect(result.isAvailable, isFalse);
      expect(
        result.unavailableReason,
        PaceAnalysisUnavailableReason.nonMonotonicSeries,
      );
    });

    test('returns unavailable for insufficient valid sample count', () {
      final result = deriver.derive(
        PaceAnalysisSeries.localAccepted(
          samples: const <PaceAnalysisSample>[
            PaceAnalysisSample.accepted(
              elapsedSeconds: 60,
              cumulativeDistanceMeters: 250,
              paceSecondsPerKm: 400,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cumulativeDistanceMeters: 500,
              paceSecondsPerKm: 410,
            ),
          ],
        ),
      );

      expect(result.isAvailable, isFalse);
      expect(
        result.unavailableReason,
        PaceAnalysisUnavailableReason.insufficientSamples,
      );
    });

    test('stable series scores higher than unstable series', () {
      final stable = deriver.derive(
        PaceAnalysisSeries.localAccepted(
          samples: const <PaceAnalysisSample>[
            PaceAnalysisSample.accepted(
              elapsedSeconds: 60,
              cumulativeDistanceMeters: 250,
              paceSecondsPerKm: 400,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cumulativeDistanceMeters: 500,
              paceSecondsPerKm: 405,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 180,
              cumulativeDistanceMeters: 750,
              paceSecondsPerKm: 410,
            ),
          ],
        ),
      );
      final unstable = deriver.derive(
        PaceAnalysisSeries.localAccepted(
          samples: const <PaceAnalysisSample>[
            PaceAnalysisSample.accepted(
              elapsedSeconds: 60,
              cumulativeDistanceMeters: 250,
              paceSecondsPerKm: 300,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cumulativeDistanceMeters: 500,
              paceSecondsPerKm: 600,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 180,
              cumulativeDistanceMeters: 750,
              paceSecondsPerKm: 900,
            ),
          ],
        ),
      );

      expect(stable.isAvailable, isTrue);
      expect(unstable.isAvailable, isTrue);
      expect(unstable.paceStabilityScore, 0);
      expect(
        stable.paceStabilityScore!,
        greaterThan(unstable.paceStabilityScore!),
      );
    });

    test('uses domain-only series source and exposes no display labels', () {
      final result = deriver.derive(
        PaceAnalysisSeries.localAccepted(
          samples: const <PaceAnalysisSample>[
            PaceAnalysisSample.accepted(
              elapsedSeconds: 60,
              cumulativeDistanceMeters: 250,
              paceSecondsPerKm: 400,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cumulativeDistanceMeters: 500,
              paceSecondsPerKm: 405,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 180,
              cumulativeDistanceMeters: 750,
              paceSecondsPerKm: 410,
            ),
          ],
        ),
      );

      expect(result.source, PaceAnalysisSource.localAccepted);
      expect(result.confidence, PaceAnalysisConfidence.derived);
      expect(result.fastestPaceSecondsPerKm, isA<int>());
      expect(result.slowestPaceSecondsPerKm, isA<int>());
      expect(result.paceStabilityScore, isA<int>());
    });

    test('derivation result constructors reject ambiguous states', () {
      expect(
        () => PaceAnalysisDerivation.available(
          source: PaceAnalysisSource.staticDemo,
          confidence: PaceAnalysisConfidence.demo,
          fastestPaceSecondsPerKm: 400,
          slowestPaceSecondsPerKm: 420,
          paceStabilityScore: 90,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PaceAnalysisDerivation.available(
          source: PaceAnalysisSource.localAccepted,
          confidence: PaceAnalysisConfidence.derived,
          fastestPaceSecondsPerKm: 400,
          slowestPaceSecondsPerKm: 420,
          paceStabilityScore: 101,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PaceAnalysisDerivation.unavailable(
          reason: PaceAnalysisUnavailableReason.none,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
