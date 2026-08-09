import type {
  WorkoutBriefingMetric,
  WorkoutBriefingRequest,
  WorkoutBriefingStep,
  WorkoutBriefingWorkout,
} from "./workoutBriefingTypes.js";
import {
  WORKOUT_BRIEFING_BODY_TEXT_LIMIT,
  WORKOUT_BRIEFING_LABEL_TEXT_LIMIT,
  WORKOUT_BRIEFING_MAX_COACH_NOTES,
  WORKOUT_BRIEFING_MAX_METRICS,
  WORKOUT_BRIEFING_MAX_STEPS,
  WORKOUT_BRIEFING_METRIC_KEYS,
  WORKOUT_BRIEFING_SHORT_TEXT_LIMIT,
  WORKOUT_BRIEFING_STEP_KEYS,
  WORKOUT_BRIEFING_TOP_LEVEL_KEYS,
  WORKOUT_BRIEFING_UNSAFE_TEXT,
  WORKOUT_BRIEFING_WEEK_NUMBER_BOUNDS,
  WORKOUT_BRIEFING_WORKOUT_KEYS,
  type WorkoutBriefingNumberBounds,
} from "./workoutBriefingContractFields.js";

export type {
  WorkoutBriefingAgentResponse,
  WorkoutBriefingMetric,
  WorkoutBriefingRequest,
  WorkoutBriefingSections,
  WorkoutBriefingStep,
  WorkoutBriefingWorkout,
} from "./workoutBriefingTypes.js";

export class WorkoutBriefingContractError extends Error {
  public constructor(readonly field: string, message: string) {
    super(message);
    this.name = "WorkoutBriefingContractError";
  }
}

/// Rejects any key the contract does not name, so a client cannot widen what
/// reaches the prompt by adding a field.
export function parseWorkoutBriefingRequest(value: unknown): WorkoutBriefingRequest {
  const data = exactRecord(value, "payload", WORKOUT_BRIEFING_TOP_LEVEL_KEYS);
  if (data["schemaVersion"] !== 1) invalid("schemaVersion", "schemaVersion must be 1.");
  return {
    schemaVersion: 1,
    workout: parseWorkout(exactRecord(data["workout"], "workout", WORKOUT_BRIEFING_WORKOUT_KEYS)),
    metrics: parseMetrics(data["metrics"]),
    steps: parseSteps(data["steps"]),
    coachNotes: parseCoachNotes(data["coachNotes"]),
  };
}

function parseWorkout(data: Readonly<Record<string, unknown>>): WorkoutBriefingWorkout {
  const weekNumber = optionalNumber(data, "weekNumber", WORKOUT_BRIEFING_WEEK_NUMBER_BOUNDS);
  const weekFocus = optionalText(data, "weekFocus", WORKOUT_BRIEFING_BODY_TEXT_LIMIT);
  return {
    dayLabel: requiredText(data, "dayLabel", WORKOUT_BRIEFING_SHORT_TEXT_LIMIT),
    planTitle: requiredText(data, "planTitle", WORKOUT_BRIEFING_BODY_TEXT_LIMIT),
    effortGuide: requiredText(data, "effortGuide", WORKOUT_BRIEFING_BODY_TEXT_LIMIT),
    ...(weekNumber === undefined ? {} : { weekNumber }),
    ...(weekFocus === undefined ? {} : { weekFocus }),
  };
}

function parseMetrics(value: unknown): readonly WorkoutBriefingMetric[] {
  return parseArray(value, "metrics", WORKOUT_BRIEFING_MAX_METRICS, (item, field) => {
    const data = exactRecord(item, field, WORKOUT_BRIEFING_METRIC_KEYS);
    return {
      label: requiredText(data, "label", WORKOUT_BRIEFING_SHORT_TEXT_LIMIT, field),
      value: requiredText(data, "value", WORKOUT_BRIEFING_LABEL_TEXT_LIMIT, field),
    };
  });
}

function parseSteps(value: unknown): readonly WorkoutBriefingStep[] {
  return parseArray(value, "steps", WORKOUT_BRIEFING_MAX_STEPS, (item, field) => {
    const data = exactRecord(item, field, WORKOUT_BRIEFING_STEP_KEYS);
    return {
      title: requiredText(data, "title", WORKOUT_BRIEFING_LABEL_TEXT_LIMIT, field),
      detail: requiredText(data, "detail", WORKOUT_BRIEFING_BODY_TEXT_LIMIT, field),
    };
  });
}

function parseCoachNotes(value: unknown): readonly string[] {
  return parseArray(value, "coachNotes", WORKOUT_BRIEFING_MAX_COACH_NOTES, (item, field) =>
    normalizedText(item, field, WORKOUT_BRIEFING_BODY_TEXT_LIMIT),
  );
}

function parseArray<T>(
  value: unknown,
  field: string,
  maximumLength: number,
  parse: (item: unknown, itemField: string) => T,
): readonly T[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > maximumLength) {
    invalid(field, `${field} must contain at most ${maximumLength} items.`);
  }
  return value.map((item, index) => parse(item, `${field}[${index}]`));
}

function requiredText(
  data: Readonly<Record<string, unknown>>,
  key: string,
  maximumLength: number,
  parentField?: string,
): string {
  const field = parentField === undefined ? key : `${parentField}.${key}`;
  const value = data[key];
  if (value === undefined) invalid(field, `${field} is required.`);
  return normalizedText(value, field, maximumLength);
}

function optionalText(
  data: Readonly<Record<string, unknown>>,
  key: string,
  maximumLength: number,
): string | undefined {
  const value = data[key];
  return value === undefined ? undefined : normalizedText(value, key, maximumLength);
}

function normalizedText(value: unknown, field: string, maximumLength: number): string {
  if (typeof value !== "string" || WORKOUT_BRIEFING_UNSAFE_TEXT.test(value)) {
    invalid(field, `${field} must be safe display text.`);
  }
  const normalized = value.replace(/\s+/gu, " ").trim();
  if (normalized.length === 0 || Array.from(normalized).length > maximumLength) {
    invalid(field, `${field} must contain 1-${maximumLength} characters.`);
  }
  return normalized;
}

function optionalNumber(
  data: Readonly<Record<string, unknown>>,
  key: string,
  bounds: WorkoutBriefingNumberBounds,
): number | undefined {
  const value = data[key];
  if (value === undefined) return undefined;
  if (
    typeof value !== "number"
    || !Number.isFinite(value)
    || value < bounds.minimum
    || value > bounds.maximum
    || (bounds.integer === true && !Number.isInteger(value))
  ) {
    invalid(key, `${key} is outside its supported bounds.`);
  }
  return value;
}

function exactRecord(
  value: unknown,
  field: string,
  keys: ReadonlySet<string>,
): Readonly<Record<string, unknown>> {
  if (!isRecord(value)) invalid(field, `${field} must be an object.`);
  for (const key of Object.keys(value)) {
    if (!keys.has(key)) invalid(`${field}.${key}`, `Unsupported workout briefing field: ${field}.${key}.`);
  }
  return value;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function invalid(field: string, message: string): never {
  throw new WorkoutBriefingContractError(field, message);
}
