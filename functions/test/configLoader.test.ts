import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Firestore } from "firebase-admin/firestore";
import {
  DEFAULT_AUTOMATION_CONFIG,
  DEFAULT_CHALLENGE_ACCESS_CONFIG,
  DEFAULT_CHARACTER_ACCESS_CONFIG,
  DEFAULT_FEATURE_ACCESS_CONFIG,
  DEFAULT_LEADERBOARD_CONFIG,
  DEFAULT_PROGRESSION_CONFIG,
  deepMerge,
  loadAutomationConfig,
  loadChallengeAccessConfig,
  loadCharacterAccessConfig,
  loadFeatureAccessConfig,
  loadLeaderboardConfig,
  loadProgressionConfig,
  type AutomationConfig,
  type ChallengeAccessConfig,
  type CharacterAccessConfig,
  type ProgressionConfig,
  validateAutomationConfig,
  validateChallengeAccessConfig,
  validateCharacterAccessConfig,
  validateFeatureAccessConfig,
  validateLeaderboardConfig,
  validateProgressionConfig,
} from "../src/config/configLoader.js";

type FakeSnapshot = {
  readonly exists: boolean;
  data(): unknown;
};

function fakeDb(docPath: string, snapshot: FakeSnapshot | (() => Promise<FakeSnapshot>)): Firestore {
  return {
    doc(path: string) {
      return {
        async get() {
          if (path !== docPath) {
            return { exists: false, data: () => undefined };
          }

          if (typeof snapshot === "function") {
            return snapshot();
          }

          return snapshot;
        },
      };
    },
  } as unknown as Firestore;
}

function missingDb(docPath: string): Firestore {
  return fakeDb(docPath, { exists: false, data: () => undefined });
}

function rejectingDb(docPath: string): Firestore {
  return {
    doc(path: string) {
      return {
        async get() {
          if (path !== docPath) {
            return { exists: false, data: () => undefined };
          }

          throw new Error("simulated firestore read failure");
        },
      };
    },
  } as unknown as Firestore;
}

describe("configLoader deepMerge", () => {
  it("partial nested config preserves missing default fields", () => {
    const merged = deepMerge(DEFAULT_PROGRESSION_CONFIG, { coolDown: { percent: 0.3 } });

    assert.equal(merged.coolDown.percent, 0.3);
    assert.equal(merged.coolDown.min, DEFAULT_PROGRESSION_CONFIG.coolDown.min);
    assert.equal(merged.coolDown.max, DEFAULT_PROGRESSION_CONFIG.coolDown.max);
    assert.equal(merged.baseCompletionXp, DEFAULT_PROGRESSION_CONFIG.baseCompletionXp);
  });

  it("replaces arrays wholesale instead of merging elements", () => {
    const merged = deepMerge(DEFAULT_PROGRESSION_CONFIG, { levelIncrements: [50, 60] });

    assert.deepEqual(merged.levelIncrements, [50, 60]);
  });
});

