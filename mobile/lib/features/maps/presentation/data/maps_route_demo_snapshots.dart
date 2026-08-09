import '../shared_route_detail_screen.dart';

const selectedRouteDemoSnapshot = SharedRouteDetailSnapshot(
  title: 'Marina Bay easy loop',
  distance: '3.2 km',
  duration: '25 min',
  difficulty: 'Easy',
  likeCountLabel: '24',
);

const favouriteRouteDemoSnapshots = <SharedRouteDetailSnapshot>[
  SharedRouteDetailSnapshot(
    title: 'Bishan Park starter route',
    distance: '2.4 km',
    duration: '18 min',
    difficulty: 'Easy',
    likeCountLabel: '18',
  ),
  SharedRouteDetailSnapshot(
    title: 'East Coast flat run',
    distance: '4.0 km',
    duration: '32 min',
    difficulty: 'Easy',
    likeCountLabel: '31',
  ),
  SharedRouteDetailSnapshot(
    title: 'Punggol waterway loop',
    distance: '3.6 km',
    duration: '28 min',
    difficulty: 'Easy',
    likeCountLabel: '22',
  ),
  SharedRouteDetailSnapshot(
    title: 'Kallang riverside run',
    distance: '3.0 km',
    duration: '23 min',
    difficulty: 'Easy',
    likeCountLabel: '15',
  ),
];

const sharedRoutesDemoSnapshot = SharedRoutesDemoSnapshot(
  title: 'Shared Routes',
  seeAllActionLabel: 'See all',
  showLessActionLabel: 'Show less',
  routeCards: [
    RouteCardDemoSnapshot(
      keySuffix: 'marina_bay_easy_loop',
      title: 'Marina Bay easy loop',
      distance: '3.2 km',
      duration: '25 min',
      difficulty: 'Easy',
      likeCount: 1400,
    ),
    RouteCardDemoSnapshot(
      keySuffix: 'bishan_park_starter_route',
      title: 'Bishan Park starter route',
      distance: '2.4 km',
      duration: '18 min',
      difficulty: 'Easy',
      likeCount: 86,
    ),
    RouteCardDemoSnapshot(
      keySuffix: 'east_coast_flat_run',
      title: 'East Coast flat run',
      distance: '4.0 km',
      duration: '32 min',
      difficulty: 'Easy',
      likeCount: 104,
    ),
    RouteCardDemoSnapshot(
      keySuffix: 'punggol_waterway_loop',
      title: 'Punggol waterway loop',
      distance: '3.6 km',
      duration: '28 min',
      difficulty: 'Easy',
      likeCount: 72,
    ),
    RouteCardDemoSnapshot(
      keySuffix: 'kallang_riverside_run',
      title: 'Kallang riverside run',
      distance: '3.0 km',
      duration: '23 min',
      difficulty: 'Easy',
      likeCount: 58,
    ),
  ],
);

class SharedRoutesDemoSnapshot {
  const SharedRoutesDemoSnapshot({
    required this.title,
    required this.seeAllActionLabel,
    required this.showLessActionLabel,
    required this.routeCards,
  });

  final String title;
  final String seeAllActionLabel;
  final String showLessActionLabel;
  final List<RouteCardDemoSnapshot> routeCards;

  Iterable<RouteCardDemoSnapshot> get previewRouteCards => routeCards.take(3);

  List<RouteCardDemoSnapshot> get expandedRouteCards => routeCards;
}

class RouteCardDemoSnapshot {
  const RouteCardDemoSnapshot({
    required this.keySuffix,
    required this.title,
    required this.distance,
    required this.duration,
    required this.difficulty,
    required this.likeCount,
  });

  final String keySuffix;
  final String title;
  final String distance;
  final String duration;
  final String difficulty;
  final int likeCount;

  String get meta => '$distance · $duration · $difficulty';
  String get likeCountLabel => formatRouteLikeCount(likeCount);
}

String formatRouteLikeCount(int count) {
  if (count < 1000) {
    return '$count';
  }

  final thousands = count / 1000;
  final formatted = thousands.toStringAsFixed(count % 1000 == 0 ? 0 : 1);
  return '${formatted.replaceAll(RegExp(r'\.0$'), '')}k';
}
