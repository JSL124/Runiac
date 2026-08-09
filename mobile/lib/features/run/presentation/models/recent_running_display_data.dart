import '../../domain/models/run_activity_display_model.dart';
import '../../domain/models/run_location_sample.dart';
import '../../domain/models/run_route_snapshot.dart';
import '../../domain/models/run_source_display.dart';
import '../../domain/models/run_summary_snapshot.dart';
import '../data/pace_graph_demo_snapshots.dart';

final recentRunningDisplayData = [
  RunActivityDisplayModel(
    timeAgoLabel: '4/11/26',
    title: 'Saturday Night Run',
    distanceLabel: '4.03 km',
    distanceMeters: 4030,
    paceLabel: '6\'30"',
    durationLabel: '30:15',
    summary: RunSummarySnapshot(
      title: 'Saturday Night Run',
      dateLabel: '4/11/26',
      timeLabel: '9:18 PM',
      distanceKm: '4.03',
      avgPace: '6’30”',
      duration: '30:15',
      avgHeartRate: '145',
      calories: '145',
      routeName: 'East Coast Park Night Loop',
      route: _recentRouteA,
      sourceType: RunSourceType.appleHealth,
      paceGraph: saturdayNightRecentPaceGraph,
    ),
  ),
  RunActivityDisplayModel(
    timeAgoLabel: '4/11/26',
    title: 'Morning Easy Run',
    distanceLabel: '3.20 km',
    distanceMeters: 3200,
    paceLabel: '7\'05"',
    durationLabel: '24:10',
    summary: RunSummarySnapshot(
      title: 'Morning Easy Run',
      dateLabel: '4/11/26',
      timeLabel: '6:45 AM',
      distanceKm: '3.20',
      avgPace: '7’05”',
      duration: '24:10',
      avgHeartRate: '138',
      calories: '212',
      routeName: 'Neighbourhood Easy Loop',
      route: _recentRouteB,
      sourceType: RunSourceType.garminViaHealth,
      paceGraph: morningEasyRecentPaceGraph,
    ),
  ),
  RunActivityDisplayModel(
    timeAgoLabel: '4/11/26',
    title: 'Recovery Jog',
    distanceLabel: '5.17 km',
    distanceMeters: 5170,
    paceLabel: '7\'40"',
    durationLabel: '39:38',
    summary: RunSummarySnapshot(
      title: 'Recovery Jog',
      dateLabel: '4/11/26',
      timeLabel: '8:10 PM',
      distanceKm: '5.17',
      avgPace: '7’40”',
      duration: '39:38',
      avgHeartRate: '132',
      calories: '286',
      routeName: 'Park Connector Recovery Loop',
      route: _recentRouteC,
      sourceType: RunSourceType.demoImport,
      paceGraph: recoveryJogPaceGraph,
    ),
  ),
];

final _recentRouteA = _demoRoute([
  (0, 1.3000, 103.8000),
  (90, 1.3008, 103.8015),
  (180, 1.3018, 103.8011),
  (270, 1.3024, 103.8023),
]);

final _recentRouteB = _demoRoute([
  (0, 1.3040, 103.8060),
  (80, 1.3049, 103.8052),
  (160, 1.3055, 103.8061),
  (240, 1.3064, 103.8054),
]);

final _recentRouteC = _demoRoute([
  (0, 1.3080, 103.8100),
  (100, 1.3084, 103.8112),
  (200, 1.3078, 103.8122),
  (300, 1.3087, 103.8130),
]);

RunRouteSnapshot _demoRoute(List<(int, double, double)> points) {
  final startedAt = DateTime.utc(2026, 4, 11, 20);
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
