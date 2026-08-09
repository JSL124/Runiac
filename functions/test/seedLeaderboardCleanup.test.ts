import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { runSeedCommand } from "../src/leaderboard/seedLeaderboardMockData.js";

describe(
  "leaderboard seed cleanup safeguards",
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

    it("reports exact selected-run cleanup counts when previewing a verified fixture", async () => {
      await seedJurongEast(firestore, "preview-run-001");

      const preview = await runSeedCommand(commandFor("preview-run-001", "--preview-cleanup"));

      assert.equal(preview["status"], "ready");
      assert.equal(preview["sourceDocumentCount"], 300);
      assert.equal(preview["rankDocumentCount"], 99);
      assert.equal(preview["currentViewDocumentCount"], 99);
      assert.equal(typeof preview["cleanupInventoryFingerprint"], "string");
    });

    it("blocks cleanup preview when the manifest period does not match the exact run", async () => {
      await seedJurongEast(firestore, "mismatch-run-001");
      await firestore.doc("leaderboardSeedRuns/mismatch-run-001").update({ periodKey: "2026-08" });

      const preview = await runSeedCommand(commandFor("mismatch-run-001", "--preview-cleanup"));

      assert.equal(preview["status"], "blocked");
      assert.ok(Array.isArray(preview["issues"]));
      assert.ok(
        preview["issues"].some(
          (issue) =>
            typeof issue === "object" &&
            issue !== null &&
            Reflect.get(issue, "code") === "manifest_period_mismatch",
        ),
      );
    });

    it("leaves a target run uncleaned when the monthly refresh lock is active", async () => {
      await seedJurongEast(firestore, "locked-run-001");
      await firestore.doc("leaderboardAggregationLocks/monthly_2026-07").set({ status: "running" });

      await assert.rejects(
        runSeedCommand([
          ...commandFor("locked-run-001", "--cleanup"),
          "--confirm-cleanup",
          "locked-run-001",
        ]),
        /active leaderboard refresh/,
      );

      assert.equal(
        (await firestore.doc("leaderboardSeedRuns/locked-run-001").get()).get("status"),
        "seeded",
      );
    });

    it("cleans a verified manifest without relaxing its verification safeguards", async () => {
      // Given: a fully verified seed manifest.
      const runId = "verified-cleanup-run-001";
      await seedJurongEast(firestore, runId);
      await runSeedCommand(commandFor(runId, "--verify"));

      // When: its confirmed cleanup is run.
      await runSeedCommand([
        ...commandFor(runId, "--cleanup"),
        "--confirm-cleanup",
        runId,
      ]);

      // Then: its terminal state is cleaned.
      assert.equal((await firestore.doc(`leaderboardSeedRuns/${runId}`).get()).get("status"), "cleaned");
    });

    it("blocks cleanup preview when a prefixed rank does not belong to its mock owner", async () => {
      await seedJurongEast(firestore, "rank-owner-run-001");
      const rank = await firestore
        .collection("leaderboardUserRanks")
        .where("periodKey", "==", "2026-07")
        .limit(1)
        .get();
      const document = rank.docs[0];
      assert.ok(document !== undefined);
      await document.ref.update({ ownerUid: "real-runner-001" });

      const preview = await runSeedCommand(commandFor("rank-owner-run-001", "--preview-cleanup"));

      assert.equal(preview["status"], "blocked");
      assert.ok(
        Array.isArray(preview["issues"]) &&
          preview["issues"].some(
            (issue) =>
              typeof issue === "object" &&
              issue !== null &&
              Reflect.get(issue, "code") === "projection_owner_or_period_mismatch",
          ),
      );
    });

    it("resumes a cleanup_pending run when only a strict subset of its exact candidates remains", async () => {
      // Given: a prior cleanup recorded its pending state before deleting one candidate from each collection.
      const runId = "cleanup-pending-subset-run-001";
      await seedJurongEast(firestore, runId);
      await deleteOneCandidateFromEachCollection(firestore, runId);
      await firestore.doc(`leaderboardSeedRuns/${runId}`).update({
        status: "cleanup_pending",
        cleanupExpectedCandidateCounts: expectedCleanupCandidateCounts,
        cleanupExpectedDocumentCount: 498,
      });

      // When: the exact same cleanup command is retried.
      const result = await runSeedCommand([
        ...commandFor(runId, "--cleanup"),
        "--confirm-cleanup",
        runId,
      ]);

      // Then: the remaining safe subset is deleted and the run reaches its terminal state.
      assert.equal((await firestore.doc(`leaderboardSeedRuns/${runId}`).get()).get("status"), "cleaned");
      assert.equal((await firestore.collection("users").where("mockSeedRunId", "==", runId).get()).size, 0);
      const cleanup = result["cleanup"];
      assert.ok(typeof cleanup === "object" && cleanup !== null);
      assert.equal(Reflect.get(cleanup, "deletedDocumentCount"), 498);
    });

    it("finishes a cleanup_pending run after a prior cleanup deleted every candidate before status update", async () => {
      // Given: all candidate deletes completed but the prior refresh/status transition did not.
      const runId = "cleanup-pending-empty-run-001";
      await seedJurongEast(firestore, runId);
      await deleteAllCandidates(firestore, runId);
      await firestore.doc(`leaderboardSeedRuns/${runId}`).update({
        status: "cleanup_pending",
        cleanupExpectedCandidateCounts: expectedCleanupCandidateCounts,
        cleanupExpectedDocumentCount: 498,
      });

      // When: cleanup is retried.
      const result = await runSeedCommand([
        ...commandFor(runId, "--cleanup"),
        "--confirm-cleanup",
        runId,
      ]);

      // Then: refresh and the terminal manifest update complete without reintroducing mock data.
      assert.equal((await firestore.doc(`leaderboardSeedRuns/${runId}`).get()).get("status"), "cleaned");
      assert.equal((await firestore.collection("users").where("mockSeedRunId", "==", runId).get()).size, 0);
      const cleanup = result["cleanup"];
      assert.ok(typeof cleanup === "object" && cleanup !== null);
      assert.equal(Reflect.get(cleanup, "deletedDocumentCount"), 498);
    });

    it("allows a cleaned manifest with no remaining mock markers in inventory", async () => {
      await seedJurongEast(firestore, "cleaned-audit-run-001");
      await runSeedCommand([
        ...commandFor("cleaned-audit-run-001", "--cleanup"),
        "--confirm-cleanup",
        "cleaned-audit-run-001",
      ]);

      const inventory = await runSeedCommand([
        "--project",
        "runiac-functions-test",
        "--firebase-cli-auth",
        "--inventory",
      ]);

      assert.equal(inventory["status"], "ready");
      assert.ok(Array.isArray(inventory["runs"]));
      assert.equal(inventory["runs"].length, 1);
      assert.equal(Reflect.get(inventory["runs"][0], "uidPrefix"), "lbmock_cleaned-audit-run-001_");
      assert.deepEqual(Reflect.get(inventory["runs"][0], "candidateCounts"), {
        users: 0,
        userProfiles: 0,
        leaderboardContributions: 0,
        leaderboardUserRanks: 0,
        leaderboardCurrentViews: 0,
      });
      assert.deepEqual(inventory["issues"], []);
    });

  },
);