describe("validateProgressionConfig", () => {
  it("accepts the default config", () => {
    const result = validateProgressionConfig(DEFAULT_PROGRESSION_CONFIG);
    assert.equal(result.valid, true);
    assert.deepEqual(result.errors, []);
  });

  it("rejects negative XP fields", () => {
    const result = validateProgressionConfig({
      ...DEFAULT_PROGRESSION_CONFIG,
      baseCompletionXp: -5,
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("baseCompletionXp")));
  });

  it("rejects dailyXpCap less than activityXpCap", () => {
    const result = validateProgressionConfig({
      ...DEFAULT_PROGRESSION_CONFIG,
      activityXpCap: 100,
      dailyXpCap: 50,
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("dailyXpCap")));
  });

  it("rejects coolDown.min greater than coolDown.max", () => {
    const result = validateProgressionConfig({
      ...DEFAULT_PROGRESSION_CONFIG,
      coolDown: { percent: 0.2, min: 30, max: 10 },
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("coolDown.min")));
  });

  it("rejects empty levelIncrements", () => {
    const result = validateProgressionConfig({
      ...DEFAULT_PROGRESSION_CONFIG,
      levelIncrements: [],
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("levelIncrements")));
  });

  it("includes default streakRewards milestones", () => {
    assert.deepEqual(DEFAULT_PROGRESSION_CONFIG.streakRewards, [
      { milestoneDays: 3, bonusXp: 30 },
      { milestoneDays: 7, bonusXp: 90 },
      { milestoneDays: 14, bonusXp: 220 },
      { milestoneDays: 30, bonusXp: 600 },
    ]);
  });

  it("accepts a custom streakRewards array", () => {
    const result = validateProgressionConfig({
      ...DEFAULT_PROGRESSION_CONFIG,
      streakRewards: [
        { milestoneDays: 2, bonusXp: 0 },
        { milestoneDays: 10, bonusXp: 250 },
      ],
    });

    assert.equal(result.valid, true);
    assert.deepEqual(result.errors, []);
  });

  it("rejects a non-array streakRewards", () => {
    const result = validateProgressionConfig({
      ...DEFAULT_PROGRESSION_CONFIG,
      streakRewards: {} as unknown as ProgressionConfig["streakRewards"],
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("streakRewards must be an array")));
  });

  it("rejects a negative streakRewards bonusXp", () => {
    const result = validateProgressionConfig({
      ...DEFAULT_PROGRESSION_CONFIG,
      streakRewards: [{ milestoneDays: 3, bonusXp: -1 }],
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("streakRewards[0].bonusXp")));
  });

  it("rejects non-increasing streakRewards milestoneDays", () => {
    const result = validateProgressionConfig({
      ...DEFAULT_PROGRESSION_CONFIG,
      streakRewards: [
        { milestoneDays: 7, bonusXp: 90 },
        { milestoneDays: 7, bonusXp: 120 },
      ],
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("streakRewards[1].milestoneDays")));
  });
});

describe("validateLeaderboardConfig", () => {
  it("accepts the default config", () => {
    const result = validateLeaderboardConfig(DEFAULT_LEADERBOARD_CONFIG);
    assert.equal(result.valid, true);
  });

  it("rejects a non-positive seasonLengthDays", () => {
    const result = validateLeaderboardConfig({
      ...DEFAULT_LEADERBOARD_CONFIG,
      seasonLengthDays: 0,
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("seasonLengthDays")));
  });
});

describe("validateFeatureAccessConfig", () => {
  it("accepts the default config", () => {
    const result = validateFeatureAccessConfig(DEFAULT_FEATURE_ACCESS_CONFIG);
    assert.equal(result.valid, true);
  });

  it("rejects a bad minimumTier value", () => {
    const result = validateFeatureAccessConfig({
      features: {
        advancedAnalysis: { minimumTier: "gold" as unknown as "premium", enabled: true },
      },
      version: 1,
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("minimumTier")));
  });

  it("ships the app-audited catalog with the expected default tiers", () => {
    assert.deepEqual(
      Object.fromEntries(
        Object.entries(DEFAULT_FEATURE_ACCESS_CONFIG.features).map(([name, entry]) => [name, entry.minimumTier]),
      ),
      {
        advancedAnalysis: "premium",
        aiHomeCoach: "premium",
        activityFeedback: "premium",
        workoutBriefing: "premium",
        shareRouteToFeed: "basic",
        shareCards: "basic",
      },
    );
  });

  it("keeps the core beginner goal plan out of the admin-flippable catalog", () => {
    // The onboarding-generated plan is the app's core beginner experience and
    // premium must never gate it, so it is not offered as a console switch at
    // all — a tier an admin cannot set is a tier that cannot be set wrong.
    assert.equal("goalPlan" in DEFAULT_FEATURE_ACCESS_CONFIG.features, false);
  });

  it("keeps the removed health workout import out of the catalog", () => {
    // 65b41c49 deleted the entire HealthKit import surface, so nothing reads
    // this key any more. Listing it rendered a console tier control that
    // silently gated nothing — the failure mode the tier model exists to
    // prevent. It comes back only alongside a real import gate.
    assert.equal("healthWorkoutImport" in DEFAULT_FEATURE_ACCESS_CONFIG.features, false);
  });

  it("keeps non-convertible and out-of-scope features out of the catalog", () => {
    // Leaderboard, challenges, feed, friends, run tracking, cool-down and
    // XP/progress must never differ by tier — their absence from the catalog
    // is the guarantee that the console cannot premium-gate (or un-gate) them
    // here.
    for (const forbidden of ["leaderboard", "challenges", "socialFeed", "friends", "runTracking", "coolDownGuide"]) {
      assert.equal(DEFAULT_FEATURE_ACCESS_CONFIG.features[forbidden], undefined);
    }
  });
});

