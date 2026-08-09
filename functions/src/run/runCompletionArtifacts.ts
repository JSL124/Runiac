import { createHash } from "node:crypto";
import { HttpsError } from "firebase-functions/v2/https";
import type { CompleteRunIds, CompleteRunResult, RawRunCompletionPayload } from "./runCompletionTypes.js";

export function deterministicIds(uid: string, clientRunSessionId: string): CompleteRunIds {
  const digest = createHash("sha256").update(`${uid}:${clientRunSessionId}`).digest("hex").slice(0, 24);
  return {
    activityId: `activity_${digest}`,
    summaryId: `summary_${digest}`,
    progressionEventId: `progression_${digest}`,
  };
}

export function coolDownProgressionEventId(uid: string, clientRunSessionId: string): string {
  const digest = createHash("sha256").update(`${uid}:${clientRunSessionId}`).digest("hex").slice(0, 24);
  return `progression_cooldown_${digest}`;
}

export function fingerprintPayload(payload: RawRunCompletionPayload): string {
  const sortedPayload = Object.fromEntries(
    Object.entries(payload).sort(([left], [right]) => left.localeCompare(right)),
  );
  return createHash("sha256").update(JSON.stringify(sortedPayload)).digest("hex");
}

export function buildRunSummary(payload: RawRunCompletionPayload): CompleteRunResult["runSummary"] {
  return {
    title: payload.activityTitle ?? "Completed Run",
    startedAt: payload.startedAt,
    endedAt: payload.completedAt,
    distanceMeters: payload.distanceMeters,
    durationSeconds: payload.durationSeconds,
    activeDurationSeconds: payload.activeDurationSeconds,
    elapsedWallSeconds: payload.elapsedWallSeconds,
    pausedDurationSeconds: payload.pausedDurationSeconds,
    averagePaceSecondsPerKm: payload.avgPaceSecondsPerKm,
    displayDistance: `${(payload.distanceMeters / 1000).toFixed(2)} km`,
    displayDuration: formatDuration(payload.durationSeconds),
    displayPace: `${Math.round(payload.avgPaceSecondsPerKm)} sec/km`,
    ...(payload.routeLabel === undefined ? {} : { routeLabel: payload.routeLabel }),
    ...(payload.cadenceAnalysisSeries === undefined
      ? {}
      : { cadenceAnalysisSeries: payload.cadenceAnalysisSeries }),
    ...(payload.routePreview === undefined ? {} : { routePreview: payload.routePreview }),
    ...(payload.paceAnalysisSeries === undefined
      ? {}
      : { paceAnalysisSeries: payload.paceAnalysisSeries }),
    ...(payload.elevationSeries === undefined ? {} : { elevationSeries: payload.elevationSeries }),
  };
}

export function assertExistingActivityMatchesPayload(
  activityData: FirebaseFirestore.DocumentData | undefined,
  payloadFingerprint: string,
): void {
  if (activityData === undefined) {
    throw new HttpsError("already-exists", "Existing run completion state is unreadable.");
  }

  if (activityData["payloadFingerprint"] !== payloadFingerprint) {
    throw new HttpsError("already-exists", "clientRunSessionId already exists with different run data.");
  }
}

function formatDuration(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

// Display label for the backend-owned lifetime longest streak. Mirrors the
// client `_streakLabel` (0 days / 1 day / N days) so the profile renders it as-is.
export function formatLongestStreakLabel(streakDays: number): string {
  const safeDays = Number.isFinite(streakDays) && streakDays > 0 ? Math.floor(streakDays) : 0;
  return safeDays === 1 ? "1 day" : `${safeDays} days`;
}

// Display label for the backend-owned lifetime total distance, one decimal km
// (e.g. "148.6 km"), matching the profile's distance formatting.
export function formatTotalDistanceLabel(totalDistanceMeters: number): string {
  const safeMeters = Number.isFinite(totalDistanceMeters) && totalDistanceMeters > 0 ? totalDistanceMeters : 0;
  return `${(safeMeters / 1000).toFixed(1)} km`;
}
