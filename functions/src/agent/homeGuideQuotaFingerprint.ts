import { createHash } from "node:crypto";
import { activePlanMarker, type HomeGuideEvidence, type HomeGuidePlanDisplayContext } from "./homeGuideContracts.js";

const SINGAPORE_OFFSET_MILLIS = 8 * 60 * 60 * 1_000;
const FINGERPRINT_SCHEMA_VERSION = 1;
export const HOME_GUIDE_PROMPT_SCHEMA_VERSION = 2;
const EVIDENCE_ALGORITHM_VERSION = 1;

export type HomeGuideFingerprintInput = {
  readonly dayKey: string;
  readonly activePlanMarker: string;
  readonly planContext: HomeGuidePlanDisplayContext;
  readonly latestAcceptedActivityMarker: string;
  readonly evidence: HomeGuideEvidence;
};

export class HomeGuideFingerprintInputError extends Error {
  public constructor() {
    super("Home guide fingerprint requires a valid server time.");
    this.name = "HomeGuideFingerprintInputError";
  }
}

export function singaporeDayKey(now: Date): string {
  const millis = now.getTime();
  if (!Number.isFinite(millis)) throw new HomeGuideFingerprintInputError();
  return new Date(millis + SINGAPORE_OFFSET_MILLIS).toISOString().slice(0, 10);
}

export function createHomeGuideContextFingerprint(input: HomeGuideFingerprintInput): string {
  const canonical = JSON.stringify({
    fingerprintSchemaVersion: FINGERPRINT_SCHEMA_VERSION,
    promptSchemaVersion: HOME_GUIDE_PROMPT_SCHEMA_VERSION,
    evidenceAlgorithmVersion: EVIDENCE_ALGORITHM_VERSION,
    dayKey: input.dayKey,
    activePlanMarker: activePlanMarker(input.activePlanMarker),
    planContext: {
      planTitle: input.planContext.planTitle,
      weekNumber: input.planContext.weekNumber,
      weekFocus: input.planContext.weekFocus,
      dayLabel: input.planContext.dayLabel,
      workoutTitle: input.planContext.workoutTitle,
      durationMinutes: input.planContext.durationMinutes,
      intensity: input.planContext.intensity,
      description: input.planContext.description,
      steps: input.planContext.steps,
      supportiveNote: input.planContext.supportiveNote,
    },
    latestAcceptedActivityMarker: input.latestAcceptedActivityMarker,
    evidence: input.evidence.facts.map((fact) => ({
      id: fact.id,
      window: fact.window,
      metric: fact.metric,
      direction: fact.direction,
      text: fact.text,
    })),
  });
  return createHash("sha256").update(canonical, "utf8").digest("hex");
}
