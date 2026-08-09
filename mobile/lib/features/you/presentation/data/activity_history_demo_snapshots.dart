// The activity history shown when the app runs without a backend.
//
// These are full runs, not stubs — each carries a route, pace and cadence
// series, and a source label — because the history, summary and analysis
// screens all read the same models. A thin fixture would make those screens
// untestable in offline mode, which is the mode the README points a reviewer at
// first.

import '../../../run/domain/models/run_activity_display_model.dart';
import '../../../run/domain/models/cadence_analysis_series.dart';
import '../../../run/domain/models/elevation_analysis_series.dart';
import '../../../run/domain/models/run_location_sample.dart';
import '../../../run/domain/models/run_route_snapshot.dart';
import '../../../run/domain/models/pace_analysis_series.dart';
import '../../../run/domain/models/run_source_display.dart';
import '../../../run/domain/models/run_summary_snapshot.dart';
import '../../../run/presentation/data/pace_graph_demo_snapshots.dart';

// Display-only activity history for the static You prototype.
final activityHistoryDisplayData = [
  ActivityHistoryMonth(
    label: 'June 2026',
    activities: [
      RunActivityDisplayModel(
        title: 'Pace Graph QA Run',
        timeAgoLabel: 'Today · Manual QA',
        distanceLabel: '1.10 km',
        distanceMeters: 1100,
        paceLabel: '7\'16"',
        durationLabel: '8:00',
        summary: RunSummarySnapshot(
          title: 'Pace Graph QA Run',
          dateLabel: 'Today',
          timeLabel: 'Manual QA',
          distanceKm: '1.10',
          avgPace: '7\'16"',
          duration: '8:00',
          avgHeartRate: '135',
          calories: '--',
          routeName: 'Manual Pace Graph Check',
          route: _historyRouteA,
          sourceType: RunSourceType.runiacGps,
          paceAnalysisSeries: PaceAnalysisSeries.localAccepted(
            samples: [
              PaceAnalysisSample.accepted(
                elapsedSeconds: 60,
                cumulativeDistanceMeters: 100,
                paceSecondsPerKm: 428,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 120,
                cumulativeDistanceMeters: 250,
                paceSecondsPerKm: 432,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 180,
                cumulativeDistanceMeters: 450,
                paceSecondsPerKm: 444,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 240,
                cumulativeDistanceMeters: 700,
                paceSecondsPerKm: 456,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 300,
                cumulativeDistanceMeters: 780,
                paceSecondsPerKm: 448,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 360,
                cumulativeDistanceMeters: 850,
                paceSecondsPerKm: 438,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 420,
                cumulativeDistanceMeters: 980,
                paceSecondsPerKm: 430,
              ),
              PaceAnalysisSample.accepted(
                elapsedSeconds: 480,
                cumulativeDistanceMeters: 1100,
                paceSecondsPerKm: 425,
              ),
            ],
          ),
          cadenceAnalysisSeries: CadenceAnalysisSeries.localAccepted(
            samples: const [
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 0,
                cadenceSpm: 173,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 120,
                cadenceSpm: 170,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 240,
                cadenceSpm: 172,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 360,
                cadenceSpm: 174,
              ),
              CadenceAnalysisSample.accepted(
                elapsedSeconds: 480,
                cadenceSpm: 176,
              ),
            ],
          ),
          elevationSeries: ElevationAnalysisSeries.localAccepted(
            samples: const [
              ElevationAnalysisSample(distanceKm: 0, elevationMeters: 4),
              ElevationAnalysisSample(distanceKm: 0.25, elevationMeters: 5.1),
              ElevationAnalysisSample(distanceKm: 0.5, elevationMeters: 7.2),
              ElevationAnalysisSample(distanceKm: 0.8, elevationMeters: 7.8),
              ElevationAnalysisSample(distanceKm: 1.1, elevationMeters: 5.8),
            ],
          ),
          paceGraph: paceGraphManualQaAvailableGraph,
        ),
      ),
      RunActivityDisplayModel(
        title: 'Easy Morning Jog',
        timeAgoLabel: '4 Jun 2026',
        distanceLabel: '4.03 km',
        distanceMeters: 4030,
        paceLabel: '6\'30"',
        durationLabel: '30:15',
        summary: RunSummarySnapshot(
          title: 'Easy Morning Jog',
          dateLabel: '4 Jun 2026',
          timeLabel: '6:45 AM',
          distanceKm: '4.03',
          avgPace: '6\'30"',
          duration: '30:15',
          avgHeartRate: '138',
          calories: '242',
          routeName: 'Neighbourhood Easy Loop',
          route: _historyRouteB,
          sourceType: RunSourceType.garminViaHealth,
          paceGraph: easyMorningHistoryPaceGraph,
        ),
      ),
      RunActivityDisplayModel(
        title: 'Riverside Recovery',
        timeAgoLabel: '1 Jun 2026',
        distanceLabel: '0.06 km',
        distanceMeters: 60,
        paceLabel: '--',
        durationLabel: '00:38',
        summary: RunSummarySnapshot(
          title: 'Riverside Recovery',
          dateLabel: '1 Jun 2026',
          timeLabel: '7:05 PM',
          distanceKm: '0.06',
          avgPace: '--',
          duration: '00:38',
          avgHeartRate: '--',
          calories: '--',
          routeName: 'Riverside Start Check',
          hasSufficientData: false,
          sourceType: RunSourceType.healthConnect,
          paceGraph: unavailablePaceGraph,
        ),
      ),
    ],
  ),
  ActivityHistoryMonth(
    label: 'May 2026',
    activities: [
      RunActivityDisplayModel(
        title: 'Sunset Loop',
        timeAgoLabel: '28 May 2026',
        distanceLabel: '4.50 km',
        distanceMeters: 4500,
        paceLabel: '6\'52"',
        durationLabel: '30:54',
        summary: RunSummarySnapshot(
          title: 'Sunset Loop',
          dateLabel: '28 May 2026',
          timeLabel: '6:12 PM',
          distanceKm: '4.50',
          avgPace: '6\'52"',
          duration: '30:54',
          avgHeartRate: '140',
          calories: '270',
          routeName: 'Sunset Park Loop',
          route: _historyRouteC,
          sourceType: RunSourceType.demoImport,
        ),
      ),
      RunActivityDisplayModel(
        title: 'Tuesday Tempo',
        timeAgoLabel: '20 May 2026',
        distanceLabel: '5.00 km',
        distanceMeters: 5000,
        paceLabel: '6\'20"',
        durationLabel: '31:40',
        summary: RunSummarySnapshot(
          title: 'Tuesday Tempo',
          dateLabel: '20 May 2026',
          timeLabel: '7:10 PM',
          distanceKm: '5.00',
          avgPace: '6\'20"',
          duration: '31:40',
          avgHeartRate: '148',
          calories: '310',
          routeName: 'Tempo Training Loop',
          route: _historyRouteD,
          sourceType: RunSourceType.demoImport,
        ),
      ),
      RunActivityDisplayModel(
        title: 'Park Walk + Run',
        timeAgoLabel: '12 May 2026',
        distanceLabel: '3.80 km',
        distanceMeters: 3800,
        paceLabel: '7\'10"',
        durationLabel: '27:14',
        summary: RunSummarySnapshot(
          title: 'Park Walk + Run',
          dateLabel: '12 May 2026',
          timeLabel: '6:40 PM',
          distanceKm: '3.80',
          avgPace: '7\'10"',
          duration: '27:14',
          avgHeartRate: '134',
          calories: '220',
          routeName: 'Neighbourhood Park Loop',
          route: _historyRouteE,
          sourceType: RunSourceType.demoImport,
        ),
      ),
    ],
  ),
  ActivityHistoryMonth(
    label: 'April 2026',
    activities: [
      RunActivityDisplayModel(
        title: 'First 5K Attempt',
        timeAgoLabel: '25 Apr 2026',
        distanceLabel: '5.00 km',
        distanceMeters: 5000,
        paceLabel: '7\'25"',
        durationLabel: '37:05',
        summary: RunSummarySnapshot(
          title: 'First 5K Attempt',
          dateLabel: '25 Apr 2026',
          timeLabel: '8:02 AM',
          distanceKm: '5.00',
          avgPace: '7\'25"',
          duration: '37:05',
          avgHeartRate: '142',
          calories: '298',
          routeName: 'First 5K Practice Loop',
          route: _historyRouteF,
          sourceType: RunSourceType.demoImport,
        ),
      ),
      RunActivityDisplayModel(
        title: 'Gentle Start',
        timeAgoLabel: '14 Apr 2026',
        distanceLabel: '2.50 km',
        distanceMeters: 2500,
        paceLabel: '7\'40"',
        durationLabel: '19:10',
        summary: RunSummarySnapshot(
          title: 'Gentle Start',
          dateLabel: '14 Apr 2026',
          timeLabel: '7:20 AM',
          distanceKm: '2.50',
          avgPace: '7\'40"',
          duration: '19:10',
          avgHeartRate: '128',
          calories: '150',
          routeName: 'Gentle Starter Loop',
          route: _historyRouteG,
          sourceType: RunSourceType.demoImport,
        ),
      ),
    ],
  ),
];

