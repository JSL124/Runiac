import type { DocumentData, DocumentReference, Transaction } from "firebase-admin/firestore";
import type { CompleteRunIds, RawRunCompletionPayload } from "../run/runCompletionTypes.js";
import {
  datePart,
  fallbackWorkoutId,
  isRecord,
  isRestWorkout,
  readOptionalInteger,
  readOptionalPositiveNumber,
  readOptionalString,
  scheduledDateFor,
} from "./planProgressParsing.js";
import { planSnapshot, readGeneratedPlanId, trustedPlanData } from "./planProgressSnapshot.js";

type MatchKind = "explicit" | "date";
type WorkoutObjective =
  | {
      readonly kind: "duration";
      readonly seconds: number;
    }
  | {
      readonly kind: "distance";
      readonly meters: number;
    };
type PlannedWorkout = {
  readonly scheduledWorkoutId: string;
  readonly scheduledDate: string | null;
  readonly title: string;
  readonly objective: WorkoutObjective;
};
type MatchedWorkout = {
  readonly workout: PlannedWorkout;
  readonly matchedBy: MatchKind;
};
type PersistPlanProgressInput = {
  readonly transaction: Transaction;
  readonly progressRef: DocumentReference;
  readonly uid: string;
  readonly ids: CompleteRunIds;
  readonly payload: RawRunCompletionPayload;
  readonly generatedPlanData: DocumentData | undefined;
  readonly progressData: DocumentData | undefined;
};
export type PersistPlanProgressResult = {
  readonly matchedPlanWorkout: boolean;
  readonly completedWorkoutRecorded: boolean;
  readonly planEnrollmentId: string | null;
  readonly scheduledWorkoutId: string | null;
  readonly matchedBy: MatchKind | null;
};

export function persistCompletedWorkoutProgress(input: PersistPlanProgressInput): PersistPlanProgressResult {
  const planData = trustedPlanData(input.generatedPlanData, input.progressData, input.payload);
  const plannedWorkouts = readPlannedWorkouts(planData);
  const matchedWorkout = findMatchedWorkout(plannedWorkouts, input.payload);
  if (matchedWorkout === null) {
    return noCompletedWorkoutRecorded();
  }

  const sourceGeneratedPlanId = readGeneratedPlanId(planData);
  if (!meetsObjective(matchedWorkout.workout.objective, input.payload)) {
    return incompleteMatchedWorkout({
      sourceGeneratedPlanId,
      matchedWorkout,
    });
  }

  const completedWorkouts = readCompletedWorkouts(input.progressData);
  const progressKey = progressWorkoutKey(sourceGeneratedPlanId, matchedWorkout.workout.scheduledWorkoutId);
  if (completedWorkouts[progressKey] !== undefined) {
    return incompleteMatchedWorkout({
      sourceGeneratedPlanId,
      matchedWorkout,
    });
  }

  const completedWorkoutCount = readCompletedWorkoutCount(input.progressData, completedWorkouts) + 1;
  const planCompletion = resolvePlanCompletion({
    progressData: input.progressData,
    completedWorkouts,
    sourceGeneratedPlanId,
    plannedWorkoutTotal: plannedWorkouts.length,
    completedAt: input.payload.completedAt,
  });
  input.transaction.set(
    input.progressRef,
    {
      ownerUid: input.uid,
      ...(sourceGeneratedPlanId === undefined ? {} : { latestSourceGeneratedPlanId: sourceGeneratedPlanId }),
      ...(sourceGeneratedPlanId === undefined ? {} : { planSnapshots: { [sourceGeneratedPlanId]: planSnapshot(planData) } }),
      completedWorkoutCount,
      updatedAt: input.payload.completedAt,
      workouts: {
        [progressKey]: completionReadModel(input, matchedWorkout),
      },
      ...(planCompletion === null ? {} : { planCompletions: planCompletion }),
    },
    { merge: true },
  );
  return {
    matchedPlanWorkout: true,
    completedWorkoutRecorded: true,
    planEnrollmentId: sourceGeneratedPlanId ?? null,
    scheduledWorkoutId: matchedWorkout.workout.scheduledWorkoutId,
    matchedBy: matchedWorkout.matchedBy,
  };
}

function incompleteMatchedWorkout(input: {
  readonly sourceGeneratedPlanId: string | undefined;
  readonly matchedWorkout: MatchedWorkout;
}): PersistPlanProgressResult {
  return {
    matchedPlanWorkout: true,
    completedWorkoutRecorded: false,
    planEnrollmentId: input.sourceGeneratedPlanId ?? null,
    scheduledWorkoutId: input.matchedWorkout.workout.scheduledWorkoutId,
    matchedBy: input.matchedWorkout.matchedBy,
  };
}

