import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { DEFAULT_PROGRESSION_CONFIG } from "../src/config/configLoader.js";
import { planMonthlyLeaderboards } from "../src/leaderboard/monthlyLeaderboard.js";
import { sumDailyXp } from "../src/progression/progressionAuditHelpers.js";
import {
  applyDailyXpCap,
  calculateActivityXp,
  calculateStreakMilestoneBonus,
  monthlyPeriodForCompletedAt,
} from "../src/progression/progressionCalculator.js";
import {
  calculateStreakExpiryTransition,
  calculateStreakTransition,
} from "../src/progression/streakCalculator.js";
import {
  assertCompletedAtNotInFuture,
  maxCompletedAtFutureSkewMs,
  progressionInstantFor,
} from "../src/run/completedAtFreshness.js";
import { parseRunCompletionPayload } from "../src/run/validateRunPayload.js";

/**
 * White-box cases W1–W15.
 *
 * Each case is written against a named internal function with knowledge of the
 * branch it exercises — the activity cap, the daily cap and its exhaustion, the
 * milestone selection loop, the streak day-delta arms, the payload allow-list,
 * the future-skew bound, the period clamp, and the leaderboard projection
 * bounds. These are the paths that decide XP, streaks and rank, i.e. the state
 * the client is never allowed to write.
 *
 * Pure calculation only: no Firestore, no emulator, no clock. Every case that
 * touches time pins its own "now".
 */

const config = DEFAULT_PROGRESSION_CONFIG;
const HOUR_MS = 60 * 60 * 1000;
// A fixed server "now", so the time-sensitive cases never drift with the wall
// clock.
const NOW_MS = Date.parse("2026-07-10T09:25:00.000Z");

describe("W1–W4 XP calculation and capping", () => {
  it("W1: caps one activity at the 100 XP activity cap and keeps the plan bonus visible", () => {
    // 15 km (150) + 120 active minutes (60) + base (20) + plan bonus (20) = 250
    // raw, which the per-activity cap must cut to 100. The bonus stays reported
    // separately so the runner still sees why the run was worth more than a
    // free run, even though the cap swallowed it.
    const result = calculateActivityXp(
      {
        distanceMeters: 15_000,
        activeDurationSeconds: 7_200,
        lowDataConfirmed: false,
        planCompletionBonusEligible: true,
      },
      config,
    );

    assert.equal(result.distanceXp, 150);
    assert.equal(result.durationXp, 60);
    assert.equal(result.planCompletionBonusXp, 20);
    assert.equal(result.rawXpBeforeActivityCap, 250);
    assert.equal(result.xpDeltaBeforeDailyCap, config.activityXpCap);
    assert.equal(result.activityCapApplied, true);
  });

  it("W2: awards only the remaining daily room, then nothing once the day is spent", () => {
    // 150 already earned leaves 50 of the 200 daily cap, so a 75 XP run is
    // truncated and closes the day exactly at the cap.
    const partial = applyDailyXpCap(
      { xpDeltaBeforeDailyCap: 75, dailyXpBefore: 150 },
      config,
    );
    assert.equal(partial.xpDelta, 50);
    assert.equal(partial.dailyXpAfter, config.dailyXpCap);
    assert.equal(partial.dailyCapApplied, true);

    // The same run against an exhausted day must award zero and leave the
    // day's total untouched — not go negative, and not top the day up.
    const exhausted = applyDailyXpCap(
      { xpDeltaBeforeDailyCap: 75, dailyXpBefore: 200 },
      config,
    );
    assert.equal(exhausted.xpDelta, 0);
    assert.equal(exhausted.dailyXpAfter, 200);
    assert.equal(exhausted.dailyCapApplied, true);
  });

  it("W3: pays only the highest milestone crossed in one jump, never the sum", () => {
    // A streak moving 1 -> 10 crosses both day 3 (30 XP) and day 7 (90 XP).
    // Paying both would be 120 XP; a repaired or backfilled streak that jumps
    // many days at once must not be able to mint XP that way.
    const bonus = calculateStreakMilestoneBonus(
      { previousStreak: 1, nextStreak: 10, highestPaidMilestoneDays: 0 },
      config,
    );

    assert.equal(bonus.milestoneDays, 7);
    assert.equal(bonus.bonusXp, 90);
  });

  it("W4: does not let a streak milestone bonus consume the day's XP budget", () => {
    // The milestone bonus is exempt from the daily cap, so the audit must net
    // it out of the stored xpDelta when reconstructing the day. A 680 XP day
    // that is 600 milestone counts as 80 against the cap — otherwise a single
    // milestone would block every later run that day from earning anything.
    const dailyCapDate = "2026-07-10";
    const counted = sumDailyXp(
      [
        { dailyCapDate, xpDelta: 680, streakBonusXp: 600 },
        // A different day never contributes, milestone or not.
        { dailyCapDate: "2026-07-09", xpDelta: 100 },
      ],
      dailyCapDate,
    );

    assert.equal(counted, 80);
  });
});