describe("configLoader loaders fall back to defaults", () => {
  it("loadProgressionConfig returns defaults when the doc does not exist", async () => {
    const config = await loadProgressionConfig(missingDb("config/progression"));
    assert.deepEqual(config, DEFAULT_PROGRESSION_CONFIG);
  });

  it("loadProgressionConfig returns defaults when the read rejects", async () => {
    const config = await loadProgressionConfig(rejectingDb("config/progression"));
    assert.deepEqual(config, DEFAULT_PROGRESSION_CONFIG);
  });

  it("loadProgressionConfig returns defaults when the stored doc is invalid", async () => {
    const db = fakeDb("config/progression", {
      exists: true,
      data: () => ({ dailyXpCap: -1 }),
    });

    const config = await loadProgressionConfig(db);
    assert.deepEqual(config, DEFAULT_PROGRESSION_CONFIG);
  });

  it("loadLeaderboardConfig returns defaults when the doc does not exist", async () => {
    const config = await loadLeaderboardConfig(missingDb("config/leaderboard"));
    assert.deepEqual(config, DEFAULT_LEADERBOARD_CONFIG);
  });

  it("loadLeaderboardConfig returns defaults when the read rejects", async () => {
    const config = await loadLeaderboardConfig(rejectingDb("config/leaderboard"));
    assert.deepEqual(config, DEFAULT_LEADERBOARD_CONFIG);
  });

  it("loadFeatureAccessConfig returns defaults when the doc does not exist", async () => {
    const config = await loadFeatureAccessConfig(missingDb("config/featureAccess"));
    assert.deepEqual(config, DEFAULT_FEATURE_ACCESS_CONFIG);
  });

  it("loadFeatureAccessConfig returns defaults when the read rejects", async () => {
    const config = await loadFeatureAccessConfig(rejectingDb("config/featureAccess"));
    assert.deepEqual(config, DEFAULT_FEATURE_ACCESS_CONFIG);
  });

  it("loadFeatureAccessConfig merges a partial stored override with defaults", async () => {
    const db = fakeDb("config/featureAccess", {
      exists: true,
      data: () => ({ features: { leaderboard: { minimumTier: "basic", enabled: false } } }),
    });

    const config = await loadFeatureAccessConfig(db);
    assert.equal(config.features["leaderboard"]?.enabled, false);
    assert.deepEqual(config.features["advancedAnalysis"], DEFAULT_FEATURE_ACCESS_CONFIG.features["advancedAnalysis"]);
  });

  it("loadFeatureAccessConfig merges a stored tier override for one of the new catalog entries", async () => {
    const db = fakeDb("config/featureAccess", {
      exists: true,
      data: () => ({ features: { activityFeedback: { minimumTier: "premium", enabled: true } } }),
    });

    const config = await loadFeatureAccessConfig(db);
    assert.equal(config.features["activityFeedback"]?.minimumTier, "premium");
    assert.equal(validateFeatureAccessConfig(config).valid, true);
    assert.deepEqual(config.features["shareRouteToFeed"], DEFAULT_FEATURE_ACCESS_CONFIG.features["shareRouteToFeed"]);
  });
});

// Both flags are read as plain truthiness tests and deepMerge passes stored
// values through verbatim, so a wrong TYPE silently inverts the policy rather
// than failing. These pin that the validator rejects them instead.
describe("policy flag type validation", () => {
  it("rejects a non-boolean premiumEarnsXp", () => {
    for (const value of ["false", "true", 0, 1, null]) {
      const result = validateProgressionConfig({
        ...DEFAULT_PROGRESSION_CONFIG,
        premiumEarnsXp: value as unknown as boolean,
      });
      assert.equal(result.valid, false, `premiumEarnsXp ${JSON.stringify(value)} must be rejected`);
      assert.ok(result.errors.some((error) => error.includes("premiumEarnsXp")));
    }
  });

  it("rejects a non-boolean excludePremium", () => {
    for (const value of ["false", "true", 0, 1, null]) {
      const result = validateLeaderboardConfig({
        ...DEFAULT_LEADERBOARD_CONFIG,
        excludePremium: value as unknown as boolean,
      });
      assert.equal(result.valid, false, `excludePremium ${JSON.stringify(value)} must be rejected`);
      assert.ok(result.errors.some((error) => error.includes("excludePremium")));
    }
  });

  it("accepts the shipped defaults", () => {
    assert.equal(validateProgressionConfig(DEFAULT_PROGRESSION_CONFIG).valid, true);
    assert.equal(validateLeaderboardConfig(DEFAULT_LEADERBOARD_CONFIG).valid, true);
  });
});