class ActivityHistoryMonth {
  const ActivityHistoryMonth({required this.label, required this.activities});

  final String label;
  final List<RunActivityDisplayModel> activities;
}

final _historyRouteA = _demoRoute(DateTime.utc(2026, 6, 18, 8), [
  (0, 1.3010, 103.8010),
  (120, 1.3015, 103.8020),
  (240, 1.3024, 103.8016),
  (360, 1.3029, 103.8028),
]);

final _historyRouteB = _demoRoute(DateTime.utc(2026, 6, 4, 6, 45), [
  (0, 1.3060, 103.8040),
  (150, 1.3067, 103.8033),
  (300, 1.3076, 103.8040),
  (450, 1.3084, 103.8032),
]);

final _historyRouteC = _demoRoute(DateTime.utc(2026, 5, 28, 18, 12), [
  (0, 1.3100, 103.8060),
  (120, 1.3104, 103.8074),
  (240, 1.3097, 103.8081),
  (360, 1.3109, 103.8092),
]);

final _historyRouteD = _demoRoute(DateTime.utc(2026, 5, 20, 19, 10), [
  (0, 1.3130, 103.8100),
  (100, 1.3142, 103.8103),
  (200, 1.3147, 103.8115),
  (300, 1.3158, 103.8111),
]);