describe("W5–W7 streak transitions", () => {
  it("W5: resets an unprotected missed day to zero and flags the profile write", () => {
    // Last run 9 July, evaluated on 11 July: 10 July was simply missed.
    const transition = calculateStreakExpiryTransition({
      currentState: { streakCount: 4, lastStreakRunDate: "2026-07-09" },
      asOfDate: "2026-07-11",
    });

    assert.equal(transition.previousStreak, 4);
    assert.equal(transition.nextStreak, 0);
    assert.equal(transition.shouldUpdateProfile, true);
  });

  it("W6: holds the streak across a rest day the runner's plan declared", () => {
    // Same gap, but 10 July is a scheduled rest day, so the whole gap is
    // protected and no profile write is issued at all.
    const transition = calculateStreakExpiryTransition({
      currentState: { streakCount: 4, lastStreakRunDate: "2026-07-09" },
      asOfDate: "2026-07-11",
      protectedRestDates: ["2026-07-10"],
    });

    assert.equal(transition.nextStreak, 4);
    assert.equal(transition.shouldUpdateProfile, false);
  });

  it("W7: dates the streak by the Singapore calendar day, not the UTC one", () => {
    // 16:30 UTC on 10 July is 00:30 on 11 July in Singapore. Crediting the run
    // to the UTC day would make it a same-day repeat of 10 July and silently
    // stall the streak at 4.
    const transition = calculateStreakTransition({
      currentState: { streakCount: 4, lastStreakRunDate: "2026-07-10" },
      completedAt: "2026-07-10T16:30:00.000Z",
    });

    assert.equal(transition.nextStreak, 5);
    assert.equal(transition.nextStreakRunDate, "2026-07-11");
    assert.equal(transition.shouldUpdateProfile, true);
  });
});

describe("W8–W12 run submission validation", () => {
  it("W8: rejects a submission missing a required field before anything is written", () => {
    const { distanceMeters: _distanceMeters, ...withoutDistance } = runPayload();

    assert.throws(
      () => parseRunCompletionPayload(withoutDistance, { nowMs: NOW_MS }),
      hasHttpsCode("invalid-argument"),
    );
  });

  it("W9: rejects backend-owned fields that lie outside the client allow-list", () => {
    // These four are computed by the backend and enumerated as protected: a
    // client that names them is trying to write progression state directly.
    const backendOwned = {
      xp: 500,
      validationStatus: "validated",
      countsTowardProgression: true,
      leaderboardScore: 9_999,
    };

    for (const [key, value] of Object.entries(backendOwned)) {
      assert.throws(
        () => parseRunCompletionPayload({ ...runPayload(), [key]: value }, { nowMs: NOW_MS }),
        hasHttpsCode("invalid-argument"),
        `${key} must be rejected on its own, not only alongside the others`,
      );
    }

    assert.throws(
      () => parseRunCompletionPayload({ ...runPayload(), ...backendOwned }, { nowMs: NOW_MS }),
      hasHttpsCode("invalid-argument"),
    );
  });

  it("W10: rejects three individually-legal values that cannot describe the same run", () => {
    // 60 s, 100,000 m and 600 s/km each sit inside their own bounds — the
    // duration limit, the distance limit and the pace band. Together they
    // claim a 100 km run in a minute, which only the cross-field consistency
    // check can catch.
    const completedAtMs = NOW_MS - HOUR_MS;
    const inconsistent = {
      ...runPayload(),
      startedAt: isoAt(completedAtMs - 60_000),
      completedAt: isoAt(completedAtMs),
      durationSeconds: 60,
      distanceMeters: 100_000,
      avgPaceSecondsPerKm: 600,
    };

    assert.throws(
      () => parseRunCompletionPayload(inconsistent, { nowMs: NOW_MS }),
      hasHttpsCode("invalid-argument"),
    );
  });

  it("W11: accepts a device clock up to six hours fast and rejects the next second", () => {
    // A misconfigured timezone must not cost the runner their run — the
    // pending-run store retries the same payload and would fail forever.
    for (const skewMs of [0, HOUR_MS, maxCompletedAtFutureSkewMs]) {
      assert.doesNotThrow(() =>
        assertCompletedAtNotInFuture(isoAt(NOW_MS + skewMs), NOW_MS),
      );
    }

    assert.throws(
      () =>
        assertCompletedAtNotInFuture(
          isoAt(NOW_MS + maxCompletedAtFutureSkewMs + 1_000),
          NOW_MS,
        ),
      hasHttpsCode("invalid-argument"),
    );
  });

  it("W12: keeps an accepted future completedAt from choosing its leaderboard period", () => {
    // 30 June 23:30 Singapore (15:30Z). A device four hours fast names 1 July
    // in Singapore — inside the six-hour allowance, so the run is kept, but
    // the period must be clamped to server time or the runner banks XP into
    // next month's board.
    const nowMs = Date.parse("2026-06-30T15:30:00.000Z");
    const claimed = isoAt(nowMs + 4 * HOUR_MS);

    assert.doesNotThrow(() => assertCompletedAtNotInFuture(claimed, nowMs));
    assert.equal(monthlyPeriodForCompletedAt(claimed), "2026-07");
    assert.equal(
      monthlyPeriodForCompletedAt(progressionInstantFor(claimed, nowMs)),
      "2026-06",
    );
  });
});