// A single bad value used to discard the whole document, so an admin fixing a
// typo would have found every other tuned field reverted with only a
// console.warn as the signal.
describe("per-field config repair", () => {
  it("keeps valid fields when one field is invalid", async () => {
    const db = fakeDb("config/progression", {
      exists: true,
      data: () => ({ premiumEarnsXp: "false", dailyXpCap: 500, xpPerKilometer: 25 }),
    });

    const config = await loadProgressionConfig(db);

    // The bad flag is reset to its default...
    assert.equal(config.premiumEarnsXp, DEFAULT_PROGRESSION_CONFIG.premiumEarnsXp);
    // ...and the admin's other tuning survives.
    assert.equal(config.dailyXpCap, 500);
    assert.equal(config.xpPerKilometer, 25);
  });

  it("keeps valid leaderboard fields when excludePremium is the wrong type", async () => {
    const db = fakeDb("config/leaderboard", {
      exists: true,
      data: () => ({ excludePremium: "false", minRunsToQualify: 4 }),
    });

    const config = await loadLeaderboardConfig(db);

    assert.equal(config.excludePremium, DEFAULT_LEADERBOARD_CONFIG.excludePremium);
    assert.equal(config.minRunsToQualify, 4);
  });

  it("still falls back to the whole default when the repair cannot succeed", async () => {
    // dailyXpCap < activityXpCap is a cross-field rule, so resetting the named
    // field alone does not necessarily satisfy it; whatever the repair does,
    // the result must be valid.
    const db = fakeDb("config/progression", {
      exists: true,
      data: () => ({ dailyXpCap: 10, activityXpCap: 100 }),
    });

    const config = await loadProgressionConfig(db);

    assert.equal(validateProgressionConfig(config).valid, true);
  });
});

describe("validateAutomationConfig", () => {
  it("accepts the default config", () => {
    const result = validateAutomationConfig(DEFAULT_AUTOMATION_CONFIG);
    assert.equal(result.valid, true);
    assert.deepEqual(result.errors, []);
  });

  it("rejects a non-boolean autoHide.enabled", () => {
    for (const value of ["false", "true", 0, 1, null]) {
      const result = validateAutomationConfig({
        ...DEFAULT_AUTOMATION_CONFIG,
        autoHide: { ...DEFAULT_AUTOMATION_CONFIG.autoHide, enabled: value as unknown as boolean },
      });
      assert.equal(result.valid, false, `autoHide.enabled ${JSON.stringify(value)} must be rejected`);
      assert.ok(result.errors.some((error) => error.includes("autoHide.enabled")));
    }
  });

  it("rejects an autoHide.reportThreshold below the minimum", () => {
    const result = validateAutomationConfig({
      ...DEFAULT_AUTOMATION_CONFIG,
      autoHide: { ...DEFAULT_AUTOMATION_CONFIG.autoHide, reportThreshold: 1 },
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("autoHide.reportThreshold")));
  });

  it("accepts an autoHide.reportThreshold at the minimum boundary", () => {
    const result = validateAutomationConfig({
      ...DEFAULT_AUTOMATION_CONFIG,
      autoHide: { ...DEFAULT_AUTOMATION_CONFIG.autoHide, reportThreshold: 2 },
    });

    assert.equal(result.valid, true);
  });

  it("rejects a staleReportEscalation.pendingDays of 0", () => {
    const result = validateAutomationConfig({
      ...DEFAULT_AUTOMATION_CONFIG,
      staleReportEscalation: { ...DEFAULT_AUTOMATION_CONFIG.staleReportEscalation, pendingDays: 0 },
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("staleReportEscalation.pendingDays")));
  });

  it("rejects a non-boolean scheduled flag", () => {
    for (const value of ["false", "true", 0, 1, null]) {
      const result = validateAutomationConfig({
        ...DEFAULT_AUTOMATION_CONFIG,
        scheduled: { ...DEFAULT_AUTOMATION_CONFIG.scheduled, subscriptionExpirySweep: value as unknown as boolean },
      });
      assert.equal(result.valid, false, `scheduled.subscriptionExpirySweep ${JSON.stringify(value)} must be rejected`);
      assert.ok(result.errors.some((error) => error.includes("scheduled.subscriptionExpirySweep")));
    }
  });

  it('rejects a minimumErrorSeverity of "medium"', () => {
    const result = validateAutomationConfig({
      ...DEFAULT_AUTOMATION_CONFIG,
      notifications: {
        ...DEFAULT_AUTOMATION_CONFIG.notifications,
        minimumErrorSeverity: "medium" as unknown as AutomationConfig["notifications"]["minimumErrorSeverity"],
      },
    });

    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.includes("notifications.minimumErrorSeverity")));
  });

  it('accepts "high" as minimumErrorSeverity', () => {
    const result = validateAutomationConfig({
      ...DEFAULT_AUTOMATION_CONFIG,
      notifications: { ...DEFAULT_AUTOMATION_CONFIG.notifications, minimumErrorSeverity: "high" },
    });

    assert.equal(result.valid, true);
  });
});

