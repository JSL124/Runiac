import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/cadence_graph_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/pace_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/pace_graph_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_source_display.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/workout_metric_contract.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';

void main() {
  group('AdvancedAnalysisSnapshotBuilder', () {
    const builder = AdvancedAnalysisSnapshotBuilder();

    test('marks trusted scalar run summary fields as available', () {
      const summary = RunSummarySnapshot(
        title: 'Easy Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '30:15',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
      );

      final snapshot = builder.fromRunSummary(summary);

      expect(snapshot.performance.duration.valueLabel, '30:15');
      expect(
        snapshot.performance.duration.availability,
        AdvancedAnalysisMetricAvailability.available,
      );
      expect(
        snapshot.performance.duration.source,
        AdvancedAnalysisMetricSource.localRunSummary,
      );
      expect(
        snapshot.performance.duration.confidence,
        AdvancedAnalysisMetricConfidence.trusted,
      );
      expect(snapshot.performance.distance.valueLabel, '4.03 km');
      expect(
        snapshot.pace.averagePace.availability,
        AdvancedAnalysisMetricAvailability.available,
      );
      expect(snapshot.pace.averagePace.valueLabel, '6’30” / km');
    });

    test(
      'maps average pace provenance from run source without changing label',
      () {
        const cases = <_AveragePaceSourceCase>[
          _AveragePaceSourceCase(
            name: 'Runiac GPS',
            sourceType: RunSourceType.runiacGps,
            expectedAvailability: AdvancedAnalysisMetricAvailability.available,
            expectedSource: AdvancedAnalysisMetricSource.localRunSummary,
            expectedConfidence: AdvancedAnalysisMetricConfidence.trusted,
            expectedLabel: '6’30” / km',
          ),
          _AveragePaceSourceCase(
            name: 'demo import',
            sourceType: RunSourceType.demoImport,
            expectedAvailability: AdvancedAnalysisMetricAvailability.demoOnly,
            expectedSource: AdvancedAnalysisMetricSource.staticDemo,
            expectedConfidence: AdvancedAnalysisMetricConfidence.demo,
            expectedLabel: '6’30” / km',
          ),
          _AveragePaceSourceCase(
            name: 'Apple Health',
            sourceType: RunSourceType.appleHealth,
            expectedAvailability: AdvancedAnalysisMetricAvailability.available,
            expectedSource: AdvancedAnalysisMetricSource.healthKitAppleWatch,
            expectedConfidence: AdvancedAnalysisMetricConfidence.derived,
            expectedLabel: '6’30” / km',
          ),
          _AveragePaceSourceCase(
            name: 'Health Connect',
            sourceType: RunSourceType.healthConnect,
            expectedAvailability: AdvancedAnalysisMetricAvailability.available,
            expectedSource: AdvancedAnalysisMetricSource.healthConnect,
            expectedConfidence: AdvancedAnalysisMetricConfidence.derived,
            expectedLabel: '6’30” / km',
          ),
          _AveragePaceSourceCase(
            name: 'Garmin via Health',
            sourceType: RunSourceType.garminViaHealth,
            expectedAvailability: AdvancedAnalysisMetricAvailability.available,
            expectedSource: AdvancedAnalysisMetricSource.garminWearable,
            expectedConfidence: AdvancedAnalysisMetricConfidence.derived,
            expectedLabel: '6’30” / km',
          ),
          _AveragePaceSourceCase(
            name: 'missing pace',
            sourceType: RunSourceType.runiacGps,
            avgPace: '--',
            expectedAvailability:
                AdvancedAnalysisMetricAvailability.unavailable,
            expectedSource: AdvancedAnalysisMetricSource.unavailable,
            expectedConfidence: AdvancedAnalysisMetricConfidence.unavailable,
          ),
        ];

        for (final testCase in cases) {
          final summary = RunSummarySnapshot(
            title: '${testCase.name} Run',
            dateLabel: 'Today',
            timeLabel: '7:06 AM',
            distanceKm: '4.03 km',
            avgPace: testCase.avgPace,
            duration: '30:15',
            avgHeartRate: '--',
            calories: '212 kcal',
            routeName: 'East Coast Park Loop',
            sourceType: testCase.sourceType,
          );

          final metric = builder.fromRunSummary(summary).pace.averagePace;

          expect(
            metric.availability,
            testCase.expectedAvailability,
            reason: testCase.name,
          );
          expect(metric.source, testCase.expectedSource, reason: testCase.name);
          expect(
            metric.confidence,
            testCase.expectedConfidence,
            reason: testCase.name,
          );
          expect(
            metric.valueLabel,
            testCase.expectedLabel,
            reason: testCase.name,
          );
        }
      },
    );

    test(
      'keeps unsupported non-HR analysis metrics unavailable by default',
      () {
        const summary = RunSummarySnapshot(
          title: 'Easy Run',
          dateLabel: 'Today',
          timeLabel: '7:06 AM',
          distanceKm: '4.03 km',
          avgPace: '6’30” / km',
          duration: '30:15',
          avgHeartRate: '145 bpm',
          calories: '212 kcal',
          routeName: 'East Coast Park Loop',
        );

        final snapshot = builder.fromRunSummary(summary);

        expect(snapshot.formCadence.averageCadence.isAvailable, isFalse);
        expect(
          snapshot.formCadence.strideLength.reason,
          AdvancedAnalysisMetricReason.missingStrideSource,
        );
        expect(snapshot.elevation.totalGain.isAvailable, isFalse);
        expect(
          snapshot.elevation.routeDifficulty.reason,
          AdvancedAnalysisMetricReason.undefinedRouteDifficultySource,
        );
        expect(snapshot.pace.fastestPace.isAvailable, isFalse);
        expect(snapshot.pace.slowestPace.isAvailable, isFalse);
        expect(snapshot.pace.paceStability.isAvailable, isFalse);
      },
    );

    test('creates mobile-only performance score without heart rate', () {
      final summary = RunSummarySnapshot(
        title: 'Phone Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.00 km',
        avgPace: '6’30” / km',
        duration: '26:00',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
        paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
          samples: const [
            PaceAnalysisSample.accepted(
              elapsedSeconds: 0,
              cumulativeDistanceMeters: 0,
              paceSecondsPerKm: 388,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 780,
              cumulativeDistanceMeters: 2000,
              paceSecondsPerKm: 392,
            ),
            PaceAnalysisSample.accepted(
              elapsedSeconds: 1560,
              cumulativeDistanceMeters: 4000,
              paceSecondsPerKm: 390,
            ),
          ],
        ),
      );

      final performance = builder.fromRunSummary(summary).performance;

      expect(performance.score.isAvailable, isTrue);
      expect(performance.score.value, greaterThan(0));
      expect(performance.scoreMode, AdvancedAnalysisScoreSourceMode.mobileOnly);
      expect(performance.scoreConfidenceLabel, 'Phone data');
    });

    test(
      'keeps demo import performance out of phone-tracked source labels',
      () {
        const summary = RunSummarySnapshot(
          title: 'Demo Run',
          dateLabel: 'Today',
          timeLabel: '7:06 AM',
          distanceKm: '4.00 km',
          avgPace: '6’30” / km',
          duration: '26:00',
          avgHeartRate: '--',
          calories: '212 kcal',
          routeName: 'East Coast Park Loop',
          sourceType: RunSourceType.demoImport,
        );

        final performance = builder.fromRunSummary(summary).performance;

        expect(performance.scoreMode, AdvancedAnalysisScoreSourceMode.demoOnly);
        expect(performance.scoreConfidenceLabel, 'Demo data');
        expect(
          performance.score.source,
          AdvancedAnalysisMetricSource.staticDemo,
        );
        expect(
          performance.score.confidence,
          AdvancedAnalysisMetricConfidence.demo,
        );
        expect(performance.score.isTrustedProduction, isFalse);
      },
    );

    test('wearable-backed performance score uses a distinct scoring mode', () {
      final baseSummary = _scoreFixtureSummary();
      final wearableSummary = _scoreFixtureSummary(
        sourceType: RunSourceType.appleHealth,
      );

      final mobileScore = builder.fromRunSummary(baseSummary).performance.score;
      final wearablePerformance = builder
          .fromRunSummary(wearableSummary)
          .performance;

      expect(wearablePerformance.score.isAvailable, isTrue);
      expect(
        wearablePerformance.scoreMode,
        AdvancedAnalysisScoreSourceMode.wearableBacked,
      );
      expect(wearablePerformance.score.value, isNot(mobileScore.value));
      expect(wearablePerformance.scoreConfidenceLabel, 'Wearable-backed');
    });

    test('derives elevation analysis from accountable local samples', () {
      final summary = RunSummarySnapshot(
        title: 'Hill Check Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '2.00 km',
        avgPace: '7’00” / km',
        duration: '14:00',
        avgHeartRate: '--',
        calories: '145 kcal',
        routeName: 'Local Hill Loop',
        elevationSeries: ElevationAnalysisSeries.localAccepted(
          samples: [
            ElevationAnalysisSample(distanceKm: 0, elevationMeters: 4),
            ElevationAnalysisSample(distanceKm: 0.5, elevationMeters: 5.2),
            ElevationAnalysisSample(distanceKm: 1, elevationMeters: 8.4),
            ElevationAnalysisSample(distanceKm: 1.5, elevationMeters: 8.9),
            ElevationAnalysisSample(distanceKm: 2, elevationMeters: 6.1),
          ],
        ),
      );

      final snapshot = builder.fromRunSummary(summary);
      final elevation = snapshot.elevation;

      expect(elevation.totalGain.valueLabel, '+3 m');
      expect(elevation.highestPoint.valueLabel, '9 m');
      expect(elevation.lowestPoint.valueLabel, '4 m');
      expect(elevation.routeDifficulty.valueLabel, 'Mostly Flat');
      for (final metric in <AdvancedAnalysisMetric<String>>[
        elevation.totalGain,
        elevation.highestPoint,
        elevation.lowestPoint,
        elevation.routeDifficulty,
      ]) {
        expect(
          metric.availability,
          AdvancedAnalysisMetricAvailability.available,
        );
        expect(metric.source, AdvancedAnalysisMetricSource.localGpsDerived);
        expect(metric.confidence, AdvancedAnalysisMetricConfidence.derived);
      }
      expect(elevation.elevationGraph.isAvailable, isTrue);
      expect(
        elevation.elevationGraph.value!.points.map((point) => point.distanceKm),
        [0, 0.5, 1, 1.5, 2],
      );
      expect(
        elevation.elevationGraph.value!.points.map(
          (point) => point.elevationMeters,
        ),
        [4, 5.2, 8.4, 8.9, 6.1],
      );
      expect(elevation.elevationGraph.value!.xAxisLabels, [
        '0 km',
        '1 km',
        '2 km',
      ]);
      expect(elevation.elevationGraph.value!.yAxisLabels, ['9 m', '4 m']);
    });

    test('ignores tiny elevation fluctuations when calculating gain', () {
      final summary = RunSummarySnapshot(
        title: 'Noisy Flat Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '1.20 km',
        avgPace: '7’00” / km',
        duration: '8:24',
        avgHeartRate: '--',
        calories: '90 kcal',
        routeName: 'Noisy Flat Loop',
        elevationSeries: ElevationAnalysisSeries.localAccepted(
          samples: [
            ElevationAnalysisSample(distanceKm: 0, elevationMeters: 10),
            ElevationAnalysisSample(distanceKm: 0.4, elevationMeters: 11.2),
            ElevationAnalysisSample(distanceKm: 0.8, elevationMeters: 10.6),
            ElevationAnalysisSample(distanceKm: 1.2, elevationMeters: 12.7),
          ],
        ),
      );

      final snapshot = builder.fromRunSummary(summary);

      expect(snapshot.elevation.totalGain.valueLabel, '+2 m');
      expect(snapshot.elevation.highestPoint.valueLabel, '13 m');
      expect(snapshot.elevation.lowestPoint.valueLabel, '10 m');
      expect(snapshot.elevation.routeDifficulty.valueLabel, 'Mostly Flat');
    });

    test('preserves backend-derived elevation metric provenance', () {
      final summary = RunSummarySnapshot(
        title: 'Backend Elevation Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '2.00 km',
        avgPace: '7’00” / km',
        duration: '14:00',
        avgHeartRate: '--',
        calories: '145 kcal',
        routeName: 'Backend Hill Loop',
        elevationSeries: ElevationAnalysisSeries.backendDerived(
          samples: const [
            ElevationAnalysisSample(distanceKm: 0, elevationMeters: 10),
            ElevationAnalysisSample(distanceKm: 1, elevationMeters: 17),
            ElevationAnalysisSample(distanceKm: 2, elevationMeters: 20),
          ],
        ),
      );

      final elevation = builder.fromRunSummary(summary).elevation;

      expect(elevation.totalGain.valueLabel, '+10 m');
      expect(
        elevation.elevationGraph.source,
        AdvancedAnalysisMetricSource.backendDerived,
      );
      for (final metric in <AdvancedAnalysisMetric<String>>[
        elevation.totalGain,
        elevation.highestPoint,
        elevation.lowestPoint,
        elevation.routeDifficulty,
      ]) {
        expect(metric.source, AdvancedAnalysisMetricSource.backendDerived);
      }
    });

    test('classifies rolling and hilly elevation routes deterministically', () {
      final rollingSummary = RunSummarySnapshot(
        title: 'Rolling Elevation Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '2.00 km',
        avgPace: '7’00” / km',
        duration: '14:00',
        avgHeartRate: '--',
        calories: '145 kcal',
        routeName: 'Rolling Loop',
        elevationSeries: ElevationAnalysisSeries.localAccepted(
          samples: const [
            ElevationAnalysisSample(distanceKm: 0, elevationMeters: 10),
            ElevationAnalysisSample(distanceKm: 1, elevationMeters: 25),
            ElevationAnalysisSample(distanceKm: 2, elevationMeters: 20),
          ],
        ),
      );
      final hillySummary = RunSummarySnapshot(
        title: 'Hilly Elevation Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '2.00 km',
        avgPace: '7’00” / km',
        duration: '14:00',
        avgHeartRate: '--',
        calories: '145 kcal',
        routeName: 'Hilly Loop',
        elevationSeries: ElevationAnalysisSeries.localAccepted(
          samples: const [
            ElevationAnalysisSample(distanceKm: 0, elevationMeters: 10),
            ElevationAnalysisSample(distanceKm: 1, elevationMeters: 65),
            ElevationAnalysisSample(distanceKm: 2, elevationMeters: 45),
          ],
        ),
      );

      expect(
        builder.fromRunSummary(rollingSummary).elevation.routeDifficulty.value,
        'Rolling',
      );
      expect(
        builder.fromRunSummary(hillySummary).elevation.routeDifficulty.value,
        'Hilly',
      );
    });

    test('keeps elevation unavailable when sample data is insufficient', () {
      final summary = RunSummarySnapshot(
        title: 'Short Elevation Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '0.05 km',
        avgPace: '--',
        duration: '00:30',
        avgHeartRate: '--',
        calories: '--',
        routeName: 'Short Start Check',
        elevationSeries: ElevationAnalysisSeries.localAccepted(
          samples: [ElevationAnalysisSample(distanceKm: 0, elevationMeters: 6)],
        ),
      );

      final snapshot = builder.fromRunSummary(summary);

      expect(snapshot.elevation.totalGain.isAvailable, isFalse);
      expect(snapshot.elevation.highestPoint.isAvailable, isFalse);
      expect(snapshot.elevation.lowestPoint.isAvailable, isFalse);
      expect(snapshot.elevation.routeDifficulty.isAvailable, isFalse);
      expect(snapshot.elevation.elevationGraph.isAvailable, isFalse);
      expect(
        snapshot.elevation.elevationGraph.reason,
        AdvancedAnalysisMetricReason.missingElevationSource,
      );
      expect(
        snapshot.elevation.unavailableReason,
        ElevationUnavailableReason.tooFewValidAltitudeSamples,
      );
    });

    test('keeps elevation unavailable with non-increasing distance reason', () {
      final summary = RunSummarySnapshot(
        title: 'Duplicate Distance Elevation Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '0.20 km',
        avgPace: '7’00” / km',
        duration: '1:24',
        avgHeartRate: '--',
        calories: '--',
        routeName: 'Duplicate Altitude Loop',
        elevationSeries: ElevationAnalysisSeries.localAccepted(
          samples: const [
            ElevationAnalysisSample(distanceKm: 0, elevationMeters: 4),
            ElevationAnalysisSample(distanceKm: 0, elevationMeters: 5),
          ],
        ),
      );

      final elevation = builder.fromRunSummary(summary).elevation;

      expect(elevation.elevationGraph.isAvailable, isFalse);
      expect(
        elevation.unavailableReason,
        ElevationUnavailableReason.nonIncreasingDistance,
      );
    });

    test('derives pace analysis metrics from accountable local series', () {
      final summary = RunSummarySnapshot(
        title: 'Local Pace Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '30:15',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
        paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
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

      final snapshot = builder.fromRunSummary(summary);

      expect(snapshot.pace.fastestPace.valueLabel, '6’00”');
      expect(snapshot.pace.slowestPace.valueLabel, '8’00”');
      expect(snapshot.pace.paceStability.valueLabel, '33');
      for (final metric in <AdvancedAnalysisMetric<String>>[
        snapshot.pace.fastestPace,
        snapshot.pace.slowestPace,
        snapshot.pace.paceStability,
      ]) {
        expect(
          metric.availability,
          AdvancedAnalysisMetricAvailability.available,
        );
        expect(metric.source, AdvancedAnalysisMetricSource.localGpsDerived);
        expect(metric.confidence, AdvancedAnalysisMetricConfidence.derived);
        expect(
          metric.source,
          isNot(AdvancedAnalysisMetricSource.backendDerived),
        );
        expect(metric.isTrustedProduction, isFalse);
      }
    });

    test('keeps pace analysis metrics unavailable for insufficient series', () {
      final summary = RunSummarySnapshot(
        title: 'Short Pace Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '30:15',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
        paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
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
          ],
        ),
      );

      final snapshot = builder.fromRunSummary(summary);

      expect(snapshot.pace.fastestPace.isAvailable, isFalse);
      expect(snapshot.pace.slowestPace.isAvailable, isFalse);
      expect(snapshot.pace.paceStability.isAvailable, isFalse);
      expect(
        snapshot.pace.fastestPace.reason,
        AdvancedAnalysisMetricReason.insufficientPaceSamples,
      );
    });

    test('does not trust demo pace analysis series as local derivation', () {
      final summary = RunSummarySnapshot(
        title: 'Demo Pace Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '30:15',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
        sourceType: RunSourceType.demoImport,
        paceAnalysisSeries: PaceAnalysisSeries.staticDemo(
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

      final snapshot = builder.fromRunSummary(summary);

      expect(snapshot.pace.fastestPace.isAvailable, isFalse);
      expect(snapshot.pace.slowestPace.isAvailable, isFalse);
      expect(snapshot.pace.paceStability.isAvailable, isFalse);
    });

    test(
      'does not trust local accepted pace series attached to demo source',
      () {
        final summary = RunSummarySnapshot(
          title: 'Demo Local Series Run',
          dateLabel: 'Today',
          timeLabel: '7:06 AM',
          distanceKm: '4.03 km',
          avgPace: '6’30” / km',
          duration: '30:15',
          avgHeartRate: '--',
          calories: '212 kcal',
          routeName: 'East Coast Park Loop',
          sourceType: RunSourceType.demoImport,
          paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
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

        final snapshot = builder.fromRunSummary(summary);

        expect(snapshot.pace.fastestPace.isAvailable, isFalse);
        expect(snapshot.pace.slowestPace.isAvailable, isFalse);
        expect(snapshot.pace.paceStability.isAvailable, isFalse);
      },
    );

    test('derives cadence metrics from accountable local series', () {
      final summary = RunSummarySnapshot(
        title: 'Local Cadence Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '30:15',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
        cadenceAnalysisSeries: CadenceAnalysisSeries.localAccepted(
          samples: const <CadenceAnalysisSample>[
            CadenceAnalysisSample.accepted(elapsedSeconds: 60, cadenceSpm: 168),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 120,
              cadenceSpm: 172,
            ),
            CadenceAnalysisSample.accepted(
              elapsedSeconds: 180,
              cadenceSpm: 176,
            ),
          ],
        ),
      );

      final cadence = builder.fromRunSummary(summary).formCadence;

      expect(cadence.averageCadence.valueLabel, '172 spm');
      expect(cadence.strideConsistency.valueLabel, 'stable');
      expect(cadence.cadenceStatus.valueLabel, 'stable');
      final cadenceGraph = cadence.cadenceGraph.value!;
      expect(cadenceGraph.isAvailable, isTrue);
      expect(cadenceGraph.points.map((point) => point.elapsedSeconds), <int>[
        60,
        120,
        180,
      ]);
      expect(cadenceGraph.points.map((point) => point.cadenceSpm), <int>[
        168,
        172,
        176,
      ]);
      expect(
        cadenceGraph.points.map((point) => point.progressFraction),
        <double>[60 / 1815, 120 / 1815, 180 / 1815],
      );
      expect(cadenceGraph.totalDurationSeconds, 1815);
      expect(cadenceGraph.lowestCadencePoint?.cadenceSpm, 168);
      expect(cadenceGraph.averageCadenceSpm, 172);
      expect(cadenceGraph.highestCadencePoint?.cadenceSpm, 176);
      expect(cadenceGraph.targetLabel, demoCadenceGraphTargetLabel);
      expect(cadenceGraph.targetMinCadenceSpm, demoCadenceGraphTargetMinSpm);
      expect(cadenceGraph.targetMaxCadenceSpm, demoCadenceGraphTargetMaxSpm);
      for (final metric in <AdvancedAnalysisMetric<String>>[
        cadence.averageCadence,
        cadence.strideConsistency,
        cadence.cadenceStatus,
      ]) {
        expect(
          metric.availability,
          AdvancedAnalysisMetricAvailability.available,
        );
        expect(metric.source, AdvancedAnalysisMetricSource.localGpsDerived);
        expect(metric.confidence, AdvancedAnalysisMetricConfidence.derived);
        expect(metric.isTrustedProduction, isFalse);
      }
      expect(
        cadence.cadenceGraph.availability,
        AdvancedAnalysisMetricAvailability.available,
      );
      expect(
        cadence.cadenceGraph.source,
        AdvancedAnalysisMetricSource.localGpsDerived,
      );
      expect(
        cadence.cadenceGraph.confidence,
        AdvancedAnalysisMetricConfidence.derived,
      );
      expect(cadence.cadenceGraph.isTrustedProduction, isFalse);
      expect(cadence.targetRange.isAvailable, isFalse);
      expect(
        cadence.targetRange.reason,
        AdvancedAnalysisMetricReason.missingCadenceSource,
      );
      expect(cadence.strideLength.isAvailable, isFalse);
      expect(
        cadence.strideLength.reason,
        AdvancedAnalysisMetricReason.missingStrideSource,
      );
    });

    test('keeps cadence unavailable without accountable cadence series', () {
      const summary = RunSummarySnapshot(
        title: 'No Cadence Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '30:15',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
      );

      final cadence = builder.fromRunSummary(summary).formCadence;

      expect(cadence.averageCadence.isAvailable, isFalse);
      expect(
        cadence.averageCadence.reason,
        AdvancedAnalysisMetricReason.missingCadenceSource,
      );
      expect(cadence.strideConsistency.isAvailable, isFalse);
      expect(cadence.cadenceStatus.isAvailable, isFalse);
      expect(cadence.cadenceGraph.isAvailable, isFalse);
      expect(cadence.targetRange.isAvailable, isFalse);
      expect(cadence.strideLength.isAvailable, isFalse);
    });

    test('keeps static and insufficient cadence series unavailable', () {
      final cases = <_CadenceUnavailableCase>[
        _CadenceUnavailableCase(
          name: 'static demo',
          series: CadenceAnalysisSeries.staticDemo(
            samples: const <CadenceAnalysisSample>[
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 60,
                cadenceSpm: 168,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 120,
                cadenceSpm: 172,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 180,
                cadenceSpm: 176,
              ),
            ],
          ),
        ),
        _CadenceUnavailableCase(
          name: 'insufficient samples',
          series: CadenceAnalysisSeries.localAccepted(
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
        _CadenceUnavailableCase(
          name: 'unavailable source',
          series: CadenceAnalysisSeries.unavailable(),
        ),
        _CadenceUnavailableCase(
          name: 'local series attached to demo source',
          sourceType: RunSourceType.demoImport,
          series: CadenceAnalysisSeries.localAccepted(
            samples: const <CadenceAnalysisSample>[
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 60,
                cadenceSpm: 168,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 120,
                cadenceSpm: 172,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 180,
                cadenceSpm: 176,
              ),
            ],
          ),
        ),
        _CadenceUnavailableCase(
          name: 'non-monotonic local series',
          series: CadenceAnalysisSeries.localAccepted(
            samples: const <CadenceAnalysisSample>[
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 120,
                cadenceSpm: 168,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 60,
                cadenceSpm: 172,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 180,
                cadenceSpm: 176,
              ),
            ],
          ),
        ),
      ];

      for (final testCase in cases) {
        final summary = RunSummarySnapshot(
          title: '${testCase.name} Cadence Run',
          dateLabel: 'Today',
          timeLabel: '7:06 AM',
          distanceKm: '4.03 km',
          avgPace: '6’30” / km',
          duration: '30:15',
          avgHeartRate: '--',
          calories: '212 kcal',
          routeName: 'East Coast Park Loop',
          sourceType: testCase.sourceType,
          cadenceAnalysisSeries: testCase.series,
        );

        final cadence = builder.fromRunSummary(summary).formCadence;

        expect(cadence.averageCadence.isAvailable, isFalse);
        expect(cadence.strideConsistency.isAvailable, isFalse);
        expect(cadence.cadenceStatus.isAvailable, isFalse);
        expect(cadence.cadenceGraph.isAvailable, isFalse);
        expect(cadence.targetRange.isAvailable, isFalse);
        expect(cadence.strideLength.isAvailable, isFalse);
      }
    });

    test(
      'does not classify demo/static metrics as trusted production data',
      () {
        const metric = AdvancedAnalysisMetric<String>.demoOnly('82');

        expect(
          metric.availability,
          AdvancedAnalysisMetricAvailability.demoOnly,
        );
        expect(metric.source, AdvancedAnalysisMetricSource.staticDemo);
        expect(metric.confidence, AdvancedAnalysisMetricConfidence.demo);
        expect(metric.isTrustedProduction, isFalse);
      },
    );

    test(
      'keeps demo import summary scalars out of trusted production data',
      () {
        const summary = RunSummarySnapshot(
          title: 'Demo Run',
          dateLabel: 'Today',
          timeLabel: '7:06 AM',
          distanceKm: '4.03 km',
          avgPace: '6’30” / km',
          duration: '30:15',
          avgHeartRate: '145 bpm',
          calories: '212 kcal',
          routeName: 'East Coast Park Loop',
          sourceType: RunSourceType.demoImport,
        );

        final snapshot = builder.fromRunSummary(summary);

        expect(
          snapshot.performance.duration.availability,
          AdvancedAnalysisMetricAvailability.demoOnly,
        );
        expect(
          snapshot.performance.duration.source,
          AdvancedAnalysisMetricSource.staticDemo,
        );
        expect(
          snapshot.performance.duration.confidence,
          AdvancedAnalysisMetricConfidence.demo,
        );
        expect(snapshot.performance.duration.isTrustedProduction, isFalse);
        expect(snapshot.pace.averagePace.isTrustedProduction, isFalse);
      },
    );

    test('keeps demo import pace graphs out of local GPS derived data', () {
      const summary = RunSummarySnapshot(
        title: 'Demo Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '30:15',
        avgHeartRate: '145 bpm',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
        sourceType: RunSourceType.demoImport,
        paceGraph: PaceGraphSnapshot(
          isAvailable: true,
          points: <PaceGraphPoint>[
            PaceGraphPoint(
              elapsedSeconds: 0,
              progressFraction: 0,
              paceSecondsPerKm: 390,
            ),
            PaceGraphPoint(
              elapsedSeconds: 120,
              progressFraction: 0.5,
              paceSecondsPerKm: 392,
            ),
            PaceGraphPoint(
              elapsedSeconds: 240,
              progressFraction: 1,
              paceSecondsPerKm: 388,
            ),
          ],
          yAxisLabels: <String>['6:00', '6:30', '7:00'],
          xAxisLabels: <String>['0:00', '2:00', '4:00'],
        ),
      );

      final snapshot = builder.fromRunSummary(summary);

      expect(
        snapshot.pace.paceGraph.availability,
        AdvancedAnalysisMetricAvailability.demoOnly,
      );
      expect(
        snapshot.pace.paceGraph.source,
        AdvancedAnalysisMetricSource.staticDemo,
      );
      expect(
        snapshot.pace.paceGraph.confidence,
        AdvancedAnalysisMetricConfidence.demo,
      );
      expect(snapshot.pace.paceGraph.isTrustedProduction, isFalse);
    });

    test('derives local GPS split rows from distance-backed pace graph', () {
      const summary = RunSummarySnapshot(
        title: 'Local Split Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '26:26',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
        paceGraph: PaceGraphSnapshot(
          isAvailable: true,
          points: <PaceGraphPoint>[
            PaceGraphPoint(
              elapsedSeconds: 0,
              progressFraction: 0,
              paceSecondsPerKm: 390,
              distanceProgressFraction: 0,
            ),
            PaceGraphPoint(
              elapsedSeconds: 360,
              progressFraction: 0.25,
              paceSecondsPerKm: 360,
              distanceProgressFraction: 1 / 4.03,
            ),
            PaceGraphPoint(
              elapsedSeconds: 750,
              progressFraction: 0.5,
              paceSecondsPerKm: 390,
              distanceProgressFraction: 2 / 4.03,
            ),
            PaceGraphPoint(
              elapsedSeconds: 1170,
              progressFraction: 0.75,
              paceSecondsPerKm: 420,
              distanceProgressFraction: 3 / 4.03,
            ),
            PaceGraphPoint(
              elapsedSeconds: 1560,
              progressFraction: 0.98,
              paceSecondsPerKm: 390,
              distanceProgressFraction: 4 / 4.03,
            ),
          ],
          yAxisLabels: <String>['6:00', '6:30', '7:00'],
          xAxisLabels: <String>['0:00', '13:13', '26:26'],
          distanceAxisLabels: <String>['0 km', '2 km', '4.03 km'],
          totalDurationSeconds: 1586,
        ),
      );

      final snapshot = builder.fromRunSummary(summary);
      final splits = snapshot.pace.splits.value!;

      expect(
        snapshot.pace.splits.availability,
        AdvancedAnalysisMetricAvailability.available,
      );
      expect(
        snapshot.pace.splits.source,
        AdvancedAnalysisMetricSource.localGpsDerived,
      );
      expect(
        snapshot.pace.splits.confidence,
        AdvancedAnalysisMetricConfidence.derived,
      );
      expect(splits.map((split) => split.distanceLabel), <String>[
        '1 km',
        '2 km',
        '3 km',
        '4 km',
        '0.03 km',
      ]);
      expect(splits.map((split) => split.paceLabel), <String>[
        '6’00”',
        '6’30”',
        '7’00”',
        '6’30”',
        '0’26”',
      ]);
      expect(splits.map((split) => split.paceSecondsPerKm), <int>[
        360,
        390,
        420,
        390,
        26,
      ]);
      expect(splits.last.isPartial, isTrue);
      expect(splits.last.elevationLabel, '--');
      expect(splits.last.heartRateLabel, '--');
    });

    test(
      'keeps local GPS splits when display graph distance anchors are noisy',
      () {
        final summary = RunSummarySnapshot(
          title: 'Noisy Local Split Run',
          dateLabel: 'Today',
          timeLabel: '9:23 PM',
          distanceKm: '5.03 km',
          avgPace: '7’56” / km',
          duration: '40:00',
          avgHeartRate: '--',
          calories: '312 kcal',
          routeName: 'Local GPS Route',
          paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
            samples: <PaceAnalysisSample>[
              PaceAnalysisSample.accepted(
                elapsedSeconds: 480,
                cumulativeDistanceMeters: 1000,
                paceSecondsPerKm: 480,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 960,
                cumulativeDistanceMeters: 2000,
                paceSecondsPerKm: 480,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 1440,
                cumulativeDistanceMeters: 3000,
                paceSecondsPerKm: 480,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 1920,
                cumulativeDistanceMeters: 4000,
                paceSecondsPerKm: 480,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 2400,
                cumulativeDistanceMeters: 5030,
                paceSecondsPerKm: 466,
              ),
            ],
          ),
          paceGraph: PaceGraphSnapshot(
            isAvailable: true,
            points: <PaceGraphPoint>[
              PaceGraphPoint(
                elapsedSeconds: 0,
                progressFraction: 0,
                paceSecondsPerKm: 480,
                distanceProgressFraction: 0,
              ),
              PaceGraphPoint(
                elapsedSeconds: 480,
                progressFraction: 0.2,
                paceSecondsPerKm: 480,
                distanceProgressFraction: 0.25,
              ),
              PaceGraphPoint(
                elapsedSeconds: 960,
                progressFraction: 0.4,
                paceSecondsPerKm: 480,
                distanceProgressFraction: 0.2,
              ),
              PaceGraphPoint(
                elapsedSeconds: 1440,
                progressFraction: 0.6,
                paceSecondsPerKm: 480,
                distanceProgressFraction: 3 / 5.03,
              ),
              PaceGraphPoint(
                elapsedSeconds: 2400,
                progressFraction: 1,
                paceSecondsPerKm: 466,
                distanceProgressFraction: 1,
              ),
            ],
            yAxisLabels: <String>['5:40', '9:10', '12:40'],
            xAxisLabels: <String>['0:00', '20:00', '40:00'],
            distanceAxisLabels: <String>['0 km', '1.6 km', '3.3 km', '5.03 km'],
            totalDurationSeconds: 2400,
          ),
        );

        final snapshot = builder.fromRunSummary(summary);

        expect(snapshot.pace.paceGraph.isAvailable, isTrue);
        expect(snapshot.pace.paceGraph.value!.hasDistanceAxis, isTrue);
        expect(snapshot.pace.splits.isAvailable, isTrue);
        expect(
          snapshot.pace.splits.value!.map((split) => split.distanceLabel),
          <String>['1 km', '2 km', '3 km', '4 km', '5 km', '0.03 km'],
        );
        expect(
          snapshot.pace.splits.value!.map((split) => split.paceLabel),
          <String>['8’00”', '8’00”', '8’00”', '8’00”', '7’46”', '0’14”'],
        );
      },
    );

    test('preserves imported pace graph source identity', () {
      const summary = RunSummarySnapshot(
        title: 'Apple Health Graph Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '26:26',
        avgHeartRate: '151 bpm',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
        sourceType: RunSourceType.appleHealth,
        paceGraph: PaceGraphSnapshot(
          isAvailable: true,
          points: <PaceGraphPoint>[
            PaceGraphPoint(
              elapsedSeconds: 0,
              progressFraction: 0,
              paceSecondsPerKm: 390,
              distanceProgressFraction: 0,
            ),
            PaceGraphPoint(
              elapsedSeconds: 120,
              progressFraction: 0.5,
              paceSecondsPerKm: 392,
              distanceProgressFraction: 0.5,
            ),
            PaceGraphPoint(
              elapsedSeconds: 240,
              progressFraction: 1,
              paceSecondsPerKm: 388,
              distanceProgressFraction: 1,
            ),
          ],
          yAxisLabels: <String>['6:00', '6:30', '7:00'],
          xAxisLabels: <String>['0:00', '2:00', '4:00'],
          distanceAxisLabels: <String>['0 km', '2 km', '4.03 km'],
          totalDurationSeconds: 1586,
        ),
      );

      final snapshot = builder.fromRunSummary(summary);

      expect(
        snapshot.pace.paceGraph.availability,
        AdvancedAnalysisMetricAvailability.available,
      );
      expect(
        snapshot.pace.paceGraph.source,
        AdvancedAnalysisMetricSource.healthKitAppleWatch,
      );
      expect(
        snapshot.pace.paceGraph.source,
        isNot(AdvancedAnalysisMetricSource.localGpsDerived),
      );
      expect(
        snapshot.pace.splits.source,
        AdvancedAnalysisMetricSource.healthKitAppleWatch,
      );
      expect(snapshot.pace.splits.value, isNotEmpty);
    });

    test('keeps splits unavailable without distance-axis graph metadata', () {
      const summary = RunSummarySnapshot(
        title: 'No Distance Axis Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03 km',
        avgPace: '6’30” / km',
        duration: '26:26',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
        paceGraph: PaceGraphSnapshot(
          isAvailable: true,
          points: <PaceGraphPoint>[
            PaceGraphPoint(
              elapsedSeconds: 0,
              progressFraction: 0,
              paceSecondsPerKm: 390,
            ),
            PaceGraphPoint(
              elapsedSeconds: 780,
              progressFraction: 0.5,
              paceSecondsPerKm: 390,
            ),
            PaceGraphPoint(
              elapsedSeconds: 1560,
              progressFraction: 1,
              paceSecondsPerKm: 390,
            ),
          ],
          yAxisLabels: <String>['6:00', '6:30', '7:00'],
          xAxisLabels: <String>['0:00', '13:00', '26:00'],
          totalDurationSeconds: 1560,
        ),
      );

      final snapshot = builder.fromRunSummary(summary);

      expect(snapshot.pace.splits.isAvailable, isFalse);
      expect(
        snapshot.pace.splits.reason,
        AdvancedAnalysisMetricReason.insufficientPaceSamples,
      );
      expect(snapshot.pace.splits.value, isNull);
    });

    test(
      'derives split rows using summary duration when graph duration is absent',
      () {
        const summary = RunSummarySnapshot(
          title: 'Fallback Duration Split Run',
          dateLabel: 'Today',
          timeLabel: '7:06 AM',
          distanceKm: '4.03 km',
          avgPace: '6’30” / km',
          duration: '26:26',
          avgHeartRate: '--',
          calories: '212 kcal',
          routeName: 'East Coast Park Loop',
          paceGraph: PaceGraphSnapshot(
            isAvailable: true,
            points: <PaceGraphPoint>[
              PaceGraphPoint(
                elapsedSeconds: 0,
                progressFraction: 0,
                paceSecondsPerKm: 390,
                distanceProgressFraction: 0,
              ),
              PaceGraphPoint(
                elapsedSeconds: 360,
                progressFraction: 0.25,
                paceSecondsPerKm: 360,
                distanceProgressFraction: 1 / 4.03,
              ),
              PaceGraphPoint(
                elapsedSeconds: 750,
                progressFraction: 0.5,
                paceSecondsPerKm: 390,
                distanceProgressFraction: 2 / 4.03,
              ),
              PaceGraphPoint(
                elapsedSeconds: 1170,
                progressFraction: 0.75,
                paceSecondsPerKm: 420,
                distanceProgressFraction: 3 / 4.03,
              ),
              PaceGraphPoint(
                elapsedSeconds: 1560,
                progressFraction: 0.98,
                paceSecondsPerKm: 390,
                distanceProgressFraction: 4 / 4.03,
              ),
            ],
            yAxisLabels: <String>['6:00', '6:30', '7:00'],
            xAxisLabels: <String>['0:00', '13:13', '26:26'],
            distanceAxisLabels: <String>['0 km', '2 km', '4.03 km'],
          ),
        );

        final snapshot = builder.fromRunSummary(summary);

        expect(snapshot.pace.splits.isAvailable, isTrue);
        expect(snapshot.pace.splits.value, hasLength(5));
        expect(
          snapshot.pace.splits.value!.map((split) => split.distanceLabel),
          <String>['1 km', '2 km', '3 km', '4 km', '0.03 km'],
        );
      },
    );

    test('preserves source and confidence for estimated future metrics', () {
      const metric = AdvancedAnalysisMetric<String>.estimated(
        valueLabel: '0.98 m',
        source: AdvancedAnalysisMetricSource.phoneSensorEstimated,
        reason: AdvancedAnalysisMetricReason.estimatedFromPhoneSensors,
      );

      expect(metric.availability, AdvancedAnalysisMetricAvailability.estimated);
      expect(metric.source, AdvancedAnalysisMetricSource.phoneSensorEstimated);
      expect(metric.confidence, AdvancedAnalysisMetricConfidence.estimated);
      expect(
        metric.reason,
        AdvancedAnalysisMetricReason.estimatedFromPhoneSensors,
      );
      expect(metric.isTrustedProduction, isFalse);
    });

    test('does not add backend-owned mutation fields to client payload paths', () {
      final sources = <String>[
        File(
          'lib/features/run/domain/models/local_run_completion_payload.dart',
        ).readAsStringSync(),
        File(
          'lib/features/run/domain/models/run_completion_request_adapter.dart',
        ).readAsStringSync(),
        File(
          'lib/features/run/domain/models/advanced_analysis_snapshot.dart',
        ).readAsStringSync(),
        File(
          'lib/features/run/domain/services/advanced_analysis_snapshot_builder.dart',
        ).readAsStringSync(),
      ];
      const forbiddenTerms = <String>[
        'calculateXp',
        'calculateXP',
        'streakCount',
        'leaderboardScore',
        'weeklyXp',
        'weeklyXP',
        'monthlyXp',
        'monthlyXP',
        'subscriptionPrivilegeState',
        'validatedActivityContributionState',
        'countsTowardProgression',
      ];

      for (final source in sources) {
        for (final term in forbiddenTerms) {
          expect(source, isNot(contains(term)), reason: term);
        }
      }
    });
  });
}

