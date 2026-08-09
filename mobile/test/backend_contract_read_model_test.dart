import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/home/domain/models/home_dashboard_read_model.dart';
import 'package:runiac_app/features/leaderboard/domain/models/leaderboard_entry_read_model.dart';
import 'package:runiac_app/features/maps/domain/models/route_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_read_model.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_read_model.dart';
import 'package:runiac_app/features/you/domain/models/user_progress_read_model.dart';

void main() {
  group('Backend contract read models', () {
    test('constructs immutable backend-produced read models', () {
      // Given: backend-produced display/read outputs for each current feature.
      const activity = RunActivityReadModel(
        activityId: 'activity_20260612_001',
        title: 'Saturday Morning Run',
        completedAtLabel: 'Today · 7:06 AM',
        distanceLabel: '4.03 km',
        durationLabel: '30:15',
        avgPaceLabel: '6’30” / km',
        routeLabel: 'East Coast Park Loop',
      );
      const summary = RunSummaryReadModel(
        summaryId: 'summary_20260612_001',
        title: 'Saturday Morning Run',
        dateLabel: 'Today',
        timeLabel: '7:06 AM',
        distanceLabel: '4.03 km',
        avgPaceLabel: '6’30” / km',
        durationLabel: '30:15',
        avgHeartRateLabel: '145 bpm',
        caloriesLabel: '212 kcal',
        routeName: 'East Coast Park Loop',
      );
      const route = RouteReadModel(
        routeId: 'route_east_coast_easy',
        title: 'East Coast flat run',
        distanceLabel: '4.0 km',
        durationLabel: '32 min',
        difficultyLabel: 'Easy',
        locationLabel: 'East Coast',
      );
      const home = HomeDashboardReadModel(
        todayPlanTitle: '20 min easy run',
        todayPlanSubtitle: 'Comfortable effort',
        goalTitle: 'First 10K Preparation',
        goalProgressLabel: '43%',
        streakLabel: '6 days',
        xpLabel: '1,240 XP',
        levelLabel: 'Level 12',
        weeklySummaryLabel: '3 runs this week',
      );
      const leaderboardEntry = LeaderboardEntryReadModel(
        userId: 'user_123',
        displayName: 'Jinseo',
        rankLabel: '#12',
        scoreLabel: '1,240 XP',
        levelLabel: 'Level 12',
        divisionLabel: 'Bronze',
        regionLabel: 'Jurong East',
      );
      const progress = UserProgressReadModel(
        userId: 'user_123',
        officialStreakLabel: '6 days',
        levelLabel: 'Level 12',
        totalXpLabel: '2,520 XP',
        weeklyXpLabel: '520 XP',
        monthlyXpLabel: '1,240 XP',
        weeklyDistanceLabel: '12.4 km',
        goalProgressLabel: '43%',
        divisionKey: 'tier_02',
        divisionLabel: 'Bronze League',
      );

      // When / Then: the read models expose immutable backend-produced labels.
      expect(activity.activityId, 'activity_20260612_001');
      expect(activity.avgPaceLabel, '6’30” / km');
      expect(summary.summaryId, 'summary_20260612_001');
      expect(summary.caloriesLabel, '212 kcal');
      expect(route.routeId, 'route_east_coast_easy');
      expect(route.locationLabel, 'East Coast');
      expect(home.todayPlanTitle, '20 min easy run');
      expect(home.xpLabel, '1,240 XP');
      expect(leaderboardEntry.rankLabel, '#12');
      expect(leaderboardEntry.scoreLabel, '1,240 XP');
      expect(progress.weeklyXpLabel, '520 XP');
      expect(progress.monthlyXpLabel, '1,240 XP');
      expect(progress.divisionKey, 'tier_02');
      expect(progress.divisionLabel, 'Bronze League');
    });

    test('keeps read model sources backend-free and immutable', () {
      // Given: only the new read model files and the existing raw payload file.
      const readModelPaths = [
        _ReadModelContract(
          path: 'lib/features/run/domain/models/run_activity_read_model.dart',
          className: 'RunActivityReadModel',
          fields: [
            'activityId',
            'title',
            'completedAtLabel',
            'distanceLabel',
            'durationLabel',
            'avgPaceLabel',
            'routeLabel',
          ],
        ),
        _ReadModelContract(
          path: 'lib/features/run/domain/models/run_summary_read_model.dart',
          className: 'RunSummaryReadModel',
          fields: [
            'summaryId',
            'title',
            'dateLabel',
            'timeLabel',
            'distanceLabel',
            'avgPaceLabel',
            'durationLabel',
            'avgHeartRateLabel',
            'caloriesLabel',
            'routeName',
          ],
        ),
        _ReadModelContract(
          path: 'lib/features/maps/domain/models/route_read_model.dart',
          className: 'RouteReadModel',
          fields: [
            'routeId',
            'title',
            'distanceLabel',
            'durationLabel',
            'difficultyLabel',
            'locationLabel',
          ],
        ),
        _ReadModelContract(
          path:
              'lib/features/home/domain/models/home_dashboard_read_model.dart',
          className: 'HomeDashboardReadModel',
          fields: [
            'todayPlanTitle',
            'todayPlanSubtitle',
            'goalTitle',
            'goalProgressLabel',
            'streakLabel',
            'xpLabel',
            'levelLabel',
            'weeklySummaryLabel',
          ],
        ),
        _ReadModelContract(
          path:
              'lib/features/leaderboard/domain/models/'
              'leaderboard_entry_read_model.dart',
          className: 'LeaderboardEntryReadModel',
          fields: [
            'userId',
            'displayName',
            'rankLabel',
            'scoreLabel',
            'levelLabel',
            'divisionLabel',
            'regionLabel',
          ],
        ),
        _ReadModelContract(
          path: 'lib/features/you/domain/models/user_progress_read_model.dart',
          className: 'UserProgressReadModel',
          fields: [
            'userId',
            'officialStreakLabel',
            'levelLabel',
            'totalXpLabel',
            'weeklyXpLabel',
            'monthlyXpLabel',
            'weeklyDistanceLabel',
            'goalProgressLabel',
            'longestStreakLabel',
            'totalDistanceLabel',
            'divisionKey',
            'divisionLabel',
          ],
          nonStringFields: [
            'level',
            'levelProgressFraction',
            'totalXp',
            'nextLevelXp',
            'xpToNextLevel',
            'isMaxLevel',
            'officialStreakCount',
            'lastStreakRunDate',
          ],
          allowedGetters: ['levelBadgeLabel'],
        ),
      ];
      const forbiddenTerms = [
        'Firebase',
        'Firestore',
        'Auth',
        'firebase_core',
        'cloud_firestore',
        'firebase_auth',
        'collection(',
        'doc(',
        'set(',
        'update(',
        'fromJson',
        'toJson',
        'Repository',
        'repository',
        'Service',
        'service',
        'Datasource',
        'datasource',
        'calculateXP',
        'calculateLevel',
        'calculateStreak',
        'calculateRank',
        'aggregateWeeklyXp',
        'aggregateMonthlyXp',
        'deriveLeaderboard',
        'validateActivity',
        'countsTowardProgression',
      ];

      // When / Then: read models are simple immutable display contracts.
      for (final contract in readModelPaths) {
        final source = File(contract.path).readAsStringSync();

        _expectReadModelContract(source, contract);
        expect(source, isNot(contains('var ')));

        for (final term in forbiddenTerms) {
          expect(
            source,
            isNot(contains(term)),
            reason: '${contract.path} contains $term',
          );
        }
      }

      final payloadSource = File(
        'lib/features/run/domain/models/run_completed_payload.dart',
      ).readAsStringSync();

      for (final term in forbiddenTerms) {
        expect(
          payloadSource,
          isNot(contains(term)),
          reason: 'RunCompletedPayload contains $term',
        );
      }

      for (final importName in [
        'run_activity_read_model.dart',
        'run_summary_read_model.dart',
        'route_read_model.dart',
        'home_dashboard_read_model.dart',
        'leaderboard_entry_read_model.dart',
        'user_progress_read_model.dart',
      ]) {
        expect(payloadSource, isNot(contains(importName)));
      }
    });

    test('requires You official streak display to come from backend label', () {
      // Given: the You progress surface currently renders an official-looking
      // consistency streak in the user profile area.
      final source = File(
        'lib/features/you/presentation/widgets/you_progress_surface.dart',
      ).readAsStringSync();

      // When / Then: official streak display must have a backend-produced label
      // input instead of relying only on UI-derived activity-history math.
      expect(
        source,
        contains('officialStreakLabel'),
        reason:
            'YouProgressSurface must accept a backend-produced official '
            'streak label/read model before displaying the official You '
            'streak.',
      );
      expect(
        source,
        isNot(contains('_computeConsistencyStreak')),
        reason:
            'The You boundary must not calculate the official streak from '
            'local activity history.',
      );
    });
  });
}

