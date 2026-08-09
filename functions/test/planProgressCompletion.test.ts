import assert from "node:assert/strict";
import test from "node:test";
import type { DocumentData, DocumentReference, Transaction } from "firebase-admin/firestore";
import { persistCompletedWorkoutProgress } from "../src/plan/planProgress.js";
import { scheduledDateFor } from "../src/plan/planProgressParsing.js";
import {
  readTrustedProtectedRestDates,
  readTrustedStreakState,
} from "../src/progression/planBoundedStreakState.js";
import { calculateStreakExpiryTransition } from "../src/progression/streakCalculator.js";
import type { CompleteRunIds, RawRunCompletionPayload } from "../src/run/runCompletionTypes.js";

const PLAN_ID = "plan-alpha";
const IDS: CompleteRunIds = {
  activityId: "activity-1",
  summaryId: "summary-1",
  progressionEventId: "progression-1",
};

type CapturedWrite = {
  readonly data: DocumentData;
};

/**
 * Minimal `Transaction` stand-in that records what would be merged into
 * `planProgress/{uid}`. Only `set` is exercised by
 * `persistCompletedWorkoutProgress`.
 */
function fakeTransaction(): { transaction: Transaction; writes: CapturedWrite[] } {
  const writes: CapturedWrite[] = [];
  const transaction = {
    set(_ref: DocumentReference, data: DocumentData) {
      writes.push({ data });
      return transaction;
    },
  } as unknown as Transaction;
  return { transaction, writes };
}

function payloadFor(scheduledWorkoutId: string, completedAt: string): RawRunCompletionPayload {
  return {
    clientRunSessionId: "session-1",
    startedAt: completedAt,
    completedAt,
    durationSeconds: 3600,
    activeDurationSeconds: 3600,
    elapsedWallSeconds: 3600,
    pausedDurationSeconds: 0,
    distanceMeters: 10000,
    avgPaceSecondsPerKm: 360,
    source: "mobile",
    routePrivacy: "private",
    scheduledWorkoutId,
  };
}

/** A plan with `workoutCount` planned (non-rest, objective-bearing) workouts. */
function planWith(workoutCount: number): DocumentData {
  return {
    planId: PLAN_ID,
    startsOnDate: "2026-07-01",
    weeks: [
      {
        weekNumber: 1,
        workouts: Array.from({ length: workoutCount }, (_unused, index) => ({
          scheduledWorkoutId: `w${index + 1}`,
          dayLabel: "Mon",
          title: `Workout ${index + 1}`,
          durationMinutes: 30,
        })),
      },
    ],
  };
}

/** Progress doc where `completedKeys` are already recorded for this plan. */
function progressWith(completedKeys: readonly string[], planCompletions?: DocumentData): DocumentData {
  const workouts: Record<string, unknown> = {};
  for (const key of completedKeys) {
    workouts[key] = { status: "completed", completedAt: "2026-07-02T00:00:00.000Z" };
  }
  return {
    workouts,
    completedWorkoutCount: completedKeys.length,
    ...(planCompletions === undefined ? {} : { planCompletions }),
  };
}

function persist(input: {
  readonly generatedPlanData: DocumentData;
  readonly progressData: DocumentData | undefined;
  readonly scheduledWorkoutId: string;
  readonly completedAt?: string;
}) {
  const { transaction, writes } = fakeTransaction();
  const result = persistCompletedWorkoutProgress({
    transaction,
    progressRef: {} as DocumentReference,
    uid: "uid-1",
    ids: IDS,
    payload: payloadFor(input.scheduledWorkoutId, input.completedAt ?? "2026-07-03T10:00:00.000Z"),
    generatedPlanData: input.generatedPlanData,
    progressData: input.progressData,
  });
  return { result, writes };
}

test("records no plan completion while planned workouts remain", () => {
  const { result, writes } = persist({
    generatedPlanData: planWith(3),
    progressData: progressWith([`${PLAN_ID}__w1`]),
    scheduledWorkoutId: "w2",
  });

  assert.equal(result.completedWorkoutRecorded, true);
  assert.equal(writes.length, 1);
  assert.equal(writes[0]?.data["planCompletions"], undefined);
});

test("records the plan completion when the final planned workout lands", () => {
  const { result, writes } = persist({
    generatedPlanData: planWith(3),
    progressData: progressWith([`${PLAN_ID}__w1`, `${PLAN_ID}__w2`]),
    scheduledWorkoutId: "w3",
    completedAt: "2026-07-05T09:30:00.000Z",
  });

  assert.equal(result.completedWorkoutRecorded, true);
  const planCompletions = writes[0]?.data["planCompletions"] as DocumentData;
  assert.deepEqual(planCompletions[PLAN_ID], {
    planId: PLAN_ID,
    completedAt: "2026-07-05T09:30:00.000Z",
    completedWorkoutCount: 3,
    plannedWorkoutTotal: 3,
  });
});

