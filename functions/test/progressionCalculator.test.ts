import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { sumDailyXp } from "../src/progression/progressionAuditHelpers.js";
import { DEFAULT_PROGRESSION_CONFIG } from "../src/config/configLoader.js";
import {
  applyDailyXpCap,
  calculateActivityXp,
  calculateCoolDownBonus,
  calculateStreakMilestoneBonus,
  dailyCapDateForCompletedAt,
  monthlyPeriodForCompletedAt,
  resolveLevelProgression,
} from "../src/progression/progressionCalculator.js";

const config = DEFAULT_PROGRESSION_CONFIG;

describe("progression calculator", () => {
  it("awards hybrid activity XP without pace input", () => {
    const result = calculateActivityXp(
      {
        distanceMeters: 4200,
        activeDurationSeconds: 1860,
        lowDataConfirmed: false,
        planCompletionBonusEligible: false,
      },
      config,
    );

    assert.equal(result.xpDeltaBeforeDailyCap, 75);
    assert.equal(result.baseCompletionXp, 20);
    assert.equal(result.distanceXp, 40);
    assert.equal(result.durationXp, 15);
    assert.equal(result.planCompletionBonusXp, 0);
    assert.equal(result.rawXpBeforeActivityCap, 75);
    assert.equal(result.activityCapApplied, false);
    assert.equal(result.reason, "run_completion_xp_awarded");
  });

  it("caps one accepted activity at 100 XP before the daily cap", () => {
    const result = calculateActivityXp(
      {
        distanceMeters: 15000,
        activeDurationSeconds: 7200,
        lowDataConfirmed: false,
        planCompletionBonusEligible: true,
      },
      config,
    );

    assert.equal(result.rawXpBeforeActivityCap, 250);
    assert.equal(result.xpDeltaBeforeDailyCap, 100);
    assert.equal(result.activityCapApplied, true);
    assert.equal(result.planCompletionBonusXp, 20);
  });

  it("keeps low-data confirmed saves at zero XP", () => {
    const result = calculateActivityXp(
      {
        distanceMeters: 0,
        activeDurationSeconds: 2,
        lowDataConfirmed: true,
        planCompletionBonusEligible: true,
      },
      config,
    );

    assert.equal(result.xpDeltaBeforeDailyCap, 0);
    assert.equal(result.planCompletionBonusXp, 0);
    assert.equal(result.reason, "low_data_no_xp");
  });

  it("applies the Asia Singapore daily cap", () => {
    const capped = applyDailyXpCap(
      {
        xpDeltaBeforeDailyCap: 75,
        dailyXpBefore: 150,
      },
      config,
    );
    const exhausted = applyDailyXpCap(
      {
        xpDeltaBeforeDailyCap: 75,
        dailyXpBefore: 200,
      },
      config,
    );

    assert.equal(capped.xpDelta, 50);
    assert.equal(capped.dailyXpAfter, 200);
    assert.equal(capped.dailyCapApplied, true);
    assert.equal(exhausted.xpDelta, 0);
    assert.equal(exhausted.dailyXpAfter, 200);
    assert.equal(exhausted.dailyCapApplied, true);
  });

  it("derives daily cap date from Asia Singapore local date", () => {
    assert.equal(
      dailyCapDateForCompletedAt("2026-06-14T16:30:00.000Z"),
      "2026-06-15",
    );
  });

  it("derives monthly leaderboard period from Asia Singapore local date", () => {
    assert.equal(
      monthlyPeriodForCompletedAt("2026-06-30T16:30:00.000Z"),
      "2026-07",
    );
  });

  it("resolves Lv.100 at 53600 total XP with stable division keys", () => {
    const initial = resolveLevelProgression(0, config);
    const mid = resolveLevelProgression(53600 - 1, config);
    const max = resolveLevelProgression(53600, config);

    assert.equal(initial.level, 1);
    assert.equal(initial.divisionKey, "tier_01");
    assert.equal(initial.divisionLabel, "Iron League");
    assert.equal(initial.nextLevelXp, 100);
    assert.equal(mid.level, 99);
    assert.equal(mid.divisionKey, "tier_10");
    assert.equal(mid.divisionLabel, "Challenger League");
    assert.equal(max.level, 100);
    assert.equal(max.divisionKey, "tier_10");
    assert.equal(max.divisionLabel, "Challenger League");
    assert.equal(max.nextLevelXp, null);
    assert.equal(max.xpToNextLevel, null);
    assert.equal(max.levelProgressPercent, 100);
  });
});

