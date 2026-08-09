// Parses and validates an activity-feedback request before anything reaches the
// model.
//
// The callable's payload is client-supplied, so `parseActivityFeedbackRequest`
// accepts only the known keys, enforces the split cap and text limits, and
// throws [ActivityFeedbackContractError] otherwise. Unknown fields are rejected
// rather than ignored — that is what stops a client from smuggling extra text
// into the prompt.

import type {
  ActivityFeedbackCadenceMetrics,
  ActivityFeedbackElevationMetrics,
  ActivityFeedbackPaceMetrics,
  ActivityFeedbackPerformanceMetrics,
  ActivityFeedbackRequest,
  ActivityFeedbackSplitMetrics,
  ActivityFeedbackSummaryMetrics,
} from "./activityFeedbackTypes.js";
import {
  ACTIVITY_FEEDBACK_CADENCE_KEYS,
  ACTIVITY_FEEDBACK_DERIVED_TEXT_LIMIT,
  ACTIVITY_FEEDBACK_ELEVATION_KEYS,
  ACTIVITY_FEEDBACK_MAX_SPLITS,
  ACTIVITY_FEEDBACK_MAX_UNAVAILABLE,
  ACTIVITY_FEEDBACK_PACE_KEYS,
  ACTIVITY_FEEDBACK_PERFORMANCE_KEYS,
  ACTIVITY_FEEDBACK_SOURCE_LABELS,
  ACTIVITY_FEEDBACK_SPLIT_KEYS,
  ACTIVITY_FEEDBACK_SUMMARY_KEYS,
  ACTIVITY_FEEDBACK_TOP_LEVEL_KEYS,
  ACTIVITY_FEEDBACK_UNAVAILABLE_TEXT_LIMIT,
  ACTIVITY_FEEDBACK_UNSAFE_DERIVED_TEXT,
  type ActivityFeedbackNumberBounds,
} from "./activityFeedbackContractFields.js";

export type {
  ActivityFeedbackAgentResponse,
  ActivityFeedbackCadenceMetrics,
  ActivityFeedbackElevationMetrics,
  ActivityFeedbackPaceMetrics,
  ActivityFeedbackPerformanceMetrics,
  ActivityFeedbackRequest,
  ActivityFeedbackSections,
  ActivityFeedbackSplitMetrics,
  ActivityFeedbackSummaryMetrics,
} from "./activityFeedbackTypes.js";

export class ActivityFeedbackContractError extends Error {
  public constructor(readonly field: string, message: string) {
    super(message);
    this.name = "ActivityFeedbackContractError";
  }
}

export function parseActivityFeedbackRequest(value: unknown): ActivityFeedbackRequest {
  const data = exactRecord(value, "payload", ACTIVITY_FEEDBACK_TOP_LEVEL_KEYS);
  if (data["schemaVersion"] !== 1) invalid("schemaVersion", "schemaVersion must be 1.");
  const performance = optionalRecord(data, "performance", ACTIVITY_FEEDBACK_PERFORMANCE_KEYS, parsePerformance);
  const pace = optionalRecord(data, "pace", ACTIVITY_FEEDBACK_PACE_KEYS, parsePace);
  const cadence = optionalRecord(data, "cadence", ACTIVITY_FEEDBACK_CADENCE_KEYS, parseCadence);
  const elevation = optionalRecord(data, "elevation", ACTIVITY_FEEDBACK_ELEVATION_KEYS, parseElevation);
  const unavailable = parseUnavailable(data["unavailable"]);
  return {
    schemaVersion: 1,
    summary: parseSummary(exactRecord(data["summary"], "summary", ACTIVITY_FEEDBACK_SUMMARY_KEYS)),
    ...(performance === undefined ? {} : { performance }),
    ...(pace === undefined ? {} : { pace }),
    ...(cadence === undefined ? {} : { cadence }),
    ...(elevation === undefined ? {} : { elevation }),
    ...(unavailable === undefined ? {} : { unavailable }),
  };
}

