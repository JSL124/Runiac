import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';

void main() {
  group('CadenceAnalysisSeries', () {
    test('valid accepted samples are included in source order', () {
      final series = CadenceAnalysisSeries.localAccepted(
        samples: <CadenceAnalysisSample>[
          const CadenceAnalysisSample.accepted(
            elapsedSeconds: 60,
            cadenceSpm: 162,
          ),
          CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 164),
          CadenceAnalysisSample.accepted(elapsedSeconds: 190, cadenceSpm: 166),
        ],
      );

      expect(series.source, CadenceAnalysisSource.runiacLocalAccepted);
      expect(series.confidence, CadenceAnalysisConfidence.medium);
      expect(series.validAcceptedSamples, hasLength(3));
      expect(
        series.validAcceptedSamples.map((sample) => sample.cadenceSpm),
        <int>[162, 164, 166],
      );
      expect(series.hasMinimumValidSamples(), isTrue);
      expect(series.hasMonotonicValidSamples, isTrue);
    });

    test('samples are defensively copied and exposed as unmodifiable', () {
      final inputSamples = <CadenceAnalysisSample>[
        const CadenceAnalysisSample.accepted(
          elapsedSeconds: 60,
          cadenceSpm: 162,
        ),
        const CadenceAnalysisSample.accepted(
          elapsedSeconds: 120,
          cadenceSpm: 164,
        ),
        const CadenceAnalysisSample.accepted(
          elapsedSeconds: 190,
          cadenceSpm: 166,
        ),
      ];

      final series = CadenceAnalysisSeries.localAccepted(samples: inputSamples);
      inputSamples.clear();

      expect(series.samples, hasLength(3));
      expect(
        () => series.samples.add(
          const CadenceAnalysisSample.accepted(
            elapsedSeconds: 240,
            cadenceSpm: 168,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('invalid cadence and invalid elapsed samples are excluded', () {
      final series = CadenceAnalysisSeries.localAccepted(
        samples: <CadenceAnalysisSample>[
          const CadenceAnalysisSample.accepted(
            elapsedSeconds: 60,
            cadenceSpm: 162,
          ),
          CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 0),
          CadenceAnalysisSample.accepted(elapsedSeconds: 190, cadenceSpm: -4),
          CadenceAnalysisSample.accepted(elapsedSeconds: 240, cadenceSpm: 321),
          CadenceAnalysisSample.accepted(elapsedSeconds: -1, cadenceSpm: 166),
          CadenceAnalysisSample.accepted(elapsedSeconds: 300, cadenceSpm: 164),
        ],
      );

      expect(series.validAcceptedSamples, hasLength(2));
      expect(
        series.validAcceptedSamples.map((sample) => sample.elapsedSeconds),
        <int>[60, 300],
      );
    });

    test('cadence safety contract includes 40 through 240 spm', () {
      final series = CadenceAnalysisSeries.phoneMotionEstimated(
        samples: const <CadenceAnalysisSample>[
          CadenceAnalysisSample.accepted(elapsedSeconds: 1, cadenceSpm: 40),
          CadenceAnalysisSample.accepted(elapsedSeconds: 2, cadenceSpm: 240),
          CadenceAnalysisSample.accepted(elapsedSeconds: 3, cadenceSpm: 241),
        ],
      );

      expect(
        series.validAcceptedSamples.map((sample) => sample.cadenceSpm),
        <int>[40, 240],
      );
    });

    test('non-finite cadence samples are excluded', () {
      final series = CadenceAnalysisSeries.localAccepted(
        samples: <CadenceAnalysisSample>[
          const CadenceAnalysisSample.accepted(
            elapsedSeconds: 60,
            cadenceSpm: 162,
          ),
          CadenceAnalysisSample(
            elapsedSeconds: 120,
            cadenceSpm: double.nan,
            status: CadenceAnalysisSampleStatus.accepted,
          ),
          CadenceAnalysisSample(
            elapsedSeconds: 190,
            cadenceSpm: double.infinity,
            status: CadenceAnalysisSampleStatus.accepted,
          ),
          const CadenceAnalysisSample.accepted(
            elapsedSeconds: 240,
            cadenceSpm: 164,
          ),
        ],
      );

      expect(series.validAcceptedSamples, hasLength(2));
      expect(
        series.validAcceptedSamples.map((sample) => sample.elapsedSeconds),
        <int>[60, 240],
      );
      expect(series.samples[1].cadenceSpm, isNull);
      expect(series.samples[2].cadenceSpm, isNull);
    });

    test(
      'monotonic elapsed validation detects duplicate and reversed order',
      () {
        final monotonic = CadenceAnalysisSeries.localAccepted(
          samples: const <CadenceAnalysisSample>[
            CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cadenceSpm: 164,
            ),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 190,
              cadenceSpm: 166,
            ),
          ],
        );
        final duplicateElapsed = CadenceAnalysisSeries.localAccepted(
          samples: const <CadenceAnalysisSample>[
            CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
            CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 164),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 190,
              cadenceSpm: 166,
            ),
          ],
        );
        final reversedElapsed = CadenceAnalysisSeries.localAccepted(
          samples: const <CadenceAnalysisSample>[
            CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 190,
              cadenceSpm: 164,
            ),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cadenceSpm: 166,
            ),
          ],
        );

        expect(monotonic.hasMonotonicValidSamples, isTrue);
        expect(duplicateElapsed.hasMonotonicValidSamples, isFalse);
        expect(reversedElapsed.hasMonotonicValidSamples, isFalse);
      },
    );

    test('rejected samples are excluded and require a reason', () {
      final series = CadenceAnalysisSeries.localAccepted(
        samples: <CadenceAnalysisSample>[
          const CadenceAnalysisSample.accepted(
            elapsedSeconds: 60,
            cadenceSpm: 162,
          ),
          CadenceAnalysisSample.rejected(
            elapsedSeconds: 120,
            cadenceSpm: 164,
            rejectionReason:
                CadenceAnalysisSampleRejectionReason.outOfRangeCadence,
          ),
          const CadenceAnalysisSample.accepted(
            elapsedSeconds: 190,
            cadenceSpm: 166,
          ),
        ],
      );

      expect(series.validAcceptedSamples, hasLength(2));
      expect(
        () => CadenceAnalysisSample.rejected(
          elapsedSeconds: 120,
          cadenceSpm: 164,
          rejectionReason: CadenceAnalysisSampleRejectionReason.none,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepted samples reject a rejection reason', () {
      expect(
        () => CadenceAnalysisSample(
          elapsedSeconds: 120,
          cadenceSpm: 164,
          status: CadenceAnalysisSampleStatus.accepted,
          rejectionReason:
              CadenceAnalysisSampleRejectionReason.outOfRangeCadence,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('empty and unavailable series stay distinguishable', () {
      final emptyLocal = CadenceAnalysisSeries.localAccepted(
        samples: const <CadenceAnalysisSample>[],
      );
      final demo = CadenceAnalysisSeries.staticDemo(
        samples: const <CadenceAnalysisSample>[],
      );
      final unavailable = CadenceAnalysisSeries.unavailable();

      expect(emptyLocal.hasMinimumValidSamples(), isFalse);
      expect(emptyLocal.isLocalAcceptedSource, isTrue);
      expect(demo.isStaticDemoSource, isTrue);
      expect(demo.confidence, CadenceAnalysisConfidence.demo);
      expect(unavailable.isUnavailable, isTrue);
      expect(unavailable.samples, isEmpty);
    });

    test('source confidence policy keeps cadence origins distinct', () {
      final samples = const <CadenceAnalysisSample>[
        CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
        CadenceAnalysisSample.accepted(elapsedSeconds: 120, cadenceSpm: 164),
        CadenceAnalysisSample.accepted(elapsedSeconds: 240, cadenceSpm: 166),
      ];
      final local = CadenceAnalysisSeries.localAccepted(samples: samples);
      final healthKit = CadenceAnalysisSeries(
        source: CadenceAnalysisSource.healthKitAppleWatch,
        confidence: CadenceAnalysisConfidence.high,
        samples: samples,
      );
      final healthConnect = CadenceAnalysisSeries(
        source: CadenceAnalysisSource.healthConnect,
        confidence: CadenceAnalysisConfidence.high,
        samples: samples,
      );
      final garmin = CadenceAnalysisSeries(
        source: CadenceAnalysisSource.garminWearable,
        confidence: CadenceAnalysisConfidence.high,
        samples: samples,
      );
      final phone = CadenceAnalysisSeries(
        source: CadenceAnalysisSource.phoneSensorEstimated,
        confidence: CadenceAnalysisConfidence.low,
        samples: samples,
      );

      expect(local.isLocalAcceptedSource, isTrue);
      expect(healthKit.isLocalAcceptedSource, isFalse);
      expect(healthConnect.isLocalAcceptedSource, isFalse);
      expect(garmin.isLocalAcceptedSource, isFalse);
      expect(phone.isProductionAnalysisEligible, isTrue);
      expect(healthKit.confidence, CadenceAnalysisConfidence.high);
      expect(healthConnect.confidence, CadenceAnalysisConfidence.high);
      expect(garmin.confidence, CadenceAnalysisConfidence.high);
      expect(phone.confidence, CadenceAnalysisConfidence.low);
      expect(
        CadenceAnalysisSeries.phoneMotionEstimated(
          samples: samples,
        ).isProductionAnalysisEligible,
        isTrue,
      );
      expect(
        CadenceAnalysisSeries.staticDemo(
          samples: samples,
        ).isProductionAnalysisEligible,
        isFalse,
      );
      expect(
        CadenceAnalysisSeries.unavailable().isProductionAnalysisEligible,
        isFalse,
      );
    });

    test('invalid source and confidence combinations are rejected', () {
      expect(
        () => CadenceAnalysisSeries(
          source: CadenceAnalysisSource.runiacLocalAccepted,
          confidence: CadenceAnalysisConfidence.demo,
          samples: const <CadenceAnalysisSample>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CadenceAnalysisSeries(
          source: CadenceAnalysisSource.unavailableUnknown,
          confidence: CadenceAnalysisConfidence.unavailable,
          samples: const <CadenceAnalysisSample>[
            CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 162),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