describe("configLoader loadAutomationConfig", () => {
  it("returns defaults when the doc does not exist", async () => {
    const config = await loadAutomationConfig(missingDb("config/automation"));
    assert.deepEqual(config, DEFAULT_AUTOMATION_CONFIG);
  });

  it("returns defaults when the read rejects", async () => {
    const config = await loadAutomationConfig(rejectingDb("config/automation"));
    assert.deepEqual(config, DEFAULT_AUTOMATION_CONFIG);
  });

  it("merges a partial stored override with defaults", async () => {
    const db = fakeDb("config/automation", {
      exists: true,
      data: () => ({ autoHide: { enabled: true, reportThreshold: 5 } }),
    });

    const config = await loadAutomationConfig(db);
    assert.equal(config.autoHide.enabled, true);
    assert.equal(config.autoHide.reportThreshold, 5);
    assert.deepEqual(config.scheduled, DEFAULT_AUTOMATION_CONFIG.scheduled);
  });

  it("resets only the invalid autoHide subtree and keeps the rest of the document", async () => {
    const db = fakeDb("config/automation", {
      exists: true,
      data: () => ({
        autoHide: { enabled: true, reportThreshold: 1 },
        staleReportEscalation: { enabled: false, pendingDays: 30 },
      }),
    });

    const config = await loadAutomationConfig(db);

    // autoHide.reportThreshold: 1 fails validation, so the whole autoHide
    // subtree is reset to its default...
    assert.deepEqual(config.autoHide, DEFAULT_AUTOMATION_CONFIG.autoHide);
    // ...while the valid staleReportEscalation override survives untouched.
    assert.deepEqual(config.staleReportEscalation, { enabled: false, pendingDays: 30 });
  });
});

describe("validateChallengeAccessConfig", () => {
  it("accepts the defaults (six premium-only tiers above 42K)", () => {
    assert.equal(validateChallengeAccessConfig(DEFAULT_CHALLENGE_ACCESS_CONFIG).valid, true);
    assert.deepEqual(
      DEFAULT_CHALLENGE_ACCESS_CONFIG.premiumOnlyTiers,
      ["100K", "200K", "250K", "300K", "500K", "1000K"],
    );
  });

  it("accepts an empty list (every tier open)", () => {
    assert.equal(validateChallengeAccessConfig({ premiumOnlyTiers: [], version: 1 }).valid, true);
  });

  it("rejects unknown tier ids", () => {
    const result = validateChallengeAccessConfig({ premiumOnlyTiers: ["100K", "5K"], version: 1 });
    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.startsWith("premiumOnlyTiers")));
  });

  it("rejects duplicates", () => {
    const result = validateChallengeAccessConfig({ premiumOnlyTiers: ["100K", "100K"], version: 1 });
    assert.equal(result.valid, false);
  });

  it("rejects a non-array", () => {
    const result = validateChallengeAccessConfig({ premiumOnlyTiers: "100K", version: 1 } as unknown as ChallengeAccessConfig);
    assert.equal(result.valid, false);
  });
});

