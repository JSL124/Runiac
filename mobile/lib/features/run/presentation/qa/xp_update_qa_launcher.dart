import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_theme.dart';
import '../../domain/models/xp_update_display_model.dart';
import '../xp_update_screen.dart';

const xpUpdateQaSurfaceName = 'xp_update';

const _qaSurface = String.fromEnvironment('RUNIAC_QA_SURFACE');
const _qaXpScenario = String.fromEnvironment(
  'RUNIAC_QA_XP_SCENARIO',
  defaultValue: 'awarded_normal',
);

Widget? buildXpUpdateQaAppFromEnvironment() {
  return buildXpUpdateQaApp(
    releaseMode: kReleaseMode,
    surface: _qaSurface,
    scenarioName: _qaXpScenario,
  );
}

@visibleForTesting
Widget? buildXpUpdateQaApp({
  required bool releaseMode,
  required String surface,
  required String scenarioName,
}) {
  if (releaseMode || surface != xpUpdateQaSurfaceName) {
    return null;
  }

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Runiac XP QA',
    theme: buildRuniacTheme(),
    home: XpUpdateScreen(model: xpUpdateQaModelForScenario(scenarioName)),
  );
}

@visibleForTesting
XpUpdateDisplayModel xpUpdateQaModelForScenario(String scenarioName) {
  return switch (scenarioName) {
    'level_up' => _levelUp,
    'low_data_no_xp' => _lowDataNoXp,
    'premium_no_competitive_xp' => _premiumNoCompetitiveXp,
    'deferred' => _deferred,
    'rest_day_streak_bridge' => _restDayStreakBridge,
    _ => _awardedNormal,
  };
}

const _awardedNormal = XpUpdateDisplayModel(
  runnerName: 'QA Runner',
  earnedXpLabel: '+75 XP',
  totalXpLabel: '1,275 XP',
  levelLabel: '4',
  nextLevelLabel: '5',
  progressTargetLabel: 'Progress to Level 5',
  xpRemainingLabel: '225 XP to Level 5',
  previousProgressFraction: 0.40,
  currentProgressFraction: 0.64,
  streakChangeLabel: '4 to 5 days',
  streakNote: 'Backend validated streak.',
  didLevelUp: false,
  xpAwardState: XpAwardState.awarded,
  heroMessage: 'Earned from this run',
  earnedXp: 75,
  totalXp: 1275,
  previousTotalXp: 1200,
  level: 4,
  previousLevel: 4,
  streakCount: 5,
  previousStreakCount: 4,
);

const _levelUp = XpUpdateDisplayModel(
  runnerName: 'QA Runner',
  earnedXpLabel: '+120 XP',
  totalXpLabel: '2,020 XP',
  levelLabel: '6',
  nextLevelLabel: '7',
  progressTargetLabel: 'Progress to Level 7',
  xpRemainingLabel: '280 XP to Level 7',
  previousProgressFraction: 0.92,
  currentProgressFraction: 0.18,
  streakChangeLabel: '8 to 9 days',
  streakNote: 'Level and streak came from backend progression.',
  didLevelUp: true,
  xpAwardState: XpAwardState.awarded,
  heroMessage: 'You reached Level 6. Keep the streak moving.',
  earnedXp: 120,
  totalXp: 2020,
  previousTotalXp: 1900,
  level: 6,
  previousLevel: 5,
  streakCount: 9,
  previousStreakCount: 8,
);

const _lowDataNoXp = XpUpdateDisplayModel(
  runnerName: 'QA Runner',
  earnedXpLabel: '+0 XP',
  totalXpLabel: '2,020 XP',
  levelLabel: '6',
  nextLevelLabel: '7',
  progressTargetLabel: 'Progress to Level 7',
  xpRemainingLabel: '280 XP to Level 7',
  previousProgressFraction: 0.18,
  currentProgressFraction: 0.18,
  streakChangeLabel: '9 days',
  streakNote: 'Run saved, but XP was not awarded.',
  didLevelUp: false,
  xpAwardState: XpAwardState.notAwarded,
  heroMessage: 'Low GPS confidence saved without XP.',
  earnedXp: 0,
  totalXp: 2020,
  previousTotalXp: 2020,
  level: 6,
  previousLevel: 6,
  streakCount: 9,
  previousStreakCount: 9,
);

const _premiumNoCompetitiveXp = XpUpdateDisplayModel(
  runnerName: 'QA Runner',
  earnedXpLabel: '+0 XP',
  totalXpLabel: '2,020 XP',
  levelLabel: '6',
  nextLevelLabel: '7',
  progressTargetLabel: 'Progress to Level 7',
  xpRemainingLabel: '280 XP to Level 7',
  previousProgressFraction: 0.18,
  currentProgressFraction: 0.18,
  streakChangeLabel: '9 to 10 days',
  streakNote: 'Premium features do not add competitive XP.',
  didLevelUp: false,
  xpAwardState: XpAwardState.notAwarded,
  heroMessage: 'Premium status gives no XP or ranking advantage.',
  earnedXp: 0,
  totalXp: 2020,
  previousTotalXp: 2020,
  level: 6,
  previousLevel: 6,
  streakCount: 10,
  previousStreakCount: 9,
);

const _deferred = XpUpdateDisplayModel(
  runnerName: 'QA Runner',
  earnedXpLabel: '+0 XP',
  totalXpLabel: '2,020 XP',
  levelLabel: '6',
  nextLevelLabel: '7',
  progressTargetLabel: 'Progress to Level 7',
  xpRemainingLabel: '280 XP to Level 7',
  previousProgressFraction: 0.18,
  currentProgressFraction: 0.18,
  streakChangeLabel: 'Pending',
  streakNote: 'Progression is waiting for backend validation.',
  didLevelUp: false,
  xpAwardState: XpAwardState.deferred,
  heroMessage: 'Run saved. Progression will update after validation.',
  earnedXp: 0,
  totalXp: 2020,
  previousTotalXp: 2020,
  level: 6,
  previousLevel: 6,
  streakCount: 9,
  previousStreakCount: 9,
);

const _restDayStreakBridge = XpUpdateDisplayModel(
  runnerName: 'QA Runner',
  earnedXpLabel: '+80 XP',
  totalXpLabel: '2,100 XP',
  levelLabel: '6',
  nextLevelLabel: '7',
  progressTargetLabel: 'Progress to Level 7',
  xpRemainingLabel: '200 XP to Level 7',
  previousProgressFraction: 0.18,
  currentProgressFraction: 0.42,
  streakChangeLabel: '2 to 3 days',
  streakNote: 'Rest day protected it.',
  didLevelUp: false,
  xpAwardState: XpAwardState.awarded,
  heroMessage: 'Rest day bridge accepted by backend progression.',
  earnedXp: 80,
  totalXp: 2100,
  previousTotalXp: 2020,
  level: 6,
  previousLevel: 6,
  streakCount: 3,
  previousStreakCount: 2,
);