function parseSummary(data: Readonly<Record<string, unknown>>): ActivityFeedbackSummaryMetrics {
  const caloriesKcal = optionalNumber(data, "caloriesKcal", { minimum: 0, maximum: 100_000 });
  const sourceLabel = requiredText(data, "sourceLabel", 40);
  if (!ACTIVITY_FEEDBACK_SOURCE_LABELS.has(sourceLabel)) invalid("summary.sourceLabel", "summary.sourceLabel is not an approved production source.");
  return {
    distanceKm: requiredNumber(data, "distanceKm", { minimum: 0, maximum: 1_000 }),
    durationSeconds: requiredNumber(data, "durationSeconds", { minimum: 0, maximum: 604_800, integer: true }),
    averagePaceSecondsPerKm: requiredNumber(data, "averagePaceSecondsPerKm", { minimum: 0, maximum: 86_400 }),
    ...(caloriesKcal === undefined ? {} : { caloriesKcal }),
    sourceLabel,
  };
}

function parsePerformance(data: Readonly<Record<string, unknown>>): ActivityFeedbackPerformanceMetrics {
  const score = optionalNumber(data, "score", { minimum: 0, maximum: 100 });
  return {
    ...(score === undefined ? {} : { score }),
    ...optionalTextProperties(data, ["qualityLabel", "takeaway", "nextFocus", "scoreConfidenceLabel"]),
  };
}

function parsePace(data: Readonly<Record<string, unknown>>): ActivityFeedbackPaceMetrics {
  const fastestPaceSecondsPerKm = optionalNumber(data, "fastestPaceSecondsPerKm", { minimum: 0, maximum: 86_400 });
  const slowestPaceSecondsPerKm = optionalNumber(data, "slowestPaceSecondsPerKm", { minimum: 0, maximum: 86_400 });
  const stabilityLabel = optionalText(data, "stabilityLabel", ACTIVITY_FEEDBACK_DERIVED_TEXT_LIMIT);
  const splits = parseSplits(data["splits"]);
  return {
    ...(fastestPaceSecondsPerKm === undefined ? {} : { fastestPaceSecondsPerKm }),
    ...(slowestPaceSecondsPerKm === undefined ? {} : { slowestPaceSecondsPerKm }),
    ...(stabilityLabel === undefined ? {} : { stabilityLabel }),
    ...(splits === undefined ? {} : { splits }),
  };
}

function parseCadence(data: Readonly<Record<string, unknown>>): ActivityFeedbackCadenceMetrics {
  const averageSpm = optionalNumber(data, "averageSpm", { minimum: 1, maximum: 300 });
  const isEstimated = optionalBoolean(data, "isEstimated");
  return {
    ...(averageSpm === undefined ? {} : { averageSpm }),
    ...optionalTextProperties(data, ["status", "strideConsistency", "confidence", "sourceReason"]),
    ...(isEstimated === undefined ? {} : { isEstimated }),
  };
}

function parseElevation(data: Readonly<Record<string, unknown>>): ActivityFeedbackElevationMetrics {
  const totalGainMeters = optionalNumber(data, "totalGainMeters", { minimum: 0, maximum: 20_000 });
  const highestPointMeters = optionalNumber(data, "highestPointMeters", { minimum: -1_000, maximum: 10_000 });
  const lowestPointMeters = optionalNumber(data, "lowestPointMeters", { minimum: -1_000, maximum: 10_000 });
  const difficulty = optionalText(data, "difficulty", ACTIVITY_FEEDBACK_DERIVED_TEXT_LIMIT);
  return {
    ...(totalGainMeters === undefined ? {} : { totalGainMeters }),
    ...(highestPointMeters === undefined ? {} : { highestPointMeters }),
    ...(lowestPointMeters === undefined ? {} : { lowestPointMeters }),
    ...(difficulty === undefined ? {} : { difficulty }),
  };
}