describe("band level-curve regression", () => {
  it("reaches level 2 at 100 XP, level 10 at 900 XP, and level 11 at 1050 XP", () => {
    // Band 0 (levelIncrements[0] = 100) funds only 9 level-ups: levels 2..10.
    assert.equal(resolveLevelProgression(100, config).level, 2);
    assert.equal(resolveLevelProgression(99, config).level, 1);
    assert.equal(resolveLevelProgression(900, config).level, 10);
    assert.equal(resolveLevelProgression(899, config).level, 9);
    // Level 11 crosses into band 1 (levelIncrements[1] = 150): 900 + 150 = 1050.
    assert.equal(resolveLevelProgression(1050, config).level, 11);
    assert.equal(resolveLevelProgression(1049, config).level, 10);
  });

  it("reaches level 20 at 2400 XP and level 100 at 53600 XP", () => {
    assert.equal(resolveLevelProgression(2400, config).level, 20);
    assert.equal(resolveLevelProgression(2399, config).level, 19);
    assert.equal(resolveLevelProgression(53600, config).level, 100);
    assert.equal(resolveLevelProgression(53599, config).level, 99);
  });

  it("lands a totalXp exactly on a threshold on that level, and one XP below on the previous level", () => {
    const onThreshold = resolveLevelProgression(2400, config);
    const belowThreshold = resolveLevelProgression(2399, config);

    assert.equal(onThreshold.level, 20);
    assert.equal(belowThreshold.level, 19);
  });

  it("clamps and reuses the last levelIncrements entry once bands exceed the array length", () => {
    const shortIncrementsConfig = {
      ...config,
      maxLevel: 40,
      levelIncrements: [100, 200],
    };

    // Band 0 (levels 2-10) still uses the first increment: 9 steps of 100 = 900.
    assert.equal(resolveLevelProgression(900, shortIncrementsConfig).level, 10);
    // Band 1+ (levels 11-40) clamps to the last increment (200) instead of
    // falling back to undefined/NaN: 900 + 200 = 1100 at level 11.
    assert.equal(resolveLevelProgression(1100, shortIncrementsConfig).level, 11);
    assert.equal(resolveLevelProgression(1099, shortIncrementsConfig).level, 10);
    // Levels 21-40 keep reusing the same clamped last increment (200):
    // 900 + 30 steps * 200 = 6900 at level 40 (maxLevel).
    assert.equal(resolveLevelProgression(6900, shortIncrementsConfig).level, 40);
    assert.equal(resolveLevelProgression(6899, shortIncrementsConfig).level, 39);
  });

  it("stops progression at maxLevel with null next-level fields and 100 percent progress", () => {
    const shortIncrementsConfig = {
      ...config,
      maxLevel: 40,
      levelIncrements: [100, 200],
    };
    const atCap = resolveLevelProgression(6900, shortIncrementsConfig);

    assert.equal(atCap.level, 40);
    assert.equal(atCap.nextLevelXp, null);
    assert.equal(atCap.xpToNextLevel, null);
    assert.equal(atCap.levelProgressPercent, 100);

    const beyondCap = resolveLevelProgression(999999, shortIncrementsConfig);
    assert.equal(beyondCap.level, 40);
    assert.equal(beyondCap.nextLevelXp, null);
  });
});

describe("cool-down bonus calculator", () => {
  it("awards a 20 percent bonus rounded to the nearest 5 XP", () => {
    assert.equal(calculateCoolDownBonus(40, config), 10);
    assert.equal(calculateCoolDownBonus(75, config), 15);
  });

  it("caps the bonus so the activity total never exceeds the 100 XP activity cap", () => {
    assert.equal(calculateCoolDownBonus(95, config), 5);
  });

  it("floors the bonus at 5 XP for small nonzero bases", () => {
    assert.equal(calculateCoolDownBonus(10, config), 5);
  });

  it("awards zero bonus once the base XP already exhausts the activity cap", () => {
    assert.equal(calculateCoolDownBonus(100, config), 0);
  });

  it("awards zero bonus for zero or invalid base XP", () => {
    assert.equal(calculateCoolDownBonus(0, config), 0);
    assert.equal(calculateCoolDownBonus(-10, config), 0);
    assert.equal(calculateCoolDownBonus(Number.NaN, config), 0);
  });
});