class _AveragePaceSourceCase {
  const _AveragePaceSourceCase({
    required this.name,
    required this.sourceType,
    required this.expectedAvailability,
    required this.expectedSource,
    required this.expectedConfidence,
    this.avgPace = '6’30” / km',
    this.expectedLabel,
  });

  final String name;
  final RunSourceType sourceType;
  final String avgPace;
  final AdvancedAnalysisMetricAvailability expectedAvailability;
  final AdvancedAnalysisMetricSource expectedSource;
  final AdvancedAnalysisMetricConfidence expectedConfidence;
  final String? expectedLabel;
}

RunSummarySnapshot _scoreFixtureSummary({
  RunSourceType sourceType = RunSourceType.runiacGps,
  List<ImportedWorkoutMetricContract> importedMetrics =
      const <ImportedWorkoutMetricContract>[],
  CadenceAnalysisSeries? cadenceAnalysisSeries,
  ElevationAnalysisSeries elevationSeries =
      const ElevationAnalysisSeries.unavailable(),
}) {
  return RunSummarySnapshot(
    title: 'Scored Run',
    dateLabel: 'Today',
    timeLabel: '7:06 AM',
    distanceKm: '4.00 km',
    avgPace: '6’30” / km',
    duration: '26:00',
    avgHeartRate: '--',
    calories: '212 kcal',
    routeName: 'East Coast Park Loop',
    sourceType: sourceType,
    importedMetrics: importedMetrics,
    paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
      samples: const [
        PaceAnalysisSample.accepted(
          elapsedSeconds: 0,
          cumulativeDistanceMeters: 0,
          paceSecondsPerKm: 388,
        ),
        PaceAnalysisSample.accepted(
          elapsedSeconds: 780,
          cumulativeDistanceMeters: 2000,
          paceSecondsPerKm: 392,
        ),
        PaceAnalysisSample.accepted(
          elapsedSeconds: 1560,
          cumulativeDistanceMeters: 4000,
          paceSecondsPerKm: 390,
        ),
      ],
    ),
    paceGraph: PaceGraphSnapshot(
      isAvailable: true,
      points: const [
        PaceGraphPoint(
          elapsedSeconds: 0,
          progressFraction: 0,
          paceSecondsPerKm: 388,
          distanceProgressFraction: 0,
        ),
        PaceGraphPoint(
          elapsedSeconds: 780,
          progressFraction: 0.5,
          paceSecondsPerKm: 392,
          distanceProgressFraction: 0.5,
        ),
        PaceGraphPoint(
          elapsedSeconds: 1560,
          progressFraction: 1,
          paceSecondsPerKm: 390,
          distanceProgressFraction: 1,
        ),
      ],
      yAxisLabels: const ['6:20', '6:30', '6:40'],
      xAxisLabels: const ['0:00', '13:00', '26:00'],
      distanceAxisLabels: const ['0 km', '2 km', '4 km'],
      totalDurationSeconds: 1560,
    ),
    cadenceAnalysisSeries: cadenceAnalysisSeries,
    elevationSeries: elevationSeries,
  );
}

class _CadenceUnavailableCase {
  const _CadenceUnavailableCase({
    required this.name,
    required this.series,
    this.sourceType = RunSourceType.runiacGps,
  });

  final String name;
  final CadenceAnalysisSeries series;
  final RunSourceType sourceType;
}
