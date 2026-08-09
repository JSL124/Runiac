import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { parseSeedCommand } from "../src/leaderboard/leaderboardSeedArguments.js";
import { runSeedCommand } from "../src/leaderboard/seedLeaderboardMockData.js";

describe("leaderboard production cleanup authorization", () => {
  it("requires both the inventory fingerprint and replacement run before Firestore access", () => {
    // Given: an otherwise exact production cleanup command.
    const originalEmulatorHost = process.env["FIRESTORE_EMULATOR_HOST"];
    delete process.env["FIRESTORE_EMULATOR_HOST"];

    try {
      // When / Then: each missing production-only acknowledgement is rejected by parsing.
      assert.throws(() => parseSeedCommand(productionCleanupCommand()), /--confirm-inventory/);
      assert.throws(
        () => parseSeedCommand([...productionCleanupCommand(), "--confirm-inventory", "sha256:current"]),
        /--replacement-run-id/,
      );
    } finally {
      if (originalEmulatorHost === undefined) delete process.env["FIRESTORE_EMULATOR_HOST"];
      else process.env["FIRESTORE_EMULATOR_HOST"] = originalEmulatorHost;
    }
  });
});

describe("leaderboard cleanup replacement authorization", { skip: process.env["FIRESTORE_EMULATOR_HOST"] === undefined }, () => {
  let firestore: Firestore;

  before(() => {
    if (getApps().length === 0) initializeApp({ projectId: "runiac-functions-test" });
    firestore = getFirestore();
  });

  beforeEach(async () => {
    await clearCollections(firestore, [
      "users", "userProfiles", "leaderboardContributions", "leaderboardSnapshots",
      "leaderboardUserRanks", "leaderboardCurrentViews", "leaderboardPeriods",
      "leaderboardAggregationLocks", "leaderboardSeedRuns",
    ]);
  });

  it("blocks an explicitly supplied unverified replacement without deleting the target", async () => {
    const targetRunId = "replacement-target-run-001";
    const replacementRunId = "replacement-unverified-run-001";
    await seedJurongEast(targetRunId);
    await seedJurongEast(replacementRunId);

    await assert.rejects(
      runSeedCommand([...cleanupCommand(targetRunId, await cleanupFingerprint(targetRunId)), "--replacement-run-id", replacementRunId]),
      /replacement manifest is not a verified Jurong East fixture/,
    );

    assert.equal((await firestore.doc(`leaderboardSeedRuns/${targetRunId}`).get()).get("status"), "seeded");
    assert.equal((await firestore.collection("users").where("mockSeedRunId", "==", targetRunId).get()).size, 100);
  });

  it("blocks a stale supplied inventory fingerprint before acquiring cleanup work", async () => {
    const targetRunId = "replacement-target-run-003";
    await seedJurongEast(targetRunId);

    await assert.rejects(
      runSeedCommand(cleanupCommand(targetRunId, "sha256:stale")),
      /cleanup inventory fingerprint does not match the current preview/,
    );

    assert.equal((await firestore.doc(`leaderboardSeedRuns/${targetRunId}`).get()).get("status"), "seeded");
    assert.equal((await firestore.collection("users").where("mockSeedRunId", "==", targetRunId).get()).size, 100);
  });

  it("permits cleanup with a verified distinct Jurong East replacement and current fingerprint", async () => {
    const targetRunId = "replacement-target-run-002";
    const replacementRunId = "replacement-verified-run-001";
    await seedJurongEast(targetRunId);
    await seedJurongEast(replacementRunId);
    await runSeedCommand(commandFor(replacementRunId, "--verify"));

    await runSeedCommand([
      ...cleanupCommand(targetRunId, await cleanupFingerprint(targetRunId)),
      "--replacement-run-id", replacementRunId,
    ]);

    assert.equal((await firestore.doc(`leaderboardSeedRuns/${targetRunId}`).get()).get("status"), "cleaned");
    assert.equal((await firestore.doc(`leaderboardSeedRuns/${replacementRunId}`).get()).get("status"), "verified");
  });

  async function seedJurongEast(runId: string): Promise<void> {
    await runSeedCommand(commandFor(runId, "--seed", "--refresh"));
  }

  async function cleanupFingerprint(runId: string): Promise<string> {
    const preview = await runSeedCommand(commandFor(runId, "--preview-cleanup"));
    const fingerprint = preview["cleanupInventoryFingerprint"];
    if (typeof fingerprint !== "string") throw new Error("preview must include cleanup inventory fingerprint");
    return fingerprint;
  }
});

function productionCleanupCommand(): readonly string[] {
  return [
    "--project", "runiac-fypp",
    "--period", "2026-07",
    "--run-id", "cleanup-target-001",
    "--region-id", "jurong-east",
    "--users-per-region", "100",
    "--firebase-cli-auth",
    "--confirm-project", "runiac-fypp",
    "--confirm-period", "2026-07",
    "--confirm-region", "jurong-east",
    "--confirm-users", "100",
    "--confirm-cleanup", "cleanup-target-001",
    "--cleanup",
  ];
}

function commandFor(runId: string, ...actions: readonly string[]): readonly string[] {
  return [
    "--project", "runiac-functions-test", "--period", "2026-07", "--run-id", runId,
    "--region-id", "jurong-east", "--users-per-region", "100", ...actions,
  ];
}

function cleanupCommand(runId: string, fingerprint: string): readonly string[] {
  return [
    ...commandFor(runId, "--cleanup"), "--confirm-cleanup", runId,
    "--confirm-inventory", fingerprint,
  ];
}

async function clearCollections(firestore: Firestore, collectionNames: readonly string[]): Promise<void> {
  for (const collectionName of collectionNames) {
    const snapshot = await firestore.collection(collectionName).get();
    if (snapshot.empty) continue;
    const batch = firestore.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
  }
}