describe("streak milestone bonus calculator", () => {
  // Default streakRewards: [3 -> 30, 7 -> 90, 14 -> 220, 30 -> 600].
  it("awards the milestone bonus when a single milestone is crossed", () => {
    const result = calculateStreakMilestoneBonus(
      { previousStreak: 2, nextStreak: 3, highestPaidMilestoneDays: 0 },
      config,
    );

    assert.equal(result.bonusXp, 30);
    assert.equal(result.milestoneDays, 3);
  });

  it("awards only the highest milestone when several are crossed in one jump", () => {
    // A backfill/data repair jumping the streak from 1 to 10 crosses both the
    // 3-day and 7-day milestones. Only the 7-day (higher) reward is paid —
    // summing would explode the XP economy.
    const result = calculateStreakMilestoneBonus(
      { previousStreak: 1, nextStreak: 10, highestPaidMilestoneDays: 0 },
      config,
    );

    assert.equal(result.bonusXp, 90);
    assert.equal(result.milestoneDays, 7);
  });

  it("awards nothing when no milestone is crossed", () => {
    const result = calculateStreakMilestoneBonus(
      { previousStreak: 4, nextStreak: 5, highestPaidMilestoneDays: 0 },
      config,
    );

    assert.equal(result.bonusXp, 0);
    assert.equal(result.milestoneDays, null);
  });

  it("awards nothing on a streak regression or reset", () => {
    const result = calculateStreakMilestoneBonus(
      { previousStreak: 10, nextStreak: 1, highestPaidMilestoneDays: 0 },
      config,
    );

    assert.equal(result.bonusXp, 0);
    assert.equal(result.milestoneDays, null);
  });

  it("awards nothing when nextStreak equals previousStreak", () => {
    const result = calculateStreakMilestoneBonus(
      { previousStreak: 5, nextStreak: 5, highestPaidMilestoneDays: 0 },
      config,
    );

    assert.equal(result.bonusXp, 0);
    assert.equal(result.milestoneDays, null);
  });

  it("awards nothing when streakRewards is empty", () => {
    const result = calculateStreakMilestoneBonus(
      { previousStreak: 2, nextStreak: 3, highestPaidMilestoneDays: 0 },
      { ...config, streakRewards: [] },
    );

    assert.equal(result.bonusXp, 0);
    assert.equal(result.milestoneDays, null);
  });

  it("selects the max crossed milestone even when streakRewards is not sorted", () => {
    const unsortedConfig = {
      ...config,
      streakRewards: [
        { milestoneDays: 14, bonusXp: 220 },
        { milestoneDays: 3, bonusXp: 30 },
        { milestoneDays: 30, bonusXp: 600 },
        { milestoneDays: 7, bonusXp: 90 },
      ],
    };

    const result = calculateStreakMilestoneBonus(
      { previousStreak: 1, nextStreak: 10, highestPaidMilestoneDays: 0 },
      unsortedConfig,
    );

    assert.equal(result.bonusXp, 90);
    assert.equal(result.milestoneDays, 7);
  });

  it("awards nothing for non-finite or negative streak inputs", () => {
    assert.equal(
      calculateStreakMilestoneBonus({ previousStreak: Number.NaN, nextStreak: 5, highestPaidMilestoneDays: 0 }, config).bonusXp,
      0,
    );
    assert.equal(
      calculateStreakMilestoneBonus({ previousStreak: 1, nextStreak: Number.POSITIVE_INFINITY, highestPaidMilestoneDays: 0 }, config)
        .bonusXp,
      0,
    );
    assert.equal(
      calculateStreakMilestoneBonus({ previousStreak: -1, nextStreak: 5, highestPaidMilestoneDays: 0 }, config).bonusXp,
      0,
    );
  });

  it("ignores a milestone whose bonusXp is malformed, without blocking other valid milestones", () => {
    const malformedConfig = {
      ...config,
      streakRewards: [
        { milestoneDays: 3, bonusXp: Number.NaN },
        { milestoneDays: 7, bonusXp: 90 },
      ],
    };

    const result = calculateStreakMilestoneBonus(
      { previousStreak: 1, nextStreak: 10, highestPaidMilestoneDays: 0 },
      malformedConfig,
    );

    // The 3-day entry is crossed too but malformed, so it is skipped; the
    // valid 7-day entry is still awarded.
    assert.equal(result.bonusXp, 90);
    assert.equal(result.milestoneDays, 7);
  });
});

