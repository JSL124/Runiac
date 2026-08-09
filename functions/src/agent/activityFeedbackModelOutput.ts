import type { ActivityFeedbackSections } from "./activityFeedbackTypes.js";

const OUTPUT_KEYS = new Set(["summary", "wentWell", "improve", "nextFocus"]);
const MAX_SECTION_LENGTH = 320;
const URL = /(?:https?:\/\/|www\.)/iu;
const MARKDOWN = /(?:^|\s)(?:#{1,6}\s|[-*+]\s|>\s)|[*_`~\[\]]/u;
const DIAGNOSIS = /\b(?:diagnos(?:is|e|ed|ing)|medical|doctor|medication|treatment|disease|injur(?:y|ed)|pain)\b/iu;
const SHAME = /\b(?:shame|ashamed|lazy|weak|pathetic|failure|embarrass(?:ed|ing)?|disappoint(?:ed|ing)?|unfit|bad runner|not trying)\b/iu;
const COMPETITIVE_PROMISE = /\b(?:xp|experience points?|leaderboards?|rank(?:ing|ed)?|competitive rewards?|league points?)\b|\b(?:earn|gain|win|receive)\b.{0,40}\bpoints?\b/iu;

export const ACTIVITY_FEEDBACK_FALLBACK_SECTIONS: ActivityFeedbackSections = {
  summary: "Your run summary is ready, but personalised feedback is temporarily unavailable.",
  wentWell: "You completed the run and captured useful derived metrics.",
  improve: "Keep the next effort comfortable and notice what feels repeatable.",
  nextFocus: "Aim for one calm, steady session when you feel ready.",
};

export type ActivityFeedbackModelValidationIssue = "json_shape" | "policy_validation";
export type ActivityFeedbackModelValidationResult =
  | { readonly kind: "valid"; readonly sections: ActivityFeedbackSections }
  | { readonly kind: "invalid"; readonly issue: ActivityFeedbackModelValidationIssue };

export function validateActivityFeedbackModelOutput(value: unknown): ActivityFeedbackSections | null {
  const result = validateActivityFeedbackModelOutputDetailed(value);
  return result.kind === "valid" ? result.sections : null;
}

export function validateActivityFeedbackModelOutputDetailed(value: unknown): ActivityFeedbackModelValidationResult {
  if (!isRecord(value) || !hasExactKeys(value, OUTPUT_KEYS)) {
    return { kind: "invalid", issue: "json_shape" };
  }
  const summary = value["summary"];
  const wentWell = value["wentWell"];
  const improve = value["improve"];
  const nextFocus = value["nextFocus"];
  if (
    typeof summary !== "string"
    || typeof wentWell !== "string"
    || typeof improve !== "string"
    || typeof nextFocus !== "string"
  ) {
    return { kind: "invalid", issue: "json_shape" };
  }
  const sections = {
    summary: safeSection(summary),
    wentWell: safeSection(wentWell),
    improve: safeSection(improve),
    nextFocus: safeSection(nextFocus),
  };
  if (
    sections.summary === null
    || sections.wentWell === null
    || sections.improve === null
    || sections.nextFocus === null
  ) {
    return { kind: "invalid", issue: "policy_validation" };
  }
  return {
    kind: "valid",
    sections: {
      summary: sections.summary,
      wentWell: sections.wentWell,
      improve: sections.improve,
      nextFocus: sections.nextFocus,
    },
  };
}

function safeSection(value: string): string | null {
  if (
    URL.test(value)
    || MARKDOWN.test(value)
    || DIAGNOSIS.test(value)
    || SHAME.test(value)
    || COMPETITIVE_PROMISE.test(value)
  ) {
    return null;
  }
  const normalized = value.replace(/\s+/gu, " ").trim();
  return normalized.length > 0 && Array.from(normalized).length <= MAX_SECTION_LENGTH
    ? normalized
    : null;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Readonly<Record<string, unknown>>, keys: ReadonlySet<string>): boolean {
  return Object.keys(value).length === keys.size && Object.keys(value).every((key) => keys.has(key));
}
