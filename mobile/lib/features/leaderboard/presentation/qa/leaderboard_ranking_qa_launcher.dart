import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_theme.dart';
import '../leaderboard_tab.dart';

const leaderboardRankingQaSurfaceName = 'leaderboard_ranking';

const _qaSurface = String.fromEnvironment('RUNIAC_QA_SURFACE');

Widget? buildLeaderboardRankingQaAppFromEnvironment() {
  if (kReleaseMode || _qaSurface != leaderboardRankingQaSurfaceName) {
    return null;
  }

  // The tab defaults to StaticLeaderboardRepository, so this boots the full
  // leaderboard surface (map background + region preview sheet) on demo data.
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Runiac Leaderboard QA',
    theme: buildRuniacTheme(),
    home: const Scaffold(body: SafeArea(child: LeaderboardTab())),
  );
}
