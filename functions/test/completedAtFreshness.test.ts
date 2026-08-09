import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  assertCompletedAtNotInFuture,
  maxCompletedAtFutureSkewMs,
  progressionInstantFor,
} from "../src/run/completedAtFreshness.js";
import {
  dailyCapDateForCompletedAt,
  monthlyPeriodForCompletedAt,
} from "../src/progression/progressionCalculator.js";
import { parseCoolDownCompletionPayload } from "../src/run/validateCoolDownPayload.js";
import { parseRunCompletionPayload } from "../src/run/validateRunPayload.js";

// A fixed server "now", so these cases never drift with the wall clock.
const NOW_MS = Date.parse("2026-06-14T09:25:00.000Z");
const HOUR_MS = 60 * 60 * 1000;

describe("completedAt future bound", () => {
  it("allows a device clock running up to six hours fast", () => {
    // A misconfigured timezone must not cost the runner their run: the
    // pending-run store would retry the same payload and fail forever.
    for (const skewMs of [0, HOUR_MS, maxCompletedAtFutureSkewMs]) {
      assert.doesNotThrow(() =>
        assertCompletedAtNotInFuture(isoAt(NOW_MS + skewMs), NOW_MS),
      );
    }
  });

  it("rejects a completedAt beyond the allowance", () => {
    assert.throws(
      () => assertCompletedAtNotInFuture(isoAt(NOW_MS + maxCompletedAtFutureSkewMs + 1000), NOW_MS),
      hasHttpsCode("invalid-argument"),
    );
  });

  it("still accepts a backdated offline re-upload", () => {
    // Bounding the past direction is deliberately out of scope: a run
    // uploaded days later is the normal offline case.
    assert.doesNotThrow(() =>
      assertCompletedAtNotInFuture(isoAt(NOW_MS - 30 * 24 * HOUR_MS), NOW_MS),
    );
  });

  it("bounds the run payload, whose dailyCapDate and monthlyPeriod derive from it", () => {
    // Without this, a caller could name any future day and bank XP into a
    // daily cap that has not happened yet or a leaderboard month that has
    // not started.
    const futureMs = NOW_MS + 48 * HOUR_MS;
    assert.throws(
      () =>
        parseRunCompletionPayload(
          runPayloadEndingAt(futureMs),
          { nowMs: NOW_MS },
        ),
      hasHttpsCode("invalid-argument"),
    );

    const accepted = parseRunCompletionPayload(
      runPayloadEndingAt(NOW_MS + 2 * HOUR_MS),
      { nowMs: NOW_MS },
    );
    assert.equal(accepted.completedAt, isoAt(NOW_MS + 2 * HOUR_MS));
  });

  it("bounds the cool-down payload on the same rule", () => {
    // completeCoolDown derives its own dailyCapDate and monthlyPeriod from
    // this field too, so leaving it open would half-close the vector.
    assert.throws(
      () =>
        parseCoolDownCompletionPayload(
          coolDownPayloadAt(NOW_MS + 48 * HOUR_MS),
          { nowMs: NOW_MS },
        ),
      hasHttpsCode("invalid-argument"),
    );

    const accepted = parseCoolDownCompletionPayload(
      coolDownPayloadAt(NOW_MS - HOUR_MS),
      { nowMs: NOW_MS },
    );
    assert.equal(accepted.completedAt, isoAt(NOW_MS - HOUR_MS));
  });
});

describe("progression instant clamp", () => {
  it("does not let an accepted future completedAt choose the next day's cap", () => {
    // 23:30 Singapore = 15:30Z. A device four hours fast names 03:30 the next
    // Singapore day, which is inside the six-hour acceptance allowance — so the
    // run is kept, but it must not spend tomorrow's untouched daily cap.
    const nowMs = Date.parse("2026-06-14T15:30:00.000Z");
    const claimed = isoAt(nowMs + 4 * HOUR_MS);

    assert.doesNotThrow(() => assertCompletedAtNotInFuture(claimed, nowMs));
    assert.notEqual(
      dailyCapDateForCompletedAt(claimed),
      dailyCapDateForCompletedAt(isoAt(nowMs)),
    );
    assert.equal(
      dailyCapDateForCompletedAt(progressionInstantFor(claimed, nowMs)),
      dailyCapDateForCompletedAt(isoAt(nowMs)),
    );
  });

  it("does not let an accepted future completedAt bank XP into next month", () => {
    // 30 June 23:30 Singapore. Four hours fast lands in July.
    const nowMs = Date.parse("2026-06-30T15:30:00.000Z");
    const claimed = isoAt(nowMs + 4 * HOUR_MS);

    assert.equal(monthlyPeriodForCompletedAt(claimed), "2026-07");
    assert.equal(
      monthlyPeriodForCompletedAt(progressionInstantFor(claimed, nowMs)),
      "2026-06",
    );
  });

  it("leaves a past completedAt on its own period", () => {
    // An offline re-upload must still land in the period it was run in.
    const nowMs = Date.parse("2026-07-02T04:00:00.000Z");
    const ranAt = "2026-06-28T04:00:00.000Z";

    assert.equal(progressionInstantFor(ranAt, nowMs), ranAt);
    assert.equal(monthlyPeriodForCompletedAt(progressionInstantFor(ranAt, nowMs)), "2026-06");
  });
});

function isoAt(ms: number): string {
  return new Date(ms).toISOString();
}

function runPayloadEndingAt(completedAtMs: number): Record<string, unknown> {
  const durationSeconds = 1500;
  return {
    clientRunSessionId: "freshness-session",
    startedAt: isoAt(completedAtMs - durationSeconds * 1000),
    completedAt: isoAt(completedAtMs),
    durationSeconds,
    distanceMeters: 3200,
    avgPaceSecondsPerKm: 469,
    source: "mobile",
    routePrivacy: "private",
  };
}

function coolDownPayloadAt(completedAtMs: number): Record<string, unknown> {
  return {
    activityId: "activity-freshness",
    clientRunSessionId: "freshness-session",
    completedStretchCount: 14,
    completedAt: isoAt(completedAtMs),
  };
}

function hasHttpsCode(code: string): (error: unknown) => boolean {
  return (error) => {
    assert.equal((error as { code?: string }).code, code);
    return true;
  };
}
