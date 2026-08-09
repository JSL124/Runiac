import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { runSeedCommand } from "../src/leaderboard/seedLeaderboardMockData.js";

describe("leaderboard seed safety", { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined }, () => {
  let firestore: Firestore;

  before(() => {
    if (getApps().length === 0) initializeApp({ projectId: "runiac-functions-test" });
    firestore = getFirestore();
  });

  beforeEach(async () => {
    await clearCollections(firestore, ["users", "userProfiles", "leaderboardContributions", "leaderboardSnapshots", "leaderboardUserRanks", "leaderboardCurrentViews", "leaderboardPeriods", "leaderboardAggregationLocks", "leaderboardSeedRuns"]);
  });

  it("preserves a non-marker source collision instead of overwriting it", async () => {
    // Given: a real document using a future mock source identifier.
    const uid = "lbmock_collision-run-001_jurong-east_001";
    await firestore.doc(`users/${uid}`).set({ subscriptionStatus: "basic", protected: true });

    // When: the seed command attempts to create that run.
    await assert.rejects(runSeedCommand(commandFor("collision-run-001", "--seed")), /seed collision/);

    // Then: the non-marker document is unchanged.
    assert.deepEqual((await firestore.doc(`users/${uid}`).get()).data(), { subscriptionStatus: "basic", protected: true });
  });

  it("fails closed before creating a seed manifest when the atomic batch would exceed 500 writes", async () => {
    // Given: a dataset whose manifest plus source writes exceed Firestore's atomic batch limit.
    const runId = "atomic-bound-run-001";
    const command = [
      "--project", "runiac-functions-test",
      "--period", "2026-07",
      "--run-id", runId,
      "--region-id", "jurong-east",
      "--users-per-region", "167",
      "--seed",
    ];

    // When: seeding is attempted.
    await assert.rejects(runSeedCommand(command), /atomic seed batch limit/);

    // Then: no retry-blocking marker or synthetic source document was created.
    assert.equal((await firestore.doc(`leaderboardSeedRuns/${runId}`).get()).exists, false);
    assert.equal((await firestore.collection("users").where("mockSeedRunId", "==", runId).get()).size, 0);
  });

  it("stops before verification when a refresh lease cannot be acquired", async () => {
    // Given: seeded sources and a lock owned by another refresh.
    await runSeedCommand(commandFor("blocked-refresh-run-001", "--seed"));
    await firestore.doc("leaderboardAggregationLocks/monthly_2026-07").set({ status: "running", leaseExpiresAt: "2099-01-01T00:00:00.000Z" });

    // When: refresh and verification are requested in one command.
    await assert.rejects(runSeedCommand(commandFor("blocked-refresh-run-001", "--refresh", "--verify")), /refresh did not complete/);

    // Then: the manifest was not advanced by verification.
    assert.equal((await firestore.doc("leaderboardSeedRuns/blocked-refresh-run-001").get()).get("status"), "seeded");
  });

  it("cleans a legacy all-region manifest without applying the Jurong East production bind", async () => {
    const legacyCommand = ["--project", "runiac-functions-test", "--period", "2026-07", "--run-id", "legacy-scope-run-001", "--users-per-region", "1"];
    await runSeedCommand([...legacyCommand, "--seed", "--refresh"]);
    await firestore.doc("leaderboardSeedRuns/legacy-scope-run-001").update({ regionIds: FieldValue.delete() });

    await runSeedCommand([...legacyCommand, "--confirm-cleanup", "legacy-scope-run-001", "--cleanup"]);

    const manifest = await firestore.doc("leaderboardSeedRuns/legacy-scope-run-001").get();
    assert.equal(manifest.get("status"), "cleaned");
    assert.equal(manifest.get("regionCount"), 37);
    assert.equal((await firestore.collection("users").where("mockSeedRunId", "==", "legacy-scope-run-001").get()).size, 0);
  });
});

function commandFor(runId: string, ...actions: readonly string[]): readonly string[] {
  return ["--project", "runiac-functions-test", "--period", "2026-07", "--run-id", runId, "--region-id", "jurong-east", "--users-per-region", "100", ...actions];
}

async function clearCollections(firestore: Firestore, collections: readonly string[]): Promise<void> {
  for (const collection of collections) {
    const snapshot = await firestore.collection(collection).get();
    if (snapshot.empty) continue;
    const batch = firestore.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
  }
}