function parseSplits(value: unknown): readonly ActivityFeedbackSplitMetrics[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length > ACTIVITY_FEEDBACK_MAX_SPLITS) invalid("pace.splits", `pace.splits must contain at most ${ACTIVITY_FEEDBACK_MAX_SPLITS} items.`);
  return value.map((split, index) => {
    const field = `pace.splits[${index}]`;
    const data = exactRecord(split, field, ACTIVITY_FEEDBACK_SPLIT_KEYS);
    const isPartial = data["isPartial"];
    if (typeof isPartial !== "boolean") invalid(`${field}.isPartial`, `${field}.isPartial must be a boolean.`);
    const elevationMeters = optionalNumber(data, "elevationMeters", { minimum: -1_000, maximum: 10_000 });
    return {
      distanceKm: requiredNumber(data, "distanceKm", { minimum: 0, maximum: 1_000 }),
      paceSecondsPerKm: requiredNumber(data, "paceSecondsPerKm", { minimum: 0, maximum: 86_400 }),
      isPartial,
      ...(elevationMeters === undefined ? {} : { elevationMeters }),
    };
  });
}

function parseUnavailable(value: unknown): readonly string[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length > ACTIVITY_FEEDBACK_MAX_UNAVAILABLE) invalid("unavailable", `unavailable must contain at most ${ACTIVITY_FEEDBACK_MAX_UNAVAILABLE} items.`);
  return value.map((item, index) => normalizedText(item, `unavailable[${index}]`, ACTIVITY_FEEDBACK_UNAVAILABLE_TEXT_LIMIT));
}

function optionalRecord<T>(
  data: Readonly<Record<string, unknown>>,
  key: string,
  keys: ReadonlySet<string>,
  parse: (value: Readonly<Record<string, unknown>>) => T,
): T | undefined {
  const value = data[key];
  return value === undefined ? undefined : parse(exactRecord(value, key, keys));
}

function optionalTextProperties(
  data: Readonly<Record<string, unknown>>,
  keys: readonly string[],
): Readonly<Record<string, string>> {
  const values: Record<string, string> = {};
  for (const key of keys) {
    const value = optionalText(data, key, ACTIVITY_FEEDBACK_DERIVED_TEXT_LIMIT);
    if (value !== undefined) values[key] = value;
  }
  return values;
}

function requiredNumber(data: Readonly<Record<string, unknown>>, key: string, bounds: ActivityFeedbackNumberBounds): number {
  const value = optionalNumber(data, key, bounds);
  if (value === undefined) invalid(key, `${key} is required.`);
  return value;
}

function optionalNumber(data: Readonly<Record<string, unknown>>, key: string, bounds: ActivityFeedbackNumberBounds): number | undefined {
  const value = data[key];
  if (value === undefined) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value) || value < bounds.minimum || value > bounds.maximum || (bounds.integer === true && !Number.isInteger(value))) {
    invalid(key, `${key} is outside its derived-metric bounds.`);
  }
  return value;
}

function requiredText(data: Readonly<Record<string, unknown>>, key: string, maximumLength: number): string {
  const value = optionalText(data, key, maximumLength);
  if (value === undefined) invalid(key, `${key} is required.`);
  return value;
}

function optionalText(data: Readonly<Record<string, unknown>>, key: string, maximumLength: number): string | undefined {
  const value = data[key];
  return value === undefined ? undefined : normalizedText(value, key, maximumLength);
}

function normalizedText(value: unknown, field: string, maximumLength: number): string {
  if (typeof value !== "string" || ACTIVITY_FEEDBACK_UNSAFE_DERIVED_TEXT.test(value)) invalid(field, `${field} must be safe derived text.`);
  const normalized = value.replace(/\s+/gu, " ").trim();
  if (normalized.length === 0 || Array.from(normalized).length > maximumLength) invalid(field, `${field} must contain 1-${maximumLength} characters.`);
  return normalized;
}

function optionalBoolean(data: Readonly<Record<string, unknown>>, key: string): boolean | undefined {
  const value = data[key];
  if (value === undefined) return undefined;
  if (typeof value !== "boolean") invalid(key, `${key} must be a boolean.`);
  return value;
}

function exactRecord(value: unknown, field: string, keys: ReadonlySet<string>): Readonly<Record<string, unknown>> {
  if (!isRecord(value)) invalid(field, `${field} must be an object.`);
  for (const key of Object.keys(value)) {
    if (!keys.has(key)) invalid(`${field}.${key}`, `Unsupported activity feedback field: ${field}.${key}.`);
  }
  return value;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function invalid(field: string, message: string): never {
  throw new ActivityFeedbackContractError(field, message);
}
