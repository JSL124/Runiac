import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { leaderboardLeagueDefinitions } from "../src/progression/leaderboardLeagues.js";
import { createSeedDataset } from "../src/leaderboard/leaderboardSeedDataset.js";
import { snapshotIdBatches } from "../src/leaderboard/leaderboardSeedVerification.js";
import { runSeedCommand } from "../src/leaderboard/seedLeaderboardMockData.js";

it("splits more than ten expected snapshot IDs into Firestore-bounded batches", () => {
  // Given: an all-region-compatible snapshot selection larger than the Firestore query bound.
  const snapshotIds = Array.from({ length: 11 }, (_, index) => `snapshot-${index + 1}`);

  // When: verifier snapshot IDs are prepared for rank reads.
  const batches = snapshotIdBatches(snapshotIds);

  // Then: each query receives at most ten IDs and no ID is dropped.
  assert.deepEqual(batches, [snapshotIds.slice(0, 10), snapshotIds.slice(10)]);
});

describe(
  "leaderboard seed read-back verification",
  { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined },
  () => {
    let firestore: Firestore;

    before(() => {
      if (getApps().length === 0) initializeApp({ projectId: "runiac-functions-test" });
      firestore = getFirestore();
    });

    beforeEach(async () => clearLeaderboardCollections(firestore));

    it("accepts all 99 Basic ranks across the ten Jurong East leagues with unrelated contributors", async () => {
      // Given: the exact Jurong East cohort plus an unrelated eligible contributor.
      const runId = "verify-full-001";
      await seed(runId);
      await writeRealContributor(firestore);

      // When: the selected run is read back after a trusted refresh.
      const result = await verify(runId);

      // Then: the verifier accepts the cohort and every Basic fixture remains ordered per league.
      assert.equal(readResult(result, "rankCount"), 99);
      assert.equal(readResult(result, "snapshotCount"), 10);
      const dataset = createSeedDataset({ runId, periodKey: "2026-07", usersPerRegion: 100, regionId: "jurong-east" });
      const ranks = await firestore.collection("leaderboardUserRanks").where("periodKey", "==", "2026-07").get();
      for (const league of leaderboardLeagueDefinitions) {
        const expected = dataset.dataset.records
          .filter((record) => record.user["subscriptionStatus"] === "basic" && record.contribution.divisionKey === league.key)
          .sort((left, right) => right.contribution.scoreXp - left.contribution.scoreXp)
          .map((record) => [record.contribution.publicAlias, record.contribution.scoreXp]);
        const actual = ranks.docs
          .filter((rank) => rank.get("ownerUid").startsWith(dataset.uidPrefix) && rank.get("divisionKey") === league.key)
          .sort((left, right) => rankNumber(left.get("rankLabel")) - rankNumber(right.get("rankLabel")))
          .map((rank) => [entryValue(rank.get("currentEntry"), "publicAlias"), rank.get("score")]);
        assert.deepEqual(actual, expected);
      }
    });

    it("rejects a tampered Premium contribution", async () => {
      // Given: a seeded cohort whose Premium contribution is changed to eligible XP.
      const runId = "verify-premium-001";
      await seed(runId);
      const premium = premiumUid(runId);
      await firestore.doc(`leaderboardContributions/${premium}_monthly_2026-07`).update({ scoreXp: 1, eligible: true });

      // When: the run is verified.
      // Then: exact source read-back fails.
      await assert.rejects(verify(runId), /source integrity/);
    });

    it("rejects tampered rank and current-view projections", async () => {
      // Given: two otherwise valid runs with a changed rank or current-view field.
      const rankRunId = "verify-rank-001";
      await seed(rankRunId);
      const basic = basicUid(rankRunId);
      await firestore.doc(`leaderboardUserRanks/${basic}_monthly_2026-07`).update({ score: 1 });

      // When: the tampered rank is read back.
      // Then: its expected score contract fails.
      await assert.rejects(verify(rankRunId), /(?:snapshot|rank) integrity/);

      await clearLeaderboardCollections(firestore);
      const viewRunId = "verify-view-001";
      await seed(viewRunId);
      await firestore.doc(`leaderboardCurrentViews/${basicUid(viewRunId)}`).update({ regionId: "tampered" });

      // When: the tampered current view is read back.
      // Then: its exact region contract fails.
      await assert.rejects(verify(viewRunId), /current view integrity/);
    });

    it("rejects a rank targeting a seeded snapshot with a wrong period and build", async () => {
      // Given: a malformed foreign rank that points at a target snapshot but is outside the target period.
      const runId = "verify-cross-period-rank-001";
      await seed(runId);
      const source = await firestore.doc(`leaderboardUserRanks/${basicUid(runId)}_monthly_2026-07`).get();
      await firestore.doc("leaderboardUserRanks/tampered-owner_monthly_2026-06").set({
        ...source.data(),
        ownerUid: "tampered-owner",
        periodKey: "2026-06",
        buildId: "tampered-build",
      });

      // When: the selected run is read back.
      // Then: every rank targeting its snapshots is checked, including the malformed foreign rank.
      await assert.rejects(verify(runId), /snapshot integrity/);
    });

    it("rejects tampered snapshot entries, build identity, and ordering", async () => {
      // Given: a seeded snapshot whose public entry no longer matches its rank projection.
      const contentsRunId = "verify-snapshot-001";
      await seed(contentsRunId);
      const snapshotRef = firestore.doc("leaderboardSnapshots/monthly_jurong-east_tier_01_2026-07");
      const snapshot = await snapshotRef.get();
      const topEntries = snapshot.get("topEntries");
      if (!Array.isArray(topEntries)) throw new Error("expected snapshot entries");
      await snapshotRef.update({ topEntries: [{ ...topEntries[0], publicAlias: "Tampered Alias" }, ...topEntries.slice(1)] });

      // When: the snapshot is verified.
      // Then: rank/snapshot entry parity fails.
      await assert.rejects(verify(contentsRunId), /snapshot integrity/);

      await clearLeaderboardCollections(firestore);
      const buildRunId = "verify-build-001";
      await seed(buildRunId);
      await snapshotRef.update({ buildId: "tampered-build" });
      await assert.rejects(verify(buildRunId), /snapshot bounds/);

      await clearLeaderboardCollections(firestore);
      const orderRunId = "verify-order-001";
      await seed(orderRunId);
      const orderedSnapshot = await snapshotRef.get();
      const orderedEntries = orderedSnapshot.get("topEntries");
      if (!Array.isArray(orderedEntries)) throw new Error("expected snapshot entries");
      await snapshotRef.update({ topEntries: [...orderedEntries].reverse() });
      await assert.rejects(verify(orderRunId), /snapshot ordering/);
    });
  },
);