// The high-water mark is the only thing standing between a collapsible streak
// baseline and unlimited milestone XP. `previousStreak` is derived from
// plan-bounded activity history, and the plan boundary moves whenever
// generatedPlans/{uid}.createdAt does — a field the owner can write. So a
// crossing alone must never authorize payment.
describe("streak milestone bonus high-water mark", () => {
  it("pays nothing for a milestone at or below the highest already paid", () => {
    for (const paid of [3, 7, 14, 30]) {
      const result = calculateStreakMilestoneBonus(
        { previousStreak: 0, nextStreak: paid, highestPaidMilestoneDays: paid },
        config,
      );
      assert.equal(result.bonusXp, 0, `milestone ${paid} must not pay twice`);
      assert.equal(result.milestoneDays, null);
    }
  });

  it("still pays a milestone strictly above the mark", () => {
    const result = calculateStreakMilestoneBonus(
      { previousStreak: 6, nextStreak: 7, highestPaidMilestoneDays: 3 },
      config,
    );
    assert.equal(result.milestoneDays, 7);
    assert.equal(result.bonusXp, 90);
  });

  it("refuses to re-pay after a collapsed baseline replays every milestone", () => {
    // A plan reset drops previousStreak to 0; the run then "crosses" 3, 7, 14
    // and 30 in one transition. All are already paid, so nothing is owed.
    const result = calculateStreakMilestoneBonus(
      { previousStreak: 0, nextStreak: 30, highestPaidMilestoneDays: 30 },
      config,
    );
    assert.equal(result.bonusXp, 0);
    assert.equal(result.milestoneDays, null);
  });

  it("pays only the highest unpaid milestone when a jump crosses several", () => {
    const result = calculateStreakMilestoneBonus(
      { previousStreak: 0, nextStreak: 30, highestPaidMilestoneDays: 7 },
      config,
    );
    assert.equal(result.milestoneDays, 30);
    assert.equal(result.bonusXp, 600);
  });

  it("treats a non-finite or negative mark as nothing paid yet", () => {
    for (const mark of [Number.NaN, -5]) {
      const result = calculateStreakMilestoneBonus(
        { previousStreak: 2, nextStreak: 3, highestPaidMilestoneDays: mark },
        config,
      );
      assert.equal(result.milestoneDays, 3, `mark ${mark} must not block payment`);
      assert.equal(result.bonusXp, 30);
    }
  });
});

// The daily cap bounds ordinary per-run earning. A streak milestone is paid at
// most once per owner ever, so capping it against a per-day budget only made
// the two largest rewards unpayable — 480 of the 30-day 600 was silently
// dropped after an ordinary run.
describe("streak milestone bonus daily-cap exemption", () => {
  it("does not let a milestone bonus consume the day's remaining budget", () => {
    // A run that already earned 80 XP leaves 120 of the 200 daily cap. The
    // milestone must still pay its full 600.
    const events = [
      { dailyCapDate: "2026-07-01", xpDelta: 680, streakBonusXp: 600 },
    ];
    assert.equal(sumDailyXp(events, "2026-07-01"), 80);
  });

  it("counts an ordinary run's XP in full", () => {
    const events = [{ dailyCapDate: "2026-07-01", xpDelta: 80 }];
    assert.equal(sumDailyXp(events, "2026-07-01"), 80);
  });

  it("ignores a malformed or zero streakBonusXp rather than dropping the run", () => {
    assert.equal(
      sumDailyXp([{ dailyCapDate: "2026-07-01", xpDelta: 80, streakBonusXp: 0 }], "2026-07-01"),
      80,
    );
    assert.equal(
      sumDailyXp(
        [{ dailyCapDate: "2026-07-01", xpDelta: 80, streakBonusXp: "600" }],
        "2026-07-01",
      ),
      80,
    );
  });

  it("never counts a negative remainder when the bonus exceeds the delta", () => {
    assert.equal(
      sumDailyXp([{ dailyCapDate: "2026-07-01", xpDelta: 100, streakBonusXp: 600 }], "2026-07-01"),
      0,
    );
  });
});