function noCompletedWorkoutRecorded(): PersistPlanProgressResult {
  return {
    matchedPlanWorkout: false,
    completedWorkoutRecorded: false,
    planEnrollmentId: null,
    scheduledWorkoutId: null,
    matchedBy: null,
  };
}

function completionReadModel(
  input: PersistPlanProgressInput,
  matchedWorkout: MatchedWorkout,
): Readonly<Record<string, unknown>> {
  const base = {
    status: "completed",
    activityId: input.ids.activityId,
    clientRunSessionId: input.payload.clientRunSessionId,
    completedAt: input.payload.completedAt,
    scheduledWorkoutId: matchedWorkout.workout.scheduledWorkoutId,
    scheduledDate: matchedWorkout.workout.scheduledDate,
    title: matchedWorkout.workout.title,
    matchedBy: matchedWorkout.matchedBy,
    actualDurationSeconds: input.payload.durationSeconds,
    actualDistanceMeters: input.payload.distanceMeters,
    objectiveKind: matchedWorkout.workout.objective.kind,
    ...(input.payload.planEnrollmentId === undefined ? {} : { planEnrollmentId: input.payload.planEnrollmentId }),
  };
  if (matchedWorkout.workout.objective.kind === "duration") {
    return {
      ...base,
      objectiveSeconds: matchedWorkout.workout.objective.seconds,
    };
  }
  return {
    ...base,
    objectiveMeters: matchedWorkout.workout.objective.meters,
  };
}

function findMatchedWorkout(
  workouts: readonly PlannedWorkout[],
  payload: RawRunCompletionPayload,
): MatchedWorkout | null {
  if (workouts.length === 0) {
    return null;
  }

  if (payload.scheduledWorkoutId !== undefined) {
    const explicitWorkout = workouts.find((workout) => workout.scheduledWorkoutId === payload.scheduledWorkoutId);
    return explicitWorkout === undefined ? null : { workout: explicitWorkout, matchedBy: "explicit" };
  }

  const completedDate = datePart(payload.completedAt);
  const activeWorkouts = workouts.filter((workout) => workout.scheduledDate === completedDate);
  if (activeWorkouts.length !== 1) {
    return null;
  }

  const activeWorkout = activeWorkouts[0];
  return activeWorkout === undefined ? null : { workout: activeWorkout, matchedBy: "date" };
}

function readPlannedWorkouts(generatedPlanData: DocumentData | undefined): readonly PlannedWorkout[] {
  if (generatedPlanData === undefined) {
    return [];
  }

  const startsOnDate = readOptionalString(generatedPlanData["startsOnDate"]);
  const weeksValue: unknown = generatedPlanData["weeks"];
  if (!Array.isArray(weeksValue)) {
    return [];
  }

  const workouts: PlannedWorkout[] = [];
  for (const weekValue of weeksValue) {
    if (!isRecord(weekValue)) {
      continue;
    }
    const weekNumber = readOptionalInteger(weekValue["weekNumber"]) ?? workouts.length + 1;
    const weekWorkoutsValue = weekValue["workouts"];
    if (!Array.isArray(weekWorkoutsValue)) {
      continue;
    }
    for (const workoutValue of weekWorkoutsValue) {
      const workout = readPlannedWorkout(workoutValue, startsOnDate, weekNumber);
      if (workout !== null) {
        workouts.push(workout);
      }
    }
  }

  return workouts;
}

function readPlannedWorkout(
  value: unknown,
  startsOnDate: string | undefined,
  weekNumber: number,
): PlannedWorkout | null {
  if (!isRecord(value)) {
    return null;
  }

  const dayLabel = readOptionalString(value["dayLabel"]);
  const title = readOptionalString(value["title"]) ?? "Planned workout";
  const objective = readObjective(value);
  if (dayLabel === undefined || objective === null || isRestWorkout(value)) {
    return null;
  }

  return {
    scheduledWorkoutId: readWorkoutId(value) ?? fallbackWorkoutId(weekNumber, dayLabel, title),
    scheduledDate: scheduledDateFor(startsOnDate, weekNumber, dayLabel),
    title,
    objective,
  };
}

function readWorkoutId(value: Readonly<Record<string, unknown>>): string | undefined {
  return readOptionalString(value["scheduledWorkoutId"]) ?? readOptionalString(value["workoutId"]) ?? readOptionalString(value["id"]);
}

