import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { completeCoolDownForCallable } from "../src/run/completeCoolDown.js";
import { completeRunForCallable } from "../src/run/completeRun.js";
import { deterministicIds } from "../src/run/runCompletionArtifacts.js";
import { DEFAULT_PROGRESSION_CONFIG } from "../src/config/configLoader.js";
import { calculateCoolDownBonus } from "../src/progression/progressionCalculator.js";

const PROJECT_ID = "runiac-functions-test";
const USER_UID = "cooldown-runner-001";

type CallableRequest = {
  readonly auth?: {
    readonly uid: string;
  };
  readonly data: unknown;
};

let firestore: Firestore;

before(() => {
  if (getApps().length === 0) {
    initializeApp({ projectId: PROJECT_ID });
  }

  firestore = getFirestore();
});

beforeEach(async () => {
  await clearCollections([
    "activities",
    "runSummaries",
    "progressionEvents",
    "users",
    "userProfiles",
    "generatedPlans",
    "planProgress",
    "adaptivePlanEstimates",
    "leaderboardContributions",
  ]);
  await firestore.doc(`userProfiles/${USER_UID}`).set({
    nickname: "Cooldown Runner",
    locationLabel: "Jurong East, Singapore",
  });
});

describe("completeCoolDown callable boundary", () => {
  it("fails when auth is missing", async () => {
    await expectRejectsCode(
      () =>
        completeCoolDownForCallable(
          { data: coolDownPayload({ activityId: "activity_anything", clientRunSessionId: "any" }) },
          firestore,
        ),
      "unauthenticated",
    );
  });

  it("rejects a suspended caller with permission-denied, even for an already-validated run (defence-in-depth)", async () => {
    const clientRunSessionId = "session-suspended-caller";
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload(clientRunSessionId) },
      firestore,
    );

    await firestore.doc(`users/${USER_UID}`).set({ accountStatus: "banned" });

    await expectRejectsCode(
      () =>
        callCompleteCoolDown({
          auth: { uid: USER_UID },
          data: coolDownPayload({ activityId: runResult.activityId, clientRunSessionId }),
        }),
      "permission-denied",
    );

    const activity = await firestore.doc(`activities/${runResult.activityId}`).get();
    assert.notEqual(activity.get("coolDownXpAwarded"), true);
  });

  it("rejects a completedStretchCount below the full sequence", async () => {
    await expectRejectsCode(
      () =>
        callCompleteCoolDown({
          auth: { uid: USER_UID },
          data: coolDownPayload({
            activityId: "activity_anything",
            clientRunSessionId: "session-invalid-count-low",
            completedStretchCount: 13,
          }),
        }),
      "invalid-argument",
    );
  });

  it("rejects a completedStretchCount above the full sequence", async () => {
    await expectRejectsCode(
      () =>
        callCompleteCoolDown({
          auth: { uid: USER_UID },
          data: coolDownPayload({
            activityId: "activity_anything",
            clientRunSessionId: "session-invalid-count-high",
            completedStretchCount: 15,
          }),
        }),
      "invalid-argument",
    );
  });

  it("rejects an activityId that does not match the derived run session id", async () => {
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload("session-mismatch") },
      firestore,
    );

    await expectRejectsCode(
      () =>
        callCompleteCoolDown({
          auth: { uid: USER_UID },
          data: coolDownPayload({
            activityId: "activity_0000000000000000000000",
            clientRunSessionId: "session-mismatch",
          }),
        }),
      "invalid-argument",
    );

    // sanity: the derived id from the actual run is different from our mismatch fixture.
    assert.notEqual(runResult.activityId, "activity_0000000000000000000000");
  });

  it("fails with not-found when the derived run was never completed", async () => {
    const clientRunSessionId = "session-never-completed";
    const ids = deterministicIds(USER_UID, clientRunSessionId);

    await expectRejectsCode(
      () =>
        callCompleteCoolDown({
          auth: { uid: USER_UID },
          data: coolDownPayload({ activityId: ids.activityId, clientRunSessionId }),
        }),
      "not-found",
    );
  });

  it("fails with permission-denied when the activity belongs to another owner", async () => {
    const clientRunSessionId = "session-permission-denied";
    const ids = deterministicIds(USER_UID, clientRunSessionId);
    await firestore.doc(`activities/${ids.activityId}`).set({
      ownerUid: "someone-else",
      validationStatus: "validated",
    });

    await expectRejectsCode(
      () =>
        callCompleteCoolDown({
          auth: { uid: USER_UID },
          data: coolDownPayload({ activityId: ids.activityId, clientRunSessionId }),
        }),
      "permission-denied",
    );
  });

  it("fails with failed-precondition when the run is not yet validated", async () => {
    const clientRunSessionId = "session-not-validated";
    const ids = deterministicIds(USER_UID, clientRunSessionId);
    await firestore.doc(`activities/${ids.activityId}`).set({
      ownerUid: USER_UID,
      validationStatus: "pending",
    });

    await expectRejectsCode(
      () =>
        callCompleteCoolDown({
          auth: { uid: USER_UID },
          data: coolDownPayload({ activityId: ids.activityId, clientRunSessionId }),
        }),
      "failed-precondition",
    );
  });

  it("awards a server-computed bonus after a validated run", async () => {
    const clientRunSessionId = "session-award-bonus";
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload(clientRunSessionId) },
      firestore,
    );
    const baseXp = runResult.progressionDisplay.xpDelta;
    assert.equal(baseXp, 60);
    const expectedBonus = calculateCoolDownBonus(baseXp, DEFAULT_PROGRESSION_CONFIG);
    assert.equal(expectedBonus, 10);

    const result = await callCompleteCoolDown({
      auth: { uid: USER_UID },
      data: coolDownPayload({ activityId: runResult.activityId, clientRunSessionId }),
    });

    assert.equal(result.alreadyAwarded, false);
    assert.equal(result.progressionDisplay.xpDelta, expectedBonus);
    assert.equal(result.progressionDisplay.status, "awarded");
    assert.equal(result.progressionDisplay.reason, "cool_down_stretch_bonus_awarded");

    const activity = await firestore.doc(`activities/${runResult.activityId}`).get();
    assert.equal(activity.get("coolDownXpAwarded"), true);
    assert.equal(activity.get("coolDownProgressionEventId"), result.coolDownProgressionEventId);

    const coolDownEvent = await firestore.doc(`progressionEvents/${result.coolDownProgressionEventId}`).get();
    assert.equal(coolDownEvent.exists, true);
    assert.equal(coolDownEvent.get("eventType"), "cool_down_stretch_bonus");
    assert.equal(coolDownEvent.get("xpDelta"), expectedBonus);
    assert.equal(coolDownEvent.get("ownerUid"), USER_UID);

    const profile = await firestore.doc(`userProfiles/${USER_UID}`).get();
    assert.equal(profile.get("totalXp"), baseXp + expectedBonus);

    const contribution = await firestore
      .doc(`leaderboardContributions/${USER_UID}_monthly_2026-06`)
      .get();
    assert.equal(contribution.get("scoreXp"), baseXp + expectedBonus);
    assert.deepEqual(contribution.get("sourceProgressionEventIds"), [
      runResult.progressionEventId,
      result.coolDownProgressionEventId,
    ]);
  });

  it("is idempotent on replay and does not double-award or double-count the leaderboard", async () => {
    const clientRunSessionId = "session-idempotent-replay";
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload(clientRunSessionId) },
      firestore,
    );
    const request: CallableRequest = {
      auth: { uid: USER_UID },
      data: coolDownPayload({ activityId: runResult.activityId, clientRunSessionId }),
    };

    const first = await callCompleteCoolDown(request);
    const second = await callCompleteCoolDown(request);

    assert.equal(first.alreadyAwarded, false);
    assert.equal(second.alreadyAwarded, true);
    assert.equal(second.progressionDisplay.xpDelta, first.progressionDisplay.xpDelta);
    assert.deepEqual(second.progressionDisplay, first.progressionDisplay);

    const profile = await firestore.doc(`userProfiles/${USER_UID}`).get();
    assert.equal(profile.get("totalXp"), runResult.progressionDisplay.xpDelta + first.progressionDisplay.xpDelta);

    const contribution = await firestore
      .doc(`leaderboardContributions/${USER_UID}_monthly_2026-06`)
      .get();
    assert.equal(
      contribution.get("scoreXp"),
      runResult.progressionDisplay.xpDelta + first.progressionDisplay.xpDelta,
    );
    assert.equal(await countDocuments("progressionEvents"), 2);
  });

  it("reduces the bonus when the daily XP cap is nearly exhausted", async () => {
    const clientRunSessionId = "session-daily-cap-partial";
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload(clientRunSessionId) },
      firestore,
    );
    assert.equal(runResult.progressionDisplay.xpDelta, 60);
    await firestore.collection("progressionEvents").doc("preseed-daily-cap-partial").set({
      ownerUid: USER_UID,
      dailyCapDate: "2026-06-14",
      monthlyPeriod: "2026-06",
      xpDelta: 131,
    });

    const result = await callCompleteCoolDown({
      auth: { uid: USER_UID },
      data: coolDownPayload({ activityId: runResult.activityId, clientRunSessionId }),
    });

    assert.equal(result.progressionDisplay.xpDelta, 9);
    assert.equal(result.progressionDisplay.status, "awarded");
    assert.equal(result.progressionDisplay.reason, "cool_down_stretch_bonus_awarded");

    const coolDownEvent = await firestore.doc(`progressionEvents/${result.coolDownProgressionEventId}`).get();
    assert.equal(coolDownEvent.get("dailyCapApplied"), true);
    assert.equal(coolDownEvent.get("rawXpBeforeDailyCap"), 10);
  });

  it("awards zero XP once the daily XP cap is fully exhausted", async () => {
    const clientRunSessionId = "session-daily-cap-exhausted";
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload(clientRunSessionId) },
      firestore,
    );
    assert.equal(runResult.progressionDisplay.xpDelta, 60);
    await firestore.collection("progressionEvents").doc("preseed-daily-cap-exhausted").set({
      ownerUid: USER_UID,
      dailyCapDate: "2026-06-14",
      monthlyPeriod: "2026-06",
      xpDelta: 140,
    });

    const result = await callCompleteCoolDown({
      auth: { uid: USER_UID },
      data: coolDownPayload({ activityId: runResult.activityId, clientRunSessionId }),
    });

    assert.equal(result.progressionDisplay.xpDelta, 0);
    assert.equal(result.progressionDisplay.status, "not_awarded");
    assert.equal(result.progressionDisplay.reason, "cool_down_daily_cap_reached");

    const contribution = await firestore
      .doc(`leaderboardContributions/${USER_UID}_monthly_2026-06`)
      .get();
    assert.equal(contribution.get("scoreXp"), 60);
  });

  // The stretch bonus is a percentage of what the run actually CREDITED, not
  // of its raw pre-cap value. A late-night run partially trimmed by the daily
  // cap (raw 60, credited 30) followed by a stretch after Singapore midnight
  // (fresh daily budget, so the cool-down's own cap trims nothing) must pay
  // round(30 * 0.2 / 5) * 5 = 5, not the round(60 * 0.2 / 5) * 5 = 10 the raw
  // amount would produce.
  it("derives the stretch bonus from the credited daily-capped run XP, not the raw pre-cap value", async () => {
    // 170 XP already earned on SGT 2026-06-14 leaves 30 of the 200 daily cap.
    await firestore.collection("progressionEvents").doc("preseed-credited-base").set({
      ownerUid: USER_UID,
      dailyCapDate: "2026-06-14",
      monthlyPeriod: "2026-06",
      xpDelta: 170,
    });
    const clientRunSessionId = "session-credited-base-bonus";
    // 15:40Z is 23:40 SGT on 2026-06-14: raw 60 XP (20 base + 30 distance +
    // 10 duration), credited only the remaining 30.
    const runResult = await completeRunForCallable(
      {
        auth: { uid: USER_UID },
        data: {
          ...validRunPayload(clientRunSessionId),
          startedAt: "2026-06-14T15:15:00.000Z",
          completedAt: "2026-06-14T15:40:00.000Z",
        },
      },
      firestore,
    );
    assert.equal(runResult.progressionDisplay.xpDelta, 30);

    // 16:10Z is 00:10 SGT on 2026-06-15: a fresh 200 XP daily budget, so the
    // only thing that can shrink the bonus is the credited base itself.
    const result = await callCompleteCoolDown({
      auth: { uid: USER_UID },
      data: coolDownPayload({
        activityId: runResult.activityId,
        clientRunSessionId,
        completedAt: "2026-06-14T16:10:00.000Z",
      }),
    });

    assert.equal(result.progressionDisplay.xpDelta, 5);
    assert.equal(result.progressionDisplay.status, "awarded");
    assert.equal(result.progressionDisplay.reason, "cool_down_stretch_bonus_awarded");

    const coolDownEvent = await firestore
      .doc(`progressionEvents/${result.coolDownProgressionEventId}`)
      .get();
    assert.equal(coolDownEvent.get("baseEarnedXp"), 30);
    assert.equal(coolDownEvent.get("rawXpBeforeDailyCap"), 5);
    assert.equal(coolDownEvent.get("dailyCapDate"), "2026-06-15");
    assert.equal(coolDownEvent.get("dailyCapApplied"), false);

    const profile = await firestore.doc(`userProfiles/${USER_UID}`).get();
    assert.equal(profile.get("totalXp"), 35);
  });

  // Premium parity: the stretch bonus follows the same rule as the run itself.
  // Regression: the cool-down bonus is a percentage of the ACTIVITY's XP, but
  // it was read from the run event's `xpDelta`, which since the milestone
  // exemption also carries the streak bonus. calculateCoolDownBonus() clamps
  // to `activityXpCap - baseEarnedXp`, so a milestone run made that term
  // negative and silently paid nothing — while reporting "low_data_no_xp" on a
  // full-GPS run.
  it("still pays the stretch bonus on a run that also paid a streak milestone", async () => {
    await firestore.doc(`userProfiles/${USER_UID}`).set(
      { streakCount: 2, lastStreakRunDate: "2026-06-13" },
      { merge: true },
    );
    const clientRunSessionId = "session-milestone-then-cooldown";
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload(clientRunSessionId) },
      firestore,
    );
    // 60 base + 30 for crossing the 3-day milestone.
    assert.equal(runResult.progressionDisplay.xpDelta, 90);

    const result = await callCompleteCoolDown({
      auth: { uid: USER_UID },
      data: coolDownPayload({ activityId: runResult.activityId, clientRunSessionId }),
    });

    // Derived from the 60 XP base, NOT the 90 XP total.
    assert.equal(result.progressionDisplay.xpDelta, 10);
    assert.equal(result.progressionDisplay.status, "awarded");
    assert.equal(result.progressionDisplay.reason, "cool_down_stretch_bonus_awarded");
  });

  it("gives premium users the same cool-down bonus as basic users", async () => {
    await firestore.doc(`users/${USER_UID}`).set({ subscriptionStatus: "premium" });
    const clientRunSessionId = "session-premium-parity-bonus";
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload(clientRunSessionId) },
      firestore,
    );
    assert.equal(runResult.progressionDisplay.xpDelta, 60);

    const result = await callCompleteCoolDown({
      auth: { uid: USER_UID },
      data: coolDownPayload({ activityId: runResult.activityId, clientRunSessionId }),
    });

    assert.equal(result.progressionDisplay.status, "awarded");
    assert.equal(result.progressionDisplay.countsTowardLeaderboard, true);
    assert.ok(
      result.progressionDisplay.xpDelta > 0,
      "a premium runner must earn the same stretch bonus a basic runner earns",
    );
  });

  // Suppression is still supported, just no longer the default.
  it("gives premium users no cool-down XP when premiumEarnsXp is false", async () => {
    await firestore.doc("config/progression").set({ premiumEarnsXp: false });
    await firestore.doc(`users/${USER_UID}`).set({ subscriptionStatus: "premium" });
    const clientRunSessionId = "session-premium-no-bonus";
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload(clientRunSessionId) },
      firestore,
    );
    assert.equal(runResult.progressionDisplay.xpDelta, 0);
    assert.equal(runResult.progressionDisplay.reason, "premium_no_progression");

    const result = await callCompleteCoolDown({
      auth: { uid: USER_UID },
      data: coolDownPayload({ activityId: runResult.activityId, clientRunSessionId }),
    });

    assert.equal(result.progressionDisplay.xpDelta, 0);
    assert.equal(result.progressionDisplay.status, "not_awarded");
    assert.equal(result.progressionDisplay.reason, "premium_no_progression");
    assert.equal(result.progressionDisplay.countsTowardLeaderboard, false);

    const contribution = await firestore
      .doc(`leaderboardContributions/${USER_UID}_monthly_2026-06`)
      .get();
    assert.equal(contribution.exists, false);

    await firestore.doc("config/progression").delete();
  });

  // The cool-down path has no streak transition of its own and must never
  // award a streak milestone bonus, regardless of the runner's live streak.
  it("pins streak bonus fields to zero/null on the cool-down event", async () => {
    const clientRunSessionId = "session-cooldown-no-streak-bonus";
    await firestore.doc(`userProfiles/${USER_UID}`).set(
      { streakCount: 2, lastStreakRunDate: "2026-06-13" },
      { merge: true },
    );
    const runResult = await completeRunForCallable(
      { auth: { uid: USER_UID }, data: validRunPayload(clientRunSessionId) },
      firestore,
    );
    // Sanity: the base run itself crossed the 3-day milestone.
    assert.equal(runResult.progressionDisplay.streak, 3);

    const result = await callCompleteCoolDown({
      auth: { uid: USER_UID },
      data: coolDownPayload({ activityId: runResult.activityId, clientRunSessionId }),
    });

    const coolDownEvent = await firestore
      .doc(`progressionEvents/${result.coolDownProgressionEventId}`)
      .get();
    assert.equal(coolDownEvent.get("streakBonusXp"), 0);
    assert.equal(coolDownEvent.get("streakMilestoneDays"), null);
    assert.equal(coolDownEvent.get("streakBonusCapped"), false);
  });
});

