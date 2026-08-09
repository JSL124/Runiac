import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/pace_analysis_series.dart';

void main() {
  group('PaceAnalysisSeries', () {
    test('valid accepted samples are included in source order', () {
      final series = PaceAnalysisSeries.localAccepted(
        samples: <PaceAnalysisSample>[
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
      );

      expect(series.source, PaceAnalysisSource.localAccepted);
      expect(series.confidence, PaceAnalysisConfidence.derived);
      expect(series.validAcceptedSamples, hasLength(3));
      expect(
        series.validAcceptedSamples.map((sample) => sample.paceSecondsPerKm),
        <int>[400, 410, 420],
      );
      expect(series.hasMinimumValidSamples(), isTrue);
    });

    test('samples are defensively copied and exposed as unmodifiable', () {
      final inputSamples = <PaceAnalysisSample>[
        const PaceAnalysisSample.accepted(
          elapsedSeconds: 60,
          cumulativeDistanceMeters: 250,
          paceSecondsPerKm: 400,
        ),
        const PaceAnalysisSample.accepted(
          elapsedSeconds: 120,
          cumulativeDistanceMeters: 500,
          paceSecondsPerKm: 410,
        ),
        const PaceAnalysisSample.accepted(
          elapsedSeconds: 180,
          cumulativeDistanceMeters: 750,
          paceSecondsPerKm: 420,
        ),
      ];
      final series = PaceAnalysisSeries.localAccepted(samples: inputSamples);

      expect(series.samples, hasLength(3));
      expect(series.hasMinimumValidSamples(), isTrue);

      inputSamples
        ..clear()
        ..add(
          const PaceAnalysisSample.accepted(
            elapsedSeconds: 60,
            cumulativeDistanceMeters: 250,
            paceSecondsPerKm: 0,
          ),
        );

      expect(series.samples, hasLength(3));
      expect(series.validAcceptedSamples, hasLength(3));
      expect(series.hasMinimumValidSamples(), isTrue);
      expect(
        () => series.samples.add(
          const PaceAnalysisSample.accepted(
            elapsedSeconds: 240,
            cumulativeDistanceMeters: 1000,
            paceSecondsPerKm: 430,
          ),
        ),
        throwsUnsupportedError,
      );
      expect(series.hasMinimumValidSamples(), isTrue);
    });

    test('rejected samples are excluded from valid accepted samples', () {
      final series = PaceAnalysisSeries.localAccepted(
        samples: <PaceAnalysisSample>[
          PaceAnalysisSample.accepted(
            elapsedSeconds: 60,
            cumulativeDistanceMeters: 250,
            paceSecondsPerKm: 400,
          ),
          PaceAnalysisSample.rejected(
            elapsedSeconds: 120,
            cumulativeDistanceMeters: 500,
            paceSecondsPerKm: 405,
            rejectionReason: PaceAnalysisSampleRejectionReason.gpsRejected,
          ),
          PaceAnalysisSample.accepted(
            elapsedSeconds: 180,
            cumulativeDistanceMeters: 750,
            paceSecondsPerKm: 410,
          ),
        ],
      );

      expect(series.validAcceptedSamples, hasLength(2));
      expect(
        series.validAcceptedSamples.map((sample) => sample.elapsedSeconds),
        <int>[60, 180],
      );
      expect(series.hasMinimumValidSamples(), isFalse);
    });

    test('invalid pace and non-finite distance samples are excluded', () {
      final series = PaceAnalysisSeries.localAccepted(
        samples: const <PaceAnalysisSample>[
          PaceAnalysisSample.accepted(
            elapsedSeconds: 60,
            cumulativeDistanceMeters: 250,
            paceSecondsPerKm: 400,
          ),
          PaceAnalysisSample.accepted(
            elapsedSeconds: 120,
            cumulativeDistanceMeters: double.nan,
            paceSecondsPerKm: 405,
          ),
          PaceAnalysisSample.accepted(
            elapsedSeconds: 180,
            cumulativeDistanceMeters: 750,
            paceSecondsPerKm: 0,
          ),
          PaceAnalysisSample.accepted(
            elapsedSeconds: 240,
            cumulativeDistanceMeters: 1000,
            paceSecondsPerKm: 1801,
          ),
          PaceAnalysisSample.accepted(
            elapsedSeconds: 300,
            cumulativeDistanceMeters: 1250,
            paceSecondsPerKm: 410,
          ),
        ],
      );

      expect(series.validAcceptedSamples, hasLength(2));
      expect(
        series.validAcceptedSamples.map((sample) => sample.elapsedSeconds),
        <int>[60, 300],
      );
    });

    test('monotonic elapsed and distance validation detects invalid order', () {
      final monotonic = PaceAnalysisSeries.localAccepted(
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
      );
      final nonMonotonicElapsed = PaceAnalysisSeries.localAccepted(
        samples: const <PaceAnalysisSample>[
          PaceAnalysisSample.accepted(
            elapsedSeconds: 60,
            cumulativeDistanceMeters: 250,
            paceSecondsPerKm: 400,
          ),
          PaceAnalysisSample.accepted(
            elapsedSeconds: 60,
            cumulativeDistanceMeters: 500,
            paceSecondsPerKm: 410,
          ),
          PaceAnalysisSample.accepted(
            elapsedSeconds: 180,
            cumulativeDistanceMeters: 750,
            paceSecondsPerKm: 420,
          ),
        ],
      );
      final nonMonotonicDistance = PaceAnalysisSeries.localAccepted(
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
      );

      expect(monotonic.hasMonotonicValidSamples, isTrue);
      expect(nonMonotonicElapsed.hasMonotonicValidSamples, isFalse);
      expect(nonMonotonicDistance.hasMonotonicValidSamples, isFalse);
    });

    test(
      'demo and unavailable sources are distinguishable from local source',
      () {
        final local = PaceAnalysisSeries.localAccepted(
          samples: const <PaceAnalysisSample>[],
        );
        final demo = PaceAnalysisSeries.staticDemo(
          samples: const <PaceAnalysisSample>[],
        );
        final unavailable = PaceAnalysisSeries.unavailable();

        expect(local.isLocalAcceptedSource, isTrue);
        expect(local.isStaticDemoSource, isFalse);
        expect(demo.isStaticDemoSource, isTrue);
        expect(demo.confidence, PaceAnalysisConfidence.demo);
        expect(unavailable.isUnavailable, isTrue);
        expect(unavailable.confidence, PaceAnalysisConfidence.unavailable);
      },
    );

    test('low-sample series can be identified as insufficient', () {
      final series = PaceAnalysisSeries.localAccepted(
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
      );

      expect(series.validAcceptedSamples, hasLength(2));
      expect(series.hasMinimumValidSamples(), isFalse);
      expect(series.hasMinimumValidSamples(minimumSampleCount: 2), isTrue);
    });

    test('run pace input requires local source and minimum run quality', () {
      final readyInput = RunPaceAnalysisInput(
        durationSeconds: 180,
        distanceMeters: 750,
        series: PaceAnalysisSeries.localAccepted(
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
      final shortInput = RunPaceAnalysisInput(
        durationSeconds: 59,
        distanceMeters: 750,
        series: readyInput.series,
      );
      final demoInput = RunPaceAnalysisInput(
        durationSeconds: 180,
        distanceMeters: 750,
        series: PaceAnalysisSeries.staticDemo(
          samples: readyInput.series.samples,
        ),
      );

      expect(readyInput.hasMinimumDurationAndDistance, isTrue);
      expect(readyInput.hasSufficientLocalSeries, isTrue);
      expect(shortInput.hasMinimumDurationAndDistance, isFalse);
      expect(shortInput.hasSufficientLocalSeries, isFalse);
      expect(demoInput.hasMinimumDurationAndDistance, isTrue);
      expect(demoInput.hasSufficientLocalSeries, isFalse);
    });

    test('invalid source and confidence combinations are rejected', () {
      expect(
        () => PaceAnalysisSeries(
          source: PaceAnalysisSource.localAccepted,
          confidence: PaceAnalysisConfidence.demo,
          samples: const <PaceAnalysisSample>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PaceAnalysisSeries(
          source: PaceAnalysisSource.staticDemo,
          confidence: PaceAnalysisConfidence.derived,
          samples: const <PaceAnalysisSample>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PaceAnalysisSeries(
          source: PaceAnalysisSource.unavailableUnknown,
          confidence: PaceAnalysisConfidence.derived,
          samples: const <PaceAnalysisSample>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PaceAnalysisSeries(
          source: PaceAnalysisSource.unavailableUnknown,
          confidence: PaceAnalysisConfidence.unavailable,
          samples: const <PaceAnalysisSample>[
            PaceAnalysisSample.accepted(
              elapsedSeconds: 60,
              cumulativeDistanceMeters: 250,
              paceSecondsPerKm: 400,
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('sample status and rejection reason invariants are enforced', () {
      expect(
        () => PaceAnalysisSample(
          elapsedSeconds: 60,
          cumulativeDistanceMeters: 250,
          paceSecondsPerKm: 400,
          status: PaceAnalysisSampleStatus.accepted,
          rejectionReason: PaceAnalysisSampleRejectionReason.gpsRejected,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PaceAnalysisSample(
          elapsedSeconds: 60,
          cumulativeDistanceMeters: 250,
          paceSecondsPerKm: 400,
          status: PaceAnalysisSampleStatus.rejected,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PaceAnalysisSample.rejected(
          elapsedSeconds: 60,
          cumulativeDistanceMeters: 250,
          paceSecondsPerKm: 400,
          rejectionReason: PaceAnalysisSampleRejectionReason.none,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
