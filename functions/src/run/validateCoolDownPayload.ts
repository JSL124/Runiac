import { HttpsError } from "firebase-functions/v2/https";
import { assertCompletedAtNotInFuture } from "./completedAtFreshness.js";
import { rejectUnsupportedFields } from "./rejectUnsupportedFields.js";
import type { RawCoolDownCompletionPayload } from "./runCompletionTypes.js";

export const requiredStretchStepCount = 14;

const allowedKeys = new Set([
  "activityId",
  "clientRunSessionId",
  "completedStretchCount",
  "completedAt",
]);

const isoDatePattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

export function parseCoolDownCompletionPayload(
  data: unknown,
  options: { readonly nowMs?: number } = {},
): RawCoolDownCompletionPayload {
  if (!isRecord(data)) {
    throw invalid("Payload must be an object.");
  }

  rejectUnsupportedFields(data, allowedKeys, "completeCoolDown payload");

  // Same bound as completeRun: this callable derives its own dailyCapDate and
  // monthlyPeriod from the client's completedAt too, so leaving it open here
  // would leave the future-dating vector half-closed.
  const completedAt = readIsoDateString(data, "completedAt");
  assertCompletedAtNotInFuture(completedAt, options.nowMs);

  return {
    activityId: readString(data, "activityId"),
    clientRunSessionId: readString(data, "clientRunSessionId"),
    completedStretchCount: readRequiredStretchStepCount(data),
    completedAt,
  };
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

function readRequiredStretchStepCount(data: Readonly<Record<string, unknown>>): number {
  const value = data["completedStretchCount"];
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value !== requiredStretchStepCount
  ) {
    throw invalid(
      `completedStretchCount must equal ${requiredStretchStepCount}; the full cool-down stretch sequence must be completed.`,
    );
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

function invalid(message: string): HttpsError {
  return new HttpsError("invalid-argument", message);
}
