import type { WorkoutBriefingSections } from "./workoutBriefingTypes.js";

// The outbound half of the guard pair. Strict structured output already fixes
// the response shape, so these checks exist for what strict mode cannot
// express: policy. A violation is a fallback, not a warning — the runner sees
// the deterministic copy below rather than a sentence that diagnoses an injury
// or promises XP the server never awards.

const OUTPUT_KEYS = new Set([
  "todaySession",
  "whyItHelps",
  "howItFeels",
  "beforeYouStart",
]);
const MAX_SECTION_LENGTH = 280;
const URL = /(?:https?:\/\/|www\.)/iu;
const MARKDOWN = /(?:^|\s)(?:#{1,6}\s|[-*+]\s|>\s)|[*_`~\[\]]/u;
const DIAGNOSIS = /\b(?:diagnos(?:is|e|ed|ing)|medical|doctor|medication|treatment|disease|injur(?:y|ed)|pain)\b/iu;
const SHAME = /\b(?:shame|ashamed|lazy|weak|pathetic|failure|embarrass(?:ed|ing)?|disappoint(?:ed|ing)?|unfit|bad runner|not trying)\b/iu;
const COMPETITIVE_PROMISE = /\b(?:xp|experience points?|leaderboards?|rank(?:ing|ed)?|competitive rewards?|league points?)\b|\b(?:earn|gain|win|receive)\b.{0,40}\bpoints?\b/iu;

export const WORKOUT_BRIEFING_FALLBACK_SECTIONS: WorkoutBriefingSections = {
  todaySession:
    "Here is today's session as your plan wrote it — the breakdown above lists every step in order.",
  whyItHelps:
    "Every session in a beginner plan is there to build easy, repeatable running rather than one hard day.",
  howItFeels:
    "Keep the effort conversational: you should be able to speak in full sentences the whole way.",
  beforeYouStart:
    "Warm up gently, start slower than feels natural, and walk whenever you need to reset.",
};

export type WorkoutBriefingModelValidationIssue = "json_shape" | "policy_validation";
export type WorkoutBriefingModelValidationResult =
  | { readonly kind: "valid"; readonly sections: WorkoutBriefingSections }
  | { readonly kind: "invalid"; readonly issue: WorkoutBriefingModelValidationIssue };

export function validateWorkoutBriefingModelOutput(value: unknown): WorkoutBriefingSections | null {
  const result = validateWorkoutBriefingModelOutputDetailed(value);
  return result.kind === "valid" ? result.sections : null;
}

export function validateWorkoutBriefingModelOutputDetailed(
  value: unknown,
): WorkoutBriefingModelValidationResult {
  if (!isRecord(value) || !hasExactKeys(value, OUTPUT_KEYS)) {
    return { kind: "invalid", issue: "json_shape" };
  }
  const todaySession = value["todaySession"];
  const whyItHelps = value["whyItHelps"];
  const howItFeels = value["howItFeels"];
  const beforeYouStart = value["beforeYouStart"];
  if (
    typeof todaySession !== "string"
    || typeof whyItHelps !== "string"
    || typeof howItFeels !== "string"
    || typeof beforeYouStart !== "string"
  ) {
    return { kind: "invalid", issue: "json_shape" };
  }
  const sections = {
    todaySession: safeSection(todaySession),
    whyItHelps: safeSection(whyItHelps),
    howItFeels: safeSection(howItFeels),
    beforeYouStart: safeSection(beforeYouStart),
  };
  if (
    sections.todaySession === null
    || sections.whyItHelps === null
    || sections.howItFeels === null
    || sections.beforeYouStart === null
  ) {
    return { kind: "invalid", issue: "policy_validation" };
  }
  return {
    kind: "valid",
    sections: {
      todaySession: sections.todaySession,
      whyItHelps: sections.whyItHelps,
      howItFeels: sections.howItFeels,
      beforeYouStart: sections.beforeYouStart,
    },
  };
}

function safeSection(value: string): string | null {
  const normalized = value.replace(/\s+/gu, " ").trim();
  if (normalized.length === 0 || Array.from(normalized).length > MAX_SECTION_LENGTH) {
    return null;
  }
  if (
    URL.test(normalized)
    || MARKDOWN.test(normalized)
    || DIAGNOSIS.test(normalized)
    || SHAME.test(normalized)
    || COMPETITIVE_PROMISE.test(normalized)
  ) {
    return null;
  }
  return normalized;
}

function hasExactKeys(value: Readonly<Record<string, unknown>>, keys: ReadonlySet<string>): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.size && actual.every((key) => keys.has(key));
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
