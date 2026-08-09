import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  CHALLENGE_CATALOG,
  CHALLENGE_TIER_IDS,
  buildChallengeRulesSnapshot,
  getChallengeCatalogEntry,
  isChallengeTierId,
} from "../src/challenge/challengeCatalog.js";
import {
  CHALLENGE_CATALOG_VERSION,
  type ChallengeTierId,
} from "../src/challenge/challengeTypes.js";

const MS_PER_DAY = 86_400_000;

// Exact contract table from challenge-distance-system.md (all values integer
// metres / integer durations). tuple: [difficulty, weeks, maxParticipants,
// maxInvitedFriends, soloTargetMeters, personalMinimumMeters].
const EXPECTED: Record<
  ChallengeTierId,
  readonly [string, number, number, number, number, number]
> = {
  "10K": ["Beginner", 1, 2, 1, 10_000, 3_000],
  "20K": ["Easy", 2, 2, 1, 20_000, 5_000],
  "42K": ["Normal", 3, 3, 2, 42_000, 7_000],
  "100K": ["Challenging", 4, 4, 3, 100_000, 13_000],
  "200K": ["Hard", 6, 5, 4, 200_000, 20_000],
  "250K": ["Hard+", 7, 5, 4, 250_000, 25_000],
  "300K": ["Very Hard", 8, 5, 4, 300_000, 30_000],
  "500K": ["Extreme", 9, 7, 6, 500_000, 36_000],
  "1000K": ["Legend", 14, 8, 7, 1_000_000, 63_000],
};

const EXPECTED_ENTRY_KEYS = [
  "tierId",
  "difficultyLabel",
  "durationDays",
  "durationMs",
  "maxParticipants",
  "maxInvitedFriends",
  "soloTargetMeters",
  "personalMinimumMeters",
].sort();

describe("challenge catalog version", () => {
  it("pins the versioned catalog constant", () => {
    assert.equal(CHALLENGE_CATALOG_VERSION, "challenge-distance-v1");
  });
});

describe("challenge catalog tier set", () => {
  it("declares all nine unique active tier ids in display order", () => {
    assert.deepEqual(CHALLENGE_TIER_IDS, [
      "10K",
      "20K",
      "42K",
      "100K",
      "200K",
      "250K",
      "300K",
      "500K",
      "1000K",
    ]);
    assert.equal(new Set(CHALLENGE_TIER_IDS).size, 9);
  });

  it("keys the catalog record by tier id (never a positional array)", () => {
    assert.ok(!Array.isArray(CHALLENGE_CATALOG));
    assert.deepEqual(Object.keys(CHALLENGE_CATALOG).sort(), [...CHALLENGE_TIER_IDS].sort());
  });
});

describe("challenge catalog exact values", () => {
  for (const tierId of CHALLENGE_TIER_IDS) {
    it(`matches the contract row for ${tierId}`, () => {
      const entry = getChallengeCatalogEntry(tierId);
      const [difficulty, weeks, maxParticipants, maxInvitedFriends, target, minimum] =
        EXPECTED[tierId];

      assert.equal(entry.tierId, tierId);
      assert.equal(entry.difficultyLabel, difficulty);
      assert.equal(entry.durationDays, weeks * 7);
      assert.equal(entry.durationMs, weeks * 7 * MS_PER_DAY);
      assert.equal(entry.maxParticipants, maxParticipants);
      assert.equal(entry.maxInvitedFriends, maxInvitedFriends);
      assert.equal(entry.soloTargetMeters, target);
      assert.equal(entry.personalMinimumMeters, minimum);
    });
  }

  it("invite cap is always max participants minus one", () => {
    for (const tierId of CHALLENGE_TIER_IDS) {
      const entry = getChallengeCatalogEntry(tierId);
      assert.equal(entry.maxInvitedFriends, entry.maxParticipants - 1);
    }
  });

  it("uses only integer metres and integer durations (no floating point)", () => {
    for (const tierId of CHALLENGE_TIER_IDS) {
      const entry = getChallengeCatalogEntry(tierId);
      for (const value of [
        entry.durationDays,
        entry.durationMs,
        entry.maxParticipants,
        entry.maxInvitedFriends,
        entry.soloTargetMeters,
        entry.personalMinimumMeters,
      ]) {
        assert.ok(Number.isInteger(value), `${tierId}: ${value} must be an integer`);
      }
    }
  });
});

describe("challenge catalog shape guards", () => {
  it("exposes no future/disabled/enabled flag on any entry", () => {
    const forbiddenKeys = ["future", "disabled", "enabled", "comingSoon", "active", "flag"];
    for (const tierId of CHALLENGE_TIER_IDS) {
      const entry = getChallengeCatalogEntry(tierId);
      assert.deepEqual(Object.keys(entry).sort(), EXPECTED_ENTRY_KEYS);
      for (const forbidden of forbiddenKeys) {
        assert.ok(
          !Object.prototype.hasOwnProperty.call(entry, forbidden),
          `${tierId} must not expose ${forbidden}`,
        );
      }
    }
  });

  it("recognises catalog tier ids and rejects unknown ids", () => {
    assert.ok(isChallengeTierId("10K"));
    assert.ok(isChallengeTierId("1000K"));
    assert.ok(!isChallengeTierId("5K"));
    assert.ok(!isChallengeTierId("toString"));
  });
});

describe("challenge rules snapshot", () => {
  it("snapshots catalog values with the team target equal to the tier target", () => {
    const snapshot = buildChallengeRulesSnapshot("100K");
    const entry = getChallengeCatalogEntry("100K");

    assert.equal(snapshot.tierId, "100K");
    assert.equal(snapshot.catalogVersion, "challenge-distance-v1");
    assert.equal(snapshot.difficultyLabel, entry.difficultyLabel);
    assert.equal(snapshot.durationDays, entry.durationDays);
    assert.equal(snapshot.durationMs, entry.durationMs);
    assert.equal(snapshot.maxParticipants, entry.maxParticipants);
    assert.equal(snapshot.maxInvitedFriends, entry.maxInvitedFriends);
    assert.equal(snapshot.targetMeters, entry.soloTargetMeters);
    assert.equal(snapshot.personalMinimumMeters, entry.personalMinimumMeters);
  });
});
