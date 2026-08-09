import { HttpsError } from "firebase-functions/v2/https";
import type { PlanCompletionResult, ProgressionDisplay } from "../run/runCompletionTypes.js";

export function progressionDisplayFromEvent(
  eventData: FirebaseFirestore.DocumentData | undefined,
): ProgressionDisplay {
  if (eventData === undefined) {
    throw new HttpsError("already-exists", "Existing run completion progression event is unreadable.");
  }
  const xpDelta = eventData["xpDelta"];
  const status = eventData["status"];
  const reason = eventData["reason"];
  const totalXp = eventData["nextTotalXp"];
  const level = eventData["nextLevel"];
  const divisionKey = eventData["nextDivisionKey"];
  const previousTotalXp = eventData["previousTotalXp"];
  const previousLevel = eventData["previousLevel"];
  const previousLevelProgressPercent = eventData["previousLevelProgressPercent"];
  const levelProgressPercent = eventData["nextLevelProgressPercent"];
  const previousStreak = eventData["previousStreak"];
  const streak = eventData["nextStreak"];
  const countsTowardLeaderboard =
    eventData["countsTowardLeaderboard"] === true;
  if (typeof xpDelta !== "number" || !isProgressionStatus(status) || !isProgressionReason(reason)) {
    throw new HttpsError("already-exists", "Existing run completion progression display is unreadable.");
  }

  return {
    xpDelta,
    countsTowardLeaderboard,
    status,
    reason,
    ...(typeof totalXp === "number" ? { totalXp } : {}),
    ...(typeof level === "number" ? { level } : {}),
    ...(typeof divisionKey === "string" ? { divisionKey } : {}),
    ...(typeof previousTotalXp === "number" ? { previousTotalXp } : {}),
    ...(typeof previousLevel === "number" ? { previousLevel } : {}),
    ...(typeof previousLevelProgressPercent === "number"
      ? { previousLevelProgressPercent }
      : {}),
    ...(typeof levelProgressPercent === "number" ? { levelProgressPercent } : {}),
    ...(readNullableNumberField(eventData, "nextLevelXpTarget", "nextLevelXp") ?? {}),
    ...(readNullableNumberField(eventData, "nextXpToNextLevel", "xpToNextLevel") ?? {}),
    ...(typeof previousStreak === "number" ? { previousStreak } : {}),
    ...(typeof streak === "number" ? { streak } : {}),
  };
}

export function planCompletionFromEvent(
  eventData: FirebaseFirestore.DocumentData | undefined,
): PlanCompletionResult {
  if (eventData?.["plannedWorkoutRecorded"] !== true) {
    return { completed: false };
  }

  const planEnrollmentId = eventData["planEnrollmentId"];
  const scheduledWorkoutId = eventData["plannedWorkoutId"];
  return {
    completed: true,
    ...(typeof planEnrollmentId === "string" ? { planEnrollmentId } : {}),
    ...(typeof scheduledWorkoutId === "string" ? { scheduledWorkoutId } : {}),
  };
}

function readNullableNumberField(
  eventData: FirebaseFirestore.DocumentData,
  storedKey: string,
  displayKey: "nextLevelXp" | "xpToNextLevel",
): Record<string, number | null> | undefined {
  if (!(storedKey in eventData)) {
    return undefined;
  }
  const value = eventData[storedKey];
  if (typeof value === "number") {
    return { [displayKey]: value };
  }
  if (value === null) {
    return { [displayKey]: null };
  }
  return undefined;
}

function isProgressionStatus(value: unknown): value is ProgressionDisplay["status"] {
  return value === "awarded" || value === "not_awarded" || value === "deferred";
}

function isProgressionReason(value: unknown): value is ProgressionDisplay["reason"] {
  return (
    value === "run_completion_xp_awarded" ||
    value === "low_data_no_xp" ||
    value === "daily_cap_reached" ||
    value === "premium_no_progression" ||
    value === "progression_formula_deferred" ||
    value === "cool_down_stretch_bonus_awarded" ||
    value === "cool_down_daily_cap_reached"
  );
}
