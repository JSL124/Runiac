import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { runSeedCommand } from "../src/leaderboard/seedLeaderboardMockData.js";

describe("leaderboard seed inventory", { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined }, () => {
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
      "leaderboardUserRanks",
      "leaderboardCurrentViews",
      "leaderboardSeedRuns",
    ]);
  });

  it("reports orphan markers as blocked without exposing a document identifier", async () => {
    await writeMarkerDocuments(firestore, "known-run-001");
    await firestore.doc("leaderboardSeedRuns/known-run-001").set({
      runId: "known-run-001",
      projectId: "runiac-functions-test",
      periodKey: "2026-07",
      profileCount: 1,
      regionCount: 1,
      status: "verified",
    });
    await firestore.doc("leaderboardCurrentViews/lbmock_known-run-001_jurong-east_001").set({
      ownerUid: "lbmock_known-run-001_jurong-east_001",
      periodKey: "2026-07",
    });
    await writeMarkerDocuments(firestore, "orphan-run-001");

    const result = await runSeedCommand([
      "--project",
      "runiac-functions-test",
      "--firebase-cli-auth",
      "--inventory",
    ]);

    assert.equal(result["status"], "blocked");
    assert.deepEqual(result["issues"], [
      { code: "orphan_markers", collection: "leaderboardSeedRuns", runId: "orphan-run-001", count: 1 },
    ]);
    assert.ok(Array.isArray(result["runs"]));
    assert.equal(Reflect.get(result["runs"][0], "ranks"), 0);
    assert.equal(Reflect.get(result["runs"][0], "currentViews"), 1);
    const orphanRun = inventoryRun(result, "orphan-run-001");
    const cleanupInventoryFingerprint = Reflect.get(orphanRun, "cleanupInventoryFingerprint");
    if (typeof cleanupInventoryFingerprint !== "string") {
      throw new Error("inventory run must include cleanupInventoryFingerprint");
    }
    assert.equal(cleanupInventoryFingerprint.includes("lbmock_orphan-run-001_jurong-east_001"), false);
  });

  it("reports a projection-only mock prefix as a blocked orphan run", async () => {
    const ownerUid = "lbmock_projection-run-001_jurong-east_001";
    await firestore.doc(`leaderboardUserRanks/${ownerUid}_monthly_2026-07`).set({
      ownerUid,
      periodKey: "2026-07",
    });

    const result = await runSeedCommand([
      "--project",
      "runiac-functions-test",
      "--firebase-cli-auth",
      "--inventory",
    ]);

    assert.equal(result["status"], "blocked");
    assert.ok(Array.isArray(result["issues"]));
    assert.ok(
      result["issues"].some(
        (issue) =>
          typeof issue === "object" &&
          issue !== null &&
          Reflect.get(issue, "code") === "orphan_markers" &&
          Reflect.get(issue, "runId") === "projection-run-001" &&
          !Object.hasOwn(issue, "documentId"),
      ),
    );
    assert.ok(Array.isArray(result["runs"]));
    assert.equal(Reflect.get(result["runs"][0], "ranks"), 1);
  });

  it("keeps cleanup inventory fingerprints stable for the same inventory and changes them when candidates change", async () => {
    const runId = "fingerprint-run-001";
    await writeMarkerDocuments(firestore, runId);
    await firestore.doc(`leaderboardSeedRuns/${runId}`).set({
      runId,
      projectId: "runiac-functions-test",
      periodKey: "2026-07",
      profileCount: 1,
      regionCount: 1,
      usersPerRegion: 1,
      status: "verified",
    });
    await firestore.doc(`leaderboardCurrentViews/lbmock_${runId}_jurong-east_001`).set({
      ownerUid: `lbmock_${runId}_jurong-east_001`,
      periodKey: "2026-07",
    });

    const firstResult = await inventory();
    const secondResult = await inventory();

    const firstFingerprint = cleanupInventoryFingerprint(firstResult, runId);
    assert.equal(firstFingerprint, cleanupInventoryFingerprint(secondResult, runId));

    await firestore.doc("users/lbmock_fingerprint-run-001_jurong-east_002").set({
      isMockData: true,
      mockSeedRunId: runId,
    });

    const changedResult = await inventory();
    assert.notEqual(firstFingerprint, cleanupInventoryFingerprint(changedResult, runId));
    assert.equal(changedResult["status"], "blocked");
  });

  async function inventory(): Promise<Record<string, unknown>> {
    return runSeedCommand([
      "--project",
      "runiac-functions-test",
      "--firebase-cli-auth",
      "--inventory",
    ]);
  }
});

function inventoryRun(result: Record<string, unknown>, runId: string): Record<string, unknown> {
  const runs = result["runs"];
  if (!Array.isArray(runs)) throw new Error("inventory result must include runs");
  const run = runs.find((candidate) =>
    typeof candidate === "object" &&
    candidate !== null &&
    Reflect.get(candidate, "runId") === runId,
  );
  if (typeof run !== "object" || run === null) throw new Error(`inventory result must include ${runId}`);
  return run;
}

function cleanupInventoryFingerprint(result: Record<string, unknown>, runId: string): string {
  const value = Reflect.get(inventoryRun(result, runId), "cleanupInventoryFingerprint");
  if (typeof value !== "string") throw new Error("inventory run must include cleanupInventoryFingerprint");
  return value;
}

async function writeMarkerDocuments(firestore: Firestore, runId: string): Promise<void> {
  const uid = `lbmock_${runId}_jurong-east_001`;
  const marker = { isMockData: true, mockSeedRunId: runId };
  await Promise.all([
    firestore.doc(`users/${uid}`).set(marker),
    firestore.doc(`userProfiles/${uid}`).set(marker),
    firestore.doc(`leaderboardContributions/${uid}_monthly_2026-07`).set({ ...marker, ownerUid: uid, periodKey: "2026-07" }),
  ]);
}

async function clearCollections(firestore: Firestore, collectionNames: readonly string[]): Promise<void> {
  for (const collectionName of collectionNames) {
    const snapshot = await firestore.collection(collectionName).get();
    const batch = firestore.batch();
    for (const document of snapshot.docs) {
      batch.delete(document.ref);
    }
    await batch.commit();
  }
}
