import { HttpsError } from "firebase-functions/v2/https";

const maxDurationSeconds = 86_400;
const maxDistanceMeters = 100_000;
const minPaceSecondsPerKm = 120;
const maxPaceSecondsPerKm = 3_600;

export function readDurationSeconds(
  data: Readonly<Record<string, unknown>>,
  userConfirmedLowDataSave: boolean,
): number {
  if (!userConfirmedLowDataSave) {
    return readBoundedPositiveNumber(data, "durationSeconds", maxDurationSeconds);
  }
  const value = readNonNegativeNumber(data, "durationSeconds");
  if (value > maxDurationSeconds) {
    throw invalid("durationSeconds exceeds the emulator skeleton safety limit.");
  }
  return value;
}

export function readOptionalDurationSeconds(
  data: Readonly<Record<string, unknown>>,
  key: string,
  userConfirmedLowDataSave: boolean,
): number | undefined {
  if (data[key] === undefined) {
    return undefined;
  }
  if (!userConfirmedLowDataSave) {
    return readBoundedPositiveNumber(data, key, maxDurationSeconds);
  }
  const value = readNonNegativeNumber(data, key);
  if (value > maxDurationSeconds) {
    throw invalid(`${key} exceeds the emulator skeleton safety limit.`);
  }
  return value;
}

export function readDistanceMeters(
  data: Readonly<Record<string, unknown>>,
  userConfirmedLowDataSave: boolean,
): number {
  if (!userConfirmedLowDataSave) {
    return readBoundedPositiveNumber(data, "distanceMeters", maxDistanceMeters);
  }
  const value = readNonNegativeNumber(data, "distanceMeters");
  if (value > maxDistanceMeters) {
    throw invalid("distanceMeters exceeds the emulator skeleton safety limit.");
  }
  return value;
}

export function readPaceSecondsPerKm(
  data: Readonly<Record<string, unknown>>,
  options: { readonly userConfirmedLowDataSave: boolean; readonly distanceMeters: number },
): number {
  const value = options.userConfirmedLowDataSave
    ? readNonNegativeNumber(data, "avgPaceSecondsPerKm")
    : readPositiveNumber(data, "avgPaceSecondsPerKm");
  if (value === 0) {
    if (options.distanceMeters > 0) {
      throw invalid("avgPaceSecondsPerKm must be positive when distanceMeters is positive.");
    }
    return value;
  }
  if (value < minPaceSecondsPerKm || value > maxPaceSecondsPerKm) {
    throw invalid("avgPaceSecondsPerKm is outside the emulator skeleton safety limits.");
  }
  return value;
}

export function readOptionalPositiveNumber(
  data: Readonly<Record<string, unknown>>,
  key: string,
): number | undefined {
  const value = data[key];
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw invalid(`${key} must be a positive number when provided.`);
  }
  return value;
}

function readPositiveNumber(data: Readonly<Record<string, unknown>>, key: string): number {
  const value = data[key];
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw invalid(`${key} must be a positive number.`);
  }
  return value;
}

function readBoundedPositiveNumber(
  data: Readonly<Record<string, unknown>>,
  key: string,
  maxValue: number,
): number {
  const value = readPositiveNumber(data, key);
  if (value > maxValue) {
    throw invalid(`${key} exceeds the emulator skeleton safety limit.`);
  }
  return value;
}

function readNonNegativeNumber(data: Readonly<Record<string, unknown>>, key: string): number {
  const value = data[key];
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw invalid(`${key} must be a non-negative number.`);
  }
  return value;
}

function invalid(message: string): HttpsError {
  return new HttpsError("invalid-argument", message);
}
