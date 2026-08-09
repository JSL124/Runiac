// Key sets and bounds for the planned-workout briefing contract.
//
// Mirrors the shape of `activityFeedbackContractFields.ts`. The unsafe-text
// pattern is the same one that guards the activity-feedback prompt: it rejects
// links, prompt-injection phrasing, and the identifier/location field names
// that must never reach the model, so a compromised or buggy client cannot
// smuggle them through a display string.

export const WORKOUT_BRIEFING_TOP_LEVEL_KEYS = new Set([
  "schemaVersion",
  "workout",
  "metrics",
  "steps",
  "coachNotes",
]);
export const WORKOUT_BRIEFING_WORKOUT_KEYS = new Set([
  "dayLabel",
  "planTitle",
  "effortGuide",
  "weekNumber",
  "weekFocus",
]);
export const WORKOUT_BRIEFING_METRIC_KEYS = new Set(["label", "value"]);
export const WORKOUT_BRIEFING_STEP_KEYS = new Set(["title", "detail"]);

export const WORKOUT_BRIEFING_MAX_METRICS = 6;
export const WORKOUT_BRIEFING_MAX_STEPS = 6;
export const WORKOUT_BRIEFING_MAX_COACH_NOTES = 6;

export const WORKOUT_BRIEFING_SHORT_TEXT_LIMIT = 40;
export const WORKOUT_BRIEFING_LABEL_TEXT_LIMIT = 120;
export const WORKOUT_BRIEFING_BODY_TEXT_LIMIT = 240;

export const WORKOUT_BRIEFING_WEEK_NUMBER_BOUNDS = {
  minimum: 1,
  maximum: 104,
  integer: true,
} as const;

export const WORKOUT_BRIEFING_UNSAFE_TEXT = /(?:https?:\/\/|www\.|ignore\s+(?:all\s+)?previous|system\s+prompt|activityId|routeName|polyline|coordinates|demo\s*only|demoOnly)/iu;

export type WorkoutBriefingNumberBounds = {
  readonly minimum: number;
  readonly maximum: number;
  readonly integer?: boolean;
};
