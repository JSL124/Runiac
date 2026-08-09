import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { getApps } from "firebase-admin/app";
import { parseSeedCommand } from "../src/leaderboard/leaderboardSeedArguments.js";
import { generateMockLeaderboardDataset } from "../src/leaderboard/leaderboardMockDataset.js";
import { productionOrEmulatorFirestore } from "../src/leaderboard/leaderboardSeedFirestore.js";
import { runSeedCommand } from "../src/leaderboard/seedLeaderboardMockData.js";

describe("leaderboard mock dataset", () => {
  it("preserves the default all-area dataset shape", () => {
    const dataset = generateMockLeaderboardDataset({ runId: "test-seed-001", periodKey: "2026-07" });

    assert.equal(dataset.regionCount, 37);
    assert.equal(dataset.usersPerRegion, 100);
    assert.equal(dataset.records.length, 3_700);
    assert.equal(new Set(dataset.records.map((record) => record.uid)).size, 3_700);
    assert.equal(new Set(dataset.records.map((record) => record.profile["locationLabel"])).size, 37);
    assert.equal(dataset.records.filter((record) => record.user["subscriptionStatus"] === "premium").length, 37);
  });

  it("generates 100 distinct safe synthetic profiles for a requested planning area", () => {
    const dataset = generateMockLeaderboardDataset({
      runId: "jurong-demo-001",
      periodKey: "2026-07",
      usersPerRegion: 100,
      regionId: "jurong-east",
    });

    assert.equal(dataset.regionCount, 1);
    assert.equal(dataset.usersPerRegion, 100);
    assert.equal(dataset.records.length, 100);
    assert.equal(new Set(dataset.records.map((record) => record.uid)).size, 100);
    const publicAliases = dataset.records.map(
      (record) => record.contribution.publicAlias,
    );
    assert.equal(new Set(publicAliases).size, 100);
    assert.ok(
      publicAliases.every(
        (alias) =>
          /^[A-Z][a-z]+ [A-Z][a-z]+$/.test(alias) &&
          !alias.startsWith("Mock "),
      ),
    );
    assert.equal(
      dataset.records.filter(
        (record) => record.user["subscriptionStatus"] === "basic",
      ).length,
      99,
    );
    assert.equal(
      dataset.records.filter(
        (record) => record.user["subscriptionStatus"] === "premium",
      ).length,
      1,
    );
    const basicContributions = dataset.records
      .filter((record) => record.user["subscriptionStatus"] === "basic")
      .map((record) => record.contribution);
    assert.equal(basicContributions.length, 99);
    assert.ok(
      basicContributions.every(
        (contribution) =>
          contribution.scoreXp > 0 &&
          contribution.eligible === true &&
          contribution.eligibilityReason === "mock_seed_basic_awarded_xp",
      ),
    );
    const premiumContributions = dataset.records
      .filter((record) => record.user["subscriptionStatus"] === "premium")
      .map((record) => record.contribution);
    assert.equal(premiumContributions.length, 1);
    const premiumContribution = premiumContributions.at(0);
    if (premiumContribution === undefined) {
      throw new Error("expected one Premium mock contribution");
    }
    assert.equal(premiumContribution.scoreXp, 0);
    assert.equal(premiumContribution.eligible, false);
    // Premium parity: the tier is not what keeps this record off the board —
    // its zero score is.
    assert.equal(premiumContribution.eligibilityReason, "ineligible_zero_score");
    assert.deepEqual(
      dataset.records.map((record) => record.contribution.divisionKey),
      [
        ...Array.from({ length: 15 }, () => "tier_01"),
        ...Array.from({ length: 5 }, () => "tier_02"),
        ...Array.from({ length: 10 }, () => "tier_03"),
        ...Array.from({ length: 10 }, () => "tier_04"),
        ...Array.from({ length: 10 }, () => "tier_05"),
        ...Array.from({ length: 10 }, () => "tier_06"),
        ...Array.from({ length: 10 }, () => "tier_07"),
        ...Array.from({ length: 10 }, () => "tier_08"),
        ...Array.from({ length: 10 }, () => "tier_09"),
        ...Array.from({ length: 10 }, () => "tier_10"),
      ],
    );
    assert.ok(
      dataset.records.every(
        (record) =>
          record.profile["locationLabel"] === "Jurong East, Singapore" &&
          record.contribution["regionId"] === "jurong-east" &&
          record.profile["isMockData"] === true &&
          record.profile["mockSeedRunId"] === "jurong-demo-001",
      ),
    );
    assert.equal(
      new Set(
        dataset.records.map((record) =>
          JSON.stringify([
            record.profile["displayName"],
            record.profile["fullName"],
            record.profile["nickname"],
            record.profile["nicknameKey"],
          ]),
        ),
      ).size,
      100,
    );
    assert.equal(
      new Set(
        dataset.records.map((record) =>
          JSON.stringify([
            record.profile["dateOfBirth"],
            record.profile["ageYears"],
            record.profile["weightKg"],
            record.profile["fitnessLevel"],
            record.profile["goals"],
            record.profile["availability"],
            record.profile["planCautiousness"],
            record.profile["healthSafetyReadiness"],
          ]),
        ),
      ).size,
      100,
    );
    assert.ok(
      dataset.records.every(
        (record) =>
          typeof record.profile["dateOfBirth"] === "string" &&
          typeof record.profile["ageYears"] === "number" &&
          typeof record.profile["weightKg"] === "number" &&
          typeof record.profile["fitnessLevel"] === "string" &&
          Array.isArray(record.profile["goals"]) &&
          typeof record.profile["availability"] === "object" &&
          typeof record.profile["planCautiousness"] === "string" &&
          hasSafeHealthReadiness(record.profile["healthSafetyReadiness"]) &&
          !Object.hasOwn(record.profile, "email") &&
          !Object.hasOwn(record.profile, "route") &&
          !Object.hasOwn(record.profile, "gps"),
      ),
    );
  });

  it("rejects a synthetic dataset request for an unsupported planning area", () => {
    assert.throws(
      () =>
        generateMockLeaderboardDataset({
          runId: "invalid-area-001",
          periodKey: "2026-07",
          regionId: "sentosa",
        }),
      /unsupported regionId: sentosa/,
    );
  });

  it("rejects unknown and duplicate seed CLI options", () => {
    // Given: CLI arguments outside the documented seed command contract.
    const unknownOption = ["--project", "runiac-functions-test", "--unknown"];
    const duplicateOption = [
      "--project",
      "runiac-functions-test",
      "--project",
      "runiac-functions-test",
      "--period",
      "2026-07",
      "--run-id",
      "duplicate-option-001",
      "--dry-run",
    ];

    // When: the command parser receives those arguments.
    // Then: it rejects both instead of silently accepting ambiguous input.
    assert.throws(() => parseSeedCommand(unknownOption), /unknown option/);
    assert.throws(() => parseSeedCommand(duplicateOption), /duplicate option/);
  });

  it("requires the production Jurong East scope and repeated mutation confirmation", async () => {
    await withFirestoreEmulatorHost(undefined, async () => {
      await assert.rejects(
        runSeedCommand(["--project", "runiac-fypp", "--period", "2026-08", "--run-id", "production-scope-001", "--region-id", "jurong-east", "--users-per-region", "100", "--dry-run"]),
        /production dataset commands require/,
      );
      await assert.rejects(
        runSeedCommand(["--project", "runiac-fypp", "--period", "2026-07", "--run-id", "production-confirm-001", "--region-id", "jurong-east", "--users-per-region", "100", "--confirm-project", "runiac-fypp", "--firebase-cli-auth", "--seed"]),
        /confirm-period 2026-07/,
      );
    });
  });

  it("requires Firebase CLI authentication and exact cleanup scope for production mutations", async () => {
    // Given: a fully scoped production seed request without explicit Firebase CLI auth.
    await withFirestoreEmulatorHost(undefined, () => {
      // When: the production command is parsed.
      assert.throws(
        () =>
          parseSeedCommand([
            "--project", "runiac-fypp", "--period", "2026-07",
            "--run-id", "production-auth-001", "--region-id", "jurong-east",
            "--users-per-region", "100", "--confirm-project", "runiac-fypp",
            "--confirm-period", "2026-07", "--confirm-region", "jurong-east",
            "--confirm-users", "100", "--seed",
          ]),
        /--firebase-cli-auth/,
      );
      // Then: parsing rejects ambient ADC and a legacy cleanup with a narrower region.
      assert.throws(
        () =>
          parseSeedCommand([
            "--project", "runiac-fypp", "--period", "2025-12",
            "--run-id", "legacy-cleanup-001", "--users-per-region", "100",
            "--confirm-project", "runiac-fypp", "--confirm-cleanup", "legacy-cleanup-001",
            "--confirm-period", "2025-12", "--confirm-region", "jurong-east",
            "--confirm-users", "100", "--firebase-cli-auth", "--cleanup",
          ]),
        /confirm-region all/,
      );
      assert.doesNotThrow(() => parseSeedCommand(["--project", "runiac-fypp", "--period", "2025-12", "--run-id", "legacy-cleanup-001", "--users-per-region", "100", "--confirm-project", "runiac-fypp", "--confirm-cleanup", "legacy-cleanup-001", "--confirm-period", "2025-12", "--confirm-region", "all", "--confirm-users", "100", "--confirm-inventory", "sha256:current-preview", "--replacement-run-id", "replacement-run-001", "--firebase-cli-auth", "--cleanup"]));
    });
  });

  it("creates a project-scoped Firestore app instead of reusing another project app", async () => {
    // Given: two emulator projects in the same Node process.
    await withFirestoreEmulatorHost("127.0.0.1:8080", () => {
      // When: each project requests its Firestore client.
      productionOrEmulatorFirestore("leaderboard-seed-project-one");
      productionOrEmulatorFirestore("leaderboard-seed-project-two");

      // Then: each client is backed by an app created for that exact project.
      for (const projectId of ["leaderboard-seed-project-one", "leaderboard-seed-project-two"]) {
        assert.ok(getApps().some((app) => app.name === `leaderboard-seed:${projectId}` && app.options.projectId === projectId));
      }
    });
  });
});

async function withFirestoreEmulatorHost<T>(
  host: string | undefined,
  action: () => T | Promise<T>,
): Promise<T> {
  const previousHost = process.env["FIRESTORE_EMULATOR_HOST"];
  if (host === undefined) delete process.env["FIRESTORE_EMULATOR_HOST"];
  else process.env["FIRESTORE_EMULATOR_HOST"] = host;
  try { return await action(); }
  finally {
    if (previousHost === undefined) delete process.env["FIRESTORE_EMULATOR_HOST"];
    else process.env["FIRESTORE_EMULATOR_HOST"] = previousHost;
  }
}

function hasSafeHealthReadiness(value: unknown): boolean {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const entries = Object.entries(value);
  return (
    entries.some(([key, item]) => key === "comfort" && item === "ready") &&
    entries.some(
      ([key, item]) =>
        key === "activitySymptoms" &&
        Array.isArray(item) &&
        item.length === 1 &&
        item[0] === "none",
    )
  );
}
