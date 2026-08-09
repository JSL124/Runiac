import { HttpsError } from "firebase-functions/v2/https";
import { assertCompletedAtNotInFuture } from "./completedAtFreshness.js";
import type { RawRunCompletionPayload } from "./runCompletionTypes.js";
import { readOptionalCadenceAnalysisSeries } from "./validateCadenceAnalysisSeries.js";
import { readOptionalRoutePreview } from "./validateRoutePreview.js";
import {
  readOptionalElevationSeries,
  readOptionalPaceAnalysisSeries,
} from "./validateRunSummaryDetails.js";
import {
  readDistanceMeters,
  readDurationSeconds,
  readOptionalDurationSeconds,
  readOptionalPositiveNumber,
  readPaceSecondsPerKm,
} from "./validateRunScalarFields.js";

const allowedKeys = new Set([
  "clientRunSessionId",
  "startedAt",
  "completedAt",
  "durationSeconds",
  "activeDurationSeconds",
  "elapsedWallSeconds",
  "pausedDurationSeconds",
  "distanceMeters",
  "avgPaceSecondsPerKm",
  "source",
  "routePrivacy",
  "userConfirmedLowDataSave",
  "activityTitle",
  "routeLabel",
  "caloriesEstimate",
  "planEnrollmentId",
  "scheduledWorkoutId",
  "deviceRecordedAt",
  "clientAppVersion",
  "cadenceAnalysisSeries",
  "routePreview",
  "paceAnalysisSeries",
  "elevationSeries",
]);

const protectedKeys = new Set([
  "xp",
  "totalXp",
  "totalXP",
  "weeklyXp",
  "weeklyXP",
  "monthlyXp",
  "monthlyXP",
  "streak",
  "streakCount",
  "level",
  "rank",
  "leaderboardScore",
  "scoreXp",
  "scoreXP",
  "subscriptionStatus",
  "subscriptionPrivilegeState",
  "userRole",
  "adminPrivilegeState",
  "expertPrivilegeState",
  "validationStatus",
  "validatedActivityContributionState",
  "countsTowardProgression",
]);

const isoDatePattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

export function parseRunCompletionPayload(
  data: unknown,
  options: { readonly nowMs?: number } = {},
): RawRunCompletionPayload {
  if (!isRecord(data)) {
    throw invalid("Payload must be an object.");
  }

  for (const key of Object.keys(data)) {
    if (protectedKeys.has(key)) {
      throw invalid(`Protected field is not accepted: ${key}.`);
    }
    if (!allowedKeys.has(key)) {
      throw invalid(`Unsupported field is not accepted: ${key}.`);
    }
  }

  const userConfirmedLowDataSave = readUserConfirmedLowDataSave(data);
  const durationSeconds = readDurationSeconds(data, userConfirmedLowDataSave);
  const activeDurationSeconds =
    readOptionalDurationSeconds(data, "activeDurationSeconds", userConfirmedLowDataSave) ?? durationSeconds;
  const distanceMeters = readDistanceMeters(data, userConfirmedLowDataSave);
  const startedAt = readIsoDateString(data, "startedAt");
  const completedAt = readIsoDateString(data, "completedAt");

  if (Date.parse(completedAt) <= Date.parse(startedAt)) {
    throw invalid("completedAt must be after startedAt.");
  }

  // startedAt needs no separate bound: it is strictly before completedAt.
  assertCompletedAtNotInFuture(completedAt, options.nowMs);

  const computedElapsedWallSeconds = (Date.parse(completedAt) - Date.parse(startedAt)) / 1000;
  const elapsedWallSeconds =
    readOptionalDurationSeconds(data, "elapsedWallSeconds", userConfirmedLowDataSave) ??
    Math.round(computedElapsedWallSeconds);
  const pausedDurationSeconds =
    readOptionalDurationSeconds(data, "pausedDurationSeconds", true) ??
    Math.max(0, elapsedWallSeconds - activeDurationSeconds);

  if (durationSeconds !== activeDurationSeconds) {
    throw invalid("durationSeconds must match activeDurationSeconds.");
  }

  if (Math.abs(computedElapsedWallSeconds - elapsedWallSeconds) > 60) {
    throw invalid("elapsedWallSeconds must match startedAt/completedAt within tolerance.");
  }

  if (activeDurationSeconds - elapsedWallSeconds > 60) {
    throw invalid("activeDurationSeconds must not exceed elapsedWallSeconds within tolerance.");
  }

  if (Math.abs(elapsedWallSeconds - activeDurationSeconds - pausedDurationSeconds) > 60) {
    throw invalid("pausedDurationSeconds must match elapsedWallSeconds minus activeDurationSeconds within tolerance.");
  }

  const activityTitle = readOptionalActivityTitle(data);
  const routeLabel = readOptionalString(data, "routeLabel");
  const caloriesEstimate = readOptionalPositiveNumber(data, "caloriesEstimate");
  const planEnrollmentId = readOptionalString(data, "planEnrollmentId");
  const scheduledWorkoutId = readOptionalString(data, "scheduledWorkoutId");
  const deviceRecordedAt = readOptionalIsoDateString(data, "deviceRecordedAt");
  const clientAppVersion = readOptionalString(data, "clientAppVersion");
  const cadenceAnalysisSeries = readOptionalCadenceAnalysisSeries(
    data,
    durationSeconds,
  );
  const routePreview = readOptionalRoutePreview(data);
  const paceAnalysisSeries = readOptionalPaceAnalysisSeries(data, {
    durationSeconds,
    distanceMeters,
  });
  const elevationSeries = readOptionalElevationSeries(data, { distanceMeters });

  const avgPaceSecondsPerKm = readPaceSecondsPerKm(data, {
    userConfirmedLowDataSave,
    distanceMeters,
  });

  if (distanceMeters > 0) {
    const impliedPace = (durationSeconds * 1000) / distanceMeters;
    // The client floors the pace (up to 1 s/km low) and computes it against
    // the raw unrounded distance while only the rounded integer metre count
    // is transmitted. At the client's own minimum submittable run (50 m /
    // 60 s) that rounding is worth ~12 s/km, so 15 s/km absolute is the
    // floor, with 2% relative taking over for slower paces.
    const tolerance = Math.max(15, Math.ceil(impliedPace * 0.02));
    if (Math.abs(avgPaceSecondsPerKm - impliedPace) > tolerance) {
      throw invalid("avgPaceSecondsPerKm is not consistent with durationSeconds and distanceMeters.");
    }
  }

  return {
    clientRunSessionId: readString(data, "clientRunSessionId"),
    startedAt,
    completedAt,
    durationSeconds,
    activeDurationSeconds,
    elapsedWallSeconds,
    pausedDurationSeconds,
    distanceMeters,
    avgPaceSecondsPerKm,
    source: readMobileSource(data),
    routePrivacy: readRoutePrivacy(data),
    ...(userConfirmedLowDataSave ? { userConfirmedLowDataSave: true } : {}),
    ...(activityTitle === undefined ? {} : { activityTitle }),
    ...(routeLabel === undefined ? {} : { routeLabel }),
    ...(caloriesEstimate === undefined ? {} : { caloriesEstimate }),
    ...(planEnrollmentId === undefined ? {} : { planEnrollmentId }),
    ...(scheduledWorkoutId === undefined ? {} : { scheduledWorkoutId }),
    ...(deviceRecordedAt === undefined ? {} : { deviceRecordedAt }),
    ...(clientAppVersion === undefined ? {} : { clientAppVersion }),
    ...(cadenceAnalysisSeries === undefined ? {} : { cadenceAnalysisSeries }),
    ...(routePreview === undefined ? {} : { routePreview }),
    ...(paceAnalysisSeries === undefined ? {} : { paceAnalysisSeries }),
    ...(elevationSeries === undefined ? {} : { elevationSeries }),
  };
}