function seed(runId: string): Promise<Record<string, unknown>> {
  return runSeedCommand(command(runId, "--seed", "--refresh"));
}

function verify(runId: string): Promise<Record<string, unknown>> {
  return runSeedCommand(command(runId, "--verify"));
}

function command(runId: string, ...actions: readonly string[]): readonly string[] {
  return ["--project", "runiac-functions-test", "--period", "2026-07", "--run-id", runId, "--region-id", "jurong-east", "--users-per-region", "100", ...actions];
}

function readResult(result: Record<string, unknown>, key: string): unknown {
  const verifyResult = result["verify"];
  return typeof verifyResult === "object" && verifyResult !== null ? Reflect.get(verifyResult, key) : undefined;
}

function basicUid(runId: string): string {
  return `lbmock_${runId}_jurong-east_001`;
}

function premiumUid(runId: string): string {
  return `lbmock_${runId}_jurong-east_100`;
}

function rankNumber(value: unknown): number {
  if (typeof value !== "string" || !/^#[1-9]\d*$/.test(value)) throw new Error("expected rank label");
  return Number(value.slice(1));
}

function entryValue(entry: unknown, key: string): unknown {
  return typeof entry === "object" && entry !== null ? Reflect.get(entry, key) : undefined;
}

async function writeRealContributor(firestore: Firestore): Promise<void> {
  await Promise.all([
    firestore.doc("users/real-runner-001").set({ subscriptionStatus: "basic" }),
    firestore.doc("userProfiles/real-runner-001").set({ nickname: "Real Runner", locationLabel: "Jurong East, Singapore", divisionKey: "tier_01", level: 1 }),
    firestore.doc("leaderboardContributions/real-runner-001_monthly_2026-07").set({ schemaVersion: 2, ownerUid: "real-runner-001", publicAlias: "Real Runner", regionId: "jurong-east", regionLabel: "Jurong East", planningAreaName: "JURONG EAST", planningAreaCode: "JE", planningRegionCode: "WR", divisionKey: "tier_01", divisionLabel: "Iron League", levelLabel: "Level 1", periodType: "monthly", periodKey: "2026-07", timezone: "Asia/Singapore", scoreXp: 50, eligible: true, eligibilityReason: "eligible_basic_awarded_xp", lastProgressionAt: "2026-07-10T00:00:00.000Z", sourceProgressionEventIds: ["real-event-001"] }),
  ]);
  await runSeedCommand(["--project", "runiac-functions-test", "--period", "2026-07", "--run-id", "verify-full-001", "--region-id", "jurong-east", "--users-per-region", "100", "--refresh"]);
}

async function clearLeaderboardCollections(firestore: Firestore): Promise<void> {
  for (const name of ["users", "userProfiles", "leaderboardContributions", "leaderboardSnapshots", "leaderboardUserRanks", "leaderboardCurrentViews", "leaderboardPeriods", "leaderboardAggregationLocks", "leaderboardSeedRuns"]) {
    const documents = await firestore.collection(name).get();
    if (documents.empty) continue;
    const batch = firestore.batch();
    for (const document of documents.docs) batch.delete(document.ref);
    await batch.commit();
  }
}