test("does not re-record or overwrite an already-completed plan", () => {
  const existing = {
    [PLAN_ID]: {
      planId: PLAN_ID,
      completedAt: "2026-07-05T09:30:00.000Z",
      completedWorkoutCount: 3,
      plannedWorkoutTotal: 3,
    },
  };
  const { writes } = persist({
    generatedPlanData: planWith(4),
    progressData: progressWith(
      [`${PLAN_ID}__w1`, `${PLAN_ID}__w2`, `${PLAN_ID}__w3`],
      existing,
    ),
    scheduledWorkoutId: "w4",
    completedAt: "2026-07-09T09:30:00.000Z",
  });

  assert.equal(writes[0]?.data["planCompletions"], undefined);
});

test("counts only this plan's workouts, not a previous plan's", () => {
  // Lifetime `completedWorkoutCount` is 3, but two of those belong to an
  // earlier plan — the current plan still has one workout outstanding.
  const { writes } = persist({
    generatedPlanData: planWith(3),
    progressData: progressWith([
      "plan-previous__w1",
      "plan-previous__w2",
      `${PLAN_ID}__w1`,
    ]),
    scheduledWorkoutId: "w2",
  });

  assert.equal(writes[0]?.data["planCompletions"], undefined);
});

test("ignores rest days and objective-less entries in the planned total", () => {
  const planData = planWith(2) as { weeks: { workouts: unknown[] }[] };
  planData.weeks[0]?.workouts.push(
    { scheduledWorkoutId: "rest", dayLabel: "Sun", title: "Rest", kind: "rest", durationMinutes: 0 },
    { scheduledWorkoutId: "no-objective", dayLabel: "Sat", title: "Mobility" },
  );

  const { writes } = persist({
    generatedPlanData: planData as unknown as DocumentData,
    progressData: progressWith([`${PLAN_ID}__w1`]),
    scheduledWorkoutId: "w2",
  });

  const planCompletions = writes[0]?.data["planCompletions"] as DocumentData;
  assert.deepEqual(planCompletions[PLAN_ID], {
    planId: PLAN_ID,
    completedAt: "2026-07-03T10:00:00.000Z",
    completedWorkoutCount: 2,
    plannedWorkoutTotal: 2,
  });
});

test("records nothing when the workout was already recorded (replay)", () => {
  const { result, writes } = persist({
    generatedPlanData: planWith(2),
    progressData: progressWith([`${PLAN_ID}__w1`, `${PLAN_ID}__w2`]),
    scheduledWorkoutId: "w2",
  });

  assert.equal(result.completedWorkoutRecorded, false);
  assert.equal(writes.length, 0);
});

/**
 * Generated plans express rest by omitting the day from `weeks[].workouts`;
 * no plan writer emits a `kind: "rest"` workout. Rest protection used to look
 * only for those explicit entries, so it resolved to nothing for every real
 * plan and the streak reset at the first midnight refresh after any off-day.
 */
const TRAINING_DAY_PLAN = {
  startsOnDate: "2026-07-06",
  createdAt: "2026-07-05T09:19:32Z",
  weeks: [1, 2, 3].map((weekNumber) => ({
    weekNumber,
    workouts: ["Mon", "Wed", "Fri", "Sat"].map((dayLabel) => ({
      dayLabel,
      title: `${dayLabel} run`,
      kind: "easyRun",
    })),
  })),
};

test("protects in-plan days the schedule omits, not the training days", () => {
  const restDates = readTrustedProtectedRestDates(TRAINING_DAY_PLAN);

  // 2026-07-21 is a Tuesday, absent from a Mon/Wed/Fri/Sat schedule.
  assert.ok(restDates.includes("2026-07-21"));
  assert.ok(restDates.includes("2026-07-23"));
  // Scheduled training days must never be protected.
  assert.ok(!restDates.includes("2026-07-20"));
  assert.ok(!restDates.includes("2026-07-22"));
});

test("keeps the streak across a day the plan simply omits", () => {
  const transition = calculateStreakExpiryTransition({
    currentState: { streakCount: 2, lastStreakRunDate: "2026-07-20" },
    asOfDate: "2026-07-22",
    protectedRestDates: readTrustedProtectedRestDates(TRAINING_DAY_PLAN),
  });

  assert.equal(transition.nextStreak, 2);
  assert.equal(transition.shouldUpdateProfile, false);
});

