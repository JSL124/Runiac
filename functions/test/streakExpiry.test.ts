import assert from "node:assert/strict";
import { before, beforeEach, describe, it } from "node:test";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { refreshStreakStatusForCallable } from "../src/progression/refreshStreakStatus.js";
import {
  calculateStreakExpiryTransition,
  calculateStreakTransition,
} from "../src/progression/streakCalculator.js";

const PROJECT_ID = "runiac-functions-test";
const USER_UID = "streak-expiry-runner";

let firestore: Firestore;

before(() => {
  if (getApps().length === 0) {
    initializeApp({ projectId: PROJECT_ID });
  }
  firestore = getFirestore();
});

beforeEach(async () => {
  await Promise.all([
    firestore.doc(`userProfiles/${USER_UID}`).delete(),
    firestore.doc(`generatedPlans/${USER_UID}`).delete(),
  ]);
});

describe("streak expiry", () => {
  it("resets after an unprotected missed day", () => {
    const transition = calculateStreakExpiryTransition({
      currentState: { streakCount: 4, lastStreakRunDate: "2026-07-09" },
      asOfDate: "2026-07-11",
      protectedRestDates: [],
    });

    assert.equal(transition.nextStreak, 0);
    assert.equal(transition.shouldUpdateProfile, true);
  });

  it("keeps the streak when every elapsed gap day is a planned rest day", () => {
    const transition = calculateStreakExpiryTransition({
      currentState: { streakCount: 4, lastStreakRunDate: "2026-07-09" },
      asOfDate: "2026-07-11",
      protectedRestDates: ["2026-07-10"],
    });

    assert.equal(transition.nextStreak, 4);
    assert.equal(transition.shouldUpdateProfile, false);
  });

  it("keeps yesterday's streak active through today", () => {
    const transition = calculateStreakExpiryTransition({
      currentState: { streakCount: 4, lastStreakRunDate: "2026-07-10" },
      asOfDate: "2026-07-11",
      protectedRestDates: [],
    });

    assert.equal(transition.nextStreak, 4);
    assert.equal(transition.shouldUpdateProfile, false);
  });

  it("records a post-midnight Singapore run on the Singapore calendar day", () => {
    const transition = calculateStreakTransition({
      currentState: { streakCount: 4, lastStreakRunDate: "2026-07-10" },
      completedAt: "2026-07-10T16:30:00.000Z",
    });

    assert.equal(transition.nextStreak, 5);
    assert.equal(transition.nextStreakRunDate, "2026-07-11");
  });

  it("callable resets backend-owned profile streak after a missed plan day", async () => {
    await seedProfileAndPlan({ fridayKind: "easyRun" });

    const result = await refreshStreakStatusForCallable(
      { auth: { uid: USER_UID }, data: null },
      firestore,
      "2026-07-10T16:05:00.000Z",
    );
    const profile = await firestore.doc(`userProfiles/${USER_UID}`).get();

    assert.equal(result.streakCount, 0);
    assert.equal(profile.get("streakCount"), 0);
    assert.equal(profile.get("streakUpdatedAt"), "2026-07-10T16:05:00.000Z");
  });

  it("callable preserves backend-owned streak across a planned rest day", async () => {
    await seedProfileAndPlan({ fridayKind: "rest" });

    const result = await refreshStreakStatusForCallable(
      { auth: { uid: USER_UID }, data: null },
      firestore,
      "2026-07-10T16:05:00.000Z",
    );
    const profile = await firestore.doc(`userProfiles/${USER_UID}`).get();

    assert.equal(result.streakCount, 4);
    assert.equal(profile.get("streakCount"), 4);
    assert.equal(profile.get("streakUpdatedAt"), "2026-07-09T09:00:00.000Z");
  });
});

async function seedProfileAndPlan(input: {
  readonly fridayKind: "easyRun" | "rest";
}): Promise<void> {
  await firestore.doc(`userProfiles/${USER_UID}`).set({
    streakCount: 4,
    lastStreakRunDate: "2026-07-09",
    streakUpdatedAt: "2026-07-09T09:00:00.000Z",
  });
  await firestore.doc(`generatedPlans/${USER_UID}`).set({
    startsOnDate: "2026-07-06",
    weeks: [
      {
        weekNumber: 1,
        workouts: [
          { dayLabel: "Fri", title: "Friday plan", kind: input.fridayKind },
        ],
      },
    ],
  });
}