async function seedJurongEast(firestore: Firestore, runId: string): Promise<void> {
  await runSeedCommand(commandFor(runId, "--seed", "--refresh"));
  await firestore.doc("users/real-runner-001").set({ subscriptionStatus: "basic" });
}

function commandFor(runId: string, ...actions: readonly string[]): readonly string[] {
  return [
    "--project",
    "runiac-functions-test",
    "--period",
    "2026-07",
    "--run-id",
    runId,
    "--region-id",
    "jurong-east",
    "--users-per-region",
    "100",
    ...actions,
  ];
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

async function deleteOneCandidateFromEachCollection(firestore: Firestore, runId: string): Promise<void> {
  const candidates = await candidateSnapshots(firestore, runId);
  const batch = firestore.batch();
  for (const candidate of candidates) {
    const document = candidate.docs[0];
    assert.ok(document !== undefined);
    batch.delete(document.ref);
  }
  await batch.commit();
}

async function deleteAllCandidates(firestore: Firestore, runId: string): Promise<void> {
  const candidates = await candidateSnapshots(firestore, runId);
  const batch = firestore.batch();
  for (const candidate of candidates) {
    for (const document of candidate.docs) {
      batch.delete(document.ref);
    }
  }
  await batch.commit();
}

function candidateSnapshots(firestore: Firestore, runId: string) {
  const uidPrefix = `lbmock_${runId}_`;
  return Promise.all([
    firestore.collection("users").where("mockSeedRunId", "==", runId).get(),
    firestore.collection("userProfiles").where("mockSeedRunId", "==", runId).get(),
    firestore.collection("leaderboardContributions").where("mockSeedRunId", "==", runId).get(),
    firestore.collection("leaderboardUserRanks").where("periodKey", "==", "2026-07").get(),
    firestore.collection("leaderboardCurrentViews").get().then((snapshot) => ({
      docs: snapshot.docs.filter((document) => document.id.startsWith(uidPrefix)),
    })),
  ]);
}

// Premium parity: the one zero-score record per region is dropped by the
// planner, so it produces neither a rank nor a current view — both projection
// counts are now 99, not 99 and 100.
const expectedCleanupCandidateCounts = {
  users: 100,
  userProfiles: 100,
  leaderboardContributions: 100,
  leaderboardUserRanks: 99,
  leaderboardCurrentViews: 99,
} as const;