function readObjective(value: Readonly<Record<string, unknown>>): WorkoutObjective | null {
  const objectiveKind = readOptionalString(value["objectiveKind"]) ?? readOptionalString(value["objectiveType"]);
  const targetDistanceMeters = readOptionalPositiveNumber(value["targetDistanceMeters"]) ?? readOptionalPositiveNumber(value["distanceMeters"]);
  if (objectiveKind === "distance" || targetDistanceMeters !== undefined) {
    return targetDistanceMeters === undefined ? null : { kind: "distance", meters: targetDistanceMeters };
  }

  const targetDurationSeconds = readOptionalPositiveNumber(value["targetDurationSeconds"]) ?? readOptionalPositiveNumber(value["durationSeconds"]);
  if (targetDurationSeconds !== undefined) {
    return { kind: "duration", seconds: targetDurationSeconds };
  }

  const durationMinutes = readOptionalPositiveNumber(value["durationMinutes"]);
  return durationMinutes === undefined ? null : { kind: "duration", seconds: durationMinutes * 60 };
}

function meetsObjective(objective: WorkoutObjective, payload: RawRunCompletionPayload): boolean {
  if (objective.kind === "duration") {
    return payload.durationSeconds >= objective.seconds;
  }

  return payload.distanceMeters >= objective.meters;
}

/**
 * Decides whether the workout being recorded is the one that finishes the
 * plan, and if so returns the `planCompletions` map fragment to merge in.
 *
 * Server-owned by construction: this runs inside the `completeRun`
 * transaction, against the same trusted plan snapshot used for matching, so
 * the client never supplies or infers the completion state.
 *
 * Scoped per generated plan rather than reusing `completedWorkoutCount`,
 * which is a lifetime counter spanning every plan the user has run. Returns
 * `null` (write nothing) when the plan cannot be scoped, when the plan has no
 * planned workouts, when workouts remain, or when this plan was already
 * recorded as completed — so the first completion timestamp is never
 * overwritten by a later replay or by an extra run on a finished plan.
 */
function resolvePlanCompletion(input: {
  readonly progressData: DocumentData | undefined;
  readonly completedWorkouts: Readonly<Record<string, unknown>>;
  readonly sourceGeneratedPlanId: string | undefined;
  readonly plannedWorkoutTotal: number;
  readonly completedAt: string;
}): Readonly<Record<string, unknown>> | null {
  const planId = input.sourceGeneratedPlanId;
  if (planId === undefined || input.plannedWorkoutTotal <= 0) {
    return null;
  }

  if (readPlanCompletions(input.progressData)[planId] !== undefined) {
    return null;
  }

  // `+ 1` folds in the workout being recorded by this same transaction, which
  // is not yet present in `completedWorkouts`.
  const planCompletedWorkoutCount = countCompletedWorkoutsForPlan(input.completedWorkouts, planId) + 1;
  if (planCompletedWorkoutCount < input.plannedWorkoutTotal) {
    return null;
  }

  return {
    [planId]: {
      planId,
      completedAt: input.completedAt,
      completedWorkoutCount: planCompletedWorkoutCount,
      plannedWorkoutTotal: input.plannedWorkoutTotal,
    },
  };
}

function countCompletedWorkoutsForPlan(
  completedWorkouts: Readonly<Record<string, unknown>>,
  planId: string,
): number {
  const prefix = `${planId}__`;
  let count = 0;
  for (const key of Object.keys(completedWorkouts)) {
    if (key.startsWith(prefix)) {
      count += 1;
    }
  }
  return count;
}

function readPlanCompletions(progressData: DocumentData | undefined): Readonly<Record<string, unknown>> {
  if (progressData === undefined) {
    return {};
  }

  const value: unknown = progressData["planCompletions"];
  return isRecord(value) ? value : {};
}

function readCompletedWorkouts(progressData: DocumentData | undefined): Readonly<Record<string, unknown>> {
  if (progressData === undefined) {
    return {};
  }

  const workoutsValue: unknown = progressData["workouts"];
  return isRecord(workoutsValue) ? workoutsValue : {};
}

function readCompletedWorkoutCount(
  progressData: DocumentData | undefined,
  completedWorkouts: Readonly<Record<string, unknown>>,
): number {
  if (progressData !== undefined) {
    const countValue: unknown = progressData["completedWorkoutCount"];
    if (typeof countValue === "number" && Number.isInteger(countValue) && countValue >= 0) {
      return countValue;
    }
  }

  return Object.keys(completedWorkouts).length;
}

function progressWorkoutKey(sourceGeneratedPlanId: string | undefined, scheduledWorkoutId: string): string {
  return sourceGeneratedPlanId === undefined ? scheduledWorkoutId : `${sourceGeneratedPlanId}__${scheduledWorkoutId}`;
}