class _ReadModelContract {
  const _ReadModelContract({
    required this.path,
    required this.className,
    required this.fields,
    this.nonStringFields = const <String>[],
    this.allowedGetters = const <String>[],
  });

  final String path;
  final String className;
  final List<String> fields;
  final List<String> nonStringFields;
  final List<String> allowedGetters;
}

void _expectReadModelContract(String source, _ReadModelContract contract) {
  expect(source, contains('class ${contract.className} {'));
  expect(source, contains('const ${contract.className}({'));

  final declaredFields = RegExp(
    r'^[ \t]*final String ([A-Za-z0-9_]+);$',
    multiLine: true,
  ).allMatches(source).map((match) => match.group(1)).toList();
  expect(declaredFields, contract.fields, reason: contract.path);

  final disallowedFieldDeclarations =
      RegExp(
        r'^[ \t]*(?:late[ \t]+)?(?:final|var|String|int|double|bool|DateTime|List|Map|Set)\b.*$',
        multiLine: true,
      ).allMatches(source).where((match) {
        final line = match.group(0) ?? '';
        final trimmed = line.trim();
        if (trimmed.startsWith('final String ')) {
          return false;
        }
        if (contract.allowedGetters.any(
          (getter) => trimmed.startsWith('String get $getter '),
        )) {
          return false;
        }
        return !contract.nonStringFields.any(
          (field) =>
              trimmed == 'final int $field;' ||
              trimmed == 'final int? $field;' ||
              trimmed == 'final double $field;' ||
              trimmed == 'final bool $field;' ||
              trimmed == 'final String? $field;',
        );
      }).toList();
  expect(disallowedFieldDeclarations, isEmpty, reason: contract.path);

  final disallowedAccessors =
      RegExp(
        r'^[ \t]*(?:set[ \t]+[A-Za-z0-9_]+\(|[A-Za-z0-9_<>,? ]+[ \t]+get[ \t]+([A-Za-z0-9_]+))',
        multiLine: true,
      ).allMatches(source).where((match) {
        final getter = match.group(1);
        return getter == null || !contract.allowedGetters.contains(getter);
      }).toList();
  expect(disallowedAccessors, isEmpty, reason: contract.path);
  final methodLikeLines = source.split('\n').where((line) {
    final trimmed = line.trim();
    final isConstructor = trimmed.startsWith('const ${contract.className}(');
    final isParameter = trimmed.startsWith('required this.');
    final isAllowedGetter = contract.allowedGetters.any(
      (getter) => trimmed == 'String get $getter => \'Lv.\$level\';',
    );
    return trimmed.contains('(') &&
        !isConstructor &&
        !isParameter &&
        !isAllowedGetter;
  }).toList();
  expect(methodLikeLines, isEmpty, reason: contract.path);
}
