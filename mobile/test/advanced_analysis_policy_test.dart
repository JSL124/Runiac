import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/advanced_analysis_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/pace_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/pace_graph_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_source_display.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/workout_metric_contract.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_achievement_badge_builder.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';
import 'package:runiac_app/features/run/presentation/widgets/advanced_analysis/advanced_analysis_overview_section.dart';
import 'package:runiac_app/features/run/presentation/widgets/advanced_analysis/advanced_analysis_score_ring.dart';

void main() {
  group('Advanced Analysis policy', () {
    const builder = AdvancedAnalysisSnapshotBuilder();

    test('calculates supportive quality indicators by source mode', () {
      final mobilePerformance = builder
          .fromRunSummary(_scoreFixtureSummary())
          .performance;
      final mixedPerformance = builder
          .fromRunSummary(
            _scoreFixtureSummary(
              cadenceAnalysisSeries: _phoneMotionCadenceSeries(),
            ),
          )
          .performance;
      final wearablePerformance = builder
          .fromRunSummary(
            _scoreFixtureSummary(
              sourceType: RunSourceType.appleHealth,
            ),
          )
          .performance;
      final demoPerformance = builder
          .fromRunSummary(
            const RunSummarySnapshot(
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
            ),
          )
          .performance;

      expect(
        mobilePerformance.scoreMode,
        AdvancedAnalysisScoreSourceMode.mobileOnly,
      );
      expect(mobilePerformance.score.value, 97);
      expect(
        mixedPerformance.scoreMode,
        AdvancedAnalysisScoreSourceMode.mobileOnly,
      );
      expect(mixedPerformance.score.value, mobilePerformance.score.value);
      expect(
        wearablePerformance.scoreMode,
        AdvancedAnalysisScoreSourceMode.wearableBacked,
      );
      expect(wearablePerformance.score.value, 73);
      expect(
        demoPerformance.scoreMode,
        AdvancedAnalysisScoreSourceMode.demoOnly,
      );
      expect(demoPerformance.score.value, 65);
      expect(demoPerformance.score.isTrustedProduction, isFalse);
      expect(mobilePerformance.qualityLabel, 'Steady effort');
      expect(mixedPerformance.qualityLabel, 'Steady effort');
    });

    test('keeps mobile-only run quality fair without optional metrics', () {
      const mobileSummary = RunSummarySnapshot(
        title: 'Phone Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.00 km',
        avgPace: '6’30” / km',
        duration: '26:00',
        avgHeartRate: '--',
        calories: '212 kcal',
        routeName: 'East Coast Park Loop',
      );
      final phoneEnhancedSummary = mobileSummary.copyWith(
        cadenceAnalysisSeries: _phoneMotionCadenceSeries(),
        elevationSeries: ElevationAnalysisSeries.localAccepted(
          samples: const [
            ElevationAnalysisSample(distanceKm: 0, elevationMeters: 4),
            ElevationAnalysisSample(distanceKm: 2, elevationMeters: 8),
            ElevationAnalysisSample(distanceKm: 4, elevationMeters: 5),
          ],
        ),
      );

      final mobilePerformance = builder
          .fromRunSummary(mobileSummary)
          .performance;
      final phoneEnhancedPerformance = builder
          .fromRunSummary(phoneEnhancedSummary)
          .performance;

      expect(
        mobilePerformance.scoreMode,
        AdvancedAnalysisScoreSourceMode.mobileOnly,
      );
      expect(mobilePerformance.score.isAvailable, isTrue);
      expect(
        phoneEnhancedPerformance.scoreMode,
        AdvancedAnalysisScoreSourceMode.mobileOnly,
      );
      expect(
        phoneEnhancedPerformance.score.value,
        mobilePerformance.score.value,
      );
      expect(mobilePerformance.qualityLabel, 'Good foundation run');
      expect(
        mobilePerformance.takeaway,
        contains('Missing wearable data does not lower this overview.'),
      );
    });

    test('uses supportive low-data run overview without numeric quality', () {
      const lowDataSummary = RunSummarySnapshot(
        title: 'Short Try',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '0.05 km',
        avgPace: '9’30” / km',
        duration: '00:20',
        avgHeartRate: '--',
        calories: '3 kcal',
        routeName: 'Starting Out',
        hasSufficientData: false,
      );

      final performance = builder.fromRunSummary(lowDataSummary).performance;

      expect(performance.score.isAvailable, isFalse);
      expect(performance.score.value, isNull);
      expect(performance.qualityLabel, 'More data needed');
      expect(
        performance.takeaway,
        'This run was a useful start, but there is not enough movement data yet to give a detailed overview.',
      );
      expect(
        performance.nextFocus,
        'Try a slightly longer easy run so Runiac can give more useful feedback.',
      );
    });

    testWidgets('keeps overview ring while removing competitive score copy', (
      tester,
    ) async {
      final performance = builder
          .fromRunSummary(_scoreFixtureSummary())
          .performance;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdvancedAnalysisOverviewSection(analysis: performance),
          ),
        ),
      );

      expect(find.byType(AdvancedAnalysisScoreRing), findsOneWidget);
      expect(find.text('Run Quality'), findsOneWidget);
      expect(find.text('Steady effort'), findsOneWidget);
      expect(find.textContaining('score', findRichText: true), findsNothing);
      expect(find.textContaining('Performance Score'), findsNothing);
      expect(find.textContaining('Rating'), findsNothing);
      expect(find.textContaining('Grade'), findsNothing);
      expect(find.textContaining('poor', findRichText: true), findsNothing);
      expect(find.textContaining('bad', findRichText: true), findsNothing);
      expect(find.textContaining('XP'), findsNothing);
      expect(find.textContaining('leaderboard'), findsNothing);
      expect(find.textContaining('rank'), findsNothing);
      expect(find.textContaining('level'), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
    });

    test(
      'returns unavailable performance score without distance or duration',
      () {
        const missingDistance = RunSummarySnapshot(
          title: 'Missing Distance',
          dateLabel: 'Today',
          timeLabel: '7:06 AM',
          distanceKm: '--',
          avgPace: '6’30” / km',
          duration: '26:00',
          avgHeartRate: '--',
          calories: '212 kcal',
          routeName: 'East Coast Park Loop',
        );
        const missingDuration = RunSummarySnapshot(
          title: 'Missing Duration',
          dateLabel: 'Today',
          timeLabel: '7:06 AM',
          distanceKm: '4.00 km',
          avgPace: '6’30” / km',
          duration: '--',
          avgHeartRate: '--',
          calories: '212 kcal',
          routeName: 'East Coast Park Loop',
        );

        for (final summary in [missingDistance, missingDuration]) {
          final score = builder.fromRunSummary(summary).performance.score;

          expect(score.isAvailable, isFalse, reason: summary.title);
          expect(
            score.reason,
            AdvancedAnalysisMetricReason.missingSummaryField,
            reason: summary.title,
          );
        }
      },
    );

    test('gates achievement badges by supporting metric data', () {
      final mobileSnapshot = builder.fromRunSummary(_scoreFixtureSummary());
      final supportingDataSnapshot = builder.fromRunSummary(
        _scoreFixtureSummary(
          sourceType: RunSourceType.runiacGps,
          cadenceAnalysisSeries: _phoneMotionCadenceSeries(),
          elevationSeries: ElevationAnalysisSeries.localAccepted(
            samples: const [
              ElevationAnalysisSample(distanceKm: 0, elevationMeters: 4),
              ElevationAnalysisSample(distanceKm: 2, elevationMeters: 10),
              ElevationAnalysisSample(distanceKm: 4, elevationMeters: 5),
            ],
          ),
        ),
      );

      expect(
        mobileSnapshot.performance.badges.map((badge) => badge.kind),
        isNot(contains(AdvancedAnalysisBadgeKind.consistentCadence)),
      );
      expect(
        mobileSnapshot.performance.badges.map((badge) => badge.kind),
        isNot(contains(AdvancedAnalysisBadgeKind.hillSteady)),
      );
      expect(
        supportingDataSnapshot.performance.badges.map((badge) => badge.kind),
        containsAll([
          AdvancedAnalysisBadgeKind.consistentCadence,
          AdvancedAnalysisBadgeKind.hillSteady,
        ]),
      );
    });

    test('documents positive badge rules with supporting metric data', () {
      final snapshot = builder.fromRunSummary(
        _scoreFixtureSummary(
          sourceType: RunSourceType.appleHealth,
          cadenceAnalysisSeries: CadenceAnalysisSeries(
            source: CadenceAnalysisSource.healthKitAppleWatch,
            confidence: CadenceAnalysisConfidence.high,
            samples: const [
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 0,
                cadenceSpm: 162,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 600,
                cadenceSpm: 164,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 1200,
                cadenceSpm: 163,
              ),
            ],
          ),
          elevationSeries: ElevationAnalysisSeries.localAccepted(
            samples: const [
              ElevationAnalysisSample(distanceKm: 0, elevationMeters: 4),
              ElevationAnalysisSample(distanceKm: 2, elevationMeters: 10),
              ElevationAnalysisSample(distanceKm: 4, elevationMeters: 5),
            ],
          ),
        ),
      );

      expect(
        snapshot.performance.badges.map((badge) => badge.kind),
        containsAll([
          AdvancedAnalysisBadgeKind.firstStep,
          AdvancedAnalysisBadgeKind.goodEndurance,
          AdvancedAnalysisBadgeKind.evenSplit,
          AdvancedAnalysisBadgeKind.consistentCadence,
          AdvancedAnalysisBadgeKind.smoothRhythm,
          AdvancedAnalysisBadgeKind.hillSteady,
        ]),
      );
      final stablePaceBadges = builder
          .fromRunSummary(
            _scoreFixtureSummary().copyWith(
              paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
                samples: const [
                  PaceAnalysisSample.accepted(
                    elapsedSeconds: 0,
                    cumulativeDistanceMeters: 0,
                    paceSecondsPerKm: 420,
                  ),
                  PaceAnalysisSample.accepted(
                    elapsedSeconds: 780,
                    cumulativeDistanceMeters: 2000,
                    paceSecondsPerKm: 400,
                  ),
                  PaceAnalysisSample.accepted(
                    elapsedSeconds: 1560,
                    cumulativeDistanceMeters: 4000,
                    paceSecondsPerKm: 390,
                  ),
                ],
              ),
            ),
          )
          .performance
          .badges
          .map((badge) => badge.kind);
      final strongFinishSummary = _scoreFixtureSummary();
      final strongFinishBadges = const AdvancedAnalysisAchievementBadgeBuilder()
          .build(
            summary: strongFinishSummary,
            paceAnalysis: null,
            cadenceAnalysis: null,
            splits: const [
              AdvancedAnalysisSplitSnapshot(
                distanceLabel: '1 km',
                paceLabel: '7’00”',
                paceSecondsPerKm: 420,
                isPartial: false,
              ),
              AdvancedAnalysisSplitSnapshot(
                distanceLabel: '2 km',
                paceLabel: '6’30”',
                paceSecondsPerKm: 390,
                isPartial: false,
              ),
            ],
          )
          .map((badge) => badge.kind);

      expect(
        stablePaceBadges,
        containsAll([
          AdvancedAnalysisBadgeKind.stablePace,
          AdvancedAnalysisBadgeKind.goodConsistency,
        ]),
      );
      expect(
        strongFinishBadges,
        containsAll([
          AdvancedAnalysisBadgeKind.strongFinish,
          AdvancedAnalysisBadgeKind.negativeSplit,
        ]),
      );
    });

    test(
      'documents even split badge when splits are steady but not faster',
      () {
        final snapshot = builder.fromRunSummary(
          _scoreFixtureSummary().copyWith(
            paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
              samples: const [
                PaceAnalysisSample.accepted(
                  elapsedSeconds: 0,
                  cumulativeDistanceMeters: 0,
                  paceSecondsPerKm: 400,
                ),
                PaceAnalysisSample.accepted(
                  elapsedSeconds: 800,
                  cumulativeDistanceMeters: 2000,
                  paceSecondsPerKm: 404,
                ),
                PaceAnalysisSample.accepted(
                  elapsedSeconds: 1600,
                  cumulativeDistanceMeters: 4000,
                  paceSecondsPerKm: 410,
                ),
              ],
            ),
          ),
        );

        expect(
          snapshot.performance.badges.map((badge) => badge.kind),
          contains(AdvancedAnalysisBadgeKind.evenSplit),
        );
        expect(
          snapshot.performance.badges.map((badge) => badge.kind),
          isNot(contains(AdvancedAnalysisBadgeKind.strongFinish)),
        );
      },
    );

    test('does not award badges when required data is missing', () {
      const missingSummaryData = RunSummarySnapshot(
        title: 'Missing Summary',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '--',
        avgPace: '--',
        duration: '--',
        avgHeartRate: '--',
        calories: '0 kcal',
        routeName: 'No Data',
      );

      final badges = builder
          .fromRunSummary(missingSummaryData)
          .performance
          .badges
          .map((badge) => badge.kind);

      expect(badges, isNot(contains(AdvancedAnalysisBadgeKind.firstStep)));
      expect(badges, isNot(contains(AdvancedAnalysisBadgeKind.goodEndurance)));
      expect(badges, isNot(contains(AdvancedAnalysisBadgeKind.stablePace)));
      expect(
        badges,
        isNot(contains(AdvancedAnalysisBadgeKind.goodConsistency)),
      );
      expect(badges, isNot(contains(AdvancedAnalysisBadgeKind.strongFinish)));
      expect(badges, isNot(contains(AdvancedAnalysisBadgeKind.negativeSplit)));
      expect(badges, isNot(contains(AdvancedAnalysisBadgeKind.evenSplit)));
      expect(
        badges,
        isNot(contains(AdvancedAnalysisBadgeKind.consistentCadence)),
      );
      expect(badges, isNot(contains(AdvancedAnalysisBadgeKind.smoothRhythm)));
      expect(badges, isNot(contains(AdvancedAnalysisBadgeKind.hillSteady)));
    });

  });
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

CadenceAnalysisSeries _phoneMotionCadenceSeries() {
  return CadenceAnalysisSeries.phoneMotionEstimated(
    samples: const [
      CadenceAnalysisSample.accepted(elapsedSeconds: 0, cadenceSpm: 162),
      CadenceAnalysisSample.accepted(elapsedSeconds: 600, cadenceSpm: 164),
      CadenceAnalysisSample.accepted(elapsedSeconds: 1200, cadenceSpm: 163),
    ],
  );
}