async function callCompleteCoolDown(request: CallableRequest): Promise<{
  readonly activityId: string;
  readonly coolDownProgressionEventId: string;
  readonly alreadyAwarded: boolean;
  readonly progressionDisplay: {
    readonly xpDelta: number;
    readonly countsTowardLeaderboard: boolean;
    readonly status: string;
    readonly reason: string;
  };
}> {
  return completeCoolDownForCallable(request, firestore);
}

function validRunPayload(clientRunSessionId: string): Record<string, unknown> {
  return {
    clientRunSessionId,
    startedAt: "2026-06-14T09:00:00.000Z",
    completedAt: "2026-06-14T09:25:00.000Z",
    durationSeconds: 1500,
    distanceMeters: 3200,
    avgPaceSecondsPerKm: 469,
    source: "mobile",
    routePrivacy: "private",
    activityTitle: "Sunday Morning Run",
  };
}

function coolDownPayload(fields: {
  readonly activityId: string;
  readonly clientRunSessionId: string;
  readonly completedStretchCount?: number;
  readonly completedAt?: string;
}): Record<string, unknown> {
  return {
    activityId: fields.activityId,
    clientRunSessionId: fields.clientRunSessionId,
    completedStretchCount: fields.completedStretchCount ?? 14,
    completedAt: fields.completedAt ?? "2026-06-14T09:35:00.000Z",
  };
}

async function expectRejectsCode(action: () => Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(action, (error: unknown) => {
    assert.equal(getErrorCode(error), code);
    return true;
  });
}

function getErrorCode(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    const code = error.code;
    if (typeof code === "string") {
      return code;
    }
  }

  return "";
}

async function clearCollections(collectionNames: readonly string[]): Promise<void> {
  await Promise.all(
    collectionNames.map(async (collectionName) => {
      const snapshot = await firestore.collection(collectionName).get();
      await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
    }),
  );
}

async function countDocuments(collectionName: string): Promise<number> {
  const snapshot = await firestore.collection(collectionName).get();
  return snapshot.size;
}
