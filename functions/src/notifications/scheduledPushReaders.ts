import type { DocumentData } from "firebase-admin/firestore";
import { scheduledDateFor } from "../plan/planProgressParsing.js";
import type { NotificationDeviceRecord } from "./dispatchPlanner.js";

export function enabledDevices(
  uid: string,
  documents: readonly DocumentData[],
): readonly NotificationDeviceRecord[] {
  const devices: NotificationDeviceRecord[] = [];
  for (const data of documents) {
    const tokenFingerprint = readString(data["tokenFingerprint"]);
    const fcmToken = readString(data["fcmToken"]);
    if (tokenFingerprint !== null && fcmToken !== null) {
      devices.push({ uid, tokenFingerprint, fcmToken });
    }
  }
  return devices;
}

export function notificationPreferences(
  preferenceData: DocumentData | undefined,
  profileData: DocumentData | undefined,
) {
  const legacyProfilePrefs = isRecord(profileData?.["notificationPreferences"])
    ? profileData["notificationPreferences"]
    : {};
  const value = preferenceData ?? legacyProfilePrefs;
  return {
    planRemindersEnabled:
      readBoolean(value["planRemindersEnabled"]) ??
      readBoolean(value["runReminderEnabled"]) ??
      true,
    streakRiskEnabled: readBoolean(value["streakRiskEnabled"]) ?? true,
  };
}

// Sibling of `notificationPreferences()` above, kept as its own reader rather
// than a new key folded into that function's return object: dispatchPlanner.ts
// and notificationDispatch.test.ts construct/consume that shape literally, and
// widening it would break both. Feed engagement (like/comment) notifications
// gate on this single boolean instead. Same legacy fallback as
// `notificationPreferences()`: a `userProfiles/{uid}.notificationPreferences`
// map is honoured when no `notificationPreferences/{uid}` document exists yet.
// Defaults to `true` when the key is absent or not a boolean, so existing
// users are opted in before their client ever mirrors this preference.
export function socialActivityEnabled(
  preferenceData: DocumentData | undefined,
  profileData: DocumentData | undefined,
): boolean {
  const legacyProfilePrefs = isRecord(profileData?.["notificationPreferences"])
    ? profileData["notificationPreferences"]
    : {};
  const value = preferenceData ?? legacyProfilePrefs;
  return readBoolean(value["socialActivityEnabled"]) ?? true;
}

export function streakState(data: DocumentData | undefined) {
  return {
    streakCount: readInteger(data?.["streakCount"]) ?? 0,
    lastStreakRunDate: readString(data?.["lastStreakRunDate"]),
  };
}

export function completedWorkoutIds(data: DocumentData | undefined): readonly string[] {
  if (!isRecord(data?.["workouts"])) {
    return [];
  }
  const ids: string[] = [];
  for (const value of Object.values(data["workouts"])) {
    if (!isRecord(value)) {
      continue;
    }
    const id = readString(value["scheduledWorkoutId"]);
    if (id !== null) {
      ids.push(id);
    }
  }
  return ids;
}

export function plannedWorkouts(data: DocumentData | undefined) {
  const startsOnDate = readString(data?.["startsOnDate"]);
  const weeks = Array.isArray(data?.["weeks"]) ? data["weeks"] : [];
  const workouts = [];
  for (const week of weeks) {
    if (!isRecord(week)) {
      continue;
    }
    const weekNumber = readInteger(week["weekNumber"]);
    const weekWorkouts = Array.isArray(week["workouts"]) ? week["workouts"] : [];
    if (weekNumber === null) {
      continue;
    }
    for (const workout of weekWorkouts) {
      if (!isRecord(workout)) {
        continue;
      }
      const title = readString(workout["title"]) ?? "Planned workout";
      const dayLabel = readString(workout["dayLabel"]);
      const scheduledWorkoutId = readString(workout["scheduledWorkoutId"]) ?? readString(workout["id"]);
      const scheduledDate = dayLabel === null
        ? null
        : scheduledDateFor(startsOnDate ?? undefined, weekNumber, dayLabel);
      const startTime = startTimeFor(workout);
      if (scheduledWorkoutId !== null && scheduledDate !== null && startTime !== null) {
        workouts.push({ scheduledWorkoutId, title, scheduledDate, startTime });
      }
    }
  }
  return workouts;
}

function startTimeFor(workout: Readonly<Record<string, unknown>>): string | null {
  const label = readString(workout["scheduleTimeLabel"]);
  if (label === null) {
    return "07:00";
  }
  const match = /\b([01]?\d|2[0-3]):([0-5]\d)\b/.exec(label);
  if (match === null) {
    return "07:00";
  }
  return `${match[1]?.padStart(2, "0")}:${match[2]}`;
}

function readBoolean(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function readInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function readString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
