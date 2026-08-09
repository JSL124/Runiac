import { HttpsError } from "firebase-functions/v2/https";
import type { ElevationSeriesPayload, PaceAnalysisSeriesPayload } from "./runCompletionTypes.js";
import { rejectUnsupportedFields } from "./rejectUnsupportedFields.js";

// Validation for the optional analysis series a client sends with a finished
// run — the pace series and the elevation series.
//
// This is a trust boundary. The payload arrives from the app, so it is checked
// for internal consistency rather than accepted: samples must be within
// plausible bounds, must not exceed the sample cap, and must agree with the
// run's own duration and distance to within the tolerances below. A payload
// that fails is rejected with an `HttpsError`, not silently trimmed.
//
// The tolerances are deliberately loose. The goal is to reject fabricated or
// corrupt data, not to re-derive the run — GPS noise means a legitimate series
// never lines up exactly with the summary.

const maxAnalysisSampleCount = 360;
const minPaceSecondsPerKm = 150;
const maxPaceSecondsPerKm = 1_800;
const paceElapsedToleranceSeconds = 60;
const distanceToleranceRatio = 1.1;
const paceDistanceToleranceMeters = 50;
const elevationDistanceToleranceKm = 0.05;
const minElevationMeters = -500;
const maxElevationMeters = 9_000;
const paceSeriesKeys = new Set(["source", "confidence", "samples"]);
const paceSampleKeys = new Set([
  "elapsedSeconds",
  "cumulativeDistanceMeters",
  "paceSecondsPerKm",
  "status",
]);
const elevationSeriesKeys = new Set(["source", "confidence", "samples"]);
const elevationSampleKeys = new Set(["distanceKm", "elevationMeters"]);

type PaceAnalysisBounds = {
  readonly durationSeconds: number;
  readonly distanceMeters: number;
};

type ElevationBounds = {
  readonly distanceMeters: number;
};

export function readOptionalPaceAnalysisSeries(
  data: Readonly<Record<string, unknown>>,
  bounds: PaceAnalysisBounds,
): PaceAnalysisSeriesPayload | undefined {
  const value = data["paceAnalysisSeries"];
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    throw invalid("paceAnalysisSeries must be an object when provided.");
  }
  rejectUnsupportedFields(value, paceSeriesKeys, "paceAnalysisSeries");

  const source = readString(value, "source", "paceAnalysisSeries.source");
  if (source !== "localAccepted") {
    throw invalid("paceAnalysisSeries.source must be localAccepted.");
  }
  const confidence = readString(value, "confidence", "paceAnalysisSeries.confidence");
  if (confidence !== "derived") {
    throw invalid("paceAnalysisSeries.confidence must be derived.");
  }
  const rawSamples = value["samples"];
  if (
    !Array.isArray(rawSamples) ||
    rawSamples.length === 0 ||
    rawSamples.length > maxAnalysisSampleCount
  ) {
    throw invalid("paceAnalysisSeries.samples must contain between 1 and 360 samples.");
  }

  const samples: PaceAnalysisSeriesPayload["samples"][number][] = [];
  let previousElapsedSeconds: number | undefined;
  let previousDistanceMeters: number | undefined;
  const maxElapsedSeconds = bounds.durationSeconds + paceElapsedToleranceSeconds;
  const maxDistanceMeters = bounds.distanceMeters * distanceToleranceRatio + paceDistanceToleranceMeters;
  for (const rawSample of rawSamples) {
    const sample = readPaceAnalysisSample(rawSample);
    if (sample.elapsedSeconds > maxElapsedSeconds) {
      throw invalid("paceAnalysisSeries.samples.elapsedSeconds exceeds run duration tolerance.");
    }
    if (sample.cumulativeDistanceMeters > maxDistanceMeters) {
      throw invalid(
        "paceAnalysisSeries.samples.cumulativeDistanceMeters exceeds run distance tolerance.",
      );
    }
    if (previousElapsedSeconds !== undefined && sample.elapsedSeconds <= previousElapsedSeconds) {
      throw invalid("paceAnalysisSeries.samples.elapsedSeconds must be strictly increasing.");
    }
    if (
      previousDistanceMeters !== undefined &&
      sample.cumulativeDistanceMeters < previousDistanceMeters
    ) {
      throw invalid("paceAnalysisSeries.samples.cumulativeDistanceMeters must be monotonic.");
    }
    samples.push(sample);
    previousElapsedSeconds = sample.elapsedSeconds;
    previousDistanceMeters = sample.cumulativeDistanceMeters;
  }

  return { source, confidence, samples };
}