describe("configLoader loadChallengeAccessConfig", () => {
  it("returns defaults when the doc does not exist", async () => {
    const config = await loadChallengeAccessConfig(missingDb("config/challengeAccess"));
    assert.deepEqual(config, DEFAULT_CHALLENGE_ACCESS_CONFIG);
  });

  it("lets a stored array REPLACE the default list (arrays are leaf values)", async () => {
    const db = fakeDb("config/challengeAccess", {
      exists: true,
      data: () => ({ premiumOnlyTiers: ["1000K"] }),
    });
    const config = await loadChallengeAccessConfig(db);
    assert.deepEqual(config.premiumOnlyTiers, ["1000K"]);
  });

  it("falls back to defaults when the stored doc is invalid", async () => {
    const db = fakeDb("config/challengeAccess", {
      exists: true,
      data: () => ({ premiumOnlyTiers: ["NOT_A_TIER"] }),
    });
    const config = await loadChallengeAccessConfig(db);
    assert.deepEqual(config, DEFAULT_CHALLENGE_ACCESS_CONFIG);
  });

  it("returns defaults when the read rejects", async () => {
    const config = await loadChallengeAccessConfig(rejectingDb("config/challengeAccess"));
    assert.deepEqual(config, DEFAULT_CHALLENGE_ACCESS_CONFIG);
  });
});

describe("validateCharacterAccessConfig", () => {
  it("accepts the defaults (Cap and Ivy premium-only)", () => {
    assert.equal(validateCharacterAccessConfig(DEFAULT_CHARACTER_ACCESS_CONFIG).valid, true);
    assert.deepEqual(
      DEFAULT_CHARACTER_ACCESS_CONFIG.premiumOnlyCharacters,
      ["cap", "purple"],
    );
  });

  it("accepts an empty list (every character open)", () => {
    assert.equal(validateCharacterAccessConfig({ premiumOnlyCharacters: [], version: 1 }).valid, true);
  });

  it("rejects unknown character ids", () => {
    const result = validateCharacterAccessConfig({ premiumOnlyCharacters: ["cap", "green"], version: 1 });
    assert.equal(result.valid, false);
    assert.ok(result.errors.some((error) => error.startsWith("premiumOnlyCharacters")));
  });

  it("rejects duplicates", () => {
    const result = validateCharacterAccessConfig({ premiumOnlyCharacters: ["cap", "cap"], version: 1 });
    assert.equal(result.valid, false);
  });

  it("rejects a non-array", () => {
    const result = validateCharacterAccessConfig({ premiumOnlyCharacters: "cap", version: 1 } as unknown as CharacterAccessConfig);
    assert.equal(result.valid, false);
  });
});

describe("configLoader loadCharacterAccessConfig", () => {
  it("returns defaults when the doc does not exist", async () => {
    const config = await loadCharacterAccessConfig(missingDb("config/characterAccess"));
    assert.deepEqual(config, DEFAULT_CHARACTER_ACCESS_CONFIG);
  });

  it("lets a stored array REPLACE the default list (arrays are leaf values)", async () => {
    const db = fakeDb("config/characterAccess", {
      exists: true,
      data: () => ({ premiumOnlyCharacters: ["purple"] }),
    });
    const config = await loadCharacterAccessConfig(db);
    assert.deepEqual(config.premiumOnlyCharacters, ["purple"]);
  });

  it("falls back to defaults when the stored doc is invalid", async () => {
    const db = fakeDb("config/characterAccess", {
      exists: true,
      data: () => ({ premiumOnlyCharacters: ["NOT_A_CHARACTER"] }),
    });
    const config = await loadCharacterAccessConfig(db);
    assert.deepEqual(config, DEFAULT_CHARACTER_ACCESS_CONFIG);
  });

  it("returns defaults when the read rejects", async () => {
    const config = await loadCharacterAccessConfig(rejectingDb("config/characterAccess"));
    assert.deepEqual(config, DEFAULT_CHARACTER_ACCESS_CONFIG);
  });
});
