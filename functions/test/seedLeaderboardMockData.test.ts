import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { runSeedCommand } from "../src/leaderboard/seedLeaderboardMockData.js";

describe(
  "leaderboard seed CLI",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;

    before(() => {
      if (getApps().length === 0) {
        initializeApp({ projectId: "runiac-functions-test" });
      }
      firestore = getFirestore();
    });

    beforeEach(async () => {
      await clearCollections(firestore, [
        "users",
        "userProfiles",
        "leaderboardContributions",
        "leaderboardSnapshots",
        "leaderboardUserRanks",
        "leaderboardCurrentViews",
        "leaderboardPeriods",
        "leaderboardAggregationLocks",
        "leaderboardSeedRuns",
      ]);
    });

    it("verifies only the selected region when unrelated real and mock data exist", async () => {
      // Given: a Jurong East fixture, an unrelated mock fixture, and a real contributor.
      await runSeedCommand([
        "--project",
        "runiac-functions-test",
        "--period",
        "2026-07",
        "--run-id",
        "jurong-run-001",
        "--region-id",
        "jurong-east",
        "--users-per-region",
        "100",
        "--seed",
        "--refresh",
      ]);
      await writeMockSourceDocuments(firestore, {
        runId: "other-run-001",
        periodKey: "2026-07",
      });
      await writeRealContributor(firestore);

      // When: verification requests the Jurong East run only.
      const result = await runSeedCommand([
        "--project",
        "runiac-functions-test",
        "--period",
        "2026-07",
        "--run-id",
        "jurong-run-001",
        "--region-id",
        "jurong-east",
        "--users-per-region",
        "100",
        "--verify",
      ]);

      // Then: its bounded projections are verified without being affected by other data.
      const verification = result["verify"];
      assert.ok(typeof verification === "object" && verification !== null);
      assert.equal(Reflect.get(verification, "profileCount"), 100);
      assert.equal(Reflect.get(verification, "rankCount"), 99);
      // Premium parity: the one zero-score record per region is dropped by the
      // planner outright, so it gets neither a rank nor a current view. Under
      // the previous premium-exclusion default it still received an
      // `ineligible_premium` view, which is why this used to be 100.
      assert.equal(Reflect.get(verification, "currentViewCount"), 99);
      assert.equal(Reflect.get(verification, "snapshotCount"), 10);
      assert.deepEqual(Reflect.get(verification, "regionIds"), ["jurong-east"]);
    });

    it("cleans only one exact manifest-backed mock run when other mock and real data exist", async () => {
      // Given: a target mock run, a different mock run, and a real contributor.
      await runSeedCommand([
        "--project",
        "runiac-functions-test",
        "--period",
        "2026-07",
        "--run-id",
        "cleanup-run-001",
        "--region-id",
        "jurong-east",
        "--users-per-region",
        "100",
        "--seed",
        "--refresh",
      ]);
      await writeMockSourceDocuments(firestore, {
        runId: "preserved-run-001",
        periodKey: "2026-07",
      });
      await writeRealContributor(firestore);

      // When: cleanup repeats only the target run ID.
      await runSeedCommand([
        "--project",
        "runiac-functions-test",
        "--period",
        "2026-07",
        "--run-id",
        "cleanup-run-001",
        "--region-id",
        "jurong-east",
        "--users-per-region",
        "100",
        "--confirm-cleanup",
        "cleanup-run-001",
        "--cleanup",
      ]);

      // Then: the target is gone while unrelated marker and real documents remain.
      assert.equal(
        (await firestore
          .collection("users")
          .where("mockSeedRunId", "==", "cleanup-run-001")
          .get()).size,
        0,
      );
      assert.equal(
        (await firestore
          .collection("users")
          .where("mockSeedRunId", "==", "preserved-run-001")
          .get()).size,
        1,
      );
      assert.equal((await firestore.doc("users/real-runner-001").get()).exists, true);
    });

  },
);

async function writeMockSourceDocuments(
  firestore: Firestore,
  input: { readonly runId: string; readonly periodKey: string },
): Promise<void> {
  const uid = `lbmock_${input.runId}_jurong-east_001`;
  const marker = { isMockData: true, mockSeedRunId: input.runId };
  await Promise.all([
    firestore.doc(`users/${uid}`).set(marker),
    firestore.doc(`userProfiles/${uid}`).set(marker),
    firestore.doc(`leaderboardContributions/${uid}_monthly_${input.periodKey}`).set({
      ...marker,
      ownerUid: uid,
      periodKey: input.periodKey,
    }),
  ]);
}

async function writeRealContributor(firestore: Firestore): Promise<void> {
  await Promise.all([
    firestore.doc("users/real-runner-001").set({ subscriptionStatus: "basic" }),
    firestore.doc("userProfiles/real-runner-001").set({
      nickname: "Real Runner",
      locationLabel: "Jurong East, Singapore",
      divisionKey: "tier_01",
      level: 1,
    }),
    firestore.doc("leaderboardContributions/real-runner-001_monthly_2026-07").set({
      schemaVersion: 2,
      ownerUid: "real-runner-001",
      publicAlias: "Real Runner",
      regionId: "jurong-east",
      regionLabel: "Jurong East",
      planningAreaName: "JURONG EAST",
      planningAreaCode: "JE",
      planningRegionCode: "WR",
      divisionKey: "tier_01",
      divisionLabel: "Iron League",
      levelLabel: "Level 1",
      periodType: "monthly",
      periodKey: "2026-07",
      timezone: "Asia/Singapore",
      scoreXp: 50,
      eligible: true,
      eligibilityReason: "eligible_basic_awarded_xp",
      lastProgressionAt: "2026-07-10T00:00:00.000Z",
      sourceProgressionEventIds: ["real-event-001"],
    }),
  ]);
}

async function clearCollections(
  firestore: Firestore,
  collectionNames: readonly string[],
): Promise<void> {
  for (const collectionName of collectionNames) {
    const snapshot = await firestore.collection(collectionName).get();
    if (snapshot.empty) {
      continue;
    }
    const batch = firestore.batch();
    for (const document of snapshot.docs) {
      batch.delete(document.ref);
    }
    await batch.commit();
  }
}
