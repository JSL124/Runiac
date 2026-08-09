import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/workout_metric_contract.dart';

void main() {
  group('ImportedWorkoutMetricContract', () {
    const source = WorkoutMetricProvenance(
      source: WorkoutMetricSource.healthKitAppleWatch,
      confidence: WorkoutMetricConfidence.high,
      evidenceKind: WorkoutMetricEvidenceKind.sampleBased,
      sourceAppName: 'Apple Health',
      sourceDeviceName: 'Apple Watch',
      adapterVersion: 'healthkit-import-v1',
      derivedLocally: false,
    );

    test('represents imported source identity and covered metric kinds', () {
      final contract = ImportedWorkoutMetricContract.sampleBased(
        metric: WorkoutMetricKind.cadenceSamples,
        unit: WorkoutMetricUnit.stepsPerMinute,
        provenance: source,
        samples: <WorkoutMetricSample>[
          WorkoutMetricSample.accepted(
            elapsedSeconds: 60,
            recordedAt: null,
            value: 162,
          ),
          WorkoutMetricSample.rejected(
            elapsedSeconds: 120,
            recordedAt: null,
            value: 0,
            rejectionReason: WorkoutSampleRejectionReason.outOfRange,
          ),
        ],
      );

      expect(
        WorkoutMetricKind.values,
        containsAll(<WorkoutMetricKind>[
          WorkoutMetricKind.distance,
          WorkoutMetricKind.elapsedDuration,
          WorkoutMetricKind.movingDuration,
          WorkoutMetricKind.pauseDuration,
          WorkoutMetricKind.averagePace,
          WorkoutMetricKind.paceSamples,
          WorkoutMetricKind.routeSamples,
          WorkoutMetricKind.gpsQuality,
          WorkoutMetricKind.cadenceSummary,
          WorkoutMetricKind.cadenceSamples,
          WorkoutMetricKind.strideLength,
          WorkoutMetricKind.calories,
        ]),
      );
      expect(contract.provenance.sourceAppName, 'Apple Health');
      expect(contract.provenance.sourceDeviceName, 'Apple Watch');
      expect(contract.provenance.adapterVersion, 'healthkit-import-v1');
      expect(
        contract.provenance.source,
        WorkoutMetricSource.healthKitAppleWatch,
      );
      expect(contract.provenance.confidence, WorkoutMetricConfidence.high);
      expect(contract.isSampleBased, isTrue);
      expect(contract.acceptedSamples, hasLength(1));
      expect(
        contract.rejectedSamples.single.rejectionReason,
        WorkoutSampleRejectionReason.outOfRange,
      );
      expect(contract.affectsBackendOwnedProgression, isFalse);
    });

    test('keeps summary-only evidence out of trend and sample eligibility', () {
      final averageCadence = ImportedWorkoutMetricContract.summaryOnly(
        metric: WorkoutMetricKind.cadenceSummary,
        unit: WorkoutMetricUnit.stepsPerMinute,
        provenance: source.copyWith(
          evidenceKind: WorkoutMetricEvidenceKind.summaryOnly,
        ),
        summaryValue: 146,
      );

      expect(averageCadence.isSummaryOnly, isTrue);
      expect(averageCadence.isSampleBased, isFalse);
      expect(averageCadence.supportsTrendAnalysis, isFalse);
      expect(averageCadence.supportsRouteSamples, isFalse);
      expect(
        () => ImportedWorkoutMetricContract.sampleBased(
          metric: WorkoutMetricKind.cadenceSamples,
          unit: WorkoutMetricUnit.stepsPerMinute,
          provenance: source.copyWith(
            evidenceKind: WorkoutMetricEvidenceKind.summaryOnly,
          ),
          samples: <WorkoutMetricSample>[
            WorkoutMetricSample.accepted(
              elapsedSeconds: 60,
              recordedAt: null,
              value: 146,
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('models unavailable metrics and static demo trust separately', () {
      final unavailable = ImportedWorkoutMetricContract.unavailable(
        metric: WorkoutMetricKind.strideLength,
        unit: WorkoutMetricUnit.meters,
        provenance: source.copyWith(
          source: WorkoutMetricSource.unavailableUnknown,
          confidence: WorkoutMetricConfidence.unavailable,
          evidenceKind: WorkoutMetricEvidenceKind.unavailable,
        ),
        unavailableReason: WorkoutMetricAvailabilityReason.notProvidedBySource,
      );
      final demo = source.copyWith(
        source: WorkoutMetricSource.staticDemo,
        confidence: WorkoutMetricConfidence.demo,
      );
      final demoSamples = ImportedWorkoutMetricContract.sampleBased(
        metric: WorkoutMetricKind.paceSamples,
        unit: WorkoutMetricUnit.secondsPerKilometer,
        provenance: demo,
        samples: <WorkoutMetricSample>[
          WorkoutMetricSample.accepted(
            elapsedSeconds: 60,
            recordedAt: null,
            value: 330,
          ),
        ],
      );

      expect(unavailable.isAvailable, isFalse);
      expect(
        unavailable.unavailableReason,
        WorkoutMetricAvailabilityReason.notProvidedBySource,
      );
      expect(demo.isProductionTrusted, isFalse);
      expect(demoSamples.supportsTrendAnalysis, isFalse);
      expect(source.isProductionTrusted, isTrue);
    });
  });

  group('WorkoutDurationBreakdown', () {
    test('distinguishes elapsed moving active and paused duration', () {
      final breakdown = WorkoutDurationBreakdown(
        elapsedDurationSeconds: 3600,
        activeDurationSeconds: 3000,
        movingDurationSeconds: 2940,
        pausedDurationSeconds: 600,
        pausePolicy: WorkoutPausePolicy.mixedManualAndAuto,
        pauseIntervals: <WorkoutPauseInterval>[
          WorkoutPauseInterval.manual(
            startElapsedSeconds: 900,
            endElapsedSeconds: 960,
          ),
          WorkoutPauseInterval.auto(
            startElapsedSeconds: 1800,
            endElapsedSeconds: 1860,
          ),
        ],
      );

      expect(
        breakdown.elapsedDurationSeconds,
        isNot(breakdown.movingDurationSeconds),
      );
      expect(breakdown.hasKnownMovingDuration, isTrue);
      expect(breakdown.hasKnownPauseIntervals, isTrue);
      expect(
        breakdown.pauseIntervals.first.kind,
        WorkoutPauseIntervalKind.manual,
      );
      expect(breakdown.pauseIntervals.last.kind, WorkoutPauseIntervalKind.auto);
    });

    test(
      'keeps unknown moving time and absent pause intervals unavailable',
      () {
        final breakdown = WorkoutDurationBreakdown(
          elapsedDurationSeconds: 1800,
          activeDurationSeconds: 1800,
          movingDurationSeconds: null,
          pausedDurationSeconds: null,
          pausePolicy: WorkoutPausePolicy.unknown,
          pauseIntervals: <WorkoutPauseInterval>[],
        );

        expect(breakdown.hasKnownMovingDuration, isFalse);
        expect(breakdown.hasKnownPauseIntervals, isFalse);
        expect(breakdown.pausedDurationSeconds, isNull);
      },
    );

    test('rejects impossible duration and pause interval values', () {
      expect(
        () => WorkoutDurationBreakdown(
          elapsedDurationSeconds: 300,
          activeDurationSeconds: 360,
          movingDurationSeconds: null,
          pausedDurationSeconds: null,
          pausePolicy: WorkoutPausePolicy.unknown,
          pauseIntervals: const <WorkoutPauseInterval>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => WorkoutPauseInterval.manual(
          startElapsedSeconds: 120,
          endElapsedSeconds: 60,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('WorkoutMetricSample', () {
    test('rejects invalid accepted elapsed alignment', () {
      expect(
        () => WorkoutMetricSample.accepted(
          elapsedSeconds: -1,
          recordedAt: null,
          value: 160,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('requires rejected samples to preserve a rejection reason', () {
      final sample = WorkoutMetricSample.rejected(
        elapsedSeconds: -1,
        recordedAt: null,
        value: 160,
        rejectionReason: WorkoutSampleRejectionReason.invalidElapsedSeconds,
      );

      expect(sample.isAccepted, isFalse);
      expect(
        sample.rejectionReason,
        WorkoutSampleRejectionReason.invalidElapsedSeconds,
      );
      expect(
        () => WorkoutMetricSample.rejected(
          elapsedSeconds: 0,
          recordedAt: null,
          value: 160,
          rejectionReason: WorkoutSampleRejectionReason.none,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
