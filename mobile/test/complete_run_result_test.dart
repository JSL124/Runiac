import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/complete_run_result.dart';
import 'package:runiac_app/features/run/domain/models/progression_display_model.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/xp_update_display_model.dart';

void main() {
  group('CompleteRunResult', () {
    test('constructs from summary and XP update display models', () {
      const summary = RunSummarySnapshot(
        title: 'Saturday Morning Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceKm: '4.03',
        avgPace: '6’30”',
        duration: '30:15',
        avgHeartRate: '145',
        calories: '145',
        routeName: 'East Coast Park Loop',
      );

      const xpUpdate = XpUpdateDisplayModel(
        runnerName: 'Jinseo',
        earnedXpLabel: '+120 XP',
        totalXpLabel: '2,520 XP',
        levelLabel: '12',
        nextLevelLabel: '13',
        progressTargetLabel: 'Progress to Lv.13',
        xpRemainingLabel: '600 XP to go',
        previousProgressFraction: 0.52,
        currentProgressFraction: 0.60,
        streakChangeLabel: '5 -> 6 days',
        streakNote: 'Great consistency!',
        didLevelUp: false,
      );

      const result = CompleteRunResult(summary: summary, xpUpdate: xpUpdate);

      expect(result.validationStatus, 'validated');
      expect(result.progressionDisplay.xpDelta, 0);
      expect(result.progressionDisplay.countsTowardLeaderboard, isFalse);
      expect(result.summary.title, 'Saturday Morning Run');
      expect(result.summary.distanceKm, '4.03');
      expect(result.summary.dateTimeLabel, 'Today · 7:06 AM');
      expect(result.xpUpdate.earnedXpLabel, '+120 XP');
      expect(result.xpUpdate.levelLabel, '12');
      expect(result.xpUpdate.streakChangeLabel, '5 -> 6 days');
    });

    test('constructs with backend-shaped completion identifiers', () {
      const result = CompleteRunResult(
        activityId: 'activity_001',
        summaryId: 'summary_001',
        progressionEventId: 'progression_001',
        validationStatus: 'validated',
        summary: RunSummarySnapshot(
          title: 'Repository Result Run',
          dateLabel: 'Today',
          timeLabel: '8:10 AM',
          distanceKm: '5.40',
          avgPace: '6’40”',
          duration: '36:00',
          avgHeartRate: '138',
          calories: '280',
          routeName: 'Repository Route',
        ),
        progressionDisplay: ProgressionDisplayModel(
          xpDelta: 0,
          countsTowardLeaderboard: false,
          status: 'deferred',
          reason: 'progression_formula_deferred',
        ),
        xpUpdate: XpUpdateDisplayModel(
          runnerName: 'Repository Runner',
          earnedXpLabel: '+0 XP',
          totalXpLabel: 'Deferred by backend',
          levelLabel: 'Pending',
          nextLevelLabel: 'Pending',
          progressTargetLabel: 'Progression deferred',
          xpRemainingLabel: 'Backend formula pending',
          previousProgressFraction: 0,
          currentProgressFraction: 0,
          streakChangeLabel: 'Deferred',
          streakNote: 'Backend validation accepted the run.',
          didLevelUp: false,
        ),
        message: 'Static repository completion accepted.',
      );

      expect(result.activityId, 'activity_001');
      expect(result.summaryId, 'summary_001');
      expect(result.progressionEventId, 'progression_001');
      expect(result.validationStatus, 'validated');
      expect(result.progressionDisplay.status, 'deferred');
      expect(result.message, 'Static repository completion accepted.');
    });

    test('source stays display-result only and backend free', () {
      final source = File(
        'lib/features/run/domain/models/complete_run_result.dart',
      ).readAsStringSync();

      const forbiddenTerms = [
        'Firebase',
        'Firestore',
        'Auth',
        'SharedPreferences',
        'countsTowardProgression',
        'leaderboardScore',
        'weeklyXp',
        'monthlyXp',
        'subscriptionPrivilegeState',
        'calculateXP',
        'calculateLevel',
        'calculateStreak',
        'save',
        'upload',
        'sync',
        'submit',
        'persist',
      ];

      for (final term in forbiddenTerms) {
        expect(source, isNot(contains(term)));
      }
    });
  });
}
