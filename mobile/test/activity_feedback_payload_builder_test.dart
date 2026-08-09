import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/cadence_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/elevation_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/pace_analysis_series.dart';
import 'package:runiac_app/features/run/domain/models/run_source_display.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/services/activity_feedback_payload_builder.dart';
import 'package:runiac_app/features/run/domain/services/advanced_analysis_snapshot_builder.dart';

void main() {
  group('ActivityFeedbackPayloadBuilder', () {
    const payloadBuilder = ActivityFeedbackPayloadBuilder();
    const analysisBuilder = AdvancedAnalysisSnapshotBuilder();

    test('builds the exact derived-metrics callable payload', () {
      // Given
      final summary = _productionSummary();
      final analysis = analysisBuilder.fromRunSummary(summary);

      // When
      final payload = payloadBuilder.build(
        summary: summary,
        analysis: analysis,
      );

      // Then
      expect(payload.keys.toSet(), <String>{
        'schemaVersion',
        'summary',
        'performance',
        'pace',
        'cadence',
        'elevation',
      });
      expect(payload['schemaVersion'], 1);
      expect(payload['summary'], <String, Object>{
        'distanceKm': 5.2,
        'durationSeconds': 1920,
        'averagePaceSecondsPerKm': 369,
        'caloriesKcal': 321,
        'sourceLabel': 'Runiac GPS',
      });

      final performance = payload['performance']! as Map<String, Object?>;
      expect(performance.keys.toSet(), <String>{
        'score',
        'qualityLabel',
        'takeaway',
        'nextFocus',
        'scoreConfidenceLabel',
      });

      final pace = payload['pace']! as Map<String, Object?>;
      expect(pace.keys.toSet(), <String>{
        'fastestPaceSecondsPerKm',
        'slowestPaceSecondsPerKm',
        'stabilityLabel',
        'splits',
      });
      expect(pace['fastestPaceSecondsPerKm'], isA<int>());
      expect(pace['slowestPaceSecondsPerKm'], isA<int>());
      expect(pace['splits'], isNotEmpty);

      final cadence = payload['cadence']! as Map<String, Object?>;
      expect(cadence, <String, Object?>{
        'averageSpm': 166,
        'status': isA<String>(),
        'strideConsistency': isA<String>(),
        'isEstimated': true,
        'confidence': 'estimated',
        'sourceReason': 'estimatedFromPhoneSensors',
      });

      final elevation = payload['elevation']! as Map<String, Object?>;
      expect(elevation.keys.toSet(), <String>{
        'totalGainMeters',
        'highestPointMeters',
        'lowestPointMeters',
        'difficulty',
      });
    });

    test('never includes private identity route or demo-only values', () {
      // Given
      final summary = _productionSummary();
      final analysis = analysisBuilder.fromRunSummary(summary);

      // When
      final payload = payloadBuilder.build(
        summary: summary,
        analysis: analysis,
      );
      final encoded = payload.toString();

      // Then
      for (final forbidden in <String>{
        'title',
        'dateLabel',
        'timeLabel',
        'routeName',
        'activityId',
        'route',
        'polyline',
        'coordinates',
        'demoOnly',
        'Private sunrise loop',
      }) {
        expect(encoded, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('rejects a demo source before a callable payload can be sent', () {
      // Given
      const summary = RunSummarySnapshot(
        title: 'Demo Run',
        dateLabel: 'Today',
        timeLabel: '7:00 AM',
        distanceKm: '5.20 km',
        avgPace: '6\u201909\u201d / km',
        duration: '32:00',
        avgHeartRate: '--',
        calories: '321 kcal',
        routeName: 'Private sunrise loop',
        sourceType: RunSourceType.demoImport,
      );
      final analysis = analysisBuilder.fromRunSummary(summary);

      // When / Then
      expect(
        () => payloadBuilder.build(summary: summary, analysis: analysis),
        throwsA(isA<ActivityFeedbackPayloadException>()),
      );
    });
  });
}

RunSummarySnapshot _productionSummary() {
  return RunSummarySnapshot(
    title: 'Saturday Morning Run',
    dateLabel: 'Today',
    timeLabel: '7:06 AM',
    distanceKm: '5.20 km',
    avgPace: '6\u201909\u201d / km',
    duration: '32:00',
    avgHeartRate: '--',
    calories: '321 kcal',
    routeName: 'Private sunrise loop',
    paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
      samples: const <PaceAnalysisSample>[
        PaceAnalysisSample.accepted(
          elapsedSeconds: 0,
          cumulativeDistanceMeters: 0,
          paceSecondsPerKm: 374,
        ),
        PaceAnalysisSample.accepted(
          elapsedSeconds: 620,
          cumulativeDistanceMeters: 1700,
          paceSecondsPerKm: 365,
        ),
        PaceAnalysisSample.accepted(
          elapsedSeconds: 1240,
          cumulativeDistanceMeters: 3400,
          paceSecondsPerKm: 371,
        ),
        PaceAnalysisSample.accepted(
          elapsedSeconds: 1920,
          cumulativeDistanceMeters: 5200,
          paceSecondsPerKm: 368,
        ),
      ],
    ),
    cadenceAnalysisSeries: CadenceAnalysisSeries.phoneMotionEstimated(
      samples: const <CadenceAnalysisSample>[
        CadenceAnalysisSample.accepted(elapsedSeconds: 0, cadenceSpm: 164),
        CadenceAnalysisSample.accepted(elapsedSeconds: 620, cadenceSpm: 166),
        CadenceAnalysisSample.accepted(elapsedSeconds: 1240, cadenceSpm: 168),
        CadenceAnalysisSample.accepted(elapsedSeconds: 1920, cadenceSpm: 166),
      ],
    ),
    elevationSeries: ElevationAnalysisSeries.localAccepted(
      samples: const <ElevationAnalysisSample>[
        ElevationAnalysisSample(distanceKm: 0, elevationMeters: 12),
        ElevationAnalysisSample(distanceKm: 2, elevationMeters: 18),
        ElevationAnalysisSample(distanceKm: 4, elevationMeters: 15),
        ElevationAnalysisSample(distanceKm: 5.2, elevationMeters: 21),
      ],
    ),
  );
}
