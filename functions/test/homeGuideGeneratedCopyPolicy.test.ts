import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  generateHomeGuideBundle,
  type HomeGuideGenerationOutcome,
} from "../src/agent/homeGuideModel.js";
import { HOME_GUIDE_PROMPT_SCHEMA_VERSION } from "../src/agent/homeGuideQuotaFingerprint.js";
import {
  evidence,
  modelOutput,
  modelPlanContext,
  StubProvider,
} from "./homeGuideModelFixtures.js";

describe("home guide generated copy policy", () => {
  it("invalidates caches created before generated-copy preservation", () => {
    assert.equal(HOME_GUIDE_PROMPT_SCHEMA_VERSION, 2);
  });

  it("returns policy fallback when model copy would be replaced", async () => {
    // Given
    const provider = new StubProvider(
      modelOutput({
        planSummaryText: "Ask a doctor about distance progress.",
        runningTipText: "Run 20% faster today.",
      }),
    );

    // When
    const outcome = await generateHomeGuideBundle({
      provider,
      planContext: modelPlanContext(),
      evidence: evidence(),
    });

    // Then
    assert.equal(readGenerated(outcome).copyStatus, "replaced");
    assert.equal(provider.calls, 1);
  });

  it("preserves bounded model copy when composed text exceeds the bubble", async () => {
    // Given
    const provider = new StubProvider(
      modelOutput({ runningTipText: "b".repeat(128) }),
    );

    // When
    const outcome = await generateHomeGuideBundle({
      provider,
      planContext: modelPlanContext(),
      evidence: evidence(),
    });

    // Then
    const generated = readGenerated(outcome);
    assert.equal(generated.copyStatus, "preserved");
    assert.match(generated.bundle.runningTip, /b{8}/u);
    assert.ok(Array.from(generated.bundle.runningTip).length <= 160);
  });

  it("returns policy fallback when generated summary repeats fallback copy", async () => {
    // Given
    const provider = new StubProvider(
      modelOutput({ planSummaryText: "Your plan is ready." }),
    );

    // When
    const outcome = await generateHomeGuideBundle({
      provider,
      planContext: modelPlanContext(),
      evidence: evidence(),
    });

    // Then
    assert.equal(readGenerated(outcome).copyStatus, "replaced");
  });
});

function readGenerated(
  outcome: HomeGuideGenerationOutcome,
): Extract<HomeGuideGenerationOutcome, { readonly kind: "generated" }> {
  if (outcome.kind !== "generated") {
    assert.fail(`Expected generated outcome, received ${outcome.kind}.`);
  }
  return outcome;
}
