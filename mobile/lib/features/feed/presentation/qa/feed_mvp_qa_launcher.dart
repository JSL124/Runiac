import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app.dart';

const feedMvpQaSurfaceName = 'feed_mvp';

const _qaSurface = String.fromEnvironment('RUNIAC_QA_SURFACE');

Widget? buildFeedMvpQaAppFromEnvironment() {
  return buildFeedMvpQaApp(releaseMode: kReleaseMode, surface: _qaSurface);
}

@visibleForTesting
Widget? buildFeedMvpQaApp({
  required bool releaseMode,
  required String surface,
}) {
  if (releaseMode || surface != feedMvpQaSurfaceName) {
    return null;
  }

  return const RuniacApp(
    showSplash: false,
    showAuth: false,
    showOnboarding: false,
    enableForegroundGps: false,
  );
}
