import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  ACTIVITY_FEEDBACK_MODEL_CONFIG,
  buildActivityFeedbackModelPrompt,
  createActivityFeedbackModelProvider,
  generateActivityFeedbackSections,
  validateActivityFeedbackModelOutput,
  type ActivityFeedbackModelProvider,
  type ActivityFeedbackProviderRequest,
} from "../src/agent/activityFeedbackModel.js";
import { parseActivityFeedbackRequest } from "../src/agent/activityFeedbackContracts.js";

describe("activity feedback structured model output", () => {
  it("accepts only the exact four-section schema", () => {
    // Given
    const output = safeOutput();

    // When
    const valid = validateActivityFeedbackModelOutput(output);

    // Then
    assert.deepEqual(valid, output);
    assert.equal(validateActivityFeedbackModelOutput({ ...output, extra: "not allowed" }), null);
    assert.equal(validateActivityFeedbackModelOutput({ summary: output.summary }), null);
  });

  it("rejects diagnosis, shame, links, markdown, and competitive promises", () => {
    // Given
    const unsafeCopy = [
      "This run diagnoses an injury.",
      "You were lazy and should feel ashamed.",
      "Read https://example.test/advice.",
      "**Push harder** on the next run.",
      "This will earn XP and move you up the leaderboard.",
    ];

    // When / Then
    for (const summary of unsafeCopy) {
      assert.equal(validateActivityFeedbackModelOutput({ ...safeOutput(), summary }), null);
    }
  });

  it("builds a derived-metrics-only prompt with explicit beginner safety rules", () => {
    // Given
    const request = parseActivityFeedbackRequest(validRequest());

    // When
    const prompt = buildActivityFeedbackModelPrompt(request);

    // Then
    assert.match(prompt.systemPrompt, /beginner/i);
    assert.match(prompt.systemPrompt, /diagnos/i);
    assert.match(prompt.systemPrompt, /sham/i);
    assert.match(prompt.systemPrompt, /XP/i);
    assert.match(prompt.userPrompt, /distanceKm/);
    for (const forbidden of ["routeName", "activityId", "polyline", "coordinates", "demoOnly"]) {
      assert.equal(prompt.userPrompt.includes(forbidden), false);
    }
  });
});

describe("activity feedback provider seam", () => {
  it("uses bounded low-temperature no-retry settings and invokes one provider once", async () => {
    // Given
    const provider = new StubProvider(safeOutput());

    // When
    const outcome = await generateActivityFeedbackSections({
      provider,
      metrics: parseActivityFeedbackRequest(validRequest()),
    });

    // Then
    assert.deepEqual(ACTIVITY_FEEDBACK_MODEL_CONFIG, {
      model: "gpt-4o-mini",
      temperature: 0.2,
      maxTokens: 360,
      timeout: 10_000,
      maxRetries: 0,
    });
    assert.equal(outcome.kind, "generated");
    assert.equal(provider.calls, 1);
  });

  it("falls back deterministically for provider, timeout, malformed, and unsafe output", async () => {
    // Given
    const metrics = parseActivityFeedbackRequest(validRequest());
    const cases = [
      { provider: new StubProvider(() => Promise.reject(new Error("provider failed"))), category: "provider_error" },
      { provider: new StubProvider(() => new Promise<unknown>(() => undefined)), category: "timeout", timeoutMillis: 1 },
      { provider: new StubProvider({ summary: "missing sections" }), category: "json_shape" },
      { provider: new StubProvider({ ...safeOutput(), improve: "You are a weak runner." }), category: "policy_validation" },
    ] as const;

    // When / Then
    for (const testCase of cases) {
      const outcome = await generateActivityFeedbackSections({
        provider: testCase.provider,
        metrics,
        ...("timeoutMillis" in testCase ? { timeoutMillis: testCase.timeoutMillis } : {}),
      });
      assert.deepEqual(outcome, { kind: "fallback", fallbackCategory: testCase.category });
      assert.equal(testCase.provider.calls, 1);
    }
  });

  it("activates the deterministic fake only in the verified Functions emulator project", async () => {
    // Given
    const metrics = parseActivityFeedbackRequest(validRequest());
    const verified = createActivityFeedbackModelProvider({
      apiKey: undefined,
      environment: {
        functionsEmulator: "true",
        projectId: "runiac-functions-test",
        fakeProviderFlag: "deterministic",
      },
    });

    // When
    const generated = await generateActivityFeedbackSections({ provider: verified, metrics });

    // Then
    assert.equal(generated.kind, "generated");
    const blocked = createActivityFeedbackModelProvider({
      apiKey: "not-used",
      environment: {
        functionsEmulator: undefined,
        projectId: "runiac-functions-test",
        fakeProviderFlag: "deterministic",
      },
    });
    assert.deepEqual(await generateActivityFeedbackSections({ provider: blocked, metrics }), {
      kind: "fallback",
      fallbackCategory: "provider_error",
    });
  });
});

function safeOutput() {
  return {
    summary: "You completed a steady run with useful pacing data.",
    wentWell: "Your effort stayed controlled across the available splits.",
    improve: "Ease into the first part of the next run.",
    nextFocus: "Keep the next session calm and repeatable.",
  };
}

function validRequest() {
  return {
    schemaVersion: 1,
    summary: {
      distanceKm: 5,
      durationSeconds: 1800,
      averagePaceSecondsPerKm: 360,
      sourceLabel: "Runiac GPS",
    },
    cadence: { averageSpm: 164, isEstimated: true },
    unavailable: ["cadence"],
  };
}

class StubProvider implements ActivityFeedbackModelProvider {
  public calls = 0;

  public constructor(private readonly result: unknown | (() => Promise<unknown>)) {}

  public async invoke(_request: ActivityFeedbackProviderRequest): Promise<unknown> {
    this.calls += 1;
    return typeof this.result === "function" ? this.result() : this.result;
  }
}