test("still resets the streak when a scheduled training day is missed", () => {
  const transition = calculateStreakExpiryTransition({
    currentState: { streakCount: 2, lastStreakRunDate: "2026-07-20" },
    asOfDate: "2026-07-23",
    protectedRestDates: readTrustedProtectedRestDates(TRAINING_DAY_PLAN),
  });

  assert.equal(transition.nextStreak, 0);
  assert.equal(transition.shouldUpdateProfile, true);
});

test("never protects a day a duplicate week entry schedules", () => {
  const restDates = readTrustedProtectedRestDates({
    startsOnDate: "2026-07-06",
    createdAt: "2026-07-05T09:19:32Z",
    weeks: [
      { weekNumber: 1, workouts: [{ dayLabel: "Mon", title: "Mon run", kind: "easyRun" }] },
      { weekNumber: 1, workouts: [{ dayLabel: "Tue", title: "Tue run", kind: "easyRun" }] },
    ],
  });

  assert.ok(!restDates.includes("2026-07-06"));
  assert.ok(!restDates.includes("2026-07-07"));
  assert.ok(restDates.includes("2026-07-08"));
});

test("resolves a dayLabel to its real weekday when the plan starts mid-week", () => {
  // 2026-07-08 is a Wednesday. A "Wed" workout belongs on the start day itself,
  // and "Fri" two days later — not two and four days out as a Monday anchor gives.
  assert.equal(scheduledDateFor("2026-07-08", 1, "Wed"), "2026-07-08");
  assert.equal(scheduledDateFor("2026-07-08", 1, "Fri"), "2026-07-10");
  // Labels earlier in the week wrap into the same seven-day window.
  assert.equal(scheduledDateFor("2026-07-08", 1, "Mon"), "2026-07-13");
  assert.equal(scheduledDateFor("2026-07-08", 2, "Wed"), "2026-07-15");
});

test("leaves Monday-start plans on exactly the dates they already had", () => {
  // 2026-07-06 is a Monday, where the new mapping must be a no-op.
  assert.equal(scheduledDateFor("2026-07-06", 1, "Mon"), "2026-07-06");
  assert.equal(scheduledDateFor("2026-07-06", 1, "Wed"), "2026-07-08");
  assert.equal(scheduledDateFor("2026-07-06", 1, "Sun"), "2026-07-12");
  assert.equal(scheduledDateFor("2026-07-06", 3, "Mon"), "2026-07-20");
});

test("resolves long weekday spellings the notification path writes", () => {
  assert.equal(scheduledDateFor("2026-07-06", 1, "Friday"), "2026-07-10");
  assert.equal(scheduledDateFor("2026-07-06", 1, "friday"), "2026-07-10");
  assert.equal(scheduledDateFor("2026-07-06", 1, "Day 1"), null);
});

test("counts a first-day run started just after Singapore midnight", () => {
  // 2026-07-06T16:30Z is 2026-07-07 00:30 in Singapore — the plan's first day.
  // Comparing raw instants against a UTC-midnight start dropped it as pre-start.
  const state = readTrustedStreakState({
    profileState: { streakCount: 0, lastStreakRunDate: null },
    generatedPlanData: { startsOnDate: "2026-07-07", weeks: [] },
    activityDocuments: [{
      activityType: "run",
      validationStatus: "validated",
      endedAt: "2026-07-06T16:30:00.000Z",
    }],
  });

  assert.equal(state.streakCount, 1);
  assert.equal(state.lastStreakRunDate, "2026-07-07");
});

test("still drops runs from the Singapore day before the plan starts", () => {
  const state = readTrustedStreakState({
    profileState: { streakCount: 9, lastStreakRunDate: "2026-01-01" },
    generatedPlanData: { startsOnDate: "2026-07-07", weeks: [] },
    activityDocuments: [{
      activityType: "run",
      validationStatus: "validated",
      endedAt: "2026-07-06T10:00:00.000Z",
    }],
  });

  assert.equal(state.streakCount, 0);
  assert.equal(state.lastStreakRunDate, null);
});

test("protects a rest day falling on the plan's creation day", () => {
  // createdAt is mid-day Singapore; the creation day itself must still resolve
  // as rest when the schedule omits it.
  const restDates = readTrustedProtectedRestDates({
    startsOnDate: "2026-07-06",
    createdAt: "2026-07-06T09:19:32.000Z",
    weeks: [
      { weekNumber: 1, workouts: [{ dayLabel: "Wed", title: "Wed run", kind: "easyRun" }] },
    ],
  });

  assert.ok(restDates.includes("2026-07-06"));
});

test("protects nothing once the plan's weeks have run out", () => {
  const restDates = readTrustedProtectedRestDates(TRAINING_DAY_PLAN);

  // Week 3 ends 2026-07-26; nothing beyond it may be treated as rest.
  assert.ok(!restDates.some((date) => date > "2026-07-26"));
});
