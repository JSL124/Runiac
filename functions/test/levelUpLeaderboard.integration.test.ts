import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { refreshMonthlyLeaderboardSnapshots } from "../src/leaderboard/monthlyLeaderboard.js";
import { completeRunForCallable } from "../src/run/completeRun.js";

const projectId = "runiac-functions-test";
const runnerUid = "level-up-runner";
const collections = [
  "activities",
  "runSummaries",
  "progressionEvents",
  "users",
  "userProfiles",
  "leaderboardContributions",
  "leaderboardSnapshots",
  "leaderboardUserRanks",
  "leaderboardCurrentViews",
  "leaderboardPeriods",
  "leaderboardAggregationLocks",
] as const;

describe(
  "level-up leaderboard integration",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;

    before(() => {
      if (getApps().length === 0) {
        initializeApp({ projectId });
      }
      firestore = getFirestore();
    });

    beforeEach(async () => {
      await clearCollections(firestore, collections);
      await firestore.doc(`userProfiles/${runnerUid}`).set({
        nickname: "League Runner",
        locationLabel: "Jurong East, Singapore",
        totalXp: 990,
      });
    });

    after(async () => {
      await clearCollections(firestore, collections);
    });

    it("moves a basic runner from Iron to Bronze after a valid level-up and refresh", async () => {
      const result = await completeRunForCallable(
        {
          auth: { uid: runnerUid },
          data: {
            clientRunSessionId: "bronze-league-level-up",
            startedAt: "2026-06-14T09:00:00.000Z",
            completedAt: "2026-06-14T09:25:00.000Z",
            durationSeconds: 1500,
            distanceMeters: 3200,
            avgPaceSecondsPerKm: 469,
            source: "mobile",
            routePrivacy: "private",
            activityTitle: "Sunday Morning Run",
          },
        },
        firestore,
      );
      const refresh = await refreshMonthlyLeaderboardSnapshots(
        firestore,
        "2026-06",
        {
          now: new Date("2026-06-14T09:26:00.000Z"),
          buildId: "level-up-leaderboard-refresh",
        },
      );
      const [profile, contribution, currentView, rank, snapshot] = await Promise.all([
        firestore.doc(`userProfiles/${runnerUid}`).get(),
        firestore.doc(`leaderboardContributions/${runnerUid}_monthly_2026-06`).get(),
        firestore.doc(`leaderboardCurrentViews/${runnerUid}`).get(),
        firestore.doc(`leaderboardUserRanks/${runnerUid}_monthly_2026-06`).get(),
        firestore.doc("leaderboardSnapshots/monthly_jurong-east_tier_02_2026-06").get(),
      ]);

      assert.equal(result.progressionDisplay.level, 11);
      assert.equal(profile.get("divisionKey"), "tier_02");
      assert.equal(contribution.get("divisionKey"), "tier_02");
      assert.equal(refresh.status, "completed");
      assert.equal(currentView.get("status"), "ranked");
      assert.equal(currentView.get("divisionKey"), "tier_02");
      assert.equal(rank.get("rankLabel"), "#1");
      assert.equal(snapshot.get("entryCount"), 1);
    });

    it("projects promoted runners into their new division and ranks only competitors in that division", async () => {
      const bronzeRivalUid = "bronze-rival";
      const ironRunnerUid = "iron-runner";
      await Promise.all([
        firestore.doc(`userProfiles/${bronzeRivalUid}`).set({
          nickname: "Bronze Rival",
          locationLabel: "Jurong East, Singapore",
          totalXp: 990,
        }),
        firestore.doc(`userProfiles/${ironRunnerUid}`).set({
          nickname: "Iron Runner",
          locationLabel: "Jurong East, Singapore",
          totalXp: 0,
        }),
      ]);

      await Promise.all([
        completeRunForCallable(
          {
            auth: { uid: runnerUid },
            data: runPayload({
              sessionId: "bronze-runner-level-up",
              startedAt: "2026-06-14T09:00:00.000Z",
              completedAt: "2026-06-14T09:25:00.000Z",
              durationSeconds: 1500,
              distanceMeters: 3200,
            }),
          },
          firestore,
        ),
        completeRunForCallable(
          {
            auth: { uid: bronzeRivalUid },
            data: runPayload({
              sessionId: "bronze-rival-level-up",
              startedAt: "2026-06-14T10:00:00.000Z",
              completedAt: "2026-06-14T10:30:00.000Z",
              durationSeconds: 1800,
              distanceMeters: 5000,
            }),
          },
          firestore,
        ),
        completeRunForCallable(
          {
            auth: { uid: ironRunnerUid },
            data: runPayload({
              sessionId: "iron-runner-level-up",
              startedAt: "2026-06-14T11:00:00.000Z",
              completedAt: "2026-06-14T11:10:00.000Z",
              durationSeconds: 600,
              distanceMeters: 1500,
            }),
          },
          firestore,
        ),
      ]);
      await refreshMonthlyLeaderboardSnapshots(firestore, "2026-06", {
        now: new Date("2026-06-14T11:11:00.000Z"),
        buildId: "division-competition-refresh",
      });
      const [runnerRank, rivalRank, ironRank, bronzeSnapshot, ironSnapshot] =
          await Promise.all([
            firestore.doc(`leaderboardUserRanks/${runnerUid}_monthly_2026-06`).get(),
            firestore.doc(`leaderboardUserRanks/${bronzeRivalUid}_monthly_2026-06`).get(),
            firestore.doc(`leaderboardUserRanks/${ironRunnerUid}_monthly_2026-06`).get(),
            firestore.doc("leaderboardSnapshots/monthly_jurong-east_tier_02_2026-06").get(),
            firestore.doc("leaderboardSnapshots/monthly_jurong-east_tier_01_2026-06").get(),
          ]);

      assert.equal(runnerRank.get("divisionKey"), "tier_02");
      assert.equal(runnerRank.get("rankLabel"), "#2");
      assert.equal(rivalRank.get("divisionKey"), "tier_02");
      assert.equal(rivalRank.get("rankLabel"), "#1");
      assert.equal(ironRank.get("divisionKey"), "tier_01");
      assert.equal(ironRank.get("rankLabel"), "#1");
      assert.equal(bronzeSnapshot.get("entryCount"), 2);
      assert.equal(ironSnapshot.get("entryCount"), 1);
    });
  },
);

function runPayload(input: {
  readonly sessionId: string;
  readonly startedAt: string;
  readonly completedAt: string;
  readonly durationSeconds: number;
  readonly distanceMeters: number;
}) {
  return {
    clientRunSessionId: input.sessionId,
    startedAt: input.startedAt,
    completedAt: input.completedAt,
    durationSeconds: input.durationSeconds,
    distanceMeters: input.distanceMeters,
    avgPaceSecondsPerKm: Math.floor(
      input.durationSeconds / (input.distanceMeters / 1000),
    ),
    source: "mobile",
    routePrivacy: "private",
    activityTitle: "Sunday Morning Run",
  };
}

async function clearCollections(
  firestore: Firestore,
  collectionNames: readonly string[],
): Promise<void> {
  for (const collectionName of collectionNames) {
    const snapshot = await firestore.collection(collectionName).get();
    await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
  }
}