export function readOptionalElevationSeries(
  data: Readonly<Record<string, unknown>>,
  bounds: ElevationBounds,
): ElevationSeriesPayload | undefined {
  const value = data["elevationSeries"];
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    throw invalid("elevationSeries must be an object when provided.");
  }
  rejectUnsupportedFields(value, elevationSeriesKeys, "elevationSeries");

  const source = readString(value, "source", "elevationSeries.source");
  if (source !== "runiacLocalAccepted") {
    throw invalid("elevationSeries.source must be runiacLocalAccepted.");
  }
  const confidence = readString(value, "confidence", "elevationSeries.confidence");
  if (confidence !== "medium") {
    throw invalid("elevationSeries.confidence must be medium.");
  }
  const rawSamples = value["samples"];
  if (
    !Array.isArray(rawSamples) ||
    rawSamples.length === 0 ||
    rawSamples.length > maxAnalysisSampleCount
  ) {
    throw invalid("elevationSeries.samples must contain between 1 and 360 samples.");
  }

  const samples: ElevationSeriesPayload["samples"][number][] = [];
  let previousDistanceKm: number | undefined;
  const maxDistanceKm =
    (bounds.distanceMeters / 1000) * distanceToleranceRatio + elevationDistanceToleranceKm;
  for (const rawSample of rawSamples) {
    const sample = readElevationSample(rawSample);
    if (sample.distanceKm > maxDistanceKm) {
      throw invalid("elevationSeries.samples.distanceKm exceeds run distance tolerance.");
    }
    if (sample.elevationMeters < minElevationMeters || sample.elevationMeters > maxElevationMeters) {
      throw invalid("elevationSeries.samples.elevationMeters must be between -500 and 9000.");
    }
    if (previousDistanceKm !== undefined && sample.distanceKm <= previousDistanceKm) {
      throw invalid("elevationSeries.samples.distanceKm must be strictly increasing.");
    }
    samples.push(sample);
    previousDistanceKm = sample.distanceKm;
  }

  return { source, confidence, samples };
}

function readPaceAnalysisSample(
  value: unknown,
): PaceAnalysisSeriesPayload["samples"][number] {
  if (!isRecord(value)) {
    throw invalid("paceAnalysisSeries.samples entries must be objects.");
  }
  rejectUnsupportedFields(value, paceSampleKeys, "paceAnalysisSeries.samples");
  const elapsedSeconds = readNonNegativeInteger(
    value,
    "elapsedSeconds",
    "paceAnalysisSeries.samples.elapsedSeconds",
  );
  const cumulativeDistanceMeters = readNonNegativeNumber(
    value,
    "cumulativeDistanceMeters",
    "paceAnalysisSeries.samples.cumulativeDistanceMeters",
  );
  const paceSecondsPerKm = readNonNegativeInteger(
    value,
    "paceSecondsPerKm",
    "paceAnalysisSeries.samples.paceSecondsPerKm",
  );
  if (paceSecondsPerKm < minPaceSecondsPerKm || paceSecondsPerKm > maxPaceSecondsPerKm) {
    throw invalid("paceAnalysisSeries.samples.paceSecondsPerKm is outside safety limits.");
  }
  const status = readString(value, "status", "paceAnalysisSeries.samples.status");
  if (status !== "accepted") {
    throw invalid("paceAnalysisSeries.samples.status must be accepted.");
  }
  return { elapsedSeconds, cumulativeDistanceMeters, paceSecondsPerKm, status };
}

function readElevationSample(value: unknown): ElevationSeriesPayload["samples"][number] {
  if (!isRecord(value)) {
    throw invalid("elevationSeries.samples entries must be objects.");
  }
  rejectUnsupportedFields(value, elevationSampleKeys, "elevationSeries.samples");
  return {
    distanceKm: readNonNegativeNumber(value, "distanceKm", "elevationSeries.samples.distanceKm"),
    elevationMeters: readFiniteNumber(
      value,
      "elevationMeters",
      "elevationSeries.samples.elevationMeters",
    ),
  };
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(
  data: Readonly<Record<string, unknown>>,
  key: string,
  fieldName: string,
): string {
  const value = data[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw invalid(`${fieldName} must be a non-empty string.`);
  }
  return value;
}

function readFiniteNumber(
  data: Readonly<Record<string, unknown>>,
  key: string,
  fieldName: string,
): number {
  const value = data[key];
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw invalid(`${fieldName} must be a finite number.`);
  }
  return value;
}

function readNonNegativeNumber(
  data: Readonly<Record<string, unknown>>,
  key: string,
  fieldName: string,
): number {
  const value = readFiniteNumber(data, key, fieldName);
  if (value < 0) {
    throw invalid(`${fieldName} must be non-negative.`);
  }
  return value;
}

function readNonNegativeInteger(
  data: Readonly<Record<string, unknown>>,
  key: string,
  fieldName: string,
): number {
  const value = readNonNegativeNumber(data, key, fieldName);
  if (!Number.isInteger(value)) {
    throw invalid(`${fieldName} must be an integer.`);
  }
  return value;
}

function invalid(message: string): HttpsError {
  return new HttpsError("invalid-argument", message);
}
