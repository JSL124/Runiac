import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/contracts/backend_owned_value_contract.dart';
import 'package:runiac_app/features/profile/domain/models/user_profile_read_model.dart';
import 'package:runiac_app/features/profile/domain/models/viewer_access_read_model.dart';
import 'package:runiac_app/features/feed/data/static_feed_repository.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/leaderboard/domain/models/leaderboard_read_model.dart';
import 'package:runiac_app/features/maps/domain/models/shared_routes_read_model.dart';
import 'package:runiac_app/features/you/domain/models/activity_history_read_model.dart';

void main() {
  group('BackendOwnedValueContract', () {
    test('exposes protected backend-owned field names', () {
      expect(
        BackendOwnedValueContract.protectedFieldNames,
        containsAll(<String>[
          'xp',
          'totalXp',
          'totalXP',
          'level',
          'divisionTier',
          'divisionKey',
          'divisionLabel',
          'levelLabel',
          'totalXpLabel',
          'nextLevelXp',
          'xpToNextLevel',
          'levelProgressPercent',
          'previousLevelProgressPercent',
          'nextLevelProgressPercent',
          'nextLevelXpTarget',
          'nextXpToNextLevel',
          'progressionUpdatedAt',
          'rank',
          'streak',
          'streakCount',
          'lastStreakRunDate',
          'streakUpdatedAt',
          'leaderboardScore',
          'weeklyXp',
          'weeklyXP',
          'monthlyXp',
          'monthlyXP',
          'monthlyXpLabel',
          'monthlyPeriod',
          'monthlyXpBefore',
          'monthlyXpAfter',
          'subscriptionPrivilegeState',
          'validatedActivityContributionState',
          'countsTowardProgression',
        ]),
      );
    });

    test('forbids client mutation verbs for trusted backend-owned values', () {
      expect(
        BackendOwnedValueContract.forbiddenClientMutationVerbs,
        containsAll(<String>[
          'calculate',
          'derive',
          'aggregate',
          'validate',
          'award',
          'increment',
          'publish',
          'approve',
          'reject',
          'suspend',
        ]),
      );
    });
  });

  group('Backend seam read models', () {
    test('construct display-only user profile output', () {
      final profile = UserProfileReadModel(
        userId: 'demo-user',
        displayName: 'Runiac Runner',
        avatarInitials: 'RR',
        locationLabel: 'Singapore',
      );

      expect(profile.displayName, 'Runiac Runner');
      expect(profile.avatarInitials, 'RR');
    });

    test('construct display-only activity history output', () {
      final history = ActivityHistoryReadModel(
        recentRuns: <ActivityHistoryItemReadModel>[
          ActivityHistoryItemReadModel(
            activityId: 'demo-activity-001',
            title: 'Easy Marina Bay run',
            completedAtLabel: 'Today',
            distanceLabel: '3.2 km',
            distanceMeters: 3200,
            paceLabel: '7:20 / km',
          ),
        ],
      );

      expect(history.recentRuns.single.title, 'Easy Marina Bay run');
    });

    test('construct display-only leaderboard output', () {
      final leaderboard = LeaderboardReadModel(
        regionLabel: 'Singapore',
        currentRunnerRankLabel: 'Display after first run',
        entries: <LeaderboardRowReadModel>[
          LeaderboardRowReadModel(
            userId: 'demo-user',
            displayName: 'Runiac Runner',
            rankLabel: 'Pending',
            scoreLabel: 'Runs count after backend validation',
          ),
        ],
      );

      expect(leaderboard.regionLabel, 'Singapore');
      expect(leaderboard.entries.single.rankLabel, 'Pending');
    });

    test('construct display-only shared routes output', () {
      final routes = SharedRoutesReadModel(
        selectedRoute: SharedRouteReadModel(
          routeId: 'marina-bay-easy-loop',
          title: 'Marina Bay easy loop',
          distanceLabel: '3.2 km',
          difficultyLabel: 'Easy',
        ),
        routes: <SharedRouteReadModel>[],
      );

      expect(routes.selectedRoute.title, 'Marina Bay easy loop');
    });

    test('construct display-only viewer access output', () {
      const access = ViewerAccessReadModel(
        subscriptionStatusLabel: 'Basic',
        userRoleLabel: 'Basic User',
      );

      expect(access.subscriptionStatusLabel, 'Basic');
      expect(access.userRoleLabel, 'Basic User');
    });

    test('defensively copies collection fields into unmodifiable lists', () {
      final profileSetupItems = <UserProfileInfoItemReadModel>[
        const UserProfileInfoItemReadModel(title: 'Region', value: 'Singapore'),
      ];
      final leaderboardEntries = <LeaderboardRowReadModel>[
        const LeaderboardRowReadModel(
          userId: 'demo-user',
          displayName: 'Runiac Runner',
          rankLabel: 'Pending',
          scoreLabel: 'Backend validated',
        ),
      ];
      final routes = <SharedRouteReadModel>[
        const SharedRouteReadModel(
          routeId: 'route-1',
          title: 'Route 1',
          distanceLabel: '3 km',
          difficultyLabel: 'Easy',
        ),
      ];
      final activities = <ActivityHistoryItemReadModel>[
        const ActivityHistoryItemReadModel(
          activityId: 'activity-1',
          title: 'Easy run',
          completedAtLabel: 'Today',
          distanceLabel: '3 km',
          distanceMeters: 3000,
          paceLabel: '7:00 / km',
        ),
      ];
      final profile = UserProfileReadModel(
        userId: 'demo-user',
        displayName: 'Runiac Runner',
        avatarInitials: 'RR',
        locationLabel: 'Singapore',
        setupItems: profileSetupItems,
      );
      final leaderboard = LeaderboardReadModel(
        regionLabel: 'Singapore',
        currentRunnerRankLabel: 'Pending',
        entries: leaderboardEntries,
      );
      final sharedRoutes = SharedRoutesReadModel(
        selectedRoute: routes.first,
        routes: routes,
      );
      final history = ActivityHistoryReadModel(recentRuns: activities);
      final month = ActivityHistoryMonthReadModel(
        label: 'June',
        activities: activities,
      );
      profileSetupItems.clear();
      leaderboardEntries.clear();
      routes.clear();
      activities.clear();

      expect(profile.setupItems, hasLength(1));
      expect(leaderboard.entries, hasLength(1));
      expect(sharedRoutes.routes, hasLength(1));
      expect(history.recentRuns, hasLength(1));
      expect(month.activities, hasLength(1));

      expect(
        () => profile.setupItems.add(
          const UserProfileInfoItemReadModel(title: 'Goal', value: '5K'),
        ),
        throwsUnsupportedError,
      );
      expect(() => leaderboard.entries.clear(), throwsUnsupportedError);
      expect(() => sharedRoutes.routes.clear(), throwsUnsupportedError);
      expect(() => history.recentRuns.clear(), throwsUnsupportedError);
      expect(() => month.activities.clear(), throwsUnsupportedError);
    });
  });

  group('Firestore base boundary', () {
    test(
      'Feed repository returns display-only posts scoped by viewer context',
      () async {
        const repository = StaticFeedRepository();
        final feed = await repository.loadFeed(
          const FeedViewerContext(
            currentUserId: 'runner-current',
            acceptedFriendUserIds: <String>{'runner-friend'},
          ),
        );

        expect(feed.posts.map((post) => post.authorUserId), [
          'runner-current',
          'runner-friend',
        ]);
        for (final post in feed.posts) {
          expect(post.distanceLabel, isNotEmpty);
          expect(post.paceLabel, isNotEmpty);
          expect(post.durationLabel, isNotEmpty);
          expect(post.routeThumbnail.thumbnailKey, isNotEmpty);

          for (final protectedField
              in BackendOwnedValueContract.protectedFieldNames) {
            expect(post.activityTitle ?? '', isNot(protectedField));
            expect(post.routeName ?? '', isNot(protectedField));
            expect(post.distanceLabel, isNot(protectedField));
            expect(post.paceLabel, isNot(protectedField));
            expect(post.durationLabel, isNot(protectedField));
          }
        }
      },
    );

    test('keeps feature code free of Firestore data access APIs', () {
      const allowedFirestoreDataAdapterPaths = <String>{
        'lib/features/profile/data/'
            'firestore_user_profile_persistence_repository.dart',
        'lib/features/profile/data/firestore_user_profile_repository.dart',
        'lib/features/profile/data/firestore_user_account_repository.dart',
        'lib/features/settings/data/firestore_profile_visibility_repository.dart',
        'lib/features/paywall/data/firestore_paywall_config_repository.dart',
        'lib/features/paywall/data/firestore_feature_access_repository.dart',
        'lib/features/paywall/data/firestore_character_access_repository.dart',
        'lib/features/challenge/data/firestore_challenge_read_store.dart',
        'lib/features/challenge/data/'
            'firestore_challenge_result_seen_store.dart',
        'lib/features/friends/data/firebase_friends_repository.dart',
        'lib/features/friends/data/friends_owner_list_reader.dart',
        'lib/features/plan/data/'
            'firestore_generated_plan_persistence_repository.dart',
        'lib/features/plan/data/firestore_adaptive_plan_estimate_repository.dart',
        'lib/features/plan/data/firestore_plan_progress_repository.dart',
        'lib/features/notifications/data/'
            'cloud_firestore_notification_inbox_document_store.dart',
        'lib/features/notifications/data/'
            'firestore_notification_preference_mirror.dart',
        'lib/features/leaderboard/data/firestore_leaderboard_repository.dart',
        'lib/features/you/data/firestore_activity_history_repository.dart',
        'lib/features/you/data/firestore_user_progress_repository.dart',
        'lib/features/feed/data/comments/firebase_feed_comment_page_port.dart',
        'lib/features/feed/data/firebase_feed_repository/'
            'firebase_feed_data_port.dart',
        'lib/features/feed/data/firebase_feed_repository/'
            'firebase_feed_post_mapper.dart',
        'lib/features/moderation/data/report_user_writer.dart',
      };
      const forbiddenFeatureTerms = <String>[
        'package:cloud_firestore',
        'FirebaseFirestore',
        'QuerySnapshot',
        'DocumentSnapshot',
        'CollectionReference',
        'DocumentReference',
        'WriteBatch',
        'Transaction',
        '.collection(',
        '.collectionGroup(',
        '.doc(',
        '.get(',
        '.snapshots(',
        '.set(',
      ];

      for (final file in _dartFilesIn('lib/features').where(
        (file) => !allowedFirestoreDataAdapterPaths.contains(file.path),
      )) {
        final source = file.readAsStringSync();
        for (final term in forbiddenFeatureTerms) {
          expect(source, isNot(contains(term)), reason: '${file.path}: $term');
        }
      }
    });

    test(
      'limits Firestore feature access to approved user profile repositories',
      () {
        final persistenceSource = File(
          'lib/features/profile/data/'
          'firestore_user_profile_persistence_repository.dart',
        ).readAsStringSync();
        final readSource = File(
          'lib/features/profile/data/firestore_user_profile_repository.dart',
        ).readAsStringSync();

        expect(persistenceSource, contains("collection('userProfiles')"));
        expect(persistenceSource, contains("checkNicknameAvailability"));
        expect(persistenceSource, contains("upsertNickname"));
        expect(persistenceSource, contains('.set('));
        expect(persistenceSource, isNot(contains("collection('users')")));
        expect(readSource, contains("collection('userProfiles')"));
        expect(readSource, contains('.get('));
        expect(readSource, isNot(contains('.set(')));
        expect(readSource, isNot(contains('.update(')));
        expect(readSource, isNot(contains('.delete(')));
        expect(readSource, isNot(contains("collection('users')")));
        for (final field in BackendOwnedValueContract.protectedFieldNames) {
          expect(persistenceSource, isNot(contains("'$field'")), reason: field);
          expect(readSource, isNot(contains("'$field'")), reason: field);
        }
      },
    );

    test('limits profile visibility writes to the owner privacy preference', () {
      final source = File(
        'lib/features/settings/data/firestore_profile_visibility_repository.dart',
      ).readAsStringSync();

      expect(source, contains("collection('userProfiles')"));
      expect(source, contains("'publicStatsHidden'"));
      expect(source, isNot(contains("collection('users')")));
      expect(source, isNot(contains('.delete(')));
      // The preference is a display choice, not a scoring value. This adapter
      // must never become a second path to a backend-owned field, and it must
      // never be the thing that hides a record — `getRunnerPublicProfile`
      // withholds the values server-side.
      for (final field in BackendOwnedValueContract.protectedFieldNames) {
        expect(source, isNot(contains("'$field'")), reason: field);
      }
    });

    test(
      'limits feature access reads to a read-only config/featureAccess get',
      () {
        final source = File(
          'lib/features/paywall/data/firestore_feature_access_repository.dart',
        ).readAsStringSync();

        expect(source, contains("collection('config')"));
        expect(source, contains("doc('featureAccess')"));
        expect(source, contains('.get('));
        expect(source, isNot(contains('.set(')));
        expect(source, isNot(contains('.update(')));
        expect(source, isNot(contains('.delete(')));
        expect(source, isNot(contains('.snapshots(')));
        expect(source, isNot(contains("collection('users')")));
      },
    );

    test(
      'limits character access reads to a read-only config/characterAccess get',
      () {
        final source = File(
          'lib/features/paywall/data/firestore_character_access_repository.dart',
        ).readAsStringSync();

        expect(source, contains("collection('config')"));
        expect(source, contains("doc('characterAccess')"));
        expect(source, contains('.get('));
        expect(source, isNot(contains('.set(')));
        expect(source, isNot(contains('.update(')));
        expect(source, isNot(contains('.delete(')));
        expect(source, isNot(contains('.snapshots(')));
        expect(source, isNot(contains("collection('users')")));
      },
    );

    test('limits paywall config access to a read-only config/paywall get', () {
      final source = File(
        'lib/features/paywall/data/firestore_paywall_config_repository.dart',
      ).readAsStringSync();

      expect(source, contains("collection('config')"));
      expect(source, contains("doc('paywall')"));
      expect(source, contains('.get('));
      expect(source, isNot(contains('.set(')));
      expect(source, isNot(contains('.update(')));
      expect(source, isNot(contains('.delete(')));
      expect(source, isNot(contains('.snapshots(')));
      expect(source, isNot(contains("collection('users')")));
    });

    test('limits Firestore activity history access to owner-scoped reads', () {
      final source = File(
        'lib/features/you/data/firestore_activity_history_repository.dart',
      ).readAsStringSync();

      expect(source, contains("collection('runSummaries')"));
      expect(source, contains("where('ownerUid'"));
      expect(source, contains("orderBy('endedAt'"));
      expect(source, contains('.get('));
      expect(source, isNot(contains('.set(')));
      expect(source, isNot(contains('.update(')));
      expect(source, isNot(contains('.delete(')));
      expect(source, isNot(contains('runTransaction')));
      expect(source, isNot(contains('writeBatch')));
    });

    test('limits leaderboard access to backend-owned read projections', () {
      final source = File(
        'lib/features/leaderboard/data/firestore_leaderboard_repository.dart',
      ).readAsStringSync();

      expect(source, contains(r'leaderboardCurrentViews/$uid'));
      expect(source, contains(r'leaderboardSnapshots/$snapshotId'));
      expect(source, contains(r'leaderboardUserRanks/$rankId'));
      expect(source, contains('.get('));
      expect(source, isNot(contains('.set(')));
      expect(source, isNot(contains('.update(')));
      expect(source, isNot(contains('.delete(')));
      expect(source, isNot(contains('runTransaction')));
      expect(source, isNot(contains('writeBatch')));
      expect(source, isNot(contains('.batch(')));
      expect(source, isNot(contains('FieldValue.')));
      expect(source, isNot(contains("collection('users')")));
      expect(source, isNot(contains("collection('leaderboardContributions')")));
      expect(
        source,
        isNot(contains("collection('leaderboardAggregationLocks')")),
      );
    });

    test(
      'limits Firestore user progress access to read-only profile fields',
      () {
        final source = File(
          'lib/features/you/data/firestore_user_progress_repository.dart',
        ).readAsStringSync();

        expect(source, contains("collection('userProfiles')"));
        expect(source, contains('.get('));
        expect(source, isNot(contains('.set(')));
        expect(source, isNot(contains('.update(')));
        expect(source, isNot(contains('.delete(')));
        expect(source, isNot(contains('runTransaction')));
        expect(source, isNot(contains('writeBatch')));
        expect(source, isNot(contains('.batch(')));
        expect(source, isNot(contains('FieldValue.')));
        expect(source, isNot(contains("collection('users')")));
        const allowedReadOnlyProgressFields = <String>{
          'streakCount',
          'lastStreakRunDate',
          'longestStreakLabel',
          'totalDistanceLabel',
          'level',
          'levelLabel',
          'levelProgressPercent',
          'totalXp',
          'nextLevelXp',
          'xpToNextLevel',
          'divisionKey',
          'divisionLabel',
          'totalXpLabel',
          'monthlyXpLabel',
        };
        for (final field in BackendOwnedValueContract.protectedFieldNames.where(
          (field) => !allowedReadOnlyProgressFields.contains(field),
        )) {
          expect(source, isNot(contains("'$field'")), reason: field);
        }
      },
    );

    test('limits generated plan persistence to plan content fields', () {
      final source = File(
        'lib/features/plan/data/'
        'firestore_generated_plan_persistence_repository.dart',
      ).readAsStringSync();

      expect(source, contains("collection('generatedPlans')"));
      expect(source, contains('.set('));
      expect(source, contains('.get('));
      expect(source, isNot(contains("collection('users')")));
      for (final field in BackendOwnedValueContract.protectedFieldNames) {
        expect(source, isNot(contains("'$field'")), reason: field);
      }
      expect(source, isNot(contains("'completedRunCount'")));
      expect(source, isNot(contains("'remainingRunCount'")));
      expect(source, isNot(contains("'planCompletion'")));
    });

    test('limits notification inbox access to owner-scoped client items', () {
      final source = File(
        'lib/features/notifications/data/'
        'cloud_firestore_notification_inbox_document_store.dart',
      ).readAsStringSync();

      expect(source, contains("collection('notificationInbox')"));
      expect(source, contains("collection('items')"));
      expect(source, contains("'ownerUid'"));
      expect(source, contains("'clientManaged'"));
      expect(source, contains('.set('));
      expect(source, contains('.update('));
      expect(source, isNot(contains("collection('users')")));
      expect(source, isNot(contains('runTransaction')));
      expect(source, isNot(contains('writeBatch')));
      for (final field in BackendOwnedValueContract.protectedFieldNames) {
        expect(source, isNot(contains("'$field'")), reason: field);
      }
    });

    test('limits report-a-user writes to create-only reports fields', () {
      final source = File(
        'lib/features/moderation/data/report_user_writer.dart',
      ).readAsStringSync();

      expect(source, contains("collection('reports')"));
      expect(source, contains('.set('));
      expect(source, isNot(contains('.update(')));
      expect(source, isNot(contains('.delete(')));
      expect(source, isNot(contains('runTransaction')));
      expect(source, isNot(contains('writeBatch')));
      expect(source, isNot(contains("collection('users')")));
      for (final field in BackendOwnedValueContract.protectedFieldNames) {
        expect(source, isNot(contains("'$field'")), reason: field);
      }
    });
  });
}

List<File> _dartFilesIn(String path) {
  final files =
      Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  return files;
}
