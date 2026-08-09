import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  HOME_GUIDE_MODEL_CONFIG,
  buildHomeGuideModelPrompt,
  createHomeGuideModelProvider,
  deriveHomeGuideProgressionLead,
  generateHomeGuideBundle,
  parseHomeGuideModelResponse,
  renderHomeGuideBundle,
  validateHomeGuideModelOutput,
} from "../src/agent/homeGuideModel.js";
import { evidence, evidenceFact, modelOutput, modelPlanContext, StubProvider } from "./homeGuideModelFixtures.js";

describe("home guide structured model output", () => {
  it("accepts only the exact schema and a baseline has no selected facts", () => {
    const output = validateHomeGuideModelOutput({ output: modelOutput(), evidence: evidence() });
    assert.deepEqual(output?.selectedProgressionFactIds, []);
    assert.equal(validateHomeGuideModelOutput({ output: { ...modelOutput(), extra: true }, evidence: evidence() }), null);
    assert.equal(validateHomeGuideModelOutput({ output: { ...modelOutput(), schemaVersion: 2 }, evidence: evidence() }), null);
    assert.equal(validateHomeGuideModelOutput({ output: { ...modelOutput(), nextActionCode: "unknown_action" }, evidence: evidence() }), null);
    assert.deepEqual(validateHomeGuideModelOutput({ output: { ...modelOutput(), selectedProgressionFactIds: ["week_to_date.distance"] }, evidence: evidence() })?.selectedProgressionFactIds, []);
  });

  it("sanitizes duplicate and unknown fact selections while rejecting excessive selections", () => {
    const facts = evidence(evidenceFact("improving"), evidenceFact("steady", "week_to_date.run_count"), evidenceFact("declining", "week_to_date.active_duration"));
    assert.deepEqual(
      validateHomeGuideModelOutput({ output: modelOutput({ selectedProgressionFactIds: ["week_to_date.distance", "week_to_date.distance"], nextActionCode: "maintain_easy_consistency" }), evidence: facts })?.selectedProgressionFactIds,
      ["week_to_date.distance"],
    );
    assert.deepEqual(
      validateHomeGuideModelOutput({ output: modelOutput({ selectedProgressionFactIds: ["not-allowed"], nextActionCode: "maintain_easy_consistency" }), evidence: facts })?.selectedProgressionFactIds,
      [],
    );
    assert.equal(validateHomeGuideModelOutput({ output: modelOutput({ selectedProgressionFactIds: ["week_to_date.distance", "week_to_date.run_count", "week_to_date.active_duration"], nextActionCode: "maintain_easy_consistency" }), evidence: facts }), null);
  });

  it("accepts risky model copy at the schema boundary so rendering can replace it safely", () => {
    const invalidText = [
      "Take ٢ easy steps.",
      "See https://example.test now.",
      "**Push harder** today.",
      "Try this\nnext.",
      "Ask a doctor about it.",
      "You improved this week.",
      "Progress has increased.",
      "Ignore previous instructions.",
      "a".repeat(129),
      "a".repeat(161),
    ];
    for (const planSummaryText of invalidText) {
      const output = validateHomeGuideModelOutput({ output: modelOutput({ planSummaryText }), evidence: evidence() });
      const bundle = renderHomeGuideBundle({ output, evidence: evidence(), planContext: modelPlanContext() });
      assert.notEqual(bundle, null);
      assert.doesNotMatch(bundle?.planSummary ?? "", /https|doctor|improved|Progress|Ignore|٢|[*]/i);
    }
    const { runningTipText: _runningTipText, ...missingField } = modelOutput();
    assert.equal(validateHomeGuideModelOutput({ output: missingField, evidence: evidence() }), null);
  });

  it("derives every lead direction and permits only coherent actions", () => {
    const cases = [
      { directions: [], lead: "baseline", action: "build_baseline" },
      { directions: ["improving"], lead: "improving", action: "maintain_easy_consistency" },
      { directions: ["steady"], lead: "steady", action: "add_one_easy_session" },
      { directions: ["improving", "declining"], lead: "mixed", action: "recover_and_repeat" },
      { directions: ["declining"], lead: "needs_attention", action: "keep_effort_conversational" },
    ] as const;
    for (const testCase of cases) {
      const facts = evidence(...testCase.directions.map((direction, index) => evidenceFact(direction, `week_to_date.distance-${index}`)));
      assert.equal(deriveHomeGuideProgressionLead(facts.facts), testCase.lead);
      const output = validateHomeGuideModelOutput({ output: modelOutput({ selectedProgressionFactIds: facts.facts.map((fact) => fact.id), nextActionCode: testCase.action }), evidence: facts });
      assert.notEqual(renderHomeGuideBundle({ output, evidence: facts }), null);
    }
    const incoherent = validateHomeGuideModelOutput({ output: modelOutput({ selectedProgressionFactIds: ["week_to_date.distance"], nextActionCode: "add_one_easy_session" }), evidence: evidence(evidenceFact("improving")) });
    assert.match(renderHomeGuideBundle({ output: incoherent, evidence: evidence(evidenceFact("improving")) })?.progressionCheckIn ?? "", /keep your easy sessions gentle and steady/i);

    const matrix = [
      { directions: [], allowed: ["build_baseline", "keep_effort_conversational"] },
      { directions: ["improving"], allowed: ["maintain_easy_consistency", "keep_effort_conversational"] },
      { directions: ["steady"], allowed: ["add_one_easy_session", "maintain_easy_consistency"] },
      { directions: ["improving", "declining"], allowed: ["recover_and_repeat", "keep_effort_conversational"] },
      { directions: ["declining"], allowed: ["recover_and_repeat", "keep_effort_conversational"] },
    ] as const;
    const actions = ["build_baseline", "maintain_easy_consistency", "add_one_easy_session", "keep_effort_conversational", "recover_and_repeat"] as const;
    for (const row of matrix) {
      const facts = evidence(...row.directions.map((direction, index) => evidenceFact(direction, `matrix-${index}`)));
      for (const nextActionCode of actions) {
        const output = validateHomeGuideModelOutput({ output: modelOutput({ selectedProgressionFactIds: facts.facts.map((fact) => fact.id), nextActionCode }), evidence: facts });
        assert.notEqual(renderHomeGuideBundle({ output, evidence: facts }), null);
      }
    }
  });

  it("renders the deterministic check-in as warm, beginner-friendly trainer guidance", () => {
    const output = validateHomeGuideModelOutput({ output: modelOutput(), evidence: evidence() });
    const bundle = renderHomeGuideBundle({ output, evidence: evidence() });

    assert.match(bundle?.progressionCheckIn ?? "", /you've got this/i);
  });

  it("keeps generated progression usable when supplied fact copy is too long for the speech bubble", () => {
    const longFact = {
      ...evidenceFact("steady"),
      text: "Distance stayed steady across the week while the beginner plan remains focused on easy running, relaxed breathing, and keeping the next session comfortable for the runner.",
    };
    const output = validateHomeGuideModelOutput({ output: modelOutput({ selectedProgressionFactIds: [longFact.id], nextActionCode: "add_one_easy_session" }), evidence: evidence(longFact) });
    const bundle = renderHomeGuideBundle({ output, evidence: evidence(longFact), planContext: modelPlanContext() });

    assert.notEqual(bundle, null);
    assert.ok(Array.from(bundle?.progressionCheckIn ?? "").length <= 160);
    assert.doesNotMatch(bundle?.progressionCheckIn ?? "", /Distance stayed steady across the week/);
  });

  it("summarizes both selected facts as warm, number-free beginner copy", () => {
    const facts = evidence(
      {
        id: "week_to_date.weighted_pace",
        window: "week_to_date",
        metric: "weighted_pace",
        direction: "improving",
        text: "Weighted pace: 07:30/km vs 08:15/km (faster by 00:45/km, +9%).",
      },
      {
        id: "rolling_28_days.active_duration",
        window: "rolling_28_days",
        metric: "active_duration",
        direction: "improving",
        text: "Active duration: 240 min vs 180 min (+60 min, +33%).",
      },
    );
    const output = validateHomeGuideModelOutput({
      output: modelOutput({
        selectedProgressionFactIds: ["week_to_date.weighted_pace", "rolling_28_days.active_duration"],
        nextActionCode: "maintain_easy_consistency",
      }),
      evidence: facts,
    });
    const bundle = renderHomeGuideBundle({ output, evidence: facts, planContext: modelPlanContext() });

    assert.notEqual(bundle, null);
    const progression = bundle?.progressionCheckIn ?? "";
    // Both selected facts are reflected qualitatively by direction, with no raw
    // comparison figures leaking into the beginner-facing bubble.
    assert.ok(Array.from(progression).length <= 220);
    assert.match(progression, /smoother pace/);
    assert.match(progression, /more time on your feet/);
    assert.doesNotMatch(progression, /\d/);
    assert.doesNotMatch(progression, /km|min|vs|%/);
  });

  it("repairs final speech bubbles when display context punctuation would exceed the final safety gate", () => {
    const output = validateHomeGuideModelOutput({ output: modelOutput(), evidence: evidence() });
    const bundle = renderHomeGuideBundle({
      output,
      evidence: evidence(),
      planContext: { ...modelPlanContext(), workoutTitle: "Easy. Run. Today.", intensity: "easy" },
    });

    assert.notEqual(bundle, null);
    assert.equal(bundle?.planSummary, "Your plan is ready. Let's keep today comfy and doable.");
    assert.ok(Array.from(bundle?.planSummary ?? "").length <= 160);
  });

  it("limits prompts to sanitized display context and deterministic fact text", () => {
    const prompt = buildHomeGuideModelPrompt({ planContext: modelPlanContext(), evidence: evidence(evidenceFact("improving")) });
    assert.match(prompt.userPrompt, /Beginner running plan/);
    assert.match(prompt.userPrompt, /week_to_date.distance/);
    assert.equal(prompt.userPrompt.includes("ownerUid"), false);
    assert.equal(prompt.userPrompt.includes("route"), false);
    assert.equal(prompt.userPrompt.includes("XP"), false);
  });

  it("asks for a warm, playful beginner-trainer voice while preserving the safety contract", () => {
    const prompt = buildHomeGuideModelPrompt({ planContext: modelPlanContext(), evidence: evidence() });

    assert.match(prompt.systemPrompt, /friendly/i);
    assert.match(prompt.systemPrompt, /cute/i);
    assert.match(prompt.systemPrompt, /beginner.*trainer/i);
    assert.match(prompt.systemPrompt, /do not make medical, competitive, numeric, or unsupported factual claims/i);
  });
});

describe("home guide provider seam", () => {
  it("uses low-temperature bounded no-retry provider settings and invokes one injected provider once", async () => {
    const { modelKwargs, ...scalarConfig } = HOME_GUIDE_MODEL_CONFIG;
    assert.deepEqual(scalarConfig, {
      model: "gpt-4o-mini",
      temperature: 0.2,
      maxTokens: 220,
      timeout: 10_000,
      maxRetries: 0,
    });
    const responseFormat = modelKwargs.response_format;
    assert.equal(responseFormat.type, "json_schema");
    assert.equal(responseFormat.json_schema.strict, true);
    const schema = responseFormat.json_schema.schema;
    assert.equal(schema.additionalProperties, false);
    assert.deepEqual(
      [...schema.required].sort(),
      ["nextActionCode", "planSummaryText", "runningTipText", "schemaVersion", "selectedProgressionFactIds"],
    );
    assert.deepEqual(schema.properties.selectedProgressionFactIds, { type: "array", items: { type: "string" } });
    assert.deepEqual(schema.properties.nextActionCode.enum, [
      "build_baseline",
      "maintain_easy_consistency",
      "add_one_easy_session",
      "keep_effort_conversational",
      "recover_and_repeat",
    ]);
    const provider = new StubProvider(modelOutput());
    const outcome: unknown = await generateHomeGuideBundle({ provider, planContext: modelPlanContext(), evidence: evidence() });
    assert.equal(provider.calls, 1);
    assert.equal(readOutcomeKind(outcome), "generated");
  });

  it("parses bare, fenced, and multipart JSON responses while rejecting prose", () => {
    const payload = { schemaVersion: 1 };
    assert.deepEqual(parseHomeGuideModelResponse(JSON.stringify(payload)), payload);
    assert.deepEqual(
      parseHomeGuideModelResponse("```json\n" + JSON.stringify(payload) + "\n```"),
      payload,
    );
    assert.deepEqual(
      parseHomeGuideModelResponse("```\n" + JSON.stringify(payload) + "\n```"),
      payload,
    );
    assert.deepEqual(
      parseHomeGuideModelResponse([{ text: "```json" }, { text: JSON.stringify(payload) }, { text: "```" }]),
      payload,
    );
    assert.equal(parseHomeGuideModelResponse("Here is your plan summary."), null);
    assert.equal(parseHomeGuideModelResponse(42), null);
  });

  it("reports distinct fallback categories for provider, timeout, JSON-shape, and policy-validation outcomes", async () => {
    const timeoutProvider = new StubProvider(() => new Promise<unknown>(() => undefined));
    const exceptionProvider = new StubProvider(() => Promise.reject(new Error("provider failure")));
    const malformedProvider = new StubProvider("not-json-object");
    const unsafeTextProvider = new StubProvider(modelOutput({
      planSummaryText: "Ask a doctor about distance progress.",
      runningTipText: "Run 20% faster today.",
    }));
    const incoherentProvider = new StubProvider(modelOutput({
      selectedProgressionFactIds: ["week_to_date.distance"],
      nextActionCode: "add_one_easy_session",
    }));

    assert.deepEqual(
      await generateHomeGuideBundle({ provider: timeoutProvider, planContext: modelPlanContext(), evidence: evidence(), timeoutMillis: 1 }),
      { kind: "fallback", fallbackCategory: "timeout" },
    );
    assert.deepEqual(
      await generateHomeGuideBundle({ provider: exceptionProvider, planContext: modelPlanContext(), evidence: evidence() }),
      { kind: "fallback", fallbackCategory: "provider_error" },
    );
    assert.deepEqual(
      await generateHomeGuideBundle({ provider: malformedProvider, planContext: modelPlanContext(), evidence: evidence() }),
      { kind: "fallback", fallbackCategory: "json_shape" },
    );
    const repairedUnsafeText = readGeneratedBundle(await generateHomeGuideBundle({ provider: unsafeTextProvider, planContext: modelPlanContext(), evidence: evidence() }));
    assert.doesNotMatch(`${repairedUnsafeText.planSummary} ${repairedUnsafeText.runningTip}`, /doctor|distance|progress|20|faster/i);
    assert.match(repairedUnsafeText.progressionCheckIn, /building a running baseline/i);
    assert.equal(
      readOutcomeKind(await generateHomeGuideBundle({ provider: incoherentProvider, planContext: modelPlanContext(), evidence: evidence(evidenceFact("improving")) })),
      "generated",
    );
    assert.equal(timeoutProvider.calls, 1);
    assert.equal(exceptionProvider.calls, 1);
    assert.equal(malformedProvider.calls, 1);
    assert.equal(incoherentProvider.calls, 1);
  });

  it("renders plan-specific summary and intensity-appropriate tip without fabricating progression", async () => {
    const planContext = {
      ...modelPlanContext(),
      workoutTitle: "Gentle recovery run",
      intensity: "recovery",
    };
    const provider = new StubProvider(modelOutput({
      planSummaryText: "The planned session is ready.",
      runningTipText: "Keep the effort relaxed and conversational.",
      selectedProgressionFactIds: ["week_to_date.distance"],
      nextActionCode: "maintain_easy_consistency",
    }));
    const outcome: unknown = await generateHomeGuideBundle({ provider, planContext, evidence: evidence(evidenceFact("improving")) });
    const bundle = readGeneratedBundle(outcome);

    assert.match(bundle.planSummary, /Gentle recovery run/);
    assert.match(bundle.runningTip, /relaxed|gentle|conversational/i);
    assert.match(bundle.progressionCheckIn, /covering more ground/);
    assert.doesNotMatch(bundle.progressionCheckIn, /\d|streak|leaderboard/i);
  });

  it("accepts harmless second-person trainer encouragement while rejecting unsupported metric claims", async () => {
    const friendlyProvider = new StubProvider(modelOutput({
      planSummaryText: "You have a calm session waiting.",
      runningTipText: "Keep your shoulders relaxed and breathe easy.",
      selectedProgressionFactIds: [],
      nextActionCode: "build_baseline",
    }));
    const metricClaimProvider = new StubProvider(modelOutput({
      planSummaryText: "Your distance is improving nicely.",
      runningTipText: "Keep your pace faster today.",
      selectedProgressionFactIds: [],
      nextActionCode: "build_baseline",
    }));

    assert.equal(
      readOutcomeKind(await generateHomeGuideBundle({ provider: friendlyProvider, planContext: modelPlanContext(), evidence: evidence() })),
      "generated",
    );
    const repaired = readGeneratedBundle(await generateHomeGuideBundle({ provider: metricClaimProvider, planContext: modelPlanContext(), evidence: evidence() }));
    assert.doesNotMatch(`${repaired.planSummary} ${repaired.runningTip}`, /distance|improving|faster/i);
  });

  it("keeps server-rendered plan context within the existing final message cap", async () => {
    const provider = new StubProvider(modelOutput({
      planSummaryText: "a".repeat(128),
      runningTipText: "b".repeat(128),
    }));
    const outcome: unknown = await generateHomeGuideBundle({
      provider,
      planContext: { ...modelPlanContext(), workoutTitle: "Very long recovery workout title", intensity: "easy" },
      evidence: evidence(),
    });
    const bundle = readGeneratedBundle(outcome);

    assert.ok(Array.from(bundle.planSummary).length <= 160);
    assert.ok(Array.from(bundle.runningTip).length <= 160);
    assert.match(bundle.planSummary, /Very long recovery/);
    assert.match(bundle.runningTip, /chatty, relaxed effort/);
  });

  it("activates the deterministic fake only for the verified emulator project and explicit flag", async () => {
    const fake = createHomeGuideModelProvider({ apiKey: undefined, environment: { functionsEmulator: "true", projectId: "runiac-functions-test", fakeProviderFlag: "deterministic" } });
    const valid: unknown = await generateHomeGuideBundle({ provider: fake, planContext: modelPlanContext(), evidence: evidence(evidenceFact("declining")) });
    assert.equal(readOutcomeKind(valid), "generated");
    for (const environment of [
      { functionsEmulator: undefined, projectId: "runiac-functions-test", fakeProviderFlag: "deterministic" },
      { functionsEmulator: "true", projectId: "another-project", fakeProviderFlag: "deterministic" },
      { functionsEmulator: "true", projectId: "runiac-functions-test", fakeProviderFlag: "other" },
    ]) {
      const blocked = createHomeGuideModelProvider({ apiKey: "not-used", environment });
      assert.deepEqual(await generateHomeGuideBundle({ provider: blocked, planContext: modelPlanContext(), evidence: evidence() }), {
        kind: "fallback",
        fallbackCategory: "provider_error",
      });
    }
  });
});

type GeneratedBundle = {
  readonly planSummary: string;
  readonly runningTip: string;
  readonly progressionCheckIn: string;
};

function readOutcomeKind(value: unknown): string {
  assert.ok(isRecord(value));
  const kind = value["kind"];
  if (typeof kind !== "string") {
    assert.fail("Expected outcome kind.");
  }
  return kind;
}

function readGeneratedBundle(value: unknown): GeneratedBundle {
  assert.equal(readOutcomeKind(value), "generated");
  assert.ok(isRecord(value));
  assert.ok(isRecord(value["bundle"]));
  const bundle = value["bundle"];
  return {
    planSummary: readString(bundle["planSummary"]),
    runningTip: readString(bundle["runningTip"]),
    progressionCheckIn: readString(bundle["progressionCheckIn"]),
  };
}

function readString(value: unknown): string {
  if (typeof value !== "string") {
    assert.fail("Expected string.");
  }
  return value;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
