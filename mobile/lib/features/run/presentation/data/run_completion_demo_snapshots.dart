import '../../domain/models/coaching_summary_snapshot.dart';
import '../../domain/models/run_summary_snapshot.dart';
import '../../domain/models/run_source_display.dart';
import '../../domain/models/xp_update_display_model.dart';
import 'pace_graph_demo_snapshots.dart';

/// Display-only run summary snapshot for the static run completion surface.
const defaultRunSummarySnapshot = RunSummarySnapshot(
  title: 'Saturday Morning Run',
  dateLabel: 'Today',
  timeLabel: '7:06 AM',
  distanceKm: '4.03',
  avgPace: '6’30”',
  duration: '30:15',
  avgHeartRate: '145',
  calories: '145',
  routeName: 'East Coast Park Loop',
  sourceType: RunSourceType.demoImport,
  paceGraph: normalEasyRunPaceGraph,
  coachingSummary: CoachingSummarySnapshot(
    source: CoachingSummarySource.ruleBased,
    interpretationId: CoachingInterpretationId.steadyEffortInterpretation,
    headline: 'Imported run with steady rhythm',
    message:
        'This demo run gives you enough pace detail for a simple rhythm note. The data suggests a steady run, which is useful for building consistency without chasing speed. Because this is demo/import data, the summary treats it as a learning note rather than a recording made by the app, and it does not judge effort from heart rate.',
    nextAction:
        'Keep the next easy run calm and repeatable, then compare the rhythm.',
  ),
);

/// Display-only result labels for the static run completion surface.
///
/// Production progression values should be supplied by backend-owned results.
const defaultXpUpdateDisplayModel = XpUpdateDisplayModel(
  runnerName: 'Jinseo',
  earnedXpLabel: '+120 XP',
  totalXpLabel: '2,520 XP',
  levelLabel: '12',
  nextLevelLabel: '13',
  progressTargetLabel: 'Progress to Level 13',
  xpRemainingLabel: '600 XP to Level 13',
  previousProgressFraction: 0.52,
  currentProgressFraction: 0.60,
  streakChangeLabel: '5 → 6 days',
  streakNote: 'Great consistency!',
  didLevelUp: false,
  xpAwardState: XpAwardState.awarded,
  heroMessage: 'Earned from this run',
  earnedXp: 120,
  totalXp: 2520,
  previousTotalXp: 2400,
  level: 12,
  previousLevel: 12,
  streakCount: 6,
  previousStreakCount: 5,
);
