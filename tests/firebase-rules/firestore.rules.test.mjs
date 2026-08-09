import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from 'firebase/firestore';

import {
  adaptivePlanEstimateReadModel,
  activityDraft,
  dbFor,
  generatedPlanDocument,
  notificationDeliveryRecord,
  notificationDeviceTokenRecord,
  notificationInboxItem,
  notificationPrefs,
  planProgressReadModel,
  profileFields,
  removeSeed,
  seed,
  seedUser,
  unauthenticatedDb,
} from './support/firestore_rules_test_support.mjs';

describe('owner-owned client records', () => {
  it('denies all direct Home Guide consent reads and writes', async () => {
    await seed('homeGuideConsents/alice', {
      ownerUid: 'alice',
      schemaVersion: 1,
      disclosureVersion: 1,
      granted: true,
    });

    const alice = dbFor('alice');
    await assertFails(getDoc(doc(alice, 'homeGuideConsents/alice')));
    await assertFails(
      setDoc(doc(alice, 'homeGuideConsents/alice'), {
        ownerUid: 'alice',
        schemaVersion: 1,
        disclosureVersion: 1,
        granted: false,
      }),
    );
  });

  it('allows an owner to write safe user profile fields', async () => {
    const alice = dbFor('alice');

    await assertSucceeds(setDoc(doc(alice, 'userProfiles/alice'), profileFields));
    await assertSucceeds(getDoc(doc(alice, 'userProfiles/alice')));
    await assertFails(getDoc(doc(dbFor('bob'), 'userProfiles/alice')));
  });

  it('denies deleting backend-owned fields during profile updates', async () => {
    await seed('userProfiles/alice', {
      ...profileFields,
      xp: 10,
      totalXp: 75,
      monthlyXp: 75,
      monthlyXpLabel: '75 XP',
      level: 2,
      divisionKey: 'tier_01',
      divisionLabel: 'Trailborn League',
      levelLabel: 'Level 2',
      totalXpLabel: '75 XP',
      nextLevelXp: 100,
      xpToNextLevel: 25,
      levelProgressPercent: 75,
      previousLevelProgressPercent: 0,
      nextLevelProgressPercent: 75,
      nextLevelXpTarget: 100,
      nextXpToNextLevel: 25,
      monthlyPeriod: '2026-06',
      monthlyXpBefore: 0,
      monthlyXpAfter: 75,
      progressionUpdatedAt: 1,
    });

    const profile = doc(dbFor('alice'), 'userProfiles/alice');

    await assertSucceeds(updateDoc(profile, { fullName: 'Updated Runner' }));
    await assertFails(updateDoc(profile, { displayName: 'Updated Runner' }));
    await assertFails(updateDoc(profile, { xp: deleteField() }));
    await assertFails(updateDoc(profile, { totalXp: 80 }));
    await assertFails(updateDoc(profile, { monthlyXp: 80 }));
    await assertFails(updateDoc(profile, { monthlyXpLabel: '80 XP' }));
    await assertFails(updateDoc(profile, { level: 3 }));
    await assertFails(updateDoc(profile, { divisionKey: 'tier_02' }));
    await assertFails(updateDoc(profile, { totalXpLabel: deleteField() }));
    await assertFails(updateDoc(profile, { nextLevelProgressPercent: 80 }));
    await assertFails(updateDoc(profile, { monthlyXpAfter: 80 }));
  });

  it('denies userRole and subscriptionStatus writes from clients', async () => {
    const alice = dbFor('alice');

    await assertFails(
      setDoc(doc(alice, 'users/alice'), {
        userRole: 'Platform Administrator',
        subscriptionStatus: 'Premium',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        userRole: 'Platform Administrator',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        subscriptionStatus: 'Premium',
      }),
    );
  });

  it('denies profile email persistence and invalid personal profile fields', async () => {
    const alice = dbFor('alice');

    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        email: 'alice@example.test',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        ageYears: 12,
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        weightKg: 251,
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        nickname: 'Line\nBreak',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        dateOfBirth: 'not-a-date',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        locationLabel: 'London, United Kingdom',
      }),
    );
  });

  it('allows read-only leaderboard views for signed-in users', async () => {
    await seed('leaderboardPeriods/monthly_current', {
      periodType: 'monthly',
      periodKey: '2026-07',
      periodLabel: 'July 2026',
    });
    await seed('leaderboardSnapshots/monthly_jurong-east_tier_01_2026-07', {
      periodType: 'monthly',
      periodKey: '2026-07',
      regionId: 'jurong-east',
      divisionKey: 'tier_01',
      entryCount: 0,
      topEntries: [],
    });
    await seed('leaderboardCurrentViews/alice', {
      ownerUid: 'alice',
      snapshotId: 'monthly_jurong-east_tier_01_2026-07',
      rankId: 'alice_monthly_2026-07',
    });
    await seed('leaderboardUserRanks/alice_monthly_2026-07', {
      ownerUid: 'alice',
      rankLabel: '#1',
      score: 120,
    });

    const alice = dbFor('alice');
    const bob = dbFor('bob');

    await assertSucceeds(
      getDoc(doc(alice, 'leaderboardPeriods/monthly_current')),
    );
    await assertSucceeds(
      getDoc(
        doc(
          alice,
          'leaderboardSnapshots/monthly_jurong-east_tier_01_2026-07',
        ),
      ),
    );
    await assertSucceeds(getDoc(doc(alice, 'leaderboardCurrentViews/alice')));
    await assertFails(getDoc(doc(bob, 'leaderboardCurrentViews/alice')));
    await assertSucceeds(
      getDoc(doc(alice, 'leaderboardUserRanks/alice_monthly_2026-07')),
    );
    await assertFails(
      getDoc(doc(bob, 'leaderboardUserRanks/alice_monthly_2026-07')),
    );
    await assertFails(
      setDoc(doc(alice, 'leaderboardCurrentViews/alice'), {
        uid: 'alice',
        snapshotId: 'client-write',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'leaderboardAggregationLocks/monthly_2026-07'), {
        status: 'completed',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'leaderboardSeedRuns/test-seed'), {
        status: 'seeded',
      }),
    );
    await assertFails(
      getDoc(doc(alice, 'leaderboardAdminCommands/test-command')),
    );
    await assertFails(
      setDoc(doc(alice, 'leaderboardAdminCommands/test-command'), {
        command: 'refresh',
        periodKey: '2026-07',
      }),
    );
  });

  it('denies all direct nickname claim reads and writes', async () => {
    const alice = dbFor('alice');

    await assertFails(
      setDoc(doc(alice, 'nicknameClaims/runner'), {
        ownerUid: 'alice',
        nicknameCanonical: 'runner',
        nicknameIndexKey: 'n1_runner',
        updatedAt: 1,
      }),
    );
    await seed('nicknameClaims/n1_runner', {
      ownerUid: 'alice',
      nicknameCanonical: 'runner',
      nicknameIndexKey: 'n1_runner',
    });
    await assertFails(getDoc(doc(alice, 'nicknameClaims/n1_runner')));
    await assertFails(
      setDoc(doc(dbFor('bob'), 'nicknameClaims/n1_runner'), {
        ownerUid: 'bob',
        nicknameCanonical: 'runner',
        nicknameIndexKey: 'n1_runner',
        updatedAt: 1,
      }),
    );
    await assertFails(deleteDoc(doc(alice, 'nicknameClaims/n1_runner')));
  });

  it('allows only the owner to read and write generated plans', async () => {
    const alice = dbFor('alice');

    await assertSucceeds(
      setDoc(doc(alice, 'generatedPlans/alice'), generatedPlanDocument),
    );
    await assertSucceeds(getDoc(doc(alice, 'generatedPlans/alice')));
    await assertFails(getDoc(doc(dbFor('bob'), 'generatedPlans/alice')));
    await assertFails(
      setDoc(doc(dbFor('bob'), 'generatedPlans/alice'), generatedPlanDocument),
    );
  });

  it('allows owner to write a full generated plan payload', async () => {
    const alice = dbFor('alice');
    const baseWorkout = generatedPlanDocument.weeks[0].workouts[0];

    await assertSucceeds(
      setDoc(doc(alice, 'generatedPlans/alice'), {
        ...generatedPlanDocument,
        weeks: Array.from({ length: 4 }, (_, weekIndex) => ({
          weekNumber: weekIndex + 1,
          title: `Week ${weekIndex + 1}`,
          focus: `Week ${weekIndex + 1} focus`,
          workouts: ['Mon', 'Fri', 'Sat'].map((dayLabel, sessionIndex) => ({
            ...baseWorkout,
            dayLabel,
            title: `${baseWorkout.title} ${sessionIndex + 1}`,
          })),
        })),
      }),
    );
  });

  it('denies backend-owned and unapproved generated plan fields', async () => {
    const alice = dbFor('alice');
    const plan = doc(alice, 'generatedPlans/alice');

    await assertFails(
      setDoc(plan, {
        ...generatedPlanDocument,
        xp: 10,
      }),
    );
    await assertFails(
      setDoc(plan, {
        ...generatedPlanDocument,
        leaderboardScore: 100,
      }),
    );
    await assertFails(
      setDoc(plan, {
        ...generatedPlanDocument,
        completedRunCount: 1,
      }),
    );
  });

  it('denies nested backend-owned and unapproved generated plan fields', async () => {
    const alice = dbFor('alice');
    const plan = doc(alice, 'generatedPlans/alice');
    const baseWeek = generatedPlanDocument.weeks[0];
    const baseWorkout = baseWeek.workouts[0];

    await assertFails(
      setDoc(plan, {
        ...generatedPlanDocument,
        weeks: [
          {
            ...baseWeek,
            workouts: [
              {
                ...baseWorkout,
                completedRunCount: 1,
              },
            ],
          },
        ],
      }),
    );
    await assertFails(
      setDoc(plan, {
        ...generatedPlanDocument,
        weeks: [
          {
            ...baseWeek,
            workouts: [
              {
                ...baseWorkout,
                detail: {
                  ...baseWorkout.detail,
                  validationStatus: 'approved',
                },
              },
            ],
          },
        ],
      }),
    );
    await assertFails(
      setDoc(plan, {
        ...generatedPlanDocument,
        weeks: [
          {
            ...baseWeek,
            workouts: [
              {
                ...baseWorkout,
                steps: [{ xp: 1 }],
              },
            ],
          },
        ],
      }),
    );
    await assertFails(
      setDoc(plan, {
        ...generatedPlanDocument,
        weeks: [
          {
            ...baseWeek,
            workouts: [
              {
                ...baseWorkout,
                detail: {
                  ...baseWorkout.detail,
                  coachNotes: [{ validationStatus: 'approved' }],
                },
              },
            ],
          },
        ],
      }),
    );
    await assertFails(
      setDoc(plan, {
        ...generatedPlanDocument,
        weeks: [
          {
            ...baseWeek,
            workouts: [
              {
                ...baseWorkout,
                scheduleTimeLabel: { userRole: 'Platform Administrator' },
              },
            ],
          },
        ],
      }),
    );
  });

  it('allows owner to write safety readiness generated plan display', async () => {
    const alice = dbFor('alice');

    await assertSucceeds(
      setDoc(doc(alice, 'generatedPlans/alice'), {
        ...generatedPlanDocument,
        title: 'Safety Readiness Plan',
        subtitle: 'Check readiness before starting workouts.',
        sourceLabel: 'Onboarding safety',
        durationWeeks: 0,
        family: null,
        familyCategory: null,
        familyReason: 'Medical clearance recommended before workouts.',
        weeklyFrequencyLabel: '0 sessions / week',
        preferredScheduleLabel: 'After clearance',
        sessionDurationLabel: 'No workouts yet',
        clientDisplayStatus: 'safetyReadiness',
        weeks: [],
      }),
    );
  });

  it('allows only the owner to read backend-owned plan progress', async () => {
    await seed('planProgress/alice', planProgressReadModel);

    const aliceProgress = await assertSucceeds(
      getDoc(doc(dbFor('alice'), 'planProgress/alice')),
    );
    assert.equal(aliceProgress.data().ownerUid, 'alice');

    await assertFails(getDoc(doc(dbFor('bob'), 'planProgress/alice')));
  });

  it('denies all client writes to backend-owned plan progress', async () => {
    const aliceProgress = doc(dbFor('alice'), 'planProgress/alice');

    await assertFails(setDoc(aliceProgress, planProgressReadModel));

    await seed('planProgress/alice', planProgressReadModel);
    await assertFails(updateDoc(aliceProgress, { completedWorkoutCount: 2 }));
    await assertFails(deleteDoc(aliceProgress));
  });

  it('allows only the owner to read backend-owned adaptive plan estimates', async () => {
    await seed('adaptivePlanEstimates/alice', adaptivePlanEstimateReadModel);

    const aliceEstimate = await assertSucceeds(
      getDoc(doc(dbFor('alice'), 'adaptivePlanEstimates/alice')),
    );
    assert.equal(aliceEstimate.data().ownerUid, 'alice');

    await assertFails(getDoc(doc(dbFor('bob'), 'adaptivePlanEstimates/alice')));
  });

  it('denies all client writes to backend-owned adaptive plan estimates', async () => {
    const aliceEstimate = doc(dbFor('alice'), 'adaptivePlanEstimates/alice');

    await assertFails(setDoc(aliceEstimate, adaptivePlanEstimateReadModel));
    await assertFails(
      setDoc(aliceEstimate, {
        ownerUid: 'alice',
        completedRunCount: 1,
        averageRecentPaceSecondsPerKm: 500,
        readinessBand: 'building',
        latestAcceptedActivityId: 'activity-client-write',
        source: 'client',
        updatedAt: 22,
      }),
    );

    await seed('adaptivePlanEstimates/alice', adaptivePlanEstimateReadModel);
    await assertFails(updateDoc(aliceEstimate, { completedRunCount: 2 }));
    await assertFails(
      updateDoc(aliceEstimate, {
        averageRecentPaceSecondsPerKm: 480,
        readinessBand: 'ready',
      }),
    );
    await assertFails(deleteDoc(aliceEstimate));
  });

  it('denies direct client nickname identity writes even when a matching claim exists', async () => {
    const alice = dbFor('alice');

    await assertSucceeds(setDoc(doc(alice, 'userProfiles/alice'), profileFields));
    await seed('nicknameClaims/runner', {
      ownerUid: 'alice',
      nicknameCanonical: 'runner',
      nicknameIndexKey: 'n1_runner',
      updatedAt: 1,
    });
    await assertFails(
      updateDoc(doc(alice, 'userProfiles/alice'), {
        displayName: 'Runner',
        avatarInitials: 'RU',
        nickname: 'Runner',
        nicknameIndexKey: 'n1_runner',
      }),
    );
  });

  it('denies unapproved nested profile fields', async () => {
    const alice = dbFor('alice');

    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        availability: {
          ...profileFields.availability,
          subscriptionStatus: 'premium',
        },
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        healthSafetyReadiness: {
          ...profileFields.healthSafetyReadiness,
          userRole: 'Platform Administrator',
        },
      }),
    );
  });

  it('denies auth bootstrap writes to users and backend-owned fields', async () => {
    const alice = dbFor('alice');
    const authBootstrapPayload = {
      email: 'alice@example.test',
      displayName: 'Synthetic Runner',
      userRole: 'Platform Administrator',
      subscriptionStatus: 'premium',
      subscriptionPrivilegeState: 'active',
      xp: 100,
      weeklyXP: 100,
      monthlyXP: 200,
      streak: 7,
      streakCount: 7,
      lastStreakRunDate: '2026-06-14',
      streakUpdatedAt: 1,
      level: 3,
      rank: 1,
      leaderboardScore: 500,
      validationStatus: 'validated',
      countsTowardProgression: true,
      validatedActivityContributionState: 'accepted',
    };

    await assertFails(setDoc(doc(alice, 'users/alice'), authBootstrapPayload));
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        userRole: 'Basic User',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        subscriptionStatus: 'basic',
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        xp: 0,
        weeklyXP: 0,
        monthlyXP: 0,
        streak: 0,
        streakCount: 0,
        lastStreakRunDate: '2026-06-14',
        streakUpdatedAt: 1,
        level: 1,
        rank: 0,
        leaderboardScore: 0,
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'userProfiles/alice'), {
        ...profileFields,
        validationStatus: 'pending',
        countsTowardProgression: false,
        validatedActivityContributionState: 'none',
      }),
    );
  });

  it('allows an owner to create a raw pending activity only', async () => {
    await assertSucceeds(
      setDoc(doc(dbFor('alice'), 'activities/activity-001'), activityDraft),
    );

    await assertFails(
      setDoc(doc(dbFor('bob'), 'activities/activity-002'), {
        ...activityDraft,
        ownerUid: 'alice',
      }),
    );
  });

  it('denies activity validation and progression contribution flags', async () => {
    const alice = dbFor('alice');
    const activity = doc(alice, 'activities/activity-001');

    await assertFails(
      setDoc(activity, {
        ...activityDraft,
        validationStatus: 'validated',
      }),
    );
    await assertFails(
      setDoc(activity, {
        ...activityDraft,
        countsTowardProgression: true,
      }),
    );
  });

  it('denies client writes to backend-owned cool-down XP fields on activities', async () => {
    await seed('activities/cooldown-001', {
      ...activityDraft,
    });

    const activity = doc(dbFor('alice'), 'activities/cooldown-001');

    await assertFails(updateDoc(activity, { coolDownXpAwarded: true }));

    await assertFails(
      setDoc(doc(dbFor('alice'), 'activities/cooldown-002'), {
        ...activityDraft,
        coolDownXpAwarded: true,
      }),
    );
  });

  it('denies overwriting or resetting backend-processed activities', async () => {
    await seed('activities/processed-001', {
      ...activityDraft,
      status: 'validated',
      validationStatus: 'validated',
      countsTowardProgression: true,
      validatedActivityContributionState: 'accepted',
    });

    const activity = doc(dbFor('alice'), 'activities/processed-001');

    await assertFails(setDoc(activity, activityDraft));
    await assertFails(updateDoc(activity, { status: 'pending' }));
    await assertFails(updateDoc(activity, { validationStatus: deleteField() }));
  });

  it('denies client writes to backend-owned streak profile fields', async () => {
    await seed('userProfiles/alice', {
      ...profileFields,
      streakCount: 2,
      lastStreakRunDate: '2026-06-15',
      streakUpdatedAt: 1,
    });

    const profile = doc(dbFor('alice'), 'userProfiles/alice');

    await assertFails(
      setDoc(profile, {
        ...profileFields,
        streakCount: 1,
        lastStreakRunDate: '2026-06-14',
        streakUpdatedAt: 1,
      }),
    );
    await assertFails(updateDoc(profile, { streakCount: 3 }));
    await assertFails(updateDoc(profile, { lastStreakRunDate: '2026-06-16' }));
    await assertFails(updateDoc(profile, { streakUpdatedAt: 2 }));
    await assertFails(updateDoc(profile, { streakCount: deleteField() }));
  });

  it('denies client writes to backend-owned lifetime stat profile fields', async () => {
    await seed('userProfiles/alice', {
      ...profileFields,
      longestStreak: 5,
      longestStreakLabel: '5 days',
      totalDistanceMeters: 12800,
      totalDistanceLabel: '12.8 km',
    });

    const profile = doc(dbFor('alice'), 'userProfiles/alice');

    await assertFails(
      setDoc(profile, {
        ...profileFields,
        longestStreak: 9,
        longestStreakLabel: '9 days',
        totalDistanceMeters: 99999,
        totalDistanceLabel: '100.0 km',
      }),
    );
    await assertFails(updateDoc(profile, { longestStreak: 9 }));
    await assertFails(updateDoc(profile, { longestStreakLabel: '9 days' }));
    await assertFails(updateDoc(profile, { totalDistanceMeters: 99999 }));
    await assertFails(updateDoc(profile, { totalDistanceLabel: '100.0 km' }));
    await assertFails(updateDoc(profile, { totalDistanceMeters: deleteField() }));
  });

  it('activity owner history list supports latest-first bounded queries', async () => {
    await seed('activities/alice-older', {
      ...activityDraft,
      ownerUid: 'alice',
      endedAt: 20,
      updatedAt: 21,
    });
    await seed('activities/alice-newer', {
      ...activityDraft,
      ownerUid: 'alice',
      endedAt: 40,
      updatedAt: 41,
    });
    await seed('activities/bob-activity', {
      ...activityDraft,
      ownerUid: 'bob',
      endedAt: 60,
      updatedAt: 61,
    });

    const aliceHistory = query(
      collection(dbFor('alice'), 'activities'),
      where('ownerUid', '==', 'alice'),
      orderBy('endedAt', 'desc'),
      limit(30),
    );
    const aliceHistorySnapshot = await assertSucceeds(getDocs(aliceHistory));
    assert.deepEqual(
      aliceHistorySnapshot.docs.map((activity) => activity.id),
      ['alice-newer', 'alice-older'],
    );

    await assertFails(
      getDocs(
        query(
          collection(dbFor('bob'), 'activities'),
          where('ownerUid', '==', 'alice'),
          orderBy('endedAt', 'desc'),
          limit(30),
        ),
      ),
    );
  });

  it('run summary owner history reads', async () => {
    await seed('runSummaries/alice-summary', {
      ownerUid: 'alice',
      activityId: 'activity-alice',
      status: 'validated',
      startedAt: 10,
      endedAt: 20,
      durationSeconds: 600,
      distanceMeters: 1200,
      averagePaceSecondsPerKm: 500,
      routePrivacy: 'private',
      createdAt: 21,
    });
    await seed('runSummaries/bob-summary', {
      ownerUid: 'bob',
      activityId: 'activity-bob',
      status: 'validated',
      startedAt: 30,
      endedAt: 40,
      durationSeconds: 900,
      distanceMeters: 1800,
      averagePaceSecondsPerKm: 500,
      routePrivacy: 'private',
      createdAt: 41,
    });

    const alice = dbFor('alice');

    const aliceSummary = await assertSucceeds(
      getDoc(doc(alice, 'runSummaries/alice-summary')),
    );
    assert.equal(aliceSummary.data().ownerUid, 'alice');

    const aliceHistory = query(
      collection(alice, 'runSummaries'),
      where('ownerUid', '==', 'alice'),
      orderBy('endedAt', 'desc'),
      limit(30),
    );
    const aliceHistorySnapshot = await assertSucceeds(getDocs(aliceHistory));
    assert.deepEqual(
      aliceHistorySnapshot.docs.map((summary) => summary.id),
      ['alice-summary'],
    );
  });

  it('denies unbounded run summary history list queries', async () => {
    await seed('runSummaries/alice-summary', {
      ownerUid: 'alice',
      activityId: 'activity-alice',
      status: 'validated',
      startedAt: 10,
      endedAt: 20,
      durationSeconds: 600,
      distanceMeters: 1200,
      averagePaceSecondsPerKm: 500,
      routePrivacy: 'private',
      createdAt: 21,
    });

    const unboundedHistory = query(
      collection(dbFor('alice'), 'runSummaries'),
      where('ownerUid', '==', 'alice'),
      orderBy('endedAt', 'desc'),
    );

    await assertFails(getDocs(unboundedHistory));
  });

  it('run summary history denies cross-owner and client writes', async () => {
    await seed('runSummaries/alice-summary', {
      ownerUid: 'alice',
      activityId: 'activity-alice',
      status: 'validated',
      startedAt: 10,
      endedAt: 20,
      durationSeconds: 600,
      distanceMeters: 1200,
      averagePaceSecondsPerKm: 500,
      routePrivacy: 'private',
      createdAt: 21,
    });
    await seed('runSummaries/bob-summary', {
      ownerUid: 'bob',
      activityId: 'activity-bob',
      status: 'validated',
      startedAt: 30,
      endedAt: 40,
      durationSeconds: 900,
      distanceMeters: 1800,
      averagePaceSecondsPerKm: 500,
      routePrivacy: 'private',
      createdAt: 41,
    });

    const bob = dbFor('bob');

    await assertFails(getDoc(doc(bob, 'runSummaries/alice-summary')));
    await assertFails(
      getDocs(
        query(
          collection(bob, 'runSummaries'),
          where('ownerUid', '==', 'alice'),
          orderBy('endedAt', 'desc'),
          limit(30),
        ),
      ),
    );
    await assertFails(
      setDoc(doc(dbFor('alice'), 'runSummaries/client-summary'), {
        ownerUid: 'alice',
        activityId: 'activity-client',
        status: 'validated',
        startedAt: 50,
        endedAt: 60,
        durationSeconds: 600,
        distanceMeters: 1200,
        averagePaceSecondsPerKm: 500,
        routePrivacy: 'private',
        createdAt: 61,
      }),
    );
  });

  it('allows report creation but denies client resolution', async () => {
    const report = doc(dbFor('alice'), 'reports/report-001');

    await assertSucceeds(
      setDoc(report, {
        reporterUid: 'alice',
        targetType: 'route',
        targetId: 'synthetic-route',
        reason: 'unsafe_surface',
        description: 'Synthetic report text only.',
        createdAt: 1,
      }),
    );
    await assertFails(updateDoc(report, { status: 'resolved' }));
  });

  it('denies report creation from a suspended reporter, but not an unsuspended one or one with no accountStatus field at all', async () => {
    const reportData = (targetId) => ({
      reporterUid: 'alice',
      targetType: 'route',
      targetId,
      reason: 'unsafe_surface',
      description: 'Synthetic report text only.',
      createdAt: 1,
    });

    // Suspended: denied. This is defence-in-depth behind the admin console's
    // Auth-layer disable (see accountStatus.ts / isNotSuspended() in
    // firestore.rules) — it only matters for an already-issued, unexpired ID
    // token.
    await seedUser('alice', 'basic');
    await seed('users/alice', { subscriptionStatus: 'basic', userRole: 'Basic User', accountStatus: 'suspended' });
    await assertFails(setDoc(doc(dbFor('alice'), 'reports/report-suspended'), reportData('synthetic-route-suspended')));

    // Banned is the other blocking value.
    await seed('users/alice', { subscriptionStatus: 'basic', userRole: 'Basic User', accountStatus: 'banned' });
    await assertFails(setDoc(doc(dbFor('alice'), 'reports/report-banned'), reportData('synthetic-route-banned')));

    // Explicitly unsuspended: unaffected.
    await seed('users/alice', { subscriptionStatus: 'basic', userRole: 'Basic User', accountStatus: 'active' });
    await assertSucceeds(setDoc(doc(dbFor('alice'), 'reports/report-active'), reportData('synthetic-route-active')));

    // No accountStatus field at all (and no users/{uid} doc at all, via bob):
    // both must keep today's behaviour, unaffected by this rule.
    await assertSucceeds(setDoc(doc(dbFor('alice'), 'reports/report-no-field'), reportData('synthetic-route-no-field')));
    await removeSeed('users/alice');
    await assertSucceeds(
      setDoc(doc(dbFor('bob'), 'reports/report-no-doc'), { ...reportData('synthetic-route-no-doc'), reporterUid: 'bob' }),
    );
  });

  it('enforces a deterministic report id and rejects self-reports for report-a-user, but leaves other target types on free-form ids', async () => {
    const userReport = (targetId) => ({
      reporterUid: 'alice',
      targetType: 'user',
      targetId,
      reason: 'harassment_or_abuse',
      description: 'Synthetic report text only.',
      createdAt: 1,
    });

    // Wrong id format for a user report: denied, even though every other
    // field is well-formed.
    await assertFails(
      setDoc(doc(dbFor('alice'), 'reports/not-the-deterministic-id'), userReport('bob')),
    );

    // Self-report: denied even with the otherwise-correct deterministic id.
    await assertFails(
      setDoc(doc(dbFor('alice'), 'reports/alice_alice'), userReport('alice')),
    );

    // Well-formed create by an unsuspended reporter: allowed.
    await assertSucceeds(
      setDoc(doc(dbFor('alice'), 'reports/alice_bob'), userReport('bob')),
    );

    // Duplicate create for the same (reporter, target) pair: the document
    // now exists, so Firestore classifies the second set() as an update,
    // which `allow update: if false` rejects — no separate duplicate check
    // is needed in the rule itself.
    await assertFails(
      setDoc(doc(dbFor('alice'), 'reports/alice_bob'), userReport('bob')),
    );

    // Non-user target types are unaffected by the deterministic-id
    // requirement and keep today's free-form report id behaviour.
    await assertSucceeds(
      setDoc(doc(dbFor('alice'), 'reports/report-free-form-route'), {
        reporterUid: 'alice',
        targetType: 'route',
        targetId: 'alice',
        reason: 'unsafe_surface',
        description: 'Synthetic report text only.',
        createdAt: 1,
      }),
    );
  });

  it('allows owners to write notification preferences only for themselves', async () => {
    await assertSucceeds(
      setDoc(doc(dbFor('alice'), 'notificationPreferences/alice'), notificationPrefs),
    );
    await assertFails(
      setDoc(doc(dbFor('bob'), 'notificationPreferences/alice'), notificationPrefs),
    );
    await assertFails(
      setDoc(doc(dbFor('alice'), 'notificationPreferences/alice'), {
        ...notificationPrefs,
        backendSchedulingStatus: 'scheduled',
      }),
    );
  });

  it('denies deleting backend-owned notification scheduling fields', async () => {
    await seed('notificationPreferences/alice', {
      ...notificationPrefs,
      backendSchedulingStatus: 'scheduled',
      lastScheduledAt: 2,
      deliveryState: 'queued',
      serverManagedTokenState: 'active',
    });

    const prefs = doc(dbFor('alice'), 'notificationPreferences/alice');

    await assertSucceeds(updateDoc(prefs, { runReminderEnabled: false }));
    await assertFails(updateDoc(prefs, { backendSchedulingStatus: deleteField() }));
    await assertFails(updateDoc(prefs, { lastScheduledAt: deleteField() }));
    await assertFails(updateDoc(prefs, { deliveryState: 'sent' }));
    await assertFails(updateDoc(prefs, { serverManagedTokenState: deleteField() }));
  });

  it('allows owners to create and update the social activity notification toggle', async () => {
    await assertSucceeds(
      setDoc(doc(dbFor('alice'), 'notificationPreferences/alice'), {
        ...notificationPrefs,
        socialActivityEnabled: true,
      }),
    );

    const prefs = doc(dbFor('alice'), 'notificationPreferences/alice');
    await assertSucceeds(updateDoc(prefs, { socialActivityEnabled: false }));
  });

  it('allows the client to merge-set only ownerUid, socialActivityEnabled, and updatedAt onto an existing preferences doc', async () => {
    await seed('notificationPreferences/alice', notificationPrefs);

    await assertSucceeds(
      setDoc(
        doc(dbFor('alice'), 'notificationPreferences/alice'),
        {
          ownerUid: 'alice',
          socialActivityEnabled: false,
          updatedAt: 2,
        },
        { merge: true },
      ),
    );
  });

  it('allows the client to merge-set the social activity toggle onto a preferences doc that has never existed', async () => {
    // The real first mirror write. `notificationPreferences/{uid}` has never
    // been written by the app, so the client's merge-set lands as a rules
    // `create` carrying only these three keys — not the full fixture the
    // create test above sends.
    await assertSucceeds(
      setDoc(
        doc(dbFor('alice'), 'notificationPreferences/alice'),
        {
          ownerUid: 'alice',
          socialActivityEnabled: true,
          updatedAt: 1,
        },
        { merge: true },
      ),
    );
  });

  it('denies non-owners from creating or updating the social activity notification toggle', async () => {
    await assertFails(
      setDoc(doc(dbFor('bob'), 'notificationPreferences/alice'), {
        ...notificationPrefs,
        socialActivityEnabled: true,
      }),
    );

    await seed('notificationPreferences/alice', notificationPrefs);
    await assertFails(
      updateDoc(
        doc(dbFor('bob'), 'notificationPreferences/alice'),
        { socialActivityEnabled: false },
      ),
    );
  });

  it('denies unknown keys on notification preferences create and update', async () => {
    await assertFails(
      setDoc(doc(dbFor('alice'), 'notificationPreferences/alice'), {
        ...notificationPrefs,
        unexpectedKey: true,
      }),
    );

    await seed('notificationPreferences/alice', notificationPrefs);
    await assertFails(
      updateDoc(
        doc(dbFor('alice'), 'notificationPreferences/alice'),
        { unexpectedKey: true },
      ),
    );
  });

  it('allows notification inbox owners to read and list their items', async () => {
    await seed('notificationInbox/alice/items/notification-001', notificationInboxItem);

    const alice = dbFor('alice');
    const inboxItem = await assertSucceeds(
      getDoc(doc(alice, 'notificationInbox/alice/items/notification-001')),
    );
    assert.equal(inboxItem.data().ownerUid, 'alice');

    const inboxSnapshot = await assertSucceeds(
      getDocs(collection(alice, 'notificationInbox/alice/items')),
    );
    assert.deepEqual(
      inboxSnapshot.docs.map((notification) => notification.id),
      ['notification-001'],
    );
  });

  it('allows notification inbox owners to soft-update read metadata only', async () => {
    await seed('notificationInbox/alice/items/notification-001', notificationInboxItem);

    const inboxItem = doc(
      dbFor('alice'),
      'notificationInbox/alice/items/notification-001',
    );

    await assertSucceeds(
      updateDoc(inboxItem, {
        readAt: Timestamp.fromDate(new Date('2026-07-08T10:00:00.000Z')),
        deletedAt: Timestamp.fromDate(new Date('2026-07-08T10:01:00.000Z')),
        updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:01:00.000Z')),
      }),
    );
  });

  it('pins the server-shaped notification inbox split for social activity notifications: owner read/readAt-update yes, client create no', async () => {
    // The social activity notification the socialActivityEnabled toggle
    // gates is delivered server-side (no clientManaged field), exactly like
    // today's Challenge notifications. Owners must still be able to read it
    // and mark it read, but only the Admin SDK may create it.
    await seed('notificationInbox/alice/items/notification-001', notificationInboxItem);

    const inboxItem = doc(
      dbFor('alice'),
      'notificationInbox/alice/items/notification-001',
    );

    await assertSucceeds(getDoc(inboxItem));
    await assertSucceeds(
      updateDoc(inboxItem, {
        readAt: Timestamp.fromDate(new Date('2026-07-08T10:00:00.000Z')),
        updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:00:00.000Z')),
      }),
    );

    await assertFails(
      setDoc(
        doc(dbFor('alice'), 'notificationInbox/alice/items/notification-002'),
        notificationInboxItem,
      ),
    );
  });

  it('allows unread notification inbox soft delete without changing read state', async () => {
    await seed('notificationInbox/alice/items/notification-001', notificationInboxItem);

    const inboxItem = doc(
      dbFor('alice'),
      'notificationInbox/alice/items/notification-001',
    );

    await assertSucceeds(
      updateDoc(inboxItem, {
        deletedAt: Timestamp.fromDate(new Date('2026-07-08T10:01:00.000Z')),
        updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:01:00.000Z')),
      }),
    );
  });

  it('allows notification inbox owners to create local client-managed items', async () => {
    const inboxItem = doc(
      dbFor('alice'),
      'notificationInbox/alice/items/local-notification-smoke-test',
    );

    await assertSucceeds(
      setDoc(inboxItem, {
        ownerUid: 'alice',
        clientManaged: true,
        title: 'Runiac local notification test',
        body: 'If you can see this, iOS local notifications are working.',
        createdAt: Timestamp.fromDate(new Date('2026-07-08T10:13:18.000Z')),
        data: {
          kind: 'localNotificationSmokeTest',
        },
        updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:13:18.000Z')),
      }),
    );
  });

  it('allows notification inbox owners to refresh local client-managed items', async () => {
    await seed('notificationInbox/alice/items/local-notification-smoke-test', {
      ownerUid: 'alice',
      clientManaged: true,
      title: 'Runiac local notification test',
      body: 'If you can see this, iOS local notifications are working.',
      createdAt: Timestamp.fromDate(new Date('2026-07-08T10:13:18.000Z')),
      data: {
        kind: 'localNotificationSmokeTest',
      },
      updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:13:18.000Z')),
    });

    await assertSucceeds(
      setDoc(
        doc(dbFor('alice'), 'notificationInbox/alice/items/local-notification-smoke-test'),
        {
          ownerUid: 'alice',
          clientManaged: true,
          title: 'Runiac local notification test',
          body: 'If you can see this, iOS local notifications are working.',
          createdAt: Timestamp.fromDate(new Date('2026-07-08T10:15:18.000Z')),
          data: {
            kind: 'localNotificationSmokeTest',
          },
          updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:15:18.000Z')),
        },
        { merge: true },
      ),
    );
  });

  it('allows notification inbox owners to restore deleted local client-managed items', async () => {
    await seed('notificationInbox/alice/items/local-notification-smoke-test', {
      ownerUid: 'alice',
      clientManaged: true,
      title: 'Runiac local notification test',
      body: 'If you can see this, iOS local notifications are working.',
      createdAt: Timestamp.fromDate(new Date('2026-07-08T10:13:18.000Z')),
      readAt: Timestamp.fromDate(new Date('2026-07-08T10:14:00.000Z')),
      deletedAt: Timestamp.fromDate(new Date('2026-07-08T10:14:30.000Z')),
      data: {
        kind: 'localNotificationSmokeTest',
      },
      updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:14:30.000Z')),
    });

    await assertSucceeds(
      setDoc(
        doc(dbFor('alice'), 'notificationInbox/alice/items/local-notification-smoke-test'),
        {
          ownerUid: 'alice',
          clientManaged: true,
          title: 'Runiac local notification test',
          body: 'If you can see this, iOS local notifications are working.',
          createdAt: Timestamp.fromDate(new Date('2026-07-08T10:15:18.000Z')),
          readAt: deleteField(),
          deletedAt: deleteField(),
          data: {
            kind: 'localNotificationSmokeTest',
          },
          updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:15:18.000Z')),
        },
        { merge: true },
      ),
    );
  });

  it('denies invalid notification inbox metadata values', async () => {
    await seed('notificationInbox/alice/items/notification-001', notificationInboxItem);

    const inboxItem = doc(
      dbFor('alice'),
      'notificationInbox/alice/items/notification-001',
    );

    await assertFails(updateDoc(inboxItem, { readAt: 3 }));
    await assertFails(updateDoc(inboxItem, { deletedAt: '2026-07-08T10:01:00.000Z' }));
    await assertFails(updateDoc(inboxItem, { updatedAt: null }));
    await assertFails(updateDoc(inboxItem, { readAt: deleteField() }));
    await assertFails(updateDoc(inboxItem, { deletedAt: deleteField() }));
    await assertFails(updateDoc(inboxItem, { updatedAt: deleteField() }));
  });

  it('denies server-owned notification inbox create and client delete operations', async () => {
    const inboxItem = doc(
      dbFor('alice'),
      'notificationInbox/alice/items/notification-001',
    );

    await assertFails(setDoc(inboxItem, notificationInboxItem));

    await seed('notificationInbox/alice/items/notification-001', notificationInboxItem);
    await assertFails(deleteDoc(inboxItem));
  });

  it('denies notification inbox owner mutation of server-owned fields', async () => {
    await seed('notificationInbox/alice/items/notification-001', notificationInboxItem);

    const inboxItem = doc(
      dbFor('alice'),
      'notificationInbox/alice/items/notification-001',
    );

    await assertFails(updateDoc(inboxItem, { ownerUid: 'bob' }));
    await assertFails(updateDoc(inboxItem, { title: 'Changed title' }));
    await assertFails(updateDoc(inboxItem, { body: 'Changed body' }));
    await assertFails(updateDoc(inboxItem, { type: 'system' }));
    await assertFails(updateDoc(inboxItem, { target: { screen: 'leaderboard' } }));
    await assertFails(updateDoc(inboxItem, { deliveryState: 'opened' }));
    await assertFails(updateDoc(inboxItem, { serverManagedTokenState: 'inactive' }));
    await assertFails(updateDoc(inboxItem, { backendSchedulingStatus: 'retrying' }));
    await assertFails(updateDoc(inboxItem, { deliveredAt: deleteField() }));
  });

  it('denies invalid local client-managed notification inbox creates', async () => {
    const alice = dbFor('alice');

    await assertFails(
      setDoc(doc(alice, 'notificationInbox/bob/items/local-notification-smoke-test'), {
        ownerUid: 'bob',
        clientManaged: true,
        title: 'Runiac local notification test',
        body: 'If you can see this, iOS local notifications are working.',
        createdAt: Timestamp.fromDate(new Date('2026-07-08T10:13:18.000Z')),
        data: {
          kind: 'localNotificationSmokeTest',
        },
        updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:13:18.000Z')),
      }),
    );
    await assertFails(
      setDoc(doc(alice, 'notificationInbox/alice/items/local-bad-xp'), {
        ownerUid: 'alice',
        clientManaged: true,
        title: 'Runiac local notification test',
        body: 'If you can see this, iOS local notifications are working.',
        createdAt: Timestamp.fromDate(new Date('2026-07-08T10:13:18.000Z')),
        data: {
          kind: 'localNotificationSmokeTest',
        },
        updatedAt: Timestamp.fromDate(new Date('2026-07-08T10:13:18.000Z')),
        xp: 10,
      }),
    );
  });

  it('denies notification inbox reads and updates from other users', async () => {
    await seed('notificationInbox/alice/items/notification-001', notificationInboxItem);

    const bob = dbFor('bob');
    const aliceItemForBob = doc(
      bob,
      'notificationInbox/alice/items/notification-001',
    );

    await assertFails(getDoc(aliceItemForBob));
    await assertFails(getDocs(collection(bob, 'notificationInbox/alice/items')));
    await assertFails(updateDoc(aliceItemForBob, { readAt: 3, updatedAt: 3 }));
  });

  it('denies client direct notification device and delivery writes', async () => {
    const alice = dbFor('alice');
    const deviceToken = doc(
      alice,
      'notificationDevices/alice/tokens/tokenFingerprint',
    );
    const delivery = doc(alice, 'notificationDeliveries/delivery-001');

    await assertFails(setDoc(deviceToken, notificationDeviceTokenRecord));
    await assertFails(setDoc(delivery, notificationDeliveryRecord));

    await seed(
      'notificationDevices/alice/tokens/tokenFingerprint',
      notificationDeviceTokenRecord,
    );
    await seed('notificationDeliveries/delivery-001', notificationDeliveryRecord);

    await assertFails(getDoc(deviceToken));
    await assertFails(getDoc(delivery));
    await assertFails(updateDoc(deviceToken, { serverManagedTokenState: 'inactive' }));
    await assertFails(updateDoc(delivery, { deliveryState: 'sent' }));
    await assertFails(deleteDoc(deviceToken));
    await assertFails(deleteDoc(delivery));
  });

  it('denies every client identity all access to server-only daily agent guidance', async () => {
    const dailyGuidancePath = 'agentGuidanceDaily/alice_2026-07-10';
    const dailyGuidanceDocument = {
      ownerUid: 'alice',
      dayKey: '2026-07-10',
      attemptCount: 1,
      cacheState: 'ready',
    };
    const malformedClientGuidance = { clientOnly: true };

    await seed(dailyGuidancePath, dailyGuidanceDocument);

    for (const [identity, client] of [
      ['unauthenticated', unauthenticatedDb()],
      ['owner', dbFor('alice')],
      ['cross-owner', dbFor('bob')],
    ]) {
      const existingGuidance = doc(client, dailyGuidancePath);
      const clientCreatedGuidance = doc(
        client,
        `agentGuidanceDaily/${identity}-client-created`,
      );
      const ownerGuidanceQuery = query(
        collection(client, 'agentGuidanceDaily'),
        where('ownerUid', '==', 'alice'),
      );

      await assertFails(getDoc(existingGuidance));
      await assertFails(getDocs(ownerGuidanceQuery));
      await assertFails(setDoc(clientCreatedGuidance, malformedClientGuidance));
      await assertFails(updateDoc(existingGuidance, { cacheState: 'client-write' }));
      await assertFails(deleteDoc(existingGuidance));
    }
  });

  it('denies all direct client access to admin notifications', async () => {
    const alice = dbFor('alice');
    const notification = doc(alice, 'adminNotifications/report_test-report');

    await assertFails(
      setDoc(notification, {
        kind: 'new-report',
        severity: 'medium',
        title: 'New report submitted',
        detail: 'A new report was submitted.',
        href: '/admin/exceptions',
        status: 'unread',
      }),
    );

    await seed('adminNotifications/report_test-report', {
      kind: 'new-report',
      severity: 'medium',
      title: 'New report submitted',
      detail: 'A new report was submitted.',
      href: '/admin/exceptions',
      status: 'unread',
    });

    await assertFails(getDoc(notification));
    await assertFails(updateDoc(notification, { status: 'read' }));
    await assertFails(deleteDoc(notification));
  });

  it('denies all direct client access to moderation commands for signed-in and unauthenticated clients', async () => {
    await seed('moderationCommands/command-001', {
      kind: 'setUserAccountStatus',
      targetUid: 'alice',
      accountStatus: 'suspended',
      requestedBy: 'admin-console',
      status: 'pending',
    });

    for (const client of [dbFor('alice'), unauthenticatedDb()]) {
      const command = doc(client, 'moderationCommands/command-001');

      await assertFails(getDoc(command));
      await assertFails(getDocs(collection(client, 'moderationCommands')));
      await assertFails(
        setDoc(doc(client, 'moderationCommands/client-created'), {
          kind: 'setUserAccountStatus',
          targetUid: 'bob',
          accountStatus: 'banned',
          requestedBy: 'client',
          status: 'pending',
        }),
      );
      await assertFails(updateDoc(command, { status: 'completed' }));
      await assertFails(deleteDoc(command));
    }
  });

  it('denies all client access to error groups and their reporter markers', async () => {
    await seed('errorGroups/group-001', {
      fingerprint: 'synthetic-fingerprint',
      message: 'Synthetic error message only.',
      occurrenceCount: 3,
      firstSeenAt: 1,
      lastSeenAt: 2,
      status: 'open',
    });
    await seed('errorGroups/group-001/reporters/alice', {
      reportedAt: 2,
    });

    for (const client of [dbFor('alice'), unauthenticatedDb()]) {
      const group = doc(client, 'errorGroups/group-001');
      const reporter = doc(client, 'errorGroups/group-001/reporters/alice');

      await assertFails(getDoc(group));
      await assertFails(getDoc(reporter));
      await assertFails(getDocs(collection(client, 'errorGroups/group-001/reporters')));
      await assertFails(
        setDoc(doc(client, 'errorGroups/client-created'), {
          fingerprint: 'client-fingerprint',
          message: 'Client-forged error group.',
          occurrenceCount: 1,
          status: 'open',
        }),
      );
      await assertFails(
        setDoc(doc(client, 'errorGroups/group-001/reporters/client-created'), {
          reportedAt: 3,
        }),
      );
      await assertFails(updateDoc(group, { status: 'resolved' }));
      await assertFails(deleteDoc(group));
      await assertFails(deleteDoc(reporter));
    }
  });

  it('denies even the owner all access to their own error report rate-limit ledger', async () => {
    await seed('errorReportRateLimit/alice', {
      lastReceivedAt: 1,
    });
    await seed('errorReportRateLimit/alice/events/event-001', {
      receivedAt: 1,
    });

    const alice = dbFor('alice');
    const ledger = doc(alice, 'errorReportRateLimit/alice');
    const event = doc(alice, 'errorReportRateLimit/alice/events/event-001');

    await assertFails(getDoc(ledger));
    await assertFails(getDoc(event));
    await assertFails(getDocs(collection(alice, 'errorReportRateLimit/alice/events')));
    await assertFails(setDoc(ledger, { lastReceivedAt: 1 }));
    await assertFails(
      setDoc(doc(alice, 'errorReportRateLimit/alice/events/client-created'), {
        receivedAt: 2,
      }),
    );
    await assertFails(updateDoc(event, { receivedAt: 2 }));
    // Deleting the ledger or its events would reset the reportAppError
    // per-uid rate limit, so even the owner uid is denied.
    await assertFails(deleteDoc(event));
    await assertFails(deleteDoc(ledger));
  });

  it('denies signed-in clients all access to leaderboard contributions, including their own', async () => {
    await seed('leaderboardContributions/alice_monthly_2026-07', {
      ownerUid: 'alice',
      periodType: 'monthly',
      periodKey: '2026-07',
      regionId: 'jurong-east',
      divisionKey: 'tier_01',
      scoreXp: 120,
      updatedAt: 1,
    });

    const alice = dbFor('alice');
    const ownContribution = doc(
      alice,
      'leaderboardContributions/alice_monthly_2026-07',
    );

    await assertFails(getDoc(ownContribution));
    await assertFails(
      getDocs(
        query(
          collection(alice, 'leaderboardContributions'),
          where('ownerUid', '==', 'alice'),
          limit(30),
        ),
      ),
    );
    await assertFails(
      setDoc(doc(alice, 'leaderboardContributions/alice_monthly_2026-08'), {
        ownerUid: 'alice',
        periodType: 'monthly',
        periodKey: '2026-08',
        regionId: 'jurong-east',
        divisionKey: 'tier_01',
        scoreXp: 999,
        updatedAt: 2,
      }),
    );
    await assertFails(updateDoc(ownContribution, { scoreXp: 999 }));
    await assertFails(deleteDoc(ownContribution));
  });

  it('allows only the owner to read a progression event and denies all client writes to it', async () => {
    await seed('progressionEvents/event-alice-001', {
      ownerUid: 'alice',
      activityId: 'activity-alice-001',
      xp: 40,
      previousTotalXp: 0,
      nextTotalXp: 40,
      previousLevel: 1,
      nextLevel: 1,
      createdAt: 1,
    });

    const ownEvent = await assertSucceeds(
      getDoc(doc(dbFor('alice'), 'progressionEvents/event-alice-001')),
    );
    assert.equal(ownEvent.data().ownerUid, 'alice');

    await assertFails(
      getDoc(doc(dbFor('bob'), 'progressionEvents/event-alice-001')),
    );
    await assertFails(
      getDoc(doc(unauthenticatedDb(), 'progressionEvents/event-alice-001')),
    );
    await assertFails(
      updateDoc(doc(dbFor('alice'), 'progressionEvents/event-alice-001'), {
        xp: 999,
      }),
    );
    await assertFails(
      deleteDoc(doc(dbFor('alice'), 'progressionEvents/event-alice-001')),
    );
  });

  it('allows only the owner to read their users account and subscription state document', async () => {
    await seed('users/alice', {
      accountStatus: 'active',
      subscriptionStatus: 'basic',
      userRole: 'Basic User',
    });

    const ownDoc = await assertSucceeds(
      getDoc(doc(dbFor('alice'), 'users/alice')),
    );
    assert.equal(ownDoc.data().subscriptionStatus, 'basic');

    await assertFails(getDoc(doc(dbFor('bob'), 'users/alice')));
    await assertFails(getDoc(doc(unauthenticatedDb(), 'users/alice')));
  });
});
