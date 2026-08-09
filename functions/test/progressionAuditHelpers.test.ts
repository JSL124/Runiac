import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Timestamp } from "firebase-admin/firestore";
import {
  isPremiumSubscription,
  sumDailyXp,
  sumMonthlyXp,
} from "../src/progression/progressionAuditHelpers.js";

const nowMs = Date.UTC(2026, 6, 13, 10, 0, 0);
const pastMs = nowMs - 24 * 60 * 60 * 1000;
const futureMs = nowMs + 24 * 60 * 60 * 1000;

describe("isPremiumSubscription", () => {
  it("is not premium when subscriptionStatus is basic or absent", () => {
    assert.equal(isPremiumSubscription({ subscriptionStatus: "basic" }, nowMs), false);
    assert.equal(isPremiumSubscription(undefined, nowMs), false);
    assert.equal(isPremiumSubscription({}, nowMs), false);
  });

  it("stays premium forever when subscriptionExpiresAt is absent (zero regression for existing docs)", () => {
    assert.equal(isPremiumSubscription({ subscriptionStatus: "premium" }, nowMs), true);
    assert.equal(
      isPremiumSubscription({ subscriptionStatus: "premium", subscriptionExpiresAt: null }, nowMs),
      true,
    );
  });

  it("stays premium while subscriptionExpiresAt (Timestamp) is in the future", () => {
    const data = {
      subscriptionStatus: "premium",
      subscriptionExpiresAt: Timestamp.fromMillis(futureMs),
    };
    assert.equal(isPremiumSubscription(data, nowMs), true);
  });

  it("is not premium once subscriptionExpiresAt (Timestamp) is in the past", () => {
    const data = {
      subscriptionStatus: "premium",
      subscriptionExpiresAt: Timestamp.fromMillis(pastMs),
    };
    assert.equal(isPremiumSubscription(data, nowMs), false);
  });

  // The stored contract is Timestamp-only. Non-Timestamp shapes are uniformly
  // treated as "no expiry" here, by the expiry sweep, and by firestore.rules,
  // so the three can never disagree about a given document. See the comment on
  // readSubscriptionExpiresAtMs() for why a tolerant reader was actively
  // harmful: Firestore orders values by type before value, so a millis number
  // is selected by the sweep's `<= Timestamp` range query even when it is in
  // the future, and an ISO string is never selected even once it has lapsed.
  it("treats an ISO string expiry as no-expiry, matching the sweep", () => {
    assert.equal(
      isPremiumSubscription(
        { subscriptionStatus: "premium", subscriptionExpiresAt: new Date(pastMs).toISOString() },
        nowMs,
      ),
      true,
    );
  });

  it("treats a millis-number expiry as no-expiry, matching the sweep", () => {
    assert.equal(
      isPremiumSubscription({ subscriptionStatus: "premium", subscriptionExpiresAt: pastMs }, nowMs),
      true,
    );
    assert.equal(
      isPremiumSubscription({ subscriptionStatus: "premium", subscriptionExpiresAt: futureMs }, nowMs),
      true,
    );
  });

  it("treats the boundary instant (expiresAt === now) as expired", () => {
    assert.equal(
      isPremiumSubscription(
        { subscriptionStatus: "premium", subscriptionExpiresAt: Timestamp.fromMillis(nowMs) },
        nowMs,
      ),
      false,
    );
  });

  it("treats an unparseable expiry value as no-expiry rather than throwing", () => {
    assert.equal(
      isPremiumSubscription({ subscriptionStatus: "premium", subscriptionExpiresAt: "not-a-date" }, nowMs),
      true,
    );
    assert.equal(
      isPremiumSubscription({ subscriptionStatus: "premium", subscriptionExpiresAt: {} }, nowMs),
      true,
    );
  });

  it("accepts the legacy capitalized 'Premium' status", () => {
    assert.equal(isPremiumSubscription({ subscriptionStatus: "Premium" }, nowMs), true);
  });
});

describe("sumMonthlyXp", () => {
  // Deliberate asymmetry with sumDailyXp: the daily sum nets streakBonusXp out
  // so an exempt milestone does not consume the day's 200 XP budget, but the
  // monthly sum keeps the full stored xpDelta — a milestone bonus is real
  // earned XP and must count toward monthly XP and leaderboard scoreXp.
  it("counts streakBonusXp toward the monthly total that sumDailyXp nets out", () => {
    const milestoneRun = {
      monthlyPeriod: "2026-07",
      dailyCapDate: "2026-07-13",
      xpDelta: 90,
      streakBonusXp: 30,
    };
    const plainRun = {
      monthlyPeriod: "2026-07",
      dailyCapDate: "2026-07-13",
      xpDelta: 60,
    };
    const otherMonthRun = {
      monthlyPeriod: "2026-06",
      dailyCapDate: "2026-06-30",
      xpDelta: 100,
      streakBonusXp: 100,
    };
    const events = [milestoneRun, plainRun, otherMonthRun];

    // Monthly: 90 + 60 — the 30 XP milestone stays in, the other month is out.
    assert.equal(sumMonthlyXp(events, "2026-07"), 150);
    // Daily, same events: (90 - 30) + 60 — the milestone is netted back out.
    assert.equal(sumDailyXp(events, "2026-07-13"), 120);
  });
});