describe("W13–W15 monthly leaderboard projection", () => {
  it("W13: bounds public rows at ten, centres a five-row window, and never publishes ownerUid", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      contributions: Array.from({ length: 15 }, (_, index) =>
        contribution({
          ownerUid: `runner-${String(index + 1).padStart(2, "0")}`,
          scoreXp: 1_000 - index,
        }),
      ),
    });

    const snapshot = plan.snapshots[0];
    assert.equal(snapshot?.entryCount, 15);
    assert.equal(snapshot?.topEntries.length, 10);

    const rank = plan.ranks.find((item) => item.ownerUid === "runner-12");
    assert.equal(rank?.rankLabel, "#12");
    assert.equal(rank?.nearbyEntries.length, 5);
    assert.deepEqual(
      rank?.nearbyEntries.map((entry) => entry.rankLabel),
      ["#10", "#11", "#12", "#13", "#14"],
    );

    // A published row is a projection, not the contribution: the owner
    // identifier must not survive into anything readable by other runners.
    for (const entry of [...(snapshot?.topEntries ?? []), ...(rank?.nearbyEntries ?? [])]) {
      assert.equal(Object.hasOwn(entry, "ownerUid"), false);
    }
    assert.equal(Object.hasOwn(rank?.currentEntry ?? {}, "ownerUid"), false);
  });

  it("W14: leaves a contribution short of the minimum qualifying runs off the board", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      minRunsToQualify: 3,
      contributions: [
        contribution({ ownerUid: "under-quota", scoreXp: 70, qualifyingRunCount: 2 }),
      ],
    });

    assert.deepEqual(
      plan.snapshots.flatMap((snapshot) => snapshot.topEntries),
      [],
    );
    // The runner still gets a view of their own standing, naming the shortfall
    // rather than leaving them with nothing to read.
    assert.equal(
      plan.currentViews.find((view) => view.ownerUid === "under-quota")?.status,
      "ineligible_min_runs",
    );
  });

  it("W15: ranks Premium and Basic on score alone, so the subscription confers no advantage", () => {
    const plan = planMonthlyLeaderboards({
      periodKey: "2026-07",
      currentPremiumUids: new Set(["premium"]),
      contributions: [
        contribution({ ownerUid: "basic", scoreXp: 70 }),
        contribution({ ownerUid: "premium", scoreXp: 500 }),
      ],
    });

    assert.deepEqual(
      plan.snapshots.flatMap((snapshot) =>
        snapshot.topEntries.map((entry) => [entry.rankLabel, entry.publicAlias]),
      ),
      [
        ["#1", "Runner premium"],
        ["#2", "Runner basic"],
      ],
    );
    assert.deepEqual(
      plan.currentViews.map((view) => [view.ownerUid, view.status]).sort(),
      [
        ["basic", "ranked"],
        ["premium", "ranked"],
      ],
    );
  });
});

function isoAt(ms: number): string {
  return new Date(ms).toISOString();
}

/** A minimal submission that parses cleanly, for the rejection cases to spoil. */
function runPayload(): Record<string, unknown> {
  const completedAtMs = NOW_MS - HOUR_MS;
  const durationSeconds = 1_500;
  return {
    clientRunSessionId: "whitebox-session",
    startedAt: isoAt(completedAtMs - durationSeconds * 1_000),
    completedAt: isoAt(completedAtMs),
    durationSeconds,
    distanceMeters: 3_200,
    avgPaceSecondsPerKm: 469,
    source: "mobile",
    routePrivacy: "private",
  };
}

function contribution(input: {
  readonly ownerUid: string;
  readonly scoreXp: number;
  readonly qualifyingRunCount?: number;
}): Record<string, unknown> {
  return {
    schemaVersion: 2,
    ownerUid: input.ownerUid,
    publicAlias: `Runner ${input.ownerUid}`,
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
    scoreXp: input.scoreXp,
    eligible: true,
    eligibilityReason: "eligible_basic_awarded_xp",
    lastProgressionAt: "2026-07-10T00:00:00.000Z",
    sourceProgressionEventIds: [`event-${input.ownerUid}`],
    ...(input.qualifyingRunCount === undefined
      ? {}
      : { qualifyingRunCount: input.qualifyingRunCount }),
  };
}

function hasHttpsCode(code: string): (error: unknown) => boolean {
  return (error) => {
    assert.equal((error as { code?: string }).code, code);
    return true;
  };
}
