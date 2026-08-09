export const ACTIVITY_FEEDBACK_TOP_LEVEL_KEYS = new Set([
  "schemaVersion",
  "summary",
  "performance",
  "pace",
  "cadence",
  "elevation",
  "unavailable",
]);
export const ACTIVITY_FEEDBACK_SUMMARY_KEYS = new Set([
  "distanceKm",
  "durationSeconds",
  "averagePaceSecondsPerKm",
  "caloriesKcal",
  "sourceLabel",
]);
export const ACTIVITY_FEEDBACK_PERFORMANCE_KEYS = new Set([
  "score",
  "qualityLabel",
  "takeaway",
  "nextFocus",
  "scoreConfidenceLabel",
]);
export const ACTIVITY_FEEDBACK_PACE_KEYS = new Set([
  "fastestPaceSecondsPerKm",
  "slowestPaceSecondsPerKm",
  "stabilityLabel",
  "splits",
]);
export const ACTIVITY_FEEDBACK_SPLIT_KEYS = new Set([
  "distanceKm",
  "paceSecondsPerKm",
  "isPartial",
  "elevationMeters",
]);
export const ACTIVITY_FEEDBACK_CADENCE_KEYS = new Set([
  "averageSpm",
  "status",
  "strideConsistency",
  "isEstimated",
  "confidence",
  "sourceReason",
]);
export const ACTIVITY_FEEDBACK_ELEVATION_KEYS = new Set([
  "totalGainMeters",
  "highestPointMeters",
  "lowestPointMeters",
  "difficulty",
]);
export const ACTIVITY_FEEDBACK_SOURCE_LABELS = new Set([
  "Runiac GPS",
  "Apple Health",
  "Health Connect",
  "Garmin via Health",
]);
export const ACTIVITY_FEEDBACK_DERIVED_TEXT_LIMIT = 280;
export const ACTIVITY_FEEDBACK_UNAVAILABLE_TEXT_LIMIT = 120;
export const ACTIVITY_FEEDBACK_MAX_SPLITS = 200;
export const ACTIVITY_FEEDBACK_MAX_UNAVAILABLE = 32;
export const ACTIVITY_FEEDBACK_UNSAFE_DERIVED_TEXT = /(?:https?:\/\/|www\.|ignore\s+(?:all\s+)?previous|system\s+prompt|activityId|routeName|polyline|coordinates|demo\s*only|demoOnly)/iu;

export type ActivityFeedbackNumberBounds = {
  readonly minimum: number;
  readonly maximum: number;
  readonly integer?: boolean;
};