function readOptionalActivityTitle(
  data: Readonly<Record<string, unknown>>,
): string | undefined {
  const value = data["activityTitle"];
  if (value === undefined) {
    return undefined;
  }
  if (
    typeof value !== "string" ||
    !/^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) (Morning|Afternoon|Evening|Night) Run$/.test(
      value,
    )
  ) {
    throw invalid("activityTitle must be a Runiac generated run title.");
  }
  return value;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(data: Readonly<Record<string, unknown>>, key: string): string {
  const value = data[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw invalid(`${key} must be a non-empty string.`);
  }
  return value;
}

function readOptionalString(data: Readonly<Record<string, unknown>>, key: string): string | undefined {
  const value = data[key];
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== "string" || value.trim().length === 0) {
    throw invalid(`${key} must be a non-empty string when provided.`);
  }
  return value;
}

function readUserConfirmedLowDataSave(data: Readonly<Record<string, unknown>>): boolean {
  const value = data["userConfirmedLowDataSave"];
  if (value === undefined) {
    return false;
  }
  if (typeof value !== "boolean") {
    throw invalid("userConfirmedLowDataSave must be true or false when provided.");
  }
  return value;
}

function readIsoDateString(data: Readonly<Record<string, unknown>>, key: string): string {
  const value = readString(data, key);
  if (!isoDatePattern.test(value) || Number.isNaN(Date.parse(value))) {
    throw invalid(`${key} must be a UTC ISO date string with milliseconds.`);
  }
  return value;
}

function readOptionalIsoDateString(data: Readonly<Record<string, unknown>>, key: string): string | undefined {
  const value = readOptionalString(data, key);
  if (value === undefined) {
    return undefined;
  }
  if (!isoDatePattern.test(value) || Number.isNaN(Date.parse(value))) {
    throw invalid(`${key} must be a UTC ISO date string with milliseconds.`);
  }
  return value;
}

function readMobileSource(data: Readonly<Record<string, unknown>>): "mobile" {
  const source = readString(data, "source");
  if (source !== "mobile") {
    throw invalid("source must be mobile.");
  }
  return source;
}

function readRoutePrivacy(data: Readonly<Record<string, unknown>>): "private" | "public" {
  const routePrivacy = readString(data, "routePrivacy");
  if (routePrivacy !== "private" && routePrivacy !== "public") {
    throw invalid("routePrivacy must be private or public.");
  }
  return routePrivacy;
}

function invalid(message: string): HttpsError {
  return new HttpsError("invalid-argument", message);
}