final _historyRouteE = _demoRoute(DateTime.utc(2026, 5, 12, 18, 40), [
  (0, 1.3180, 103.8130),
  (110, 1.3186, 103.8142),
  (220, 1.3193, 103.8136),
  (330, 1.3200, 103.8148),
]);

final _historyRouteF = _demoRoute(DateTime.utc(2026, 4, 25, 8, 2), [
  (0, 1.3220, 103.8160),
  (140, 1.3231, 103.8155),
  (280, 1.3240, 103.8166),
  (420, 1.3250, 103.8162),
]);

final _historyRouteG = _demoRoute(DateTime.utc(2026, 4, 14, 7, 20), [
  (0, 1.3270, 103.8190),
  (100, 1.3274, 103.8202),
  (200, 1.3282, 103.8200),
  (300, 1.3288, 103.8211),
]);

RunRouteSnapshot _demoRoute(
  DateTime startedAt,
  List<(int, double, double)> points,
) {
  final samples = points
      .map((point) {
        return RunLocationSample(
          recordedAt: startedAt.add(Duration(seconds: point.$1)),
          latitude: point.$2,
          longitude: point.$3,
        );
      })
      .toList(growable: false);

  return RunRouteSnapshot(segments: [samples], lastKnownLocation: samples.last);
}
