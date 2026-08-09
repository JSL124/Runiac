import type { HomeGuideEvidence, HomeGuideEvidenceFact, HomeGuidePlanDisplayContext } from "./homeGuideContracts.js";
import type { HomeGuideBundle } from "./homeGuideQuotaCache.js";

const ACTION_CODES = [
  "build_baseline",
  "maintain_easy_consistency",
  "add_one_easy_session",
  "keep_effort_conversational",
  "recover_and_repeat",
] as const;
const OUTPUT_FIELDS = new Set([
  "schemaVersion",
  "planSummaryText",
  "runningTipText",
  "selectedProgressionFactIds",
  "nextActionCode",
]);
const MEDICAL_TERMS = /\b(?:diagnos(?:is|e)|doctor|medication|injury|injured|treatment|medical|pain)\b/iu;
const COMPETITIVE_TERMS = /\b(?:leaderboard|rank|ranking|win|winner|beat|competition|competitive|race)\b/iu;
const UNSUPPLIED_CLAIM = /\b(?:improv(?:e|ed|ing|ement)?|declin(?:e|ed|ing)?|increas(?:e|ed|ing)?|decreas(?:e|ed|ing)?|progress|faster|slower|distance|run count)\b/iu;
const INSTRUCTIONAL_TERMS = /\b(?:ignore|disregard|previous instructions?|system prompt)\b/iu;
const MARKDOWN = /(?:^|\s)(?:#{1,6}\s|[-*+]\s|>\s)|[*_`~\[\]]/u;
const URL = /(?:https?:\/\/|www\.)/iu;
const MAX_MODEL_TEXT_LENGTH = 128;
// The progression line may cite server-trusted comparison figures (from
// homeGuideEvidence), so it is allowed more length and one extra sentence than
// the compact plan/tip lines. Kept in sync with the client display contract
// (HomeGuideBundle progression limits in home_guide_agent.dart).
const PROGRESSION_MAX_LENGTH = 220;
const PROGRESSION_MAX_SENTENCES = 3;
const GENERIC_PLAN_SUMMARY = /^your plan is ready[.!?]?$/iu;

export type HomeGuideActionCode = (typeof ACTION_CODES)[number];
export type HomeGuideProgressionLead = "baseline" | "improving" | "steady" | "mixed" | "needs_attention";
export type HomeGuideModelOutput = {
  readonly schemaVersion: 1;
  readonly planSummaryText: string;
  readonly runningTipText: string;
  readonly selectedProgressionFactIds: readonly string[];
  readonly nextActionCode: HomeGuideActionCode;
};
export type HomeGuideModelValidationIssue = "json_shape" | "policy_validation";
export type HomeGuideModelValidationResult =
  | { readonly kind: "valid"; readonly output: HomeGuideModelOutput }
  | { readonly kind: "invalid"; readonly issue: HomeGuideModelValidationIssue };
export type HomeGuideModelCopyStatus = "preserved" | "replaced";
export type HomeGuideModelValidationInput = {
  readonly output: unknown;
  readonly evidence: HomeGuideEvidence;
};
export type HomeGuideRenderInput = {
  readonly output: HomeGuideModelOutput | null;
  readonly evidence: HomeGuideEvidence;
  readonly planContext?: HomeGuidePlanDisplayContext;
};

class HomeGuideUnreachableVariantError extends Error {
  public constructor() {
    super("Home guide encountered an unhandled variant.");
    this.name = "HomeGuideUnreachableVariantError";
  }
}

export function assertNever(value: never): never {
  void value;
  throw new HomeGuideUnreachableVariantError();
}

export function validateHomeGuideModelOutput(input: HomeGuideModelValidationInput): HomeGuideModelOutput | null {
  const result = validateHomeGuideModelOutputDetailed(input);
  switch (result.kind) {
    case "valid": return result.output;
    case "invalid": return null;
    default: return assertNever(result);
  }
}

export function validateHomeGuideModelOutputDetailed(input: HomeGuideModelValidationInput): HomeGuideModelValidationResult {
  if (!isRecord(input.output) || !hasExactKeys(input.output, OUTPUT_FIELDS)) return { kind: "invalid", issue: "json_shape" };
  const schemaVersion = input.output["schemaVersion"];
  const planSummaryText = input.output["planSummaryText"];
  const runningTipText = input.output["runningTipText"];
  const selectedProgressionFactIds = input.output["selectedProgressionFactIds"];
  const nextActionCode = input.output["nextActionCode"];
  if (
    schemaVersion !== 1 ||
    !isActionCode(nextActionCode) ||
    typeof planSummaryText !== "string" ||
    typeof runningTipText !== "string" ||
    !isSelectedFactIdArray(selectedProgressionFactIds)
  ) return { kind: "invalid", issue: "json_shape" };
  return {
    kind: "valid",
    output: {
      schemaVersion,
      planSummaryText,
      runningTipText,
      selectedProgressionFactIds: allowedSelectedFactIds(selectedProgressionFactIds, input.evidence),
      nextActionCode,
    },
  };
}

export function deriveHomeGuideProgressionLead(facts: readonly HomeGuideEvidenceFact[]): HomeGuideProgressionLead {
  if (facts.length === 0) return "baseline";
  const hasImproving = facts.some((fact) => fact.direction === "improving");
  const hasDeclining = facts.some((fact) => fact.direction === "declining");
  if (hasImproving && hasDeclining) return "mixed";
  if (hasImproving) return "improving";
  if (hasDeclining) return "needs_attention";
  return "steady";
}

export function renderHomeGuideBundle(input: HomeGuideRenderInput): HomeGuideBundle | null {
  if (input.output === null) return null;
  const facts = selectedFacts(input.output.selectedProgressionFactIds, input.evidence.facts);
  const lead = deriveHomeGuideProgressionLead(facts);
  const action = coherentAction(lead, input.output.nextActionCode);
  const bundle = {
    planSummary: safeFinalMessage(
      renderPlanSummary(input.output.planSummaryText, input.planContext),
      "Your plan is ready. Let's keep today comfy and doable.",
    ),
    runningTip: safeFinalMessage(
      renderRunningTip(input.output.runningTipText, input.planContext),
      "Tiny trainer tip: Start gently and keep effort smooth.",
    ),
    progressionCheckIn: safeProgressionMessage(
      renderProgression(facts, action),
      actionSentence(action),
    ),
  };
  return bundle;
}

export function homeGuideModelCopyStatus(
  input: HomeGuideRenderInput,
): HomeGuideModelCopyStatus {
  if (input.output === null) return "replaced";
  const { planSummaryText, runningTipText } = input.output;
  if (
    !isSafeModelText(planSummaryText)
    || !isSafeModelText(runningTipText)
    || GENERIC_PLAN_SUMMARY.test(planSummaryText.trim())
  ) return "replaced";
  return isSafeFinalMessage(renderPlanSummary(planSummaryText, input.planContext))
    && isSafeFinalMessage(renderRunningTip(runningTipText, input.planContext))
    ? "preserved"
    : "replaced";
}

// The plan bubble is a single, self-contained beginner-friendly walkthrough of
// today's session. It intentionally does NOT append the model's free-text
// encouragement: that generic cheer reads as a disconnected leftover line glued
// onto the plan explanation. The model's warmth still lives in the running-tip
// and progression bubbles.
function renderPlanSummary(_text: string, planContext: HomeGuidePlanDisplayContext | undefined): string {
  if (planContext === undefined) return "Your plan is ready, superstar!";
  return planElaborationSentence(planContext);
}

// Beginner-friendly one-sentence walkthrough of today's session, composed only
// from already-rendered plan display fields (never a backend-owned value) so a
// first-time runner learns what the plan actually is instead of just that it is
// "ready". The workout title is kept verbatim (only length-compacted) so a
// punctuation-heavy title still trips the final sentence-count safety gate and
// falls back, matching the compact-bubble contract.
function planElaborationSentence(planContext: HomeGuidePlanDisplayContext): string {
  const withFocus = composePlanElaboration(planContext, true);
  // Prefer the fuller sentence, but never surface a mid-phrase ellipsis: if the
  // focus clause pushes the line past the compact bubble, drop the clause whole
  // rather than truncating the week focus into "... .".
  return isSafeFinalMessage(withFocus) ? withFocus : composePlanElaboration(planContext, false);
}

function composePlanElaboration(planContext: HomeGuidePlanDisplayContext, includeFocus: boolean): string {
  const title = compactText(planContext.workoutTitle, 40);
  const effort = planEffortWord(planContext.intensity);
  const focus = includeFocus ? planFocusClause(planContext.weekFocus) : "";
  return `Today's ${title} is a ${effort} ${planContext.durationMinutes}-minute session${focus}.`;
}

function planEffortWord(intensity: string): string {
  const normalized = intensity.toLocaleLowerCase("en-SG");
  if (/\b(?:easy|recovery|rest|gentle|light)\b/u.test(normalized)) return "gentle";
  if (/\b(?:tempo|interval|hard|speed|hill)\b/u.test(normalized)) return "focused";
  return "steady";
}

// Keeps the week focus verbatim (only whitespace-normalized). Length is handled
// by the caller dropping the whole clause, so this never emits a truncating
// ellipsis mid-phrase.
function planFocusClause(weekFocus: string): string {
  const focus = weekFocus.replace(/\s+/gu, " ").trim();
  if (focus.length === 0) return "";
  const lead = focus.charAt(0).toLocaleLowerCase("en-SG") + focus.slice(1);
  return ` to ${lead}`;
}

function renderRunningTip(text: string, planContext: HomeGuidePlanDisplayContext | undefined): string {
  const safeText = isSafeModelText(text) ? text : "";
  if (planContext === undefined) return `Tiny trainer tip:${safeText.length === 0 ? "" : ` ${safeText}`}`;
  const prefix = `Tiny trainer tip: ${intensityCue(planContext.intensity)}`;
  if (safeText.length === 0) return prefix;
  const availableCharacters = 160 - codePointLength(prefix) - 1;
  return `${prefix} ${compactText(safeText, availableCharacters)}`;
}

function intensityCue(intensity: string): string {
  const normalized = intensity.toLocaleLowerCase("en-SG");
  if (/\b(?:easy|recovery|rest|gentle|light)\b/u.test(normalized)) return "Keep a chatty, relaxed effort.";
  if (/\b(?:tempo|interval|hard|speed|hill)\b/u.test(normalized)) return "Warm up, then stay controlled.";
  return "Start gently and keep effort smooth.";
}

// Beginner-friendly, number-free reading of the selected trusted evidence. It
// speaks to the direction of change (trending up, easing off, holding steady)
// in warm words instead of surfacing the raw comparison figures, which read as
// cold data to a first-time runner. The action clause still comes from the
// coherent next step.
function renderProgression(
  facts: readonly HomeGuideEvidenceFact[],
  action: HomeGuideActionCode,
): string {
  const actionText = actionSentence(action);
  if (facts.length === 0) {
    return `You are building a running baseline, and every easy session counts. ${actionText}`;
  }
  const message = `${progressionSummary(facts)} ${actionText}`;
  return isSafeProgressionMessage(message) ? message : actionText;
}

function progressionSummary(facts: readonly HomeGuideEvidenceFact[]): string {
  const phrases: string[] = [];
  for (const fact of facts) {
    const phrase = progressionPhrase(fact.metric, fact.direction);
    if (!phrases.includes(phrase)) phrases.push(phrase);
  }
  const [first, second] = phrases;
  const joined = first === undefined
    ? "keeping your running going"
    : second === undefined
      ? first
      : `${first} and ${second}`;
  const comparison = progressionComparison(facts);
  return comparison === null
    ? `Lately you've been ${joined}.`
    : `You've been ${joined} ${comparison}.`;
}

// A qualitative "compared with" label, but only when every selected fact shares
// the same window so the timeframe stays accurate; mixed windows fall back to a
// neutral "lately" (handled by the caller returning null here).
function progressionComparison(facts: readonly HomeGuideEvidenceFact[]): string | null {
  const first = facts[0];
  if (first === undefined) return null;
  const windows = new Set(facts.map((fact) => fact.window));
  if (windows.size !== 1) return null;
  return first.window === "week_to_date" ? "compared with last week" : "compared with the past month";
}

function progressionPhrase(
  metric: HomeGuideEvidenceFact["metric"],
  direction: HomeGuideEvidenceFact["direction"],
): string {
  switch (metric) {
    case "run_count":
      return direction === "improving"
        ? "running more often"
        : direction === "declining"
          ? "running a little less often"
          : "running just as regularly";
    case "distance":
      return direction === "improving"
        ? "covering more ground"
        : direction === "declining"
          ? "covering a bit less ground"
          : "covering steady ground";
    case "active_duration":
      return direction === "improving"
        ? "spending more time on your feet"
        : direction === "declining"
          ? "easing back your time on your feet"
          : "keeping steady time on your feet";
    case "weighted_pace":
      return direction === "improving"
        ? "settling into a smoother pace"
        : direction === "declining"
          ? "taking your pace a touch easier"
          : "holding a steady pace";
    default:
      return assertNever(metric);
  }
}

function actionSentence(action: HomeGuideActionCode): string {
  switch (action) {
    case "build_baseline": return "You've got this; one comfy session at a time is plenty.";
    case "maintain_easy_consistency": return "You've got this; keep your easy sessions gentle and steady.";
    case "add_one_easy_session": return "You've got this; add one easy session only when you feel ready.";
    case "keep_effort_conversational": return "You've got this; keep the effort conversational and enjoy the rhythm.";
    case "recover_and_repeat": return "You've got this; rest kindly, then repeat an easy session when ready.";
    default: return assertNever(action);
  }
}

function selectedFacts(ids: readonly string[], facts: readonly HomeGuideEvidenceFact[]): readonly HomeGuideEvidenceFact[] {
  return ids.flatMap((id) => facts.filter((fact) => fact.id === id));
}

function isCoherentAction(lead: HomeGuideProgressionLead, action: HomeGuideActionCode): boolean {
  switch (lead) {
    case "baseline": return action === "build_baseline" || action === "keep_effort_conversational";
    case "improving": return action === "maintain_easy_consistency" || action === "keep_effort_conversational";
    case "steady": return action === "add_one_easy_session" || action === "maintain_easy_consistency";
    case "mixed":
    case "needs_attention": return action === "recover_and_repeat" || action === "keep_effort_conversational";
    default: return assertNever(lead);
  }
}

function coherentAction(lead: HomeGuideProgressionLead, action: HomeGuideActionCode): HomeGuideActionCode {
  if (isCoherentAction(lead, action)) return action;
  switch (lead) {
    case "baseline": return "keep_effort_conversational";
    case "improving": return "maintain_easy_consistency";
    case "steady": return "maintain_easy_consistency";
    case "mixed":
    case "needs_attention": return "recover_and_repeat";
    default: return assertNever(lead);
  }
}

function isSelectedFactIdArray(value: unknown): value is readonly string[] {
  return Array.isArray(value) && value.length <= 2 && value.every((id) => typeof id === "string");
}

function allowedSelectedFactIds(value: readonly string[], evidence: HomeGuideEvidence): readonly string[] {
  const allowedIds = new Set(evidence.facts.map((fact) => fact.id));
  const result: string[] = [];
  for (const id of value) {
    if (allowedIds.has(id) && !result.includes(id)) result.push(id);
    if (result.length === 2) return result;
  }
  return result;
}

function isSafeModelText(value: unknown): value is string {
  return typeof value === "string" &&
    value.trim().length > 0 &&
    codePointLength(value) <= MAX_MODEL_TEXT_LENGTH &&
    sentenceCount(value) <= 2 &&
    !/[\r\n%\p{N}]/u.test(value) &&
    !MARKDOWN.test(value) &&
    !URL.test(value) &&
    !MEDICAL_TERMS.test(value) &&
    !COMPETITIVE_TERMS.test(value) &&
    !INSTRUCTIONAL_TERMS.test(value) &&
    !UNSUPPLIED_CLAIM.test(value);
}

function isSafeFinalMessage(value: string): boolean {
  return value.trim().length > 0 && codePointLength(value) <= 160 && sentenceCount(value) <= 2;
}

function safeFinalMessage(value: string, fallback: string): string {
  return isSafeFinalMessage(value) ? value : fallback;
}

// Progression copy is rendered only from server-trusted evidence facts, so it
// may carry comparison figures and a "what to improve" clause. It uses looser
// length/sentence bounds than the plain plan/tip lines.
function isSafeProgressionMessage(value: string): boolean {
  return (
    value.trim().length > 0 &&
    codePointLength(value) <= PROGRESSION_MAX_LENGTH &&
    sentenceCount(value) <= PROGRESSION_MAX_SENTENCES
  );
}

function safeProgressionMessage(value: string, fallback: string): string {
  return isSafeProgressionMessage(value) ? value : fallback;
}

function sentenceCount(value: string): number {
  const punctuation = value.match(/(?:[!?]+|\.(?=\s|$))/gu)?.length ?? 0;
  return punctuation === 0 ? 1 : punctuation;
}

function codePointLength(value: string): number {
  return Array.from(value).length;
}

function compactText(value: string, maximumLength: number): string {
  const characters = Array.from(value);
  return characters.length <= maximumLength ? value : `${characters.slice(0, maximumLength - 3).join("")}...`;
}

function isActionCode(value: unknown): value is HomeGuideActionCode {
  return typeof value === "string" && ACTION_CODES.some((code) => code === value);
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Readonly<Record<string, unknown>>, keys: ReadonlySet<string>): boolean {
  return Object.keys(value).length === keys.size && Object.keys(value).every((key) => keys.has(key));
}
